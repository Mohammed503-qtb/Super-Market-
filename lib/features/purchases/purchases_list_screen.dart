import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة قائمة فواتير المشتريات
/// ----------------------------
/// - تعرض آخر فواتير الشراء مع إمكانية البحث برقم الفاتورة وفلترة بالفترة
///   (منتقي تاريخ "من" و"إلى").
/// - كل صف يعرض: رقم الفاتورة، التاريخ والوقت، اسم المورد (أو "مورد نقدي")،
///   الإجمالي، المدفوع، المتبقي (بالأحمر عند وجود دين للمورد)، نوع الدفع،
///   والحالة.
/// - النقر على فاتورة يفتح نافذة تفاصيل تعرض بيانات الفاتورة الكاملة + جدول
///   الأصناف (المنتج، الكمية، تكلفة الوحدة، الإجمالي).
/// - بطاقات إحصائية في الأعلى: عدد الفواتير، إجمالي المشتريات، إجمالي
///   المستحقات (ديون للموردين)، مشتريات نقدي.
/// - التخطيط متجاوب: قائمة عمودية ببطاقات تتمدد حسب عرض الشاشة. النصوص
///   عربية RTL.
class PurchasesListScreen extends StatefulWidget {
  const PurchasesListScreen({super.key});

  @override
  State<PurchasesListScreen> createState() => _PurchasesListScreenState();
}

class _PurchasesListScreenState extends State<PurchasesListScreen> {
  // ===== Controllers =====
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ===== Data =====
  final List<Purchase> _purchases = [];
  final Map<int, Supplier> _suppliersMap = {};
  final Map<int, Product> _productsMap = {};
  final Map<int, User> _usersMap = {};

  // ===== Filters =====
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchQuery = '';

  // ===== State =====
  bool _isLoading = true;

  // =====================
  // دورة الحياة
  // =====================

