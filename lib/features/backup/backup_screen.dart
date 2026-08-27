import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة النسخ الاحتياطي والاستعادة
/// --------------------------------
/// تعرض قائمة النسخ الاحتياطية المخزّنة محلياً مع:
///  - بطاقتا إجراء: "إنشاء نسخة احتياطية" (تتطلب backup.create) و"استعادة
///    نسخة" (تتطلب backup.restore).
///  - بطاقات إحصائية: عدد النسخ، الحجم الكلي، تاريخ آخر نسخة.
///  - بطاقة معلومات تشرح سلوك النسخ/الاستعادة (يتم إنشاء نسخة أمان تلقائياً
///    قبل أي استعادة، وبياناتك الحالية ستُستبدل بالكامل).
///  - قائمة النسخ مع زر حذف لكل عنصر (يتطلب backup.create).
/// التخطيط متجاوب: شبكة StatCards بعمودين على الهواتف وثلاثة على الأجهزة العريضة،
/// وقائمة النسخ تتحول إلى شبكة بطاقات على العروض الكبيرة.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  // ===== Data =====
  final List<BackupMetadataData> _backups = [];

  // ===== State =====
  bool _isLoading = true;
  bool _busy = false; // عمليات إنشاء/استعادة/حذف

  // ===== Permissions =====
  bool _canCreate = false;
  bool _canRestore = false;

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _loadBackups();
  }

  void _initPermissions() {
    final auth = context.read<AuthProvider>();
    _canCreate = auth.hasPermission(PermissionCodes.backupCreate);
    _canRestore = auth.hasPermission(PermissionCodes.backupRestore);
  }

  // =====================
  // تحميل البيانات
  // =====================

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      final list = await ServiceLocator.backupService.listBackups();
      _backups
        ..clear()
        ..addAll(list);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل قائمة النسخ الاحتياطية: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =====================
  // إحصائيات
  // =====================

  int get _totalCount => _backups.length;

  int get _totalSizeBytes => _backups.fold<int>(0, (sum, b) => sum + b.size);

  DateTime? get _lastBackupDate =>
      _backups.isNotEmpty ? _backups.first.createdAt : null;

  // =====================
  // إنشاء نسخة احتياطية
  // =====================

  Future<void> _onCreateBackup() async {
    if (!_canCreate) return;
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser!.id;

    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _BackupNoteDialog(),
    );

    if (note == null) return; // ألغى المستخدم
    // نسمح بملاحظة فارغة (تُعامل كـ null في الخدمة)

    setState(() => _busy = true);
    try {
      final file = await ServiceLocator.backupService.createBackup(
        userId: userId,
        note: note.trim().isEmpty ? null : note.trim(),
      );
      if (mounted) {
        showSuccessSnackBar(
          context,
          'تم إنشاء النسخة الاحتياطية بنجاح: ${file.path.split('/').last}',
        );
      }
      await _loadBackups();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل إنشاء النسخة الاحتياطية: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =====================
  // استعادة نسخة احتياطية
  // =====================

  Future<void> _onRestoreBackup() async {
    if (!_canRestore) return;

    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser!.id;

    // إدخال مسار ملف النسخة الاحتياطية يدوياً (بديل عن file_picker الذي
    // تمت إزالته لتقليل حجم التطبيق).
    if (!mounted) return;
    final path = await showDialog<String>(
      context: context,
      builder: (_) => const _RestorePathDialog(),
    );

    if (path == null) return; // ألغى المستخدم

    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      if (mounted) showErrorSnackBar(context, 'لم يتم إدخال مسار الملف');
      return;
    }

    final file = File(trimmedPath);
    if (!await file.exists()) {
      if (mounted) {
        showErrorSnackBar(context, 'الملف المحدد غير موجود: $trimmedPath');
      }
      return;
    }

    // تأكيد قبل الاستعادة (تحذير: ستُستبدل البيانات الحالية)
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'تأكيد الاستعادة',
      message:
          'سيتم استبدال جميع البيانات الحالية بالبيانات الموجودة في الملف.\n'
          'سيتم إنشاء نسخة احتياطية تلقائياً قبل الاستعادة كإجراء أمان.\n\n'
          'هل أنت متأكد من المتابعة؟',
      confirmText: 'استعادة الآن',
      cancelText: 'إلغاء',
      isDanger: true,
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ServiceLocator.backupService.restoreBackup(file, userId);
      if (mounted) {
        showSuccessSnackBar(
          context,
          'تمت الاستعادة بنجاح. قد تحتاج لإعادة تشغيل التطبيق لتحديث الشاشات.',
        );
      }
      await _loadBackups();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشلت الاستعادة: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =====================
  // حذف نسخة
  // =====================

  Future<void> _onDeleteBackup(BackupMetadataData backup) async {
    if (!_canCreate) return;
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser!.id;

    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف النسخة الاحتياطية',
      message: 'سيتم حذف الملف "${backup.fileName}" نهائياً.\n'
          'لا يمكن التراجع عن هذا الإجراء.',
      confirmText: 'حذف',
      cancelText: 'إلغاء',
      isDanger: true,
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ServiceLocator.backupService.deleteBackup(backup.id, userId);
      if (mounted) {
        showSuccessSnackBar(context, 'تم حذف النسخة الاحتياطية');
      }
      await _loadBackups();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل حذف النسخة: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =====================
  // تنسيق الحجم
  // =====================

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    const kb = 1024;
    const mb = 1024 * 1024;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadBackups,
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const LoadingIndicator(message: 'جارٍ تحميل النسخ الاحتياطية...')
              : RefreshIndicator(
                  onRefresh: _loadBackups,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildActionsRow(isWide),
                            const SizedBox(height: 16),
                            _buildStatsGrid(isWide),
                            const SizedBox(height: 16),
                            _buildInfoCard(),
                            const SizedBox(height: 16),
                            SectionHeader(
                              title: 'النسخ الاحتياطية المحفوظة',
                              icon: Icons.history_outlined,
                            ),
                            const SizedBox(height: 8),
                            if (_backups.isEmpty)
                              const EmptyState(
                                message:
                                    'لا توجد نسخ احتياطية بعد.\nاستخدم زر "إنشاء نسخة احتياطية" أعلاه.',
                                icon: Icons.cloud_off_outlined,
                              )
                            else
                              _buildBackupsList(isWide),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('جارٍ المعالجة...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =====================
  // صف الأزرار
  // =====================

  Widget _buildActionsRow(bool isWide) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: _canCreate && !_busy ? _onCreateBackup : null,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('إنشاء نسخة احتياطية'),
        ),
        OutlinedButton.icon(
          onPressed: _canRestore && !_busy ? _onRestoreBackup : null,
          icon: const Icon(Icons.restore_outlined),
          label: const Text('استعادة نسخة'),
        ),
      ],
    );
  }

  // =====================
  // بطاقات الإحصائيات
  // =====================

  Widget _buildStatsGrid(bool isWide) {
    final stats = <Widget>[
      StatCard(
        title: 'إجمالي النسخ',
        value: '$_totalCount',
        icon: Icons.layers_outlined,
        color: AppColors.primary,
      ),
      StatCard(
        title: 'الحجم الكلي',
        value: _formatSize(_totalSizeBytes),
        icon: Icons.sd_storage_outlined,
        color: AppColors.info,
      ),
      StatCard(
        title: 'آخر نسخة',
        value: _lastBackupDate != null
            ? FormatUtils.formatDateTime(_lastBackupDate!)
            : '--',
        icon: Icons.access_time,
        color: AppColors.secondary,
      ),
    ];

    // أجهزة الهاتف (عرض ضيق) نستخدم عمودين للحقلين الأولين والثالث يتمدد بالعرض
    if (!isWide) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: stats[0]),
              const SizedBox(width: 12),
              Expanded(child: stats[1]),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: stats[2]),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: stats[0]),
        const SizedBox(width: 12),
        Expanded(child: stats[1]),
        const SizedBox(width: 12),
        Expanded(child: stats[2]),
      ],
    );
  }

  // =====================
  // بطاقة المعلومات
  // =====================

  Widget _buildInfoCard() {
    return Card(
      color: AppColors.info.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.info, size: 22),
                const SizedBox(width: 8),
                Text(
                  'معلومات عن النسخ الاحتياطي',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _bullet('يتم حفظ النسخ الاحتياطية كملفات JSON داخل ذاكرة الجهاز.'),
            _bullet('تحتوي كل نسخة على كامل بيانات النظام (المبيعات، المخزون، '
                'العملاء، الموردون، الحسابات...).'),
            _bullet('عند الاستعادة يتم استبدال كل البيانات الحالية بالبيانات '
                'الموجودة في الملف المحدد.'),
            _bullet('يُنشئ النظام تلقائياً نسخة أمان قبل أي عملية استعادة '
                'يمكنك الرجوع إليها عند الحاجة.'),
            _bullet('يمكنك حذف النسخ القديمة لتحرير مساحة التخزين.'),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 8),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.info,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  // =====================
  // قائمة النسخ
  // =====================

  Widget _buildBackupsList(bool isWide) {
    if (isWide) {
      // شبكة بطاقات
      return LayoutBuilder(
        builder: (context, constraints) {
          const cardWidth = 320.0;
          final crossCount =
              (constraints.maxWidth / cardWidth).floor().clamp(1, 3);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _backups.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            itemBuilder: (context, i) =>
                _buildBackupCard(_backups[i], isWide: true),
          );
        },
      );
    }
    return Column(
      children: _backups
          .map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildBackupCard(b, isWide: false),
              ))
          .toList(),
    );
  }

  Widget _buildBackupCard(BackupMetadataData b, {required bool isWide}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    b.fileName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_canCreate)
                  IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: AppColors.error,
                    onPressed: _busy ? null : () => _onDeleteBackup(b),
                  ),
              ],
            ),
            const Divider(height: 12),
            InfoRow(
              label: 'التاريخ',
              value: FormatUtils.formatDateTime(b.createdAt),
              icon: Icons.event_outlined,
            ),
            InfoRow(
              label: 'الحجم',
              value: _formatSize(b.size),
              icon: Icons.data_usage_outlined,
            ),
            InfoRow(
              label: 'إصدار القاعدة',
              value: '${b.databaseVersion}',
              icon: Icons.dns_outlined,
            ),
            if (b.note != null && b.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: AppColors.secondaryDark,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        b.note!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  نافذة إدخال ملاحظة النسخة الاحتياطية (Private Widget)
// ============================================================================

class _BackupNoteDialog extends StatefulWidget {
  const _BackupNoteDialog();

  @override
  State<_BackupNoteDialog> createState() => _BackupNoteDialogState();
}

class _BackupNoteDialogState extends State<_BackupNoteDialog> {
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit_note, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('ملاحظة النسخة الاحتياطية')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'أضف ملاحظة اختيارية لتسهيل التعرف على هذه النسخة لاحقاً '
            '(مثال: "قبل إغلاق الشهر").',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'الملاحظة (اختياري)',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.sticky_note_2_outlined),
              hintText: 'اكتب ملاحظة...',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_noteCtrl.text),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('إنشاء النسخة'),
        ),
      ],
    );
  }
}

