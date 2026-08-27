import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';

/// خدمة سجل التدقيق - تسجل كل العمليات الحساسة
class AuditService {
  final AppDatabase _db;

  AuditService(this._db);

  Future<int> log({
    required int userId,
    required String action,
    String? module,
    String? entityType,
    int? entityId,
    String? oldValue,
    String? newValue,
    String? description,
  }) async {
    return _db.auditLogDao.insertLog(AuditLogsCompanion.insert(
      userId: Value(userId),
      action: action,
      module: module != null ? Value(module) : const Value.absent(),
      entityType: entityType != null ? Value(entityType) : const Value.absent(),
      entityId: entityId != null ? Value(entityId) : const Value.absent(),
      oldValue: oldValue != null ? Value(oldValue) : const Value.absent(),
      newValue: newValue != null ? Value(newValue) : const Value.absent(),
      description: description != null ? Value(description) : const Value.absent(),
    ));
  }

  Future<List<AuditLog>> getRecent({int limit = 100}) {
    return _db.auditLogDao.getRecent(limit: limit);
  }

  Future<List<AuditLog>> getByUser(int userId) {
    return _db.auditLogDao.getByUser(userId);
  }

  Future<List<AuditLog>> getByModule(String module) {
    return _db.auditLogDao.getByModule(module);
  }
}
