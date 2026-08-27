import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة إدارة الموردين
/// -------------------
/// - قائمة الموردين مع بحث فوري (الاسم / الهاتف).
/// - كل صف يعرض: الاسم، الهاتف، الرصيد الحالي (أحمر إذا له مديونية، أخضر إذا
///   معدوم)، وشارة المعطّل.
/// - زر "مورد جديد" (FAB) يتطلب صلاحية suppliers.create.
/// - تعديل/حذف مورد، الحذف مرفوض إذا كان له فواتير شراء (الخدمة ترمي
///   OperationNotAllowedException).
/// - نافذة تفاصيل المورد تعرض ملخص الحساب (افتتاحي / إجمالي الآجل /
///   إجمالي المدفوع / الرصيد الحالي) + كشف حركة مفصل + زر "سداد دفعة".
/// - صلاحيات: create/edit/delete/payment تتحكم في ظهور الأزرار.
/// - تخطيط متجاوب: شبكة بطاقات على الشاشات العريضة، قائمة على الهواتف.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  // ===== Controllers =====
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ===== Data =====
  final List<Supplier> _suppliers = [];

  // ===== حالة الواجهة =====
  bool _isLoading = true;
  String _searchQuery = '';

  // ===== الصلاحيات =====
  bool _canCreate = false;
  bool _canEdit = false;
  bool _canDelete = false;
  bool _canPayment = false;

  // =====================
  // دورة الحياة
  // =====================

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _refreshSuppliers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _initPermissions() {
    final auth = context.read<AuthProvider>();
    _canCreate = auth.hasPermission(PermissionCodes.suppliersCreate);
    _canEdit = auth.hasPermission(PermissionCodes.suppliersEdit);
    _canDelete = auth.hasPermission(PermissionCodes.suppliersDelete);
    _canPayment = auth.hasPermission(PermissionCodes.suppliersPayment);
  }

  Future<void> _refreshSuppliers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final db = ServiceLocator.database;
      List<Supplier> result;
      if (_searchQuery.trim().isNotEmpty) {
        result = await db.supplierDao.search(_searchQuery.trim());
      } else {
        result = await db.supplierDao.getAll();
      }
      _suppliers
        ..clear()
        ..addAll(result);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل الموردين: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () {
        _searchQuery = _searchController.text;
        _refreshSuppliers();
      },
    );
  }

  // =====================
  // إحصائيات سريعة
  // =====================

  int get _suppliersWithDebtCount =>
      _suppliers.where((s) => s.currentBalance > 0).length;
  num get _totalPayables => _suppliers.fold<num>(
      0, (s, c) => s + (c.currentBalance > 0 ? c.currentBalance : 0));

  // =====================
  // فتح النماذج
  // =====================

  Future<void> _openSupplierForm({Supplier? supplier}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SupplierFormDialog(supplier: supplier),
    );
    if (result == true) {
      await _refreshSuppliers();
    }
  }

  Future<void> _openSupplierDetail(Supplier supplier) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _SupplierDetailDialog(
        supplier: supplier,
        canPayment: _canPayment,
        canEdit: _canEdit,
        canDelete: _canDelete,
        onEdit: () => _openSupplierForm(supplier: supplier),
        onDelete: () => _confirmDelete(supplier),
        onPayment: () => _openPaymentDialog(supplier),
      ),
    );
    if (result == true) {
      await _refreshSuppliers();
    }
  }

  Future<void> _openPaymentDialog(Supplier supplier) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(supplier: supplier),
    );
    if (result == true) {
      // أعد فتح تفاصيل المورد لإظهار التحديث؟ نكتفي بإغلاق وفتح جديد.
    }
  }

  // =====================
  // حذف المورد
  // =====================

  Future<void> _confirmDelete(Supplier supplier) async {
    // نلتقط الـ userId قبل أي async gap لتفادي استخدام BuildContext بعد await.
    final userId = context.read<AuthProvider>().currentUser!.id;
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف المورد',
      message: 'هل أنت متأكد من حذف "${supplier.name}"؟ '
          'لا يمكن الحذف إذا كان له فواتير شراء.',
      confirmText: 'حذف',
      isDanger: true,
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await ServiceLocator.suppliersService.deleteSupplier(supplier.id, userId);
      if (mounted) {
        showSuccessSnackBar(context, 'تم حذف المورد بنجاح');
        Navigator.of(context).pop(true); // أغلق نافذة التفاصيل
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل الحذف: $e');
      }
    }
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموردون'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshSuppliers,
          ),
        ],
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openSupplierForm(),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('مورد جديد'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refreshSuppliers,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildSearchAndStats()),
            if (_isLoading && _suppliers.isEmpty)
              const SliverFillRemaining(
                child: LoadingIndicator(message: 'جارٍ تحميل الموردين...'),
              )
            else if (_suppliers.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.local_shipping_outlined,
                  message: _searchQuery.isNotEmpty
                      ? 'لا يوجد موردون مطابقون لبحثك'
                      : 'لا يوجد موردون بعد',
                  actionLabel: _canCreate ? 'إضافة مورد' : null,
                  onAction: _canCreate ? () => _openSupplierForm() : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                sliver: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (wide) {
                      return SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 420,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.0,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _SupplierCard(
                            supplier: _suppliers[i],
                            canEdit: _canEdit,
                            canPayment: _canPayment,
                            onTap: () => _openSupplierDetail(_suppliers[i]),
                            onEdit: () =>
                                _openSupplierForm(supplier: _suppliers[i]),
                            onPayment: () => _openPaymentDialog(_suppliers[i]),
                          ),
                          childCount: _suppliers.length,
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _SupplierTile(
                          supplier: _suppliers[i],
                          canEdit: _canEdit,
                          canPayment: _canPayment,
                          onTap: () => _openSupplierDetail(_suppliers[i]),
                          onEdit: () =>
                              _openSupplierForm(supplier: _suppliers[i]),
                          onPayment: () => _openPaymentDialog(_suppliers[i]),
                        ),
                        childCount: _suppliers.length,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          SearchField(
            controller: _searchController,
            hintText: 'ابحث بالاسم أو رقم الهاتف...',
            onChanged: _onSearchChanged,
            onClear: () {
              _searchQuery = '';
              _refreshSuppliers();
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _miniStat(
                  'إجمالي الموردين',
                  '${_suppliers.length}',
                  Icons.local_shipping_outlined,
                  AppColors.primary,
                ),
                _miniStat(
                  'إجمالي المستحقات',
                  FormatUtils.formatMoneyAr(_totalPayables),
                  Icons.account_balance_wallet_outlined,
                  AppColors.error,
                ),
                _miniStat(
                  'موردون عليهم مستحقات',
                  '$_suppliersWithDebtCount',
                  Icons.trending_up,
                  AppColors.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, String value, IconData icon, Color color) {
    return Container(
      width: 170,
      margin: const EdgeInsets.only(left: 8),
      child: StatCard(
        title: title,
        value: value,
        icon: icon,
        color: color,
      ),
    );
  }
}

// =====================================================
// بطاقة المورد (للشاشات العريضة)
// =====================================================
class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final bool canEdit;
  final bool canPayment;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPayment;

  const _SupplierCard({
    required this.supplier,
    required this.canEdit,
    required this.canPayment,
    required this.onTap,
    required this.onEdit,
    required this.onPayment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDebt = supplier.currentBalance > 0;
    final balanceColor = hasDebt ? AppColors.error : AppColors.success;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_shipping,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if ((supplier.phone ?? '').isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.phone_outlined,
                                  size: 14,
                                  color: AppColors.textSecondaryLight),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  supplier.phone!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondaryLight,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (!supplier.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.textSecondaryLight
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'معطّل',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondaryLight,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(height: 18),
              // الرصيد الحالي
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: balanceColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: balanceColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasDebt
                          ? Icons.account_balance_wallet
                          : Icons.check_circle_outline,
                      color: balanceColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasDebt ? 'له مستحقات' : 'خالص',
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      FormatUtils.formatMoneyAr(supplier.currentBalance),
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canPayment && hasDebt)
                    TextButton.icon(
                      onPressed: onPayment,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('سداد دفعة'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'تعديل',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: onEdit,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================
// عنصر قائمة المورد (للهواتف)
// =====================================================
class _SupplierTile extends StatelessWidget {
  final Supplier supplier;
  final bool canEdit;
  final bool canPayment;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPayment;

  const _SupplierTile({
    required this.supplier,
    required this.canEdit,
    required this.canPayment,
    required this.onTap,
    required this.onEdit,
    required this.onPayment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDebt = supplier.currentBalance > 0;
    final balanceColor = hasDebt ? AppColors.error : AppColors.success;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if ((supplier.phone ?? '').isNotEmpty)
                          Text(
                            'هاتف: ${supplier.phone}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!supplier.isActive)
                    const Text(
                      'معطّل',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: balanceColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasDebt
                          ? Icons.account_balance_wallet
                          : Icons.check_circle_outline,
                      color: balanceColor,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        hasDebt ? 'له مستحقات' : 'خالص',
                        style: TextStyle(
                          color: balanceColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      FormatUtils.formatMoneyAr(supplier.currentBalance),
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canPayment && hasDebt)
                    TextButton.icon(
                      onPressed: onPayment,
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('دفعة', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'تعديل',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================
// نموذج إضافة/تعديل مورد
// =====================================================
class _SupplierFormDialog extends StatefulWidget {
  final Supplier? supplier;

  const _SupplierFormDialog({this.supplier});

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _openingBalanceCtrl;

  bool _isActive = true;
  bool _saving = false;
  bool get _isEdit => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _phoneCtrl = TextEditingController(text: s?.phone ?? '');
    _addressCtrl = TextEditingController(text: s?.address ?? '');
    _notesCtrl = TextEditingController(text: s?.notes ?? '');
    _openingBalanceCtrl = TextEditingController(text: '0');
    _isActive = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _openingBalanceCtrl.dispose();
    super.dispose();
  }

  double _parseNum(String s) {
    final v = num.tryParse(s.trim());
    return (v ?? 0).toDouble();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final userId = context.read<AuthProvider>().currentUser!.id;
      final svc = ServiceLocator.suppliersService;

      final name = _nameCtrl.text.trim();
      final phone =
          _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim();
      final address =
          _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim();
      final notes =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

      if (_isEdit) {
        final existing = widget.supplier!;
        final updated = existing.copyWith(
          name: name,
          phone: Value(phone),
          address: Value(address),
          notes: Value(notes),
          isActive: _isActive,
          updatedAt: DateTime.now(),
        );
        await svc.updateSupplier(updated, userId);
        if (mounted) {
          showSuccessSnackBar(context, 'تم تحديث بيانات المورد');
          Navigator.of(context).pop(true);
        }
      } else {
        final openingBalance = _parseNum(_openingBalanceCtrl.text);
        final companion = SuppliersCompanion.insert(
          name: name,
          phone: Value(phone),
          address: Value(address),
          notes: Value(notes),
          openingBalance: Value(openingBalance),
          currentBalance: Value(openingBalance),
          isActive: Value(_isActive),
        );
        await svc.createSupplier(companion, userId);
        if (mounted) {
          showSuccessSnackBar(context, 'تم إنشاء المورد بنجاح');
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل الحفظ: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 700 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: _buildScaffold(_isEdit ? 'تعديل المورد' : 'مورد جديد'),
      ),
    );
  }

  Widget _buildScaffold(String title) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'إغلاق',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== معلومات أساسية =====
              const SectionHeader(
                title: 'معلومات أساسية',
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 8),
              _field(
                _nameCtrl,
                'اسم المورد *',
                'مثال: شركة الإمداد الغذائية',
                validator: (v) =>
                    Validators.required(v, fieldName: 'اسم المورد'),
              ),
              const SizedBox(height: 12),
              _field(
                _phoneCtrl,
                'رقم الهاتف',
                'اختياري',
                keyboardType: TextInputType.phone,
                validator: Validators.phone,
              ),
              const SizedBox(height: 12),
              _field(
                _addressCtrl,
                'العنوان',
                'اختياري',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _field(
                _notesCtrl,
                'ملاحظات',
                'اختياري',
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                title: const Text('المورد نشط'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // ===== مالية =====
              const SectionHeader(
                title: 'المعلومات المالية',
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 8),
              if (!_isEdit) ...[
                _field(
                  _openingBalanceCtrl,
                  'الرصيد الافتتاحي (مديونية سابقة للمورد)',
                  '0',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppColors.info),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'الرصيد الافتتاحي يمثل مديونية سابقة للمورد '
                          'سيتم إضافتها للرصيد الحالي (مستحقات عليك).',
                          style: TextStyle(fontSize: 11, color: AppColors.info),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 24),

              // ===== أزرار الحفظ =====
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                      label: const Text('إلغاء'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء المورد'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
      ),
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
    );
  }
}

// =====================================================
// نافذة تفاصيل المورد + كشف الحساب
// =====================================================
class _SupplierDetailDialog extends StatefulWidget {
  final Supplier supplier;
  final bool canPayment;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function() onPayment;

  const _SupplierDetailDialog({
    required this.supplier,
    required this.canPayment,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
    required this.onPayment,
  });

  @override
  State<_SupplierDetailDialog> createState() => _SupplierDetailDialogState();
}

class _SupplierDetailDialogState extends State<_SupplierDetailDialog> {
  Map<String, num>? _summary;
  List<Map<String, dynamic>>? _statement;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ServiceLocator.suppliersService;
      final results = await Future.wait([
        svc.getSummary(widget.supplier.id),
        svc.getStatement(widget.supplier.id),
      ]);
      _summary = results[0] as Map<String, num>;
      _statement = results[1] as List<Map<String, dynamic>>;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final hasDebt = (widget.supplier.currentBalance > 0);
    final balanceColor = hasDebt ? AppColors.error : AppColors.success;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 1000 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.supplier.name),
            actions: [
              IconButton(
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh),
                onPressed: _loadData,
              ),
              IconButton(
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          body: _loading
              ? const LoadingIndicator(message: 'جارٍ تحميل كشف الحساب...')
              : _error != null
                  ? EmptyState(
                      icon: Icons.error_outline,
                      message: 'فشل تحميل البيانات: $_error',
                      actionLabel: 'إعادة المحاولة',
                      onAction: _loadData,
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // ===== بطاقة المعلومات =====
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: AppColors.dividerLight,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.local_shipping,
                                            color: AppColors.primary),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          widget.supplier.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ),
                                      if (!widget.supplier.isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.textSecondaryLight
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'معطّل',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  AppColors.textSecondaryLight,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 4,
                                    children: [
                                      if ((widget.supplier.phone ?? '')
                                          .isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.phone_outlined,
                                                size: 16,
                                                color: AppColors
                                                    .textSecondaryLight),
                                            const SizedBox(width: 4),
                                            Text(widget.supplier.phone!),
                                          ],
                                        ),
                                      if ((widget.supplier.address ?? '')
                                          .isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                                Icons.location_on_outlined,
                                                size: 16,
                                                color: AppColors
                                                    .textSecondaryLight),
                                            const SizedBox(width: 4),
                                            Text(widget.supplier.address!),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if ((widget.supplier.notes ?? '')
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                              Icons.sticky_note_2_outlined,
                                              size: 16,
                                              color: AppColors.warning),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              widget.supplier.notes!,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ===== ملخص الحساب =====
                          SectionHeader(
                            title: 'ملخص الحساب',
                            icon: Icons.summarize_outlined,
                            action: widget.canPayment &&
                                    widget.supplier.isActive
                                ? FilledButton.tonalIcon(
                                    onPressed: () async {
                                      await _openPayment();
                                    },
                                    icon: const Icon(Icons.payments_outlined,
                                        size: 18),
                                    label: const Text('سداد دفعة'),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryGrid(balanceColor),
                          const SizedBox(height: 16),

                          // ===== كشف الحركة =====
                          const SectionHeader(
                            title: 'كشف الحركة',
                            icon: Icons.receipt_long_outlined,
                          ),
                          const SizedBox(height: 8),
                          _buildStatementTable(),
                          const SizedBox(height: 16),

                          // ===== أزرار الإجراءات =====
                          Row(
                            children: [
                              if (widget.canEdit)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      Navigator.of(context).pop(false);
                                      widget.onEdit();
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('تعديل'),
                                  ),
                                ),
                              if (widget.canEdit && widget.canDelete) ...[
                                const SizedBox(width: 12),
                              ],
                              if (widget.canDelete)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.error,
                                    ),
                                    onPressed: () async {
                                      Navigator.of(context).pop(false);
                                      widget.onDelete();
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('حذف'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Future<void> _openPayment() async {
    await widget.onPayment();
    // إعادة تحميل البيانات بعد إغلاق نافذة الدفع
    if (!mounted) return;
    await _loadData();
  }

  Widget _buildSummaryGrid(Color balanceColor) {
    final s = _summary;
    if (s == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 600 ? 4 : 2;
        final cells = <_SummaryCell>[
          _SummaryCell(
            label: 'الرصيد الافتتاحي',
            value: FormatUtils.formatMoneyAr(s['openingBalance'] ?? 0),
            color: AppColors.accent,
            icon: Icons.history,
          ),
          _SummaryCell(
            label: 'إجمالي الآجل',
            value: FormatUtils.formatMoneyAr(s['totalCredit'] ?? 0),
            color: AppColors.secondary,
            icon: Icons.trending_up,
          ),
          _SummaryCell(
            label: 'إجمالي المدفوع',
            value: FormatUtils.formatMoneyAr(s['totalPaid'] ?? 0),
            color: AppColors.success,
            icon: Icons.check_circle_outline,
          ),
          _SummaryCell(
            label: 'الرصيد الحالي',
            value: FormatUtils.formatMoneyAr(s['currentBalance'] ?? 0),
            color: balanceColor,
            icon: Icons.account_balance_wallet_outlined,
          ),
        ];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cells
              .map((cell) => SizedBox(
                    width: (c.maxWidth - 8 * (cols - 1)) / cols,
                    child: cell,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildStatementTable() {
    final entries = _statement ?? [];
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          message: 'لا توجد حركات سابقة لهذا المورد',
        ),
      );
    }
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.dividerLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 12,
          headingRowColor: WidgetStateProperty.all(
            AppColors.primary.withValues(alpha: 0.06),
          ),
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('الوصف')),
            DataColumn(label: Text('مدين'), numeric: true),
            DataColumn(label: Text('دائن'), numeric: true),
            DataColumn(label: Text('الرصيد'), numeric: true),
          ],
          rows: entries.map((e) {
            final DateTime date = e['date'] as DateTime;
            final num debit = (e['debit'] as num?) ?? 0;
            final num credit = (e['credit'] as num?) ?? 0;
            final num balance = (e['balance'] as num?) ?? 0;
            final String desc = (e['description'] as String?) ?? '';
            final String type = (e['type'] as String?) ?? '';
            final Color rowColor;
            IconData leading;
            switch (type) {
              case 'OPENING':
                rowColor = AppColors.accent;
                leading = Icons.history;
                break;
              case 'PURCHASE':
                rowColor = AppColors.secondary;
                leading = Icons.shopping_cart_outlined;
                break;
              case 'PAYMENT':
                rowColor = AppColors.success;
                leading = Icons.payments_outlined;
                break;
              default:
                rowColor = AppColors.textSecondaryLight;
                leading = Icons.circle_outlined;
            }
            return DataRow(
              cells: [
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(leading, size: 14, color: rowColor),
                    const SizedBox(width: 4),
                    Text(
                      FormatUtils.formatDateTime(date),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                )),
                DataCell(
                  Text(desc, style: const TextStyle(fontSize: 12)),
                ),
                DataCell(
                  Text(
                    debit > 0 ? FormatUtils.formatMoneyAr(debit) : '—',
                    style: TextStyle(
                      fontSize: 12,
                      color: debit > 0 ? AppColors.success : null,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    credit > 0 ? FormatUtils.formatMoneyAr(credit) : '—',
                    style: TextStyle(
                      fontSize: 12,
                      color: credit > 0 ? AppColors.secondary : null,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    FormatUtils.formatMoneyAr(balance),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: balance > 0 ? AppColors.error : AppColors.success,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// نافذة سداد دفعة للمورد
// =====================================================
class _PaymentDialog extends StatefulWidget {
  final Supplier supplier;

  const _PaymentDialog({required this.supplier});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;

  String _paymentMethod = PaymentType.cash;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    // اقتراح سداد كامل للمديونية الحالية
    if (widget.supplier.currentBalance > 0) {
      _amountCtrl.text = _formatNum(widget.supplier.currentBalance);
    }
  }

  String _formatNum(num v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double _parseNum(String s) {
    final v = num.tryParse(s.trim());
    return (v ?? 0).toDouble();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final userId = context.read<AuthProvider>().currentUser!.id;
      final amount = _parseNum(_amountCtrl.text);
      await ServiceLocator.suppliersService.paySupplier(
        supplierId: widget.supplier.id,
        amount: amount,
        userId: userId,
        paymentMethod: _paymentMethod,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) {
        showSuccessSnackBar(context, 'تم تسجيل الدفعة بنجاح');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تسجيل الدفعة: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 600;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 500 : double.infinity,
        ),
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.payments,
                            color: AppColors.success),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'سداد دفعة للمورد',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.supplier.name,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  // عرض المديونية الحالية
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (widget.supplier.currentBalance > 0
                              ? AppColors.error
                              : AppColors.success)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.supplier.currentBalance > 0
                              ? Icons.account_balance_wallet
                              : Icons.check_circle_outline,
                          color: widget.supplier.currentBalance > 0
                              ? AppColors.error
                              : AppColors.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'الرصيد الحالي',
                            style:
                                TextStyle(color: AppColors.textSecondaryLight),
                          ),
                        ),
                        Text(
                          FormatUtils.formatMoneyAr(
                              widget.supplier.currentBalance),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: widget.supplier.currentBalance > 0
                                ? AppColors.error
                                : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ المدفوع *',
                      hintText: '0',
                      prefixIcon: Icon(Icons.attach_money),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                    ],
                    validator: (v) =>
                        Validators.positiveNonZero(v, fieldName: 'المبلغ'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'طريقة الدفع',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PaymentType.cash,
                        child: Text('نقدي'),
                      ),
                      DropdownMenuItem(
                        value: 'CARD',
                        child: Text('بطاقة'),
                      ),
                      DropdownMenuItem(
                        value: 'BANK',
                        child: Text('تحويل بنكي'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _paymentMethod = v);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      hintText: 'اختياري',
                      prefixIcon: Icon(Icons.note_outlined),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close),
                          label: const Text('إلغاء'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: const Text('تأكيد السداد'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
