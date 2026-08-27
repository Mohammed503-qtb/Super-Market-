import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة "تغيير كلمة المرور"
/// ----------------------
/// تتيح للمستخدم الحالي تغيير كلمة مروره بعد التحقق من كلمة المرور الحالية.
/// التحقق يتم عبر PasswordHasher.verify، والتشفير الجديد عبر PasswordHasher.hash،
/// ثم حفظ المستخدم بواسطة userDao.updateUser.
/// تُسجَّل العملية في سجل التدقيق عبر AuditService.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  // الحد الأدنى لطول كلمة المرور.
  static const int _minPasswordLength = 4;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // =====================
  // الحفظ
  // =====================

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      if (mounted) showErrorSnackBar(context, 'لا يوجد مستخدم نشط');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final db = ServiceLocator.database;

      // 1) التحقق من كلمة المرور الحالية.
      if (!PasswordHasher.verify(_currentCtrl.text, user.passwordHash)) {
        if (mounted) {
          showErrorSnackBar(context, 'كلمة المرور الحالية غير صحيحة');
        }
        return;
      }

      // 2) تشفير كلمة المرور الجديدة.
      final newHash = PasswordHasher.hash(_newCtrl.text);

      // 3) تحديث بيانات المستخدم.
      final updated = user.copyWith(
        passwordHash: newHash,
        updatedAt: DateTime.now(),
      );
      await db.userDao.updateUser(updated);

      // ملاحظة: تبقى كائنة الجلسة الحالية في AuthProvider كما هي. لم نُحدّث
      // حقل passwordHash داخلها لأن AuthProvider لا يوفّر setter عاماً،
      // لكن القاعدة محدّثة وكلمة المرور الجديدة ستُستخدم في تسجيل الدخول
      // التالي. والجلسة الحالية تبقى فعّالة حتى تسجيل الخروج.

      // 4) تسجيل العملية في سجل التدقيق.
      await ServiceLocator.auditService.log(
        userId: user.id,
        action: 'PASSWORD_CHANGED',
        module: 'auth',
        entityType: 'user',
        entityId: user.id,
        description: 'تغيير كلمة المرور',
      );

      // 5) إفراغ الحقول وإظهار رسالة النجاح ثم العودة.
      _currentCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();

      if (mounted) {
        showSuccessSnackBar(context, 'تم تغيير كلمة المرور بنجاح');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تغيير كلمة المرور: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('تغيير كلمة المرور')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(theme, user?.displayName ?? ''),
                  const SizedBox(height: 16),
                  _buildForm(theme),
                  const SizedBox(height: 16),
                  _buildHint(),
                  const SizedBox(height: 16),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, String displayName) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.lock_person_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تغيير كلمة المرور',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  if (displayName.isNotEmpty)
                    Text(
                      'المستخدم: $displayName',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondaryLight),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _currentCtrl,
              obscureText: _obscureCurrent,
              enabled: !_isSaving,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية *',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureCurrent
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(
                      () => _obscureCurrent = !_obscureCurrent),
                ),
                hintText: 'أدخل كلمة المرور الحالية',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'كلمة المرور الحالية مطلوبة';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newCtrl,
              obscureText: _obscureNew,
              enabled: !_isSaving,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة *',
                prefixIcon: const Icon(Icons.lock_reset, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNew
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureNew = !_obscureNew),
                ),
                hintText: '$_minPasswordLength أحرف على الأقل',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'كلمة المرور الجديدة مطلوبة';
                if (v.length < _minPasswordLength) {
                  return 'كلمة المرور يجب أن تكون $_minPasswordLength أحرف على الأقل';
                }
                if (v == _currentCtrl.text) {
                  return 'كلمة المرور الجديدة يجب أن تختلف عن الحالية';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              enabled: !_isSaving,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _isSaving ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور الجديدة *',
                prefixIcon: const Icon(Icons.lock_clock_outlined, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(
                      () => _obscureConfirm = !_obscureConfirm),
                ),
                hintText: 'أعد إدخال كلمة المرور الجديدة',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'تأكيد كلمة المرور مطلوب';
                if (v != _newCtrl.text) {
                  return 'تأكيد كلمة المرور لا يطابق كلمة المرور الجديدة';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              color: AppColors.info, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'بعد تغيير كلمة المرور بنجاح ستظل الجلسة الحالية نشطة. '
              'ستُستخدم كلمة المرور الجديدة عند تسجيل الدخول التالي.',
              style: TextStyle(
                color: AppColors.info,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          label: const Text('إلغاء'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _isSaving ? null : _submit,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }
}
