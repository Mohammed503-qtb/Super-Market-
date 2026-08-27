import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة إدارة العملاء
/// -------------------
/// - قائمة العملاء مع بحث فوري (الاسم / الهاتف).
/// - كل صف يعرض: الاسم، الهاتف، الرصيد الحالي (أحمر إذا عليه دين، أخضر إذا
///   معدوم)، حد الائتمان إن وُجد، وشارة المعطّل.
/// - زر "عميل جديد" (FAB) يتطلب صلاحية customers.create.
/// - تعديل/حذف عميل، الحذف مرفوض إذا كان له فواتير بيع (الخدمة ترمي
///   OperationNotAllowedException).
/// - نافذة تفاصيل العميل تعرض ملخص الحساب (افتتاحي / إجمالي الآجل /
///   إجمالي المدفوع / الرصيد الحالي) + كشف حركة مفصل + زر "استلام دفعة".
/// - صلاحيات: create/edit/delete/payment تتحكم في ظهور الأزرار.
/// - تخطيط متجاوب: شبكة بطاقات على الشاشات العريضة، قائمة على الهواتف.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  // ===== Controllers =====
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ===== Data =====
  final List<Customer> _customers = [];

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
    _refreshCustomers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _initPermissions() {
    final auth = context.read<AuthProvider>();
    _canCreate = auth.hasPermission(PermissionCodes.customersCreate);
    _canEdit = auth.hasPermission(PermissionCodes.customersEdit);
    _canDelete = auth.hasPermission(PermissionCodes.customersDelete);
    _canPayment = auth.hasPermission(PermissionCodes.customersPayment);
  }

  Future<void> _refreshCustomers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final db = ServiceLocator.database;
      List<Customer> result;
      if (_searchQuery.trim().isNotEmpty) {
        result = await db.customerDao.search(_searchQuery.trim());
      } else {
        result = await db.customerDao.getAll();
      }
      _customers
        ..clear()
        ..addAll(result);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل العملاء: $e');
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
        _refreshCustomers();
      },
    );
  }

  // =====================
  // إحصائيات سريعة
  // =====================

  int get _customersWithDebtCount =>
      _customers.where((c) => c.currentBalance > 0).length;
  num get _totalDebts => _customers.fold<num>(
      0, (s, c) => s + (c.currentBalance > 0 ? c.currentBalance : 0));

  // =====================
  // فتح النماذج
  // =====================

  Future<void> _openCustomerForm({Customer? customer}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CustomerFormDialog(customer: customer),
    );
    if (result == true) {
      await _refreshCustomers();
    }
  }

  Future<void> _openCustomerDetail(Customer customer) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CustomerDetailDialog(
        customer: customer,
        canPayment: _canPayment,
        canEdit: _canEdit,
        canDelete: _canDelete,
        onEdit: () => _openCustomerForm(customer: customer),
        onDelete: () => _confirmDelete(customer),
        onPayment: () => _openPaymentDialog(customer),
      ),
    );
    if (result == true) {
      await _refreshCustomers();
    }
  }

  Future<void> _openPaymentDialog(Customer customer) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(customer: customer),
    );
    if (result == true) {
      // أعد فتح تفاصيل العميل لإظهار التحديث؟ نكتفي بإغلاق وفتح جديد.
    }
  }

  // =====================
  // حذف العميل
  // =====================

  Future<void> _confirmDelete(Customer customer) async {
    // نلتقط الـ userId قبل أي async gap لتفادي استخدام BuildContext بعد await.
    final userId = context.read<AuthProvider>().currentUser!.id;
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف العميل',
      message: 'هل أنت متأكد من حذف "${customer.name}"؟ '
          'لا يمكن الحذف إذا كان له فواتير بيع.',
      confirmText: 'حذف',
      isDanger: true,
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await ServiceLocator.customersService.deleteCustomer(customer.id, userId);
      if (mounted) {
        showSuccessSnackBar(context, 'تم حذف العميل بنجاح');
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
        title: const Text('العملاء'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCustomers,
          ),
        ],
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openCustomerForm(),
              icon: const Icon(Icons.person_add),
              label: const Text('عميل جديد'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refreshCustomers,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildSearchAndStats()),
            if (_isLoading && _customers.isEmpty)
              const SliverFillRemaining(
                child: LoadingIndicator(message: 'جارٍ تحميل العملاء...'),
              )
            else if (_customers.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.people_outline,
                  message: _searchQuery.isNotEmpty
                      ? 'لا يوجد عملاء مطابقون لبحثك'
                      : 'لا يوجد عملاء بعد',
                  actionLabel: _canCreate ? 'إضافة عميل' : null,
                  onAction: _canCreate ? () => _openCustomerForm() : null,
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
                          (context, i) => _CustomerCard(
                            customer: _customers[i],
                            canEdit: _canEdit,
                            canPayment: _canPayment,
                            onTap: () => _openCustomerDetail(_customers[i]),
                            onEdit: () =>
                                _openCustomerForm(customer: _customers[i]),
                            onPayment: () => _openPaymentDialog(_customers[i]),
                          ),
                          childCount: _customers.length,
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _CustomerTile(
                          customer: _customers[i],
                          canEdit: _canEdit,
                          canPayment: _canPayment,
                          onTap: () => _openCustomerDetail(_customers[i]),
                          onEdit: () =>
                              _openCustomerForm(customer: _customers[i]),
                          onPayment: () => _openPaymentDialog(_customers[i]),
                        ),
                        childCount: _customers.length,
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
              _refreshCustomers();
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _miniStat(
                  'إجمالي العملاء',
                  '${_customers.length}',
                  Icons.people_alt_outlined,
                  AppColors.primary,
                ),
                _miniStat(
                  'إجمالي الديون',
                  FormatUtils.formatMoneyAr(_totalDebts),
                  Icons.account_balance_wallet_outlined,
                  AppColors.error,
                ),
                _miniStat(
                  'عملاء عليهم دين',
                  '$_customersWithDebtCount',
                  Icons.trending_down,
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
// بطاقة العميل (للشاشات العريضة)
// =====================================================
class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final bool canEdit;
  final bool canPayment;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPayment;

  const _CustomerCard({
    required this.customer,
    required this.canEdit,
    required this.canPayment,
    required this.onTap,
    required this.onEdit,
    required this.onPayment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDebt = customer.currentBalance > 0;
    final balanceColor = hasDebt ? AppColors.error : AppColors.success;
    final exceededLimit = customer.creditLimit != null &&
        customer.creditLimit! > 0 &&
        customer.currentBalance > customer.creditLimit!;

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
                      Icons.person,
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
                          customer.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if ((customer.phone ?? '').isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.phone_outlined,
                                  size: 14,
                                  color: AppColors.textSecondaryLight),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  customer.phone!,
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
                  if (!customer.isActive)
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
                      hasDebt ? 'عليه دين' : 'خالص',
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      FormatUtils.formatMoneyAr(customer.currentBalance),
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (customer.creditLimit != null &&
                  customer.creditLimit! > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        size: 14, color: AppColors.textSecondaryLight),
                    const SizedBox(width: 4),
                    Text(
                      'حد الائتمان: ${FormatUtils.formatMoneyAr(customer.creditLimit!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: exceededLimit
                            ? AppColors.error
                            : AppColors.textSecondaryLight,
                        fontWeight:
                            exceededLimit ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (exceededLimit) ...[
                      const SizedBox(width: 4),
                      const Text(
                        '⚠ تجاوز',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canPayment && hasDebt)
                    TextButton.icon(
                      onPressed: onPayment,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('استلام دفعة'),
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
// عنصر قائمة العميل (للهواتف)
// =====================================================
class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final bool canEdit;
  final bool canPayment;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPayment;

  const _CustomerTile({
    required this.customer,
    required this.canEdit,
    required this.canPayment,
    required this.onTap,
    required this.onEdit,
    required this.onPayment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDebt = customer.currentBalance > 0;
    final balanceColor = hasDebt ? AppColors.error : AppColors.success;
    final exceededLimit = customer.creditLimit != null &&
        customer.creditLimit! > 0 &&
        customer.currentBalance > customer.creditLimit!;

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
                          customer.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if ((customer.phone ?? '').isNotEmpty)
                          Text(
                            'هاتف: ${customer.phone}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!customer.isActive)
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
                        hasDebt ? 'عليه دين' : 'خالص',
                        style: TextStyle(
                          color: balanceColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      FormatUtils.formatMoneyAr(customer.currentBalance),
                      style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (customer.creditLimit != null &&
                  customer.creditLimit! > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'حد الائتمان: ${FormatUtils.formatMoneyAr(customer.creditLimit!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: exceededLimit
                            ? AppColors.error
                            : AppColors.textSecondaryLight,
                        fontWeight:
                            exceededLimit ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (exceededLimit)
                      const Text(
                        ' ⚠ تجاوز',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
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
// نموذج إضافة/تعديل عميل
// =====================================================
class _CustomerFormDialog extends StatefulWidget {
  final Customer? customer;

  const _CustomerFormDialog({this.customer});

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _openingBalanceCtrl;
  late final TextEditingController _creditLimitCtrl;

  bool _isActive = true;
  bool _saving = false;
  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _addressCtrl = TextEditingController(text: c?.address ?? '');
    _notesCtrl = TextEditingController(text: c?.notes ?? '');
    _openingBalanceCtrl = TextEditingController(text: '0');
    _creditLimitCtrl = TextEditingController(
      text: c?.creditLimit != null ? _formatNum(c!.creditLimit!) : '',
    );
    _isActive = c?.isActive ?? true;
  }

  String _formatNum(num v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _openingBalanceCtrl.dispose();
    _creditLimitCtrl.dispose();
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
      final svc = ServiceLocator.customersService;

      final name = _nameCtrl.text.trim();
      final phone =
          _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim();
      final address =
          _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim();
      final notes =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
      final creditLimitText = _creditLimitCtrl.text.trim();
      final creditLimit =
          creditLimitText.isEmpty ? null : _parseNum(creditLimitText);

      if (_isEdit) {
        final existing = widget.customer!;
        final updated = existing.copyWith(
          name: name,
          phone: Value(phone),
          address: Value(address),
          notes: Value(notes),
          creditLimit: Value(creditLimit),
          isActive: _isActive,
          updatedAt: DateTime.now(),
        );
        await svc.updateCustomer(updated, userId);
        if (mounted) {
          showSuccessSnackBar(context, 'تم تحديث بيانات العميل');
          Navigator.of(context).pop(true);
        }
      } else {
        final openingBalance = _parseNum(_openingBalanceCtrl.text);
        final companion = CustomersCompanion.insert(
          name: name,
          phone: Value(phone),
          address: Value(address),
          notes: Value(notes),
          openingBalance: Value(openingBalance),
          currentBalance: Value(openingBalance),
          creditLimit: Value(creditLimit),
          isActive: Value(_isActive),
        );
        await svc.createCustomer(companion, userId);
        if (mounted) {
          showSuccessSnackBar(context, 'تم إنشاء العميل بنجاح');
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
        child: _buildScaffold(_isEdit ? 'تعديل العميل' : 'عميل جديد'),
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
                'اسم العميل *',
                'مثال: محمد أحمد',
                validator: (v) =>
                    Validators.required(v, fieldName: 'اسم العميل'),
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
                title: const Text('العميل نشط'),
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
                  'الرصيد الافتتاحي (مديونية سابقة)',
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
                          'الرصيد الافتتاحي يمثل مديونية سابقة على العميل '
                          'سيتم إضافتها للرصيد الحالي.',
                          style: TextStyle(fontSize: 11, color: AppColors.info),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _field(
                _creditLimitCtrl,
                'حد الائتمان الأقصى (اختياري)',
                'اتركه فارغاً لإلغاء الحد',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
              ),
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
                      label: Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء العميل'),
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
// نافذة تفاصيل العميل + كشف الحساب
// =====================================================
class _CustomerDetailDialog extends StatefulWidget {
  final Customer customer;
  final bool canPayment;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function() onPayment;

  const _CustomerDetailDialog({
    required this.customer,
    required this.canPayment,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
    required this.onPayment,
  });

  @override
  State<_CustomerDetailDialog> createState() => _CustomerDetailDialogState();
}

class _CustomerDetailDialogState extends State<_CustomerDetailDialog> {
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
      final svc = ServiceLocator.customersService;
      final results = await Future.wait([
        svc.getSummary(widget.customer.id),
        svc.getStatement(widget.customer.id),
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
    final hasDebt = (widget.customer.currentBalance > 0);
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
            title: Text(widget.customer.name),
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
                                        child: const Icon(Icons.person,
                                            color: AppColors.primary),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          widget.customer.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ),
                                      if (!widget.customer.isActive)
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
                                      if ((widget.customer.phone ?? '')
                                          .isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.phone_outlined,
                                                size: 16,
                                                color: AppColors
                                                    .textSecondaryLight),
                                            const SizedBox(width: 4),
                                            Text(widget.customer.phone!),
                                          ],
                                        ),
                                      if ((widget.customer.address ?? '')
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
                                            Text(widget.customer.address!),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if ((widget.customer.notes ?? '')
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
                                              widget.customer.notes!,
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
                                    widget.customer.isActive
                                ? FilledButton.tonalIcon(
                                    onPressed: () async {
                                      await _openPayment();
                                    },
                                    icon: const Icon(Icons.payments_outlined,
                                        size: 18),
                                    label: const Text('استلام دفعة'),
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
          message: 'لا توجد حركات سابقة لهذا العميل',
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
              case 'SALE':
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
                      color: debit > 0 ? AppColors.secondary : null,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    credit > 0 ? FormatUtils.formatMoneyAr(credit) : '—',
                    style: TextStyle(
                      fontSize: 12,
                      color: credit > 0 ? AppColors.success : null,
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
// نافذة استلام دفعة
// =====================================================
class _PaymentDialog extends StatefulWidget {
  final Customer customer;

  const _PaymentDialog({required this.customer});

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
    if (widget.customer.currentBalance > 0) {
      _amountCtrl.text = _formatNum(widget.customer.currentBalance);
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
      await ServiceLocator.customersService.receivePayment(
        customerId: widget.customer.id,
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
                              'استلام دفعة',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.customer.name,
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
                      color: (widget.customer.currentBalance > 0
                              ? AppColors.error
                              : AppColors.success)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.customer.currentBalance > 0
                              ? Icons.account_balance_wallet
                              : Icons.check_circle_outline,
                          color: widget.customer.currentBalance > 0
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
                              widget.customer.currentBalance),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: widget.customer.currentBalance > 0
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
                      labelText: 'المبلغ المسدد *',
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