  @override
  void initState() {
    super.initState();
    // نقرأ AuthProvider مبكرًا للتأكد من بنائه قبل أي use لـ context.mounted
    context.read<AuthProvider>();
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
      // حمّل الفواتير والخرائط المساعدة (الموردين/المنتجات/المستخدمين) بشكل متوازٍ
      final results = await Future.wait([
        _loadPurchases(),
        db.supplierDao.getAll(),
        db.productDao.getAll(),
        db.userDao.getAll(),
      ]);
      _suppliersMap
        ..clear()
        ..addEntries(
            (results[1] as List<Supplier>).map((s) => MapEntry(s.id, s)));
      _productsMap
        ..clear()
        ..addEntries(
            (results[2] as List<Product>).map((p) => MapEntry(p.id, p)));
      _usersMap
        ..clear()
        ..addEntries((results[3] as List<User>).map((u) => MapEntry(u.id, u)));
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل بيانات المشتريات: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// يجلب الفواتير ويطبّق فلترة البحث برقم الفاتورة وفلترة الفترة (client-side)
  /// لأنّ PurchaseDao لا يوفّر getByDateRange.
  Future<void> _loadPurchases() async {
    final db = ServiceLocator.database;
    // عند وجود بحث أو فلتر تاريخ نرفع الحد ليصل البحث للسجلات القديمة
    final hasFilters =
        _searchQuery.trim().isNotEmpty || _startDate != null || _endDate != null;
    final limit = hasFilters ? 500 : 100;
    var result = await db.purchaseDao.getRecent(limit: limit);

    // فلترة بحث برقم الفاتورة (بحث جزئي غير حساس لحالة الأحرف)
    final q = _searchQuery.trim();
    if (q.isNotEmpty) {
      final lower = q.toLowerCase();
      result = result
          .where((p) => p.invoiceNumber.toLowerCase().contains(lower))
          .toList();
    }

    // فلترة بالفترة (client-side) — نمدّ النهاية لنهاية اليوم
    if (_startDate != null) {
      final start = DateTime(
          _startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0);
      result = result.where((p) => !p.createdAt.isBefore(start)).toList();
    }
    if (_endDate != null) {
      final end =
          DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      result = result.where((p) => p.createdAt.isBefore(end)).toList();
    }

    if (!mounted) return;
    setState(() {
      _purchases
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
        _refreshPurchases();
      },
    );
  }

  Future<void> _refreshPurchases() async {
    try {
      await _loadPurchases();
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
    await _refreshPurchases();
  }

  void _clearFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _searchController.clear();
      _searchQuery = '';
    });
    _refreshPurchases();
  }

  // =====================
  // إحصائيات سريعة (محسوبة من القائمة المحمّلة)
  // =====================

  int get _totalCount => _purchases.length;

  num get _totalPurchasesAmount => _purchases
      .where((p) => p.status == InvoiceStatus.completed)
      .fold<num>(0, (sum, p) => sum + p.total);

  num get _totalPayables => _purchases
      .where((p) =>
          p.status == InvoiceStatus.completed && p.remainingAmount > 0)
      .fold<num>(0, (sum, p) => sum + p.remainingAmount);

  num get _totalCashPurchases => _purchases
      .where((p) =>
          p.status == InvoiceStatus.completed &&
          p.paymentType == PaymentType.cash)
      .fold<num>(0, (sum, p) => sum + p.total);

  // =====================
  // فتح نافذة التفاصيل
  // =====================

  Future<void> _openDetail(Purchase purchase) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PurchaseDetailDialog(
        purchase: purchase,
        suppliersMap: _suppliersMap,
        productsMap: _productsMap,
        usersMap: _usersMap,
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
        title: const Text('المشتريات'),
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
            if (_isLoading && _purchases.isEmpty)
              const SliverFillRemaining(
                child: LoadingIndicator(message: 'جارٍ تحميل الفواتير...'),
              )
            else if (_purchases.isEmpty)
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
                    (context, i) => _PurchaseRow(
                      purchase: _purchases[i],
                      supplierName: _supplierName(_purchases[i]),
                      onTap: () => _openDetail(_purchases[i]),
                    ),
                    childCount: _purchases.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _supplierName(Purchase purchase) {
    if (purchase.supplierId == null) return 'مورد نقدي';
    final s = _suppliersMap[purchase.supplierId!];
    if (s == null) return 'مورد محذوف';
    return s.name;
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
            title: 'إجمالي المشتريات',
            value: FormatUtils.formatMoneyAr(_totalPurchasesAmount),
            icon: Icons.payments_outlined,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          StatCard(
            title: 'إجمالي المستحقات',
            value: FormatUtils.formatMoneyAr(_totalPayables),
            icon: Icons.account_balance_outlined,
            color: AppColors.error,
          ),
          const SizedBox(width: 8),
          StatCard(
            title: 'مشتريات نقدي',
            value: FormatUtils.formatMoneyAr(_totalCashPurchases),
            icon: Icons.north_east,
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
                  _refreshPurchases();
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
// صف فاتورة الشراء
// =====================================================================

class _PurchaseRow extends StatelessWidget {
  final Purchase purchase;
  final String supplierName;
  final VoidCallback onTap;

  const _PurchaseRow({
    required this.purchase,
    required this.supplierName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasRemaining = purchase.remainingAmount > 0;
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
                          purchase.invoiceNumber,
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
                      FormatUtils.formatDateTime(purchase.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusBadge(status: purchase.status),
                ],
              ),
              const SizedBox(height: 10),
              // الصف الأوسط: اسم المورد + نوع الدفع
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 16, color: AppColors.textSecondaryLight),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      supplierName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _PaymentTypeChip(paymentType: purchase.paymentType),
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
                      value: FormatUtils.formatMoneyAr(purchase.total),
                      color: AppColors.textPrimaryLight,
                    ),
                  ),
                  Expanded(
                    child: _moneyColumn(
                      context,
                      label: 'المدفوع',
                      value: FormatUtils.formatMoneyAr(purchase.paidAmount),
                      color: AppColors.success,
                    ),
                  ),
                  Expanded(
                    child: _moneyColumn(
                      context,
                      label: 'المتبقي',
                      value: FormatUtils.formatMoneyAr(purchase.remainingAmount),
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

class _PurchaseDetailDialog extends StatelessWidget {
  final Purchase purchase;
  final Map<int, Supplier> suppliersMap;
  final Map<int, Product> productsMap;
  final Map<int, User> usersMap;

  const _PurchaseDetailDialog({
    required this.purchase,
    required this.suppliersMap,
    required this.productsMap,
    required this.usersMap,
  });

  String get _supplierName {
    if (purchase.supplierId == null) return 'مورد نقدي';
    final s = suppliersMap[purchase.supplierId!];
    return s?.name ?? 'مورد محذوف';
  }

  String get _userName {
    final u = usersMap[purchase.userId];
    return u?.displayName ?? 'مستخدم محذوف';
  }

  String get _paymentLabel {
    switch (purchase.paymentType) {
      case PaymentType.cash:
        return 'نقدي';
      case PaymentType.credit:
        return 'آجل';
      case PaymentType.mixed:
        return 'مختلط';
      default:
        return purchase.paymentType;
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
            title: Text('فاتورة ${purchase.invoiceNumber}'),
            actions: [
              IconButton(
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: FutureBuilder<List<PurchaseItem>>(
            future: ServiceLocator.database.purchaseDao.getItems(purchase.id),
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
              final items = snapshot.data ?? const <PurchaseItem>[];
              return _DetailBody(
                purchase: purchase,
                items: items,
                productsMap: productsMap,
                supplierName: _supplierName,
                userName: _userName,
                paymentLabel: _paymentLabel,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Purchase purchase;
  final List<PurchaseItem> items;
  final Map<int, Product> productsMap;
  final String supplierName;
  final String userName;
  final String paymentLabel;

  const _DetailBody({
    required this.purchase,
    required this.items,
    required this.productsMap,
    required this.supplierName,
    required this.userName,
    required this.paymentLabel,
  });

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
                    purchase.invoiceNumber,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                StatusBadge(status: purchase.status),
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
                    value: FormatUtils.formatDateTime(purchase.createdAt)),
                _infoChip(context,
                    icon: Icons.local_shipping_outlined,
                    label: 'المورد',
                    value: supplierName),
                _infoChip(context,
                    icon: Icons.badge_outlined,
                    label: 'المستخدم',
                    value: userName),
                _infoChip(context,
                    icon: Icons.payments_outlined,
                    label: 'نوع الدفع',
                    value: paymentLabel),
              ],
            ),
            if (purchase.notes != null && purchase.notes!.trim().isNotEmpty) ...[
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
                          Text(purchase.notes!),
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
            flex: 5,
            child: Text('المنتج', style: headerStyle),
          ),
          // الكمية
          SizedBox(
            width: 70,
            child: Text('الكمية', style: headerStyle, textAlign: TextAlign.center),
          ),
          // تكلفة الوحدة
          SizedBox(
            width: 100,
            child: Text('تكلفة الوحدة',
                style: headerStyle, textAlign: TextAlign.center),
          ),
          // الإجمالي
          SizedBox(
            width: 110,
            child: Text('الإجمالي',
                style: headerStyle, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, PurchaseItem item) {
    final productName = productsMap[item.productId]?.name ?? 'منتج محذوف';
    final valueStyle = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              productName,
              style: valueStyle?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              FormatUtils.formatQuantity(item.quantity),
              style: valueStyle,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              FormatUtils.formatMoneyAr(item.unitCost),
              style: valueStyle,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              FormatUtils.formatMoneyAr(item.total),
              style: valueStyle?.copyWith(fontWeight: FontWeight.bold),
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
              value: FormatUtils.formatMoneyAr(purchase.subtotal),
            ),
            if (purchase.discount > 0)
              InfoRow(
                label: 'الخصم',
                value: '- ${FormatUtils.formatMoneyAr(purchase.discount)}',
                valueColor: AppColors.error,
              ),
            const Divider(),
            InfoRow(
              label: 'الإجمالي',
              value: FormatUtils.formatMoneyAr(purchase.total),
              icon: Icons.calculate_outlined,
            ),
            InfoRow(
              label: 'المدفوع',
              value: FormatUtils.formatMoneyAr(purchase.paidAmount),
              icon: Icons.check_circle_outline,
              valueColor: AppColors.success,
            ),
            if (purchase.remainingAmount > 0)
              InfoRow(
                label: 'المتبقي (مستحق للمورد)',
                value: FormatUtils.formatMoneyAr(purchase.remainingAmount),
                icon: Icons.error_outline,
                valueColor: AppColors.error,
              ),
          ],
        ),
      ),
    );
  }
}
