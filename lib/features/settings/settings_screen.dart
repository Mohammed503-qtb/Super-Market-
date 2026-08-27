import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة الإعدادات
/// ----------------
/// تدير الإعدادات العامة للمتجر المخزّنة في جدول Settings (سجل واحد برقم 1).
/// الأقسام:
///  1) بيانات المنشأة: الاسم، العنوان، الهاتف، العملة.
///  2) إعدادات المخزون: منع السالب، السماح بالدفع الزائد.
///  3) إعدادات الضريبة: تفعيل الضريبة، النسبة (تظهر فقط عند التفعيل).
///  4) إعدادات الصندوق: رصيد الافتتاح.
/// تتطلب صلاحية `settings.edit` للحفظ؛ أما `settings.view` فقط فتُعرض الحقول
/// للقراءة. التخطيط متجاوب: عمود واحد على الهواتف، وعمودان على الشاشات العريضة.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ===== Controllers =====
  final TextEditingController _storeNameCtrl = TextEditingController();
  final TextEditingController _storeAddressCtrl = TextEditingController();
  final TextEditingController _storePhoneCtrl = TextEditingController();
  final TextEditingController _currencyCtrl = TextEditingController();
  final TextEditingController _taxRateCtrl = TextEditingController();
  final TextEditingController _openingBalanceCtrl = TextEditingController();

  // ===== Form =====
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // ===== State =====
  bool _isLoading = true;
  bool _isSaving = false;
  bool _preventNegativeStock = true;
  bool _allowOverpayment = false;
  bool _taxEnabled = false;
  bool _canEdit = false;

  // علامة اكتمال تحميل البيانات لتجنّب الكتابة فوق إدخال المستخدم أثناء init.
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _loadSettings();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storeAddressCtrl.dispose();
    _storePhoneCtrl.dispose();
    _currencyCtrl.dispose();
    _taxRateCtrl.dispose();
    _openingBalanceCtrl.dispose();
    super.dispose();
  }

  void _initPermissions() {
    final auth = context.read<AuthProvider>();
    _canEdit = auth.hasPermission(PermissionCodes.settingsEdit);
  }

  // =====================
  // تحميل الإعدادات
  // =====================

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final setting = await ServiceLocator.database.settingDao.getSettings();
      if (setting != null) {
        _storeNameCtrl.text = setting.storeName;
        _storeAddressCtrl.text = setting.storeAddress ?? '';
        _storePhoneCtrl.text = setting.storePhone ?? '';
        _currencyCtrl.text = setting.currency;
        _taxRateCtrl.text = setting.taxRate.toStringAsFixed(2);
        _openingBalanceCtrl.text =
            setting.cashboxOpeningBalance.toStringAsFixed(0);
        _preventNegativeStock = setting.preventNegativeStock;
        _allowOverpayment = setting.allowOverpayment;
        _taxEnabled = setting.taxEnabled;
      } else {
        // قيم افتراضية
        _currencyCtrl.text = AppConstants.defaultCurrency;
        _taxRateCtrl.text = '0.00';
        _openingBalanceCtrl.text = '0';
      }
      _initialized = true;
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل الإعدادات: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =====================
  // الحفظ
  // =====================

  Future<void> _save() async {
    if (!_canEdit) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final storeName = _storeNameCtrl.text.trim();
      final currency = _currencyCtrl.text.trim().isEmpty
          ? AppConstants.defaultCurrency
          : _currencyCtrl.text.trim();
      final taxRate = double.tryParse(_taxRateCtrl.text.trim()) ?? 0.0;
      final opening =
          double.tryParse(_openingBalanceCtrl.text.trim()) ?? 0.0;

      final companion = SettingsCompanion(
        storeName: Value(storeName),
        storeAddress: Value(_storeAddressCtrl.text.trim().isEmpty
            ? null
            : _storeAddressCtrl.text.trim()),
        storePhone: Value(_storePhoneCtrl.text.trim().isEmpty
            ? null
            : _storePhoneCtrl.text.trim()),
        currency: Value(currency),
        preventNegativeStock: Value(_preventNegativeStock),
        allowOverpayment: Value(_allowOverpayment),
        cashboxOpeningBalance: Value(opening),
        taxEnabled: Value(_taxEnabled),
        taxRate: Value(taxRate),
      );

      await ServiceLocator.database.settingDao.updateSettings(companion);
      if (mounted) {
        showSuccessSnackBar(context, 'تم حفظ الإعدادات بنجاح');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل حفظ الإعدادات: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingIndicator(message: 'جارٍ تحميل الإعدادات...')
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_canEdit)
                          _buildReadOnlyBanner(),
                        if (isWide)
                          // عمودان على الشاشات العريضة
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    _buildStoreInfoSection(),
                                    const SizedBox(height: 16),
                                    _buildTaxSection(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  children: [
                                    _buildInventorySection(),
                                    const SizedBox(height: 16),
                                    _buildCashboxSection(),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          // عمود واحد على الهواتف
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildStoreInfoSection(),
                              const SizedBox(height: 16),
                              _buildInventorySection(),
                              const SizedBox(height: 16),
                              _buildTaxSection(),
                              const SizedBox(height: 16),
                              _buildCashboxSection(),
                            ],
                          ),
                        const SizedBox(height: 24),
                        _buildActions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // =====================
  // ملاحظة القراءة فقط
  // =====================

  Widget _buildReadOnlyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'لديك صلاحية عرض الإعدادات فقط. الحقول للقراءة ولن يمكنك الحفظ.',
              style: TextStyle(color: AppColors.secondaryDark),
            ),
          ),
        ],
      ),
    );
  }

  // =====================
  // الأقسام
  // =====================

  Widget _buildStoreInfoSection() {
    return _SettingsCard(
      title: 'بيانات المنشأة',
      icon: Icons.store_outlined,
      color: AppColors.primary,
      children: [
        TextFormField(
          controller: _storeNameCtrl,
          enabled: _canEdit,
          decoration: const InputDecoration(
            labelText: 'اسم المنشأة *',
            prefixIcon: Icon(Icons.store, size: 20),
            hintText: 'مثال: بقالة الأمانة',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'اسم المنشأة مطلوب';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _storeAddressCtrl,
          enabled: _canEdit,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'العنوان',
            prefixIcon: Icon(Icons.location_on_outlined, size: 20),
            hintText: 'المدينة، الشارع، رقم المبنى',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _storePhoneCtrl,
          enabled: _canEdit,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            prefixIcon: Icon(Icons.phone_outlined, size: 20),
            hintText: '7xx xxx xxx',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _currencyCtrl,
          enabled: _canEdit,
          decoration: const InputDecoration(
            labelText: 'رمز العملة',
            prefixIcon: Icon(Icons.monetization_on_outlined, size: 20),
            hintText: 'ر.ي',
            helperText: 'رمز العملة المستخدمة في الفواتير والتقارير',
          ),
        ),
      ],
    );
  }

  Widget _buildInventorySection() {
    return _SettingsCard(
      title: 'إعدادات المخزون',
      icon: Icons.inventory_2_outlined,
      color: AppColors.secondary,
      children: [
        SwitchListTile(
          title: const Text('منع البيع عند نفاد المخزون'),
          subtitle: const Text(
            'يمنع إتمام البيع إذا لم يكن هناك كمية كافية في المخزون.',
          ),
          value: _preventNegativeStock,
          onChanged: _canEdit
              ? (v) => setState(() => _preventNegativeStock = v)
              : null,
          secondary: Icon(
            Icons.block_outlined,
            color: _preventNegativeStock
                ? AppColors.success
                : AppColors.textSecondaryLight,
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          title: const Text('السماح بالدفع الزائد'),
          subtitle: const Text(
            'السماح بقبض مبلغ أكبر من قيمة الفاتورة في المبيعات.',
          ),
          value: _allowOverpayment,
          onChanged: _canEdit
              ? (v) => setState(() => _allowOverpayment = v)
              : null,
          secondary: Icon(
            Icons.payments_outlined,
            color: _allowOverpayment
                ? AppColors.success
                : AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  Widget _buildTaxSection() {
    return _SettingsCard(
      title: 'إعدادات الضريبة',
      icon: Icons.percent_outlined,
      color: AppColors.accent,
      children: [
        SwitchListTile(
          title: const Text('تفعيل الضريبة'),
          subtitle: const Text('إضافة نسبة ضريبة على الفواتير.'),
          value: _taxEnabled,
          onChanged: _canEdit
              ? (v) => setState(() => _taxEnabled = v)
              : null,
          secondary: Icon(
            Icons.receipt_long_outlined,
            color: _taxEnabled
                ? AppColors.accent
                : AppColors.textSecondaryLight,
          ),
        ),
        if (_taxEnabled) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextFormField(
              controller: _taxRateCtrl,
              enabled: _canEdit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d*$'),
                ),
              ],
              decoration: const InputDecoration(
                labelText: 'نسبة الضريبة (%) *',
                prefixIcon: Icon(Icons.percent, size: 20),
                hintText: 'مثال: 5',
                suffixText: '%',
              ),
              validator: (v) {
                if (!_taxEnabled) return null;
                final value = double.tryParse(v ?? '');
                if (value == null) return 'أدخل نسبة صحيحة';
                if (value < 0) return 'النسبة لا يمكن أن تكون سالبة';
                if (value > 100) return 'النسبة يجب أن لا تتجاوز 100';
                return null;
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCashboxSection() {
    return _SettingsCard(
      title: 'إعدادات الصندوق',
      icon: Icons.savings_outlined,
      color: AppColors.info,
      children: [
        TextFormField(
          controller: _openingBalanceCtrl,
          enabled: _canEdit,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          decoration: const InputDecoration(
            labelText: 'رصيد الصندوق الافتتاحي *',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined, size: 20),
            helperText: 'الرصيد الذي يبدأ به الصندوق في بداية اليوم.',
          ),
          validator: (v) {
            final value = double.tryParse(v ?? '');
            if (value == null) return 'أدخل رقماً صحيحاً';
            if (value < 0) return 'الرصيد لا يمكن أن يكون سالباً';
            return null;
          },
        ),
      ],
    );
  }

  // =====================
  // أزرار الحفظ
  // =====================

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: (_isSaving || !_initialized) ? null : _loadSettings,
          icon: const Icon(Icons.restart_alt),
          label: const Text('استعادة'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: (_canEdit && !_isSaving) ? _save : null,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات'),
        ),
      ],
    );
  }
}

// ============================================================================
//  بطاقة قسم إعدادات
// ============================================================================

class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
