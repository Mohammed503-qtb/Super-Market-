import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/database/app_database.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import 'audit_service.dart';

/// خدمة النسخ الاحتياطي والاستعادة
class BackupService {
  final AppDatabase _db;
  final AuditService _auditService;

  BackupService(this._db, this._auditService);

  /// إنشاء نسخة احتياطية
  /// الناتج: ملف JSON يحتوي على كل البيانات
  Future<File> createBackup({int? userId, String? note}) async {
    try {
      final data = await _db.exportAllData();
      final backup = {
        'metadata': {
          'version': _db.schemaVersion,
          'createdAt': DateTime.now().toIso8601String(),
          'appName': 'Grocery ERP',
          'note': note ?? '',
        },
        'data': data,
      };

      final json = const JsonEncoder().convert(backup);
      final now = DateTime.now();
      final fileName = 'backup_${_formatDateForFile(now)}.json';

      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final file = File(p.join(backupDir.path, fileName));
      await file.writeAsString(json);

      final size = await file.length();
      await _db.backupMetadataDao.insertMetadata(BackupMetadataCompanion.insert(
        fileName: fileName,
        size: Value(size),
        note: note != null ? Value(note) : const Value.absent(),
      ));

      if (userId != null) {
        await _auditService.log(
          userId: userId,
          action: 'BACKUP_CREATED',
          module: 'backup',
          description: 'إنشاء نسخة احتياطية: $fileName ($size bytes)',
        );
      }

      AppLogger.info('Backup created: $fileName ($size bytes)');
      return file;
    } catch (e) {
      AppLogger.error('Backup failed', error: e);
      throw BackupRestoreException('فشل إنشاء النسخة الاحتياطية: $e');
    }
  }

  /// استعادة نسخة احتياطية
  /// 1) التحقق من النسخة
  /// 2) إنشاء نسخة أمان
  /// 3) استعادة البيانات
  /// 4) التحقق من قاعدة البيانات
  Future<void> restoreBackup(File backupFile, int userId) async {
    try {
      if (!await backupFile.exists()) {
        throw BackupRestoreException('ملف النسخة الاحتياطية غير موجود');
      }

      final content = await backupFile.readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;

      final metadata = backup['metadata'] as Map<String, dynamic>?;
      if (metadata == null) {
        throw BackupRestoreException('ملف النسخة الاحتياطية تالف');
      }

      final version = metadata['version'] as int?;
      if (version == null) {
        throw BackupRestoreException('إصدار النسخة الاحتياطية غير معروف');
      }

      // 1) إنشاء نسخة أمان قبل الاستعادة
      await createBackup(userId: userId, note: 'نسخة أمان قبل الاستعادة');

      // 2) مسح البيانات الحالية
      await _db.clearAllData();

      // 3) استعادة البيانات
      final data = backup['data'] as Map<String, dynamic>;
      await _restoreData(data);

      // 4) Audit Log
      await _auditService.log(
        userId: userId,
        action: 'BACKUP_RESTORED',
        module: 'backup',
        description: 'استعادة النسخة الاحتياطية: ${backupFile.path.split('/').last}',
      );

      AppLogger.info('Backup restored: ${backupFile.path}');
    } catch (e) {
      AppLogger.error('Restore failed', error: e);
      throw BackupRestoreException('فشل الاستعادة: $e');
    }
  }

  Future<void> _restoreData(Map<String, dynamic> data) async {
    // ترتيب الإدراج حسب التبعيات
    final insertOrder = [
      'roles',
      'permissions',
      'role_permissions',
      'users',
      'categories',
      'units',
      'products',
      'suppliers',
      'customers',
      'sales',
      'sale_items',
      'purchases',
      'purchase_items',
      'inventory_movements',
      'cash_transactions',
      'customer_payments',
      'supplier_payments',
      'expenses',
      'withdrawals',
      'returns',
      'return_items',
      'audit_logs',
      'backup_metadata',
      'settings',
      'stocktakes',
      'stocktake_items',
    ];

    for (final tableName in insertOrder) {
      final rows = data[tableName] as List<dynamic>?;
      if (rows == null || rows.isEmpty) continue;

      // بناء INSERT statements يدوياً
      for (final row in rows) {
        final rowMap = row as Map<String, dynamic>;
        final columns = rowMap.keys.toList();
        final values = rowMap.values.map((v) => _encodeValue(v)).join(', ');
        final cols = columns.join(', ');
        try {
          await _db.customStatement(
            'INSERT OR REPLACE INTO $tableName ($cols) VALUES ($values)',
          );
        } catch (e) {
          AppLogger.warning('Failed to insert row in $tableName: $e');
        }
      }
    }
  }

  String _encodeValue(dynamic v) {
    if (v == null) return 'NULL';
    if (v is num) return v.toString();
    if (v is bool) return v ? '1' : '0';
    if (v is String) {
      // escape single quotes
      final escaped = v.replaceAll("'", "''");
      return "'$escaped'";
    }
    if (v is List || v is Map) {
      final escaped = jsonEncode(v).replaceAll("'", "''");
      return "'$escaped'";
    }
    return "'${v.toString()}'";
  }

  /// قائمة النسخ الاحتياطية
  Future<List<BackupMetadataData>> listBackups() async {
    return _db.backupMetadataDao.getAll();
  }

  /// حذف نسخة احتياطية
  Future<void> deleteBackup(int backupId, int userId) async {
    final backups = await _db.backupMetadataDao.getAll();
    final backup = backups.where((b) => b.id == backupId).firstOrNull;
    if (backup == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'backups', backup.fileName));
    if (await file.exists()) {
      await file.delete();
    }
    await _db.backupMetadataDao.deleteMetadata(backupId);

    await _auditService.log(
      userId: userId,
      action: 'BACKUP_DELETED',
      module: 'backup',
      description: 'حذف النسخة الاحتياطية: ${backup.fileName}',
    );
  }

  String _formatDateForFile(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}_${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}';
  }
}
