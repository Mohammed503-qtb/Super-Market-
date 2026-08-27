import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة قائمة فواتير المبيعات
/// ----------------------------
/// - تعرض آخر فواتير البيع مع إمكانية البحث برقم الفاتورة وفلترة بالفترة
///   (منتقي تاريخ "من" و"إلى").
/// - كل صف يعرض: رقم الفاتورة، التاريخ والوقت، اسم العميل (أو "عميل نقدي")،
///   الإجمالي، المدفوع، المتبقي (بالأحمر عند وجود دين)، نوع الدفع، والحالة.
/// - النقر على فاتورة يفتح نافذة تفاصيل تعرض بيانات الفاتورة الكاملة + جدول
///   الأصناف (المنتج، الكمية، سعر الوحدة، التكلفة [عند توفّر صلاحية تقارير
///   الأرباح]، الإجمالي، ربح البند).
/// - بطاقات إحصائية في الأعلى: عدد الفواتير، إجمالي المبيعات، إجمالي الديون،
///   مبيعات نقدي.
/// - التخطيط متجاوب: شبكة صفوف على الشاشات العريضة (≥900px)، قائمة عمودية
///   على الهواتف. النصوص عربية RTL.
class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key});

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  // ===== Controllers =====
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ===== Data =====
  final List<Sale> _sales = [];
  final Map<int, Customer> _customersMap = {};
  final Map<int, Product> _productsMap = {};
  final Map<int, User> _usersMap = {};

  // ===== Filters =====
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchQuery = '';

  // ===== State =====
  bool _isLoading = true;
  bool _canViewCost = false;
  bool _canDelete = false;

  // =====================
  // دورة الحياة
  // =====================

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _canViewCost = auth.hasPermission(PermissionCodes.reportsProfit);
    _canDelete = auth.hasPermission(PermissionCodes.salesDelete);
    _loadAll();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // =====================
  // تحميل البيانات
  // =====================

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final db = ServiceLocator.database;
      // حمّل الخرائط المساعدة (العملاء/المنتجات/المستخدمين) بشكل متوازٍ
      final results = await Future.wait([
        _loadSales(),
        db.customerDao.getAll(),
        db.productDao.getAll(),
        db.userDao.getAll(),
      ]);
      _customersMap
        ..clear()
        ..addEntries(
            (results[1] as List<Customer>).map((c) => MapEntry(c.id, c)));
      _productsMap
        ..clear()
        ..addEntries(
            (results[2] as List<Product>).map((p) => MapEntry(p.id, p)));
      _usersMap
        ..clear()
        ..addEntries((results[3] as List<User>).map((u) => MapEntry(u.id, u)));
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل بيانات المبيعات: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSales() async {
    final db = ServiceLocator.database;
    List<Sale> result;
    if (_startDate != null && _endDate != null) {
      // getByDateRange يستخدم isBetweenValues — نمدّ النهاية لنهاية اليوم
      final endInclusive =
          DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      result = await db.saleDao.getByDateRange(_startDate!, endInclusive);
    } else {
      // عند وجود بحث برقم الفاتورة نرفع الحد ليصل البحث للسجلات القديمة
      final limit = _searchQuery.trim().isNotEmpty ? 500 : 100;
      result = await db.saleDao.getRecent(limit: limit);
    }
    // فلترة بحث برقم الفاتورة (بحث جزئي غير حساس لحالة الأحرف)
    final q = _searchQuery.trim();
    if (q.isNotEmpty) {
      final lower = q.toLowerCase();
      result = result
          .where((s) => s.invoiceNumber.toLowerCase().contains(lower))
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _sales
        ..clear()
        ..addAll(result);
    });
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () {
        _searchQuery = _searchController.text;
        _refreshSales();
      },
    );
  }

  Future<void> _refreshSales() async {
    try {
      await _loadSales();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحديث القائمة: $e');
    }
  }

  // =====================
  // منتقي التاريخ
  // =====================

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initial = isStart ? (_startDate ?? now) : (_endDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      helpText: isStart ? 'اختر تاريخ البداية' : 'اختر تاريخ النهاية',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
    await _refreshSales();
  }

  void _clearFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _searchController.clear();
      _searchQuery = '';
    });
    _refreshSales();
  }

  // =====================
  // إحصائيات سريعة (محسوبة من القائمة المحمّلة)
  // =====================

  int get _totalCount => _sales.length;

  num get _totalSalesAmount => _sales
      .where((s) => s.status == InvoiceStatus.completed)
      .fold<num>(0, (sum, s) => sum + s.total);

  num get _totalRemaining => _sales
      .where(
          (s) => s.status == InvoiceStatus.completed && s.remainingAmount > 0)
      .fold<num>(0, (sum, s) => sum + s.remainingAmount);

  num get _totalCashSales => _sales
      .where((s) =>
          s.status == InvoiceStatus.completed &&
          s.paymentType == PaymentType.cash)
      .fold<num>(0, (sum, s) => sum + s.total);

  // =====================
  // فتح نافذة التفاصيل
  // =====================

  Future<void> _openDetail(Sale sale) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SaleDetailDialog(
        sale: sale,
        customersMap: _customersMap,
        productsMap: _productsMap,
        usersMap: _usersMap,
        canViewCost: _canViewCost,
        canDelete: _canDelete,
      ),
    );
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المبيعات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildStatsRow()),
            SliverToBoxAdapter(child: _buildFilters()),
            if (_isLoading && _sales.isEmpty)
              const SliverFillRemaining(
                child: LoadingIndicator(message: 'جارٍ تحميل الفواتير...'),
              )
            else if (_sales.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: _searchQuery.isNotEmpty ||
                          _startDate != null ||
                          _endDate != null
                      ? 'لا توجد فواتير مطابقة للبحث'
                      : 'لا توجد فواتير بعد',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _SaleRow(
                      sale: _sales[i],
                      customerName: _customerName(_sales[i]),
                      onTap: () => _openDetail(_sales[i]),
                    ),
                    childCount: _sales.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _customerName(Sale sale) {
    if (sale.customerId == null) return 'عميل نقدي';
    final c = _customersMap[sale.customerId!];
    if (c == null) return 'عميل محذوف';
    return c.name;
  }

  Widget _buildStatsRow() {
    return SizedBox(
      height: 116,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        children: [
          StatCard(
            title: 'عدد الفواتير',
            value: _totalCount.toString(),
            icon: Icons.receipt_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          StatCard(
            title: 'إجمالي المبيعات',
            value: FormatUtils.formatMoneyAr(_totalSalesAmount),
            icon: Icons.payments_outlined,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          StatCard(
            title: 'إجمالي الديون',
            value: FormatUtils.formatMoneyAr(_totalRemaining),
            icon: Icons.account_balance_outlined,
            color: AppColors.error,
          ),
          const SizedBox(width: 8),
          StatCard(
            title: 'مبيعات نقدي',
            value: FormatUtils.formatMoneyAr(_totalCashSales),
            icon: Icons.south_west,
            color: AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final hasFilters =
        _startDate != null || _endDate != null || _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SearchField(
                controller: _searchController,
                hintText: 'بحث برقم الفاتورة...',
                onChanged: _onSearchChanged,
                onClear: () {
                  _searchQuery = '';
                  _refreshSales();
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _dateButton(
                      label: _startDate != null
                          ? FormatUtils.formatDate(_startDate!)
                          : 'من تاريخ',
                      onTap: () => _pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _dateButton(
                      label: _endDate != null
                          ? FormatUtils.formatDate(_endDate!)
                          : 'إلى تاريخ',
                      onTap: () => _pickDate(false),
                    ),
                  ),
                  if (hasFilters) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'مسح الفلاتر',
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      onPressed: _clearFilters,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateButton({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.date_range, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// صف فاتورة البيع
// =====================================================================

class _SaleRow extends StatelessWidget {
  final Sale sale;
  final String customerName;
  final VoidCallback onTap;

  const _SaleRow({
    required this.sale,
    required this.customerName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasRemaining = sale.remainingAmount > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الصف العلوي: رقم الفاتورة + التاريخ + الحالة
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_outlined,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          sale.invoiceNumber,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      FormatUtils.formatDateTime(sale.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusBadge(status: sale.status),
                ],
              ),
              const SizedBox(height: 10),
              // الصف الأوسط: اسم العميل + نوع الدفع
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: AppColors.textSecondaryLight),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      customerName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _PaymentTypeChip(paymentType: sale.paymentType),
                ],
              ),
              const Divider(height: 16),
              // الصف السفلي: الإجمالي / المدفوع / المتبقي
              Row(
                children: [
                  Expanded(
                    child: _moneyColumn(
                      context,
                      label: 'الإجمالي',
                      value: FormatUtils.formatMoneyAr(sale.total),
                      color: AppColors.textPrimaryLight,
                    ),
                  ),
                  Expanded(
                    child: _moneyColumn(
                      context,
                      label: 'المدفوع',
                      value: FormatUtils.formatMoneyAr(sale.paidAmount),
                      color: AppColors.success,
                    ),
                  ),
                  Expanded(
                    child: _moneyColumn(
                      context,
                      label: 'المتبقي',
                      value: FormatUtils.formatMoneyAr(sale.remainingAmount),
                      color: hasRemaining ? AppColors.error : null,
                      bold: hasRemaining,
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

  Widget _moneyColumn(
    BuildContext context, {
    required String label,
    required String value,
    Color? color,
    bool bold = false,
  }) {
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          color: color,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondaryLight,
                fontSize: 11,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: valueStyle,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// =====================================================================
// شارة نوع الدفع
// =====================================================================

class _PaymentTypeChip extends StatelessWidget {
  final String paymentType;

  const _PaymentTypeChip({required this.paymentType});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _meta();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  (String, Color) _meta() {
    switch (paymentType) {
      case PaymentType.cash:
        return ('نقدي', AppColors.success);
      case PaymentType.credit:
        return ('آجل', AppColors.warning);
      case PaymentType.mixed:
        return ('مختلط', AppColors.info);
      default:
        return (paymentType, AppColors.textSecondaryLight);
    }
  }
}

// =====================================================================
// نافذة تفاصيل الفاتورة
// =====================================================================

class _SaleDetailDialog extends StatelessWidget {
  final Sale sale;
  final Map<int, Customer> customersMap;
  final Map<int, Product> productsMap;
  final Map<int, User> usersMap;
  final bool canViewCost;
  final bool canDelete;

  const _SaleDetailDialog({
    required this.sale,
    required this.customersMap,
    required this.productsMap,
    required this.usersMap,
    required this.canViewCost,
    required this.canDelete,
  });

  String get _customerName {
    if (sale.customerId == null) return 'عميل نقدي';
    final c = customersMap[sale.customerId!];
    return c?.name ?? 'عميل محذوف';
  }

  String get _userName {
    final u = usersMap[sale.userId];
    return u?.displayName ?? 'مستخدم محذوف';
  }

  String get _paymentLabel {
    switch (sale.paymentType) {
      case PaymentType.cash:
        return 'نقدي';
      case PaymentType.credit:
        return 'آجل';
      case PaymentType.mixed:
        return 'مختلط';
      default:
        return sale.paymentType;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 900,
        height: MediaQuery.of(context).size.height * 0.88,
        child: Scaffold(
          appBar: AppBar(
            title: Text('فاتورة ${sale.invoiceNumber}'),
            actions: [
              IconButton(
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: FutureBuilder<List<SaleItem>>(
            future: ServiceLocator.database.saleDao.getItems(sale.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingIndicator(
                    message: 'جارٍ تحميل أصناف الفاتورة...');
              }
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  message: 'فشل تحميل الأصناف: ${snapshot.error}',
                );
              }
              final items = snapshot.data ?? const <SaleItem>[];
              return _DetailBody(
                sale: sale,
                items: items,
                productsMap: productsMap,
                customerName: _customerName,
                userName: _userName,
                paymentLabel: _paymentLabel,
                canViewCost: canViewCost,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Sale sale;
  final List<SaleItem> items;
  final Map<int, Product> productsMap;
  final String customerName;
  final String userName;
  final String paymentLabel;
  final bool canViewCost;

  const _DetailBody({
    required this.sale,
    required this.items,
    required this.productsMap,
    required this.customerName,
    required this.userName,
    required this.paymentLabel,
    required this.canViewCost,
  });

  num get _itemsTotalCost =>
      items.fold<num>(0, (s, i) => s + (i.costPrice * i.quantity));
  num get _invoiceProfit =>
      sale.total - _itemsTotalCost; // ربح الفاتورة بعد الخصم والضريبة

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderCard(context),
          const SizedBox(height: 12),
          _buildItemsCard(context),
          const SizedBox(height: 12),
          _buildTotalsCard(context),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    sale.invoiceNumber,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                StatusBadge(status: sale.status),
              ],
            ),
            const Divider(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 0,
              children: [
                _infoChip(context,
                    icon: Icons.calendar_today_outlined,
                    label: 'التاريخ',
                    value: FormatUtils.formatDateTime(sale.createdAt)),
                _infoChip(context,
                    icon: Icons.person_outline,
                    label: 'العميل',
                    value: customerName),
                _infoChip(context,
                    icon: Icons.badge_outlined,
                    label: 'البائع',
                    value: userName),
                _infoChip(context,
                    icon: Icons.payments_outlined,
                    label: 'نوع الدفع',
                    value: paymentLabel),
              ],
            ),
            if (sale.notes != null && sale.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.info.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sticky_note_2_outlined,
                        size: 18, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ملاحظات',
                            style: TextStyle(
                              color: AppColors.info,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(sale.notes!),
                        ],
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

  Widget _infoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondaryLight),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryLight,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'أصناف الفاتورة',
              icon: Icons.list_alt_outlined,
              action: Text(
                '${items.length} صنف',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            // عنوان الجدول
            _itemsHeaderRow(context),
            const Divider(height: 1),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyState(
                  icon: Icons.inbox_outlined,
                  message: 'لا توجد أصناف في هذه الفاتورة',
                ),
              )
            else
              ...items.map((i) => _itemRow(context, i)),
          ],
        ),
      ),
    );
  }

  Widget _itemsHeaderRow(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondaryLight,
          fontWeight: FontWeight.bold,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // المنتج
          Expanded(
            flex: 4,
            child: Text('المنتج', style: headerStyle),
          ),
          // الكمية
          SizedBox(
            width: 60,
            child:
                Text('الكمية', style: headerStyle, textAlign: TextAlign.center),
          ),
          // سعر الوحدة
          SizedBox(
            width: 80,
            child: Text('سعر الوحدة',
                style: headerStyle, textAlign: TextAlign.center),
          ),
          // التكلفة (اختياري)
          if (canViewCost)
            SizedBox(
              width: 80,
              child: Text('التكلفة',
                  style: headerStyle, textAlign: TextAlign.center),
            ),
          // الإجمالي
          SizedBox(
            width: 90,
            child: Text('الإجمالي',
                style: headerStyle, textAlign: TextAlign.center),
          ),
          // الربح (اختياري)
          if (canViewCost)
            SizedBox(
              width: 80,
              child: Text('الربح',
                  style: headerStyle, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, SaleItem item) {
    final productName = productsMap[item.productId]?.name ?? 'منتج محذوف';
    final lineProfit = item.total - (item.costPrice * item.quantity);
    final profitColor = lineProfit >= 0 ? AppColors.success : AppColors.error;
    final valueStyle = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              productName,
              style: valueStyle?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              FormatUtils.formatQuantity(item.quantity),
              style: valueStyle,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              FormatUtils.formatMoneyAr(item.unitPrice),
              style: valueStyle,
              textAlign: TextAlign.center,
            ),
          ),
          if (canViewCost)
            SizedBox(
              width: 80,
              child: Text(
                FormatUtils.formatMoneyAr(item.costPrice),
                style: valueStyle,
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: 90,
            child: Text(
              FormatUtils.formatMoneyAr(item.total),
              style: valueStyle?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          if (canViewCost)
            SizedBox(
              width: 80,
              child: Text(
                FormatUtils.formatMoneyAr(lineProfit),
                style: valueStyle?.copyWith(
                  color: profitColor,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            InfoRow(
              label: 'المجموع الفرعي',
              value: FormatUtils.formatMoneyAr(sale.subtotal),
            ),
            if (sale.discount > 0)
              InfoRow(
                label: 'الخصم',
                value: '- ${FormatUtils.formatMoneyAr(sale.discount)}',
                valueColor: AppColors.error,
              ),
            if (sale.tax > 0)
              InfoRow(
                label: 'الضريبة',
                value: '+ ${FormatUtils.formatMoneyAr(sale.tax)}',
                valueColor: AppColors.info,
              ),
            const Divider(),
            InfoRow(
              label: 'الإجمالي',
              value: FormatUtils.formatMoneyAr(sale.total),
              icon: Icons.calculate_outlined,
            ),
            InfoRow(
              label: 'المدفوع',
              value: FormatUtils.formatMoneyAr(sale.paidAmount),
              icon: Icons.check_circle_outline,
              valueColor: AppColors.success,
            ),
            if (sale.remainingAmount > 0)
              InfoRow(
                label: 'المتبقي (دين)',
                value: FormatUtils.formatMoneyAr(sale.remainingAmount),
                icon: Icons.error_outline,
                valueColor: AppColors.error,
              ),
            if (canViewCost) ...[
              const Divider(),
              InfoRow(
                label: 'إجمالي التكلفة',
                value: FormatUtils.formatMoneyAr(_itemsTotalCost),
                icon: Icons.savings_outlined,
                valueColor: AppColors.textSecondaryLight,
              ),
              InfoRow(
                label: 'صافي الربح',
                value: FormatUtils.formatMoneyAr(_invoiceProfit),
                icon: Icons.trending_up,
                valueColor:
                    _invoiceProfit >= 0 ? AppColors.success : AppColors.error,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