// ============================================================================
//  نافذة إدخال مسار ملف النسخة الاحتياطية للاستعادة (Private Widget)
//  بديل بسيط عن file_picker الذي تمت إزالته لتقليل حجم الـ APK.
//  يدخل المستخدم المسار الكامل للملف يدوياً ثم يتم التحقق من وجوده.
// ============================================================================

class _RestorePathDialog extends StatefulWidget {
  const _RestorePathDialog();

  @override
  State<_RestorePathDialog> createState() => _RestorePathDialogState();
}

class _RestorePathDialogState extends State<_RestorePathDialog> {
  final TextEditingController _pathCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return 'الرجاء إدخال المسار الكامل للملف';
    }
    if (!v.toLowerCase().endsWith('.json')) {
      return 'يجب أن يكون الملف بامتداد .json';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_pathCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.restore_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('استعادة نسخة احتياطية')),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'أدخل المسار الكامل لملف النسخة الاحتياطية (JSON) الذي '
              'تريد استعادته. سيتم التحقق من وجود الملف قبل المتابعة.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pathCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: _validate,
              decoration: const InputDecoration(
                labelText: 'مسار الملف',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.folder_open_outlined),
                hintText: 'مثال: /storage/emulated/0/backup.json',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('متابعة'),
        ),
      ],
    );
  }
}
