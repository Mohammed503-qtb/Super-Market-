import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../../domain/services/accounting_service.dart';
import '../shared/widgets.dart';

/// شاشة التقارير
/// -----------
/// تعرض خمسة أنواع من التقارير عبر TabBar، وتعرض فقط التبويبات التي يملك
/// المستخدم صلاحية رؤيتها:
///  1) تقرير المبيعات اليومي   - reports.view
///  2) تقرير الصندوق           - reports.cash
///  3) تقرير الأرباح           - reports.profit
///  4) تقرير الديون            - reports.debts
///  5) تقرير المخزون           - reports.inventory
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final List<_ReportTab> _tabs = [];

  @override
  void initState() {
    super.initState();
    _initTabs();
  }

  void _initTabs() {
    final auth = context.read<AuthProvider>();
    _tabs.clear();
    if (auth.hasPermission(PermissionCodes.reportsView)) {
      _tabs.add(const _ReportTab(
        icon: Icons.today_outlined,
        label: 'اليومي',
        child: _DailyReportTab(),
      ));
    }
    if (auth.hasPermission(PermissionCodes.reportsCash)) {
      _tabs.add(const _ReportTab(
        icon: Icons.account_balance_wallet_outlined,
        label: 'الصندوق',
        child: _CashReportTab(),
      ));
    }
    if (auth.hasPermission(PermissionCodes.reportsProfit)) {
      _tabs.add(const _ReportTab(
        icon: Icons.trending_up,
        label: 'الأرباح',
        child: _ProfitReportTab(),
      ));
    }
    if (auth.hasPermission(PermissionCodes.reportsDebts)) {
      _tabs.add(const _ReportTab(
        icon: Icons.handshake_outlined,
        label: 'الديون',
        child: _DebtsReportTab(),
      ));
    }
    if (auth.hasPermission(PermissionCodes.reportsInventory)) {
      _tabs.add(const _ReportTab(
        icon: Icons.inventory_2_outlined,
        label: 'المخزون',
        child: _InventoryReportTab(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // لا يملك أي صلاحية تقارير: عرض حالة فارغة.
    if (_tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('التقارير')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message: 'لا تملك صلاحية للوصول إلى التقارير',
        ),
      );
    }

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التقارير'),
          bottom: TabBar(
            isScrollable: _tabs.length > 4,
            tabAlignment: _tabs.length > 4 ? TabAlignment.start : TabAlignment.center,
            tabs: _tabs
                .map((t) => Tab(
                      icon: Icon(t.icon),
                      text: t.label,
                    ))
                .toList(),
          ),
        ),
        body: TabBarView(
          children: _tabs.map((t) => t.child).toList(),
        ),
      ),
    );
  }
}

/// تعريف تبويب تقرير: عنوان + أيقونة + العنصر الذي يُعرض داخل التبويب.
class _ReportTab {
  final IconData icon;
  final String label;
  final Widget child;
  const _ReportTab({
    required this.icon,
    required this.label,
    required this.child,
  });
}

// ===================================================
// 1) تقرير المبيعات اليومي
// ===================================================

class _DailyReportTab extends StatefulWidget {
  const _DailyReportTab();

  @override
  State<_DailyReportTab> createState() => _DailyReportTabState();
}

class _DailyReportTabState extends State<_DailyReportTab> {
  DateTime _selectedDay = DateTime.now();
  DailyReport? _report;
  bool _isLoading = false;
  String? _error;
  // هل يملك المستخدم صلاحية الاطلاع على الأرباح؟
  late final bool _canSeeProfit;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _canSeeProfit = auth.hasPermission(PermissionCodes.reportsProfit);
    _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'اختر اليوم',
    );
    if (picked != null && picked != _selectedDay) {
      setState(() => _selectedDay = picked);
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final report =
          await ServiceLocator.accountingService.getDailyReport(_selectedDay);
      if (mounted) {
        setState(() {
          _report = report;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DateRangeBar(
          label: 'اليوم: ${FormatUtils.formatDateAr(_selectedDay)}',
          onPick: _pickDay,
          onRefresh: _isLoading ? null : _load,
        ),
        Expanded(
          child: _isLoading
              ? const LoadingIndicator(message: 'جارٍ تجهيز التقرير اليومي...')
              : _error != null
                  ? _ErrorView(error: _error!, onRetry: _load)
                  : _report == null
                      ? const EmptyState(message: 'لا توجد بيانات')
                      : _buildBody(_report!),
        ),
      ],
    );
  }

  Widget _buildBody(DailyReport r) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          // بطاقات إحصائية سريعة
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              StatCard(
                title: 'إجمالي المبيعات',
                value: FormatUtils.formatMoneyAr(r.salesTotal),
                icon: Icons.point_of_sale_outlined,
                color: AppColors.primary,
              ),
              StatCard(
                title: 'عدد الفواتير',
                value: r.invoiceCount.toString(),
                icon: Icons.receipt_long_outlined,
                color: AppColors.info,
              ),
              StatCard(
                title: 'مبيعات نقدي',
                value: FormatUtils.formatMoneyAr(r.cashSales),
                icon: Icons.payments_outlined,
                color: AppColors.success,
              ),
              StatCard(
                title: 'مبيعات آجل',
                value: FormatUtils.formatMoneyAr(r.creditSales),
                icon: Icons.credit_card_outlined,
                color: AppColors.secondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'تفاصيل المبيعات', icon: Icons.sell_outlined),
                  const Divider(height: 24),
                  InfoRow(
                    label: 'إجمالي المبيعات',
                    value: FormatUtils.formatMoneyAr(r.salesTotal),
                    icon: Icons.add_circle_outline,
                  ),
                  InfoRow(
                    label: 'مرتجعات المبيعات',
                    value: '- ${FormatUtils.formatMoneyAr(r.salesReturns)}',
                    icon: Icons.remove_circle_outline,
                    valueColor: AppColors.error,
                  ),
                  InfoRow(
                    label: 'صافي المبيعات',
                    value: FormatUtils.formatMoneyAr(r.netSales),
                    icon: Icons.check_circle_outline,
                    valueColor: AppColors.primary,
                  ),
                  InfoRow(
                    label: 'المبيعات النقدية',
                    value: FormatUtils.formatMoneyAr(r.cashSales),
                    icon: Icons.payments_outlined,
                  ),
                  InfoRow(
                    label: 'المبيعات الآجلة',
                    value: FormatUtils.formatMoneyAr(r.creditSales),
                    icon: Icons.credit_card_outlined,
                  ),
                  InfoRow(
                    label: 'عدد الفواتير',
                    value: r.invoiceCount.toString(),
                    icon: Icons.receipt_long_outlined,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // الأرباح (مشروطة بصلاحية reports.profit)
          if (_canSeeProfit)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(title: 'الأرباح والتكاليف', icon: Icons.trending_up),
                    const Divider(height: 24),
                    InfoRow(
                      label: 'تكلفة البضاعة المباعة (COGS)',
                      value: FormatUtils.formatMoneyAr(r.cogs),
                      icon: Icons.local_shipping_outlined,
                      valueColor: AppColors.error,
                    ),
                    InfoRow(
                      label: 'الربح الإجمالي',
                      value: FormatUtils.formatMoneyAr(r.grossProfit),
                      icon: Icons.savings_outlined,
                      valueColor: AppColors.primary,
                    ),
                    InfoRow(
                      label: 'المصروفات',
                      value: FormatUtils.formatMoneyAr(r.expenses),
                      icon: Icons.money_off_outlined,
                      valueColor: AppColors.error,
                    ),
                    InfoRow(
                      label: 'الربح التشغيلي',
                      value: FormatUtils.formatMoneyAr(r.operatingProfit),
                      icon: Icons.workspaces_outline,
                      valueColor: r.operatingProfit >= 0
                          ? AppColors.primary
                          : AppColors.error,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          // الصندوق المتوقع وحركة النقد في اليوم
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'حركة النقد المتوقعة', icon: Icons.account_balance),
                  const Divider(height: 24),
                  InfoRow(
                    label: 'مقبوضات (مبيعات نقدية + سداد عملاء)',
                    value: FormatUtils.formatMoneyAr(r.cashSales + r.customerPayments),
                    icon: Icons.south_west,
                    valueColor: AppColors.success,
                  ),
                  InfoRow(
                    label: 'مدفوعات (مشتريات + سداد موردين + مصروفات + سحوبات)',
                    value: FormatUtils.formatMoneyAr(
                        r.purchases + r.supplierPayments + r.expenses + r.withdrawals),
                    icon: Icons.north_east,
                    valueColor: AppColors.error,
                  ),
                  InfoRow(
                    label: 'النقد المتوقع في الصندوق',
                    value: FormatUtils.formatMoneyAr(r.expectedCash),
                    icon: Icons.account_balance_wallet_outlined,
                    valueColor: AppColors.primary,
                  ),
                  InfoRow(
                    label: 'قيمة المخزون الحالية',
                    value: FormatUtils.formatMoneyAr(r.inventoryValue),
                    icon: Icons.inventory_2_outlined,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================
// 2) تقرير الصندوق
// ===================================================

class _CashReportTab extends StatefulWidget {
  const _CashReportTab();

  @override
  State<_CashReportTab> createState() => _CashReportTabState();
}

class _CashReportTabState extends State<_CashReportTab> {
  late DateTime _start;
  late DateTime _end;
  CashReport? _report;
  num _actualCash = 0;
  final TextEditingController _actualController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _end = _start.add(const Duration(days: 1));
    _load();
  }

  @override
  void dispose() {
    _actualController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'من تاريخ',
    );
    if (picked != null) {
      setState(() => _start = DateTime(picked.year, picked.month, picked.day));
      await _load();
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 2)),
      helpText: 'إلى تاريخ',
    );
    if (picked != null) {
      setState(() => _end = DateTime(picked.year, picked.month, picked.day)
          .add(const Duration(days: 1)));
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final report = await ServiceLocator.accountingService
          .getCashReport(_start, _end);
      if (mounted) {
        setState(() {
          _report = report;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _updateActual(String value) {
    final parsed = double.tryParse(value);
    setState(() {
      _actualCash = parsed ?? 0;
    });
  }

  num get _diff => _actualCash - (_report?.expectedBalance ?? 0);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DateRangeBar(
          label:
              'الفترة: ${FormatUtils.formatDateAr(_start)} ← ${FormatUtils.formatDateAr(_end.subtract(const Duration(days: 1)))}',
          onPick: _pickStart,
          onPickSecondary: _pickEnd,
          pickSecondaryLabel: 'إلى',
          pickLabel: 'من',
          onRefresh: _isLoading ? null : _load,
        ),
        Expanded(
          child: _isLoading
              ? const LoadingIndicator(message: 'جارٍ تجهيز تقرير الصندوق...')
              : _error != null
                  ? _ErrorView(error: _error!, onRetry: _load)
                  : _report == null
                      ? const EmptyState(message: 'لا توجد بيانات')
                      : _buildBody(_report!),
        ),
      ],
    );
  }

  Widget _buildBody(CashReport r) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          // ملخص الصندوق
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              StatCard(
                title: 'رصيد افتتاحي',
                value: FormatUtils.formatMoneyAr(r.opening),
                icon: Icons.account_balance_outlined,
                color: AppColors.info,
              ),
              StatCard(
                title: 'الرصيد المتوقع',
                value: FormatUtils.formatMoneyAr(r.expectedBalance),
                icon: Icons.account_balance,
                color: AppColors.primary,
              ),
              StatCard(
                title: 'إجمالي المقبوضات',
                value: FormatUtils.formatMoneyAr(r.cashIn),
                icon: Icons.south_west,
                color: AppColors.success,
              ),
              StatCard(
                title: 'إجمالي المدفوعات',
                value: FormatUtils.formatMoneyAr(r.cashOut),
                icon: Icons.north_east,
                color: AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // المقارنة بين الفعلي والمتوقع
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'مطابقة الصندوق', icon: Icons.fact_check_outlined),
                  const Divider(height: 24),
                  InfoRow(
                    label: 'الرصيد المتوقع',
                    value: FormatUtils.formatMoneyAr(r.expectedBalance),
                    icon: Icons.calculate_outlined,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _actualController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'النقد الفعلي المعدود',
                      prefixIcon: Icon(Icons.edit_outlined),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _updateActual,
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'الفرق (الفعلي - المتوقع)',
                    value: FormatUtils.formatMoneyAr(_diff),
                    icon: Icons.compare_arrows_outlined,
                    valueColor: _diff.abs() < 0.001
                        ? AppColors.success
                        : (_diff < 0 ? AppColors.error : AppColors.warning),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // تفصيل حسب النوع
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'تفصيل حسب نوع الحركة', icon: Icons.category_outlined),
                  const Divider(height: 24),
                  if (r.byType.isEmpty)
                    const EmptyState(
                      icon: Icons.inbox_outlined,
                      message: 'لا توجد حركات نقد في هذه الفترة',
                    )
                  else
                    ...r.byType.entries.map((e) => InfoRow(
                          label: _cashTypeLabel(e.key),
                          value: FormatUtils.formatMoneyAr(e.value),
                          icon: e.value >= 0 ? Icons.south_west : Icons.north_east,
                          valueColor:
                              e.value >= 0 ? AppColors.success : AppColors.error,
                        )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // قائمة الحركات
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: 'الحركات (${r.transactions.length})',
                    icon: Icons.list_alt,
                  ),
                  const Divider(height: 24),
                  if (r.transactions.isEmpty)
                    const EmptyState(
                      icon: Icons.swap_vert,
                      message: 'لا توجد حركات',
                    )
                  else
                    ...r.transactions.map(_buildTxTile),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTxTile(CashTransaction t) {
    final isIn = t.direction == CashDirection.inbound;
    final color = isIn ? AppColors.success : AppColors.error;
    final typeMeta = _cashTypeMeta(t.transactionType);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(isIn ? Icons.south_west : Icons.north_east, color: color, size: 20),
      ),
      title: Row(
        children: [
          Expanded(child: Text(typeMeta.label)),
          _TypeChip(label: isIn ? 'دخل' : 'صرف', color: color),
        ],
      ),
      subtitle: Text(
        t.description != null && t.description!.isNotEmpty
            ? '${t.description} • ${FormatUtils.formatDateTime(t.createdAt)}'
            : FormatUtils.formatDateTime(t.createdAt),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '${isIn ? '+' : '-'} ${FormatUtils.formatMoneyAr(t.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// ===================================================
// 3) تقرير الأرباح
// ===================================================

class _ProfitReportTab extends StatefulWidget {
  const _ProfitReportTab();

  @override
  State<_ProfitReportTab> createState() => _ProfitReportTabState();
}

class _ProfitReportTabState extends State<_ProfitReportTab> {
  late DateTime _start;
  late DateTime _end;
  // مخرجات الحسابات المنفصلة
  num _grossSales = 0;
  num _returns = 0;
  num _netSales = 0;
  num _cogs = 0;
  num _grossProfit = 0;
  num _expenses = 0;
  num _operatingProfit = 0;
  bool _isLoading = false;
  String? _error;
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1); // بداية الشهر
    _end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _load();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'من تاريخ',
    );
    if (picked != null) {
      setState(() => _start = DateTime(picked.year, picked.month, picked.day));
      await _load();
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 2)),
      helpText: 'إلى تاريخ',
    );
    if (picked != null) {
      setState(() => _end = DateTime(picked.year, picked.month, picked.day)
          .add(const Duration(days: 1)));
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final svc = ServiceLocator.accountingService;
      final results = await Future.wait([
        svc.grossSales(_start, _end),
        svc.salesReturns(_start, _end),
        svc.netSales(_start, _end),
        svc.calculateCOGS(_start, _end),
        svc.grossProfit(_start, _end),
        svc.operatingProfit(_start, _end),
      ]);
      // المصروفات = grossProfit - operatingProfit
      _grossSales = results[0];
      _returns = results[1];
      _netSales = results[2];
      _cogs = results[3];
      _grossProfit = results[4];
      final op = results[5];
      _operatingProfit = op;
      _expenses = _grossProfit - op;
      _hasData = true;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DateRangeBar(
          label:
              'الفترة: ${FormatUtils.formatDateAr(_start)} ← ${FormatUtils.formatDateAr(_end.subtract(const Duration(days: 1)))}',
          onPick: _pickStart,
          onPickSecondary: _pickEnd,
          pickSecondaryLabel: 'إلى',
          pickLabel: 'من',
          onRefresh: _isLoading ? null : _load,
        ),
        Expanded(
          child: _isLoading
              ? const LoadingIndicator(message: 'جارٍ حساب الأرباح...')
              : _error != null
                  ? _ErrorView(error: _error!, onRetry: _load)
                  : !_hasData
                      ? const EmptyState(message: 'لا توجد بيانات')
                      : _buildBody(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          // بطاقات إحصائية
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              StatCard(
                title: 'صافي المبيعات',
                value: FormatUtils.formatMoneyAr(_netSales),
                icon: Icons.sell_outlined,
                color: AppColors.primary,
              ),
              StatCard(
                title: 'الربح الإجمالي',
                value: FormatUtils.formatMoneyAr(_grossProfit),
                icon: Icons.savings_outlined,
                color: AppColors.accent,
              ),
              StatCard(
                title: 'الربح التشغيلي',
                value: FormatUtils.formatMoneyAr(_operatingProfit),
                icon: Icons.trending_up,
                color: _operatingProfit >= 0 ? AppColors.success : AppColors.error,
              ),
              StatCard(
                title: 'هامش الربح %',
                value: _netSales == 0
                    ? '0%'
                    : '${(_grossProfit / _netSales * 100).toStringAsFixed(1)}%',
                icon: Icons.percent_outlined,
                color: AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // تفصيل معادلة الأرباح خطوة بخطوة
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'معادلة احتساب الربح', icon: Icons.calculate),
                  const Divider(height: 24),
                  // الخطوة 1: إجمالي المبيعات
                  _FormulaStep(
                    label: 'إجمالي المبيعات',
                    value: _grossSales,
                    icon: Icons.point_of_sale_outlined,
                    color: AppColors.primary,
                  ),
                  // ناقص المرتجعات
                  _FormulaStep(
                    label: 'مرتجعات المبيعات',
                    value: -_returns,
                    icon: Icons.remove_circle_outline,
                    color: AppColors.error,
                    sign: '−',
                  ),
                  const Divider(),
                  // = صافي المبيعات
                  _FormulaResult(
                    label: '= صافي المبيعات',
                    value: _netSales,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  // ناقص COGS
                  _FormulaStep(
                    label: 'تكلفة البضاعة المباعة (COGS)',
                    value: -_cogs,
                    icon: Icons.local_shipping_outlined,
                    color: AppColors.error,
                    sign: '−',
                  ),
                  const Divider(),
                  _FormulaResult(
                    label: '= الربح الإجمالي',
                    value: _grossProfit,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 16),
                  // ناقص المصروفات التشغيلية
                  _FormulaStep(
                    label: 'المصروفات التشغيلية',
                    value: -_expenses,
                    icon: Icons.money_off_outlined,
                    color: AppColors.error,
                    sign: '−',
                  ),
                  const Divider(),
                  _FormulaResult(
                    label: '= الربح التشغيلي',
                    value: _operatingProfit,
                    color: _operatingProfit >= 0 ? AppColors.success : AppColors.error,
                    isFinal: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // شريط الهامش التشغيلي
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'مؤشرات الأداء', icon: Icons.insights_outlined),
                  const Divider(height: 24),
                  InfoRow(
                    label: 'هامش الربح الإجمالي',
                    value: _netSales == 0
                        ? '0%'
                        : '${(_grossProfit / _netSales * 100).toStringAsFixed(1)}%',
                    icon: Icons.percent_outlined,
                  ),
                  InfoRow(
                    label: 'هامش الربح التشغيلي',
                    value: _netSales == 0
                        ? '0%'
                        : '${(_operatingProfit / _netSales * 100).toStringAsFixed(1)}%',
                    icon: Icons.percent_outlined,
                  ),
                  InfoRow(
                    label: 'نسبة تكلفة البضاعة من المبيعات',
                    value: _grossSales == 0
                        ? '0%'
                        : '${(_cogs / _grossSales * 100).toStringAsFixed(1)}%',
                    icon: Icons.percent_outlined,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================
// 4) تقرير الديون
// ===================================================

class _DebtsReportTab extends StatefulWidget {
  const _DebtsReportTab();

  @override
  State<_DebtsReportTab> createState() => _DebtsReportTabState();
}

class _DebtsReportTabState extends State<_DebtsReportTab> {
  DebtsReport? _report;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final report = await ServiceLocator.accountingService.getDebtsReport();
      if (mounted) {
        setState(() {
          _report = report;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingIndicator(message: 'جارٍ تجهيز تقرير الديون...');
    }
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_report == null) {
      return const EmptyState(message: 'لا توجد بيانات');
    }
    final r = _report!;
    final totalNet = r.totalCustomerDebt - r.totalSupplierDebt;

    // فرز العملاء/الموردين حسب الرصيد تنازلياً
    final customers = List<Customer>.from(r.customersWithDebt)
      ..sort((a, b) => b.currentBalance.compareTo(a.currentBalance));
    final suppliers = List<Supplier>.from(r.suppliersWithDebt)
      ..sort((a, b) => b.currentBalance.compareTo(a.currentBalance));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // بطاقات الإجماليات
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              StatCard(
                title: 'إجمالي ديون العملاء (لنا)',
                value: FormatUtils.formatMoneyAr(r.totalCustomerDebt),
                icon: Icons.people_alt_outlined,
                color: AppColors.success,
              ),
              StatCard(
                title: 'إجمالي ديون الموردين (علينا)',
                value: FormatUtils.formatMoneyAr(r.totalSupplierDebt),
                icon: Icons.local_shipping_outlined,
                color: AppColors.error,
              ),
              StatCard(
                title: 'الرصيد الصافي',
                value: FormatUtils.formatMoneyAr(totalNet),
                icon: Icons.scale_outlined,
                color: totalNet >= 0 ? AppColors.success : AppColors.error,
              ),
              StatCard(
                title: 'عدد العملاء المدينين',
                value: customers.length.toString(),
                icon: Icons.person_outline,
                color: AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // قائمة العملاء المدينين
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: 'العملاء المدينون (${customers.length})',
                    icon: Icons.people_alt_outlined,
                  ),
                  const Divider(height: 24),
                  if (customers.isEmpty)
                    const EmptyState(
                      icon: Icons.check_circle_outline,
                      message: 'لا يوجد عملاء مدينون',
                    )
                  else
                    ...customers.map(_buildCustomerTile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // قائمة الموردين المستحق لهم
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: 'موردون مستحق لهم (${suppliers.length})',
                    icon: Icons.local_shipping_outlined,
                  ),
                  const Divider(height: 24),
                  if (suppliers.isEmpty)
                    const EmptyState(
                      icon: Icons.check_circle_outline,
                      message: 'لا يوجد مبالغ مستحقة للموردين',
                    )
                  else
                    ...suppliers.map(_buildSupplierTile),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerTile(Customer c) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.success.withValues(alpha: 0.12),
        child: const Icon(Icons.person_outline, color: AppColors.success, size: 20),
      ),
      title: Text(c.name),
      subtitle: Text(
        c.phone?.isNotEmpty == true ? c.phone! : 'لا يوجد هاتف',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        FormatUtils.formatMoneyAr(c.currentBalance),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.success,
        ),
      ),
    );
  }

  Widget _buildSupplierTile(Supplier s) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.error.withValues(alpha: 0.12),
        child: const Icon(Icons.local_shipping_outlined, color: AppColors.error, size: 20),
      ),
      title: Text(s.name),
      subtitle: Text(
        s.phone?.isNotEmpty == true ? s.phone! : 'لا يوجد هاتف',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        FormatUtils.formatMoneyAr(s.currentBalance),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.error,
        ),
      ),
    );
  }
}

// ===================================================
// 5) تقرير المخزون
// ===================================================

class _InventoryReportTab extends StatefulWidget {
  const _InventoryReportTab();

  @override
  State<_InventoryReportTab> createState() => _InventoryReportTabState();
}

class _InventoryReportTabState extends State<_InventoryReportTab> {
  num _inventoryValue = 0;
  int _totalCount = 0;
  List<Product> _lowStock = const [];
  List<Product> _outOfStock = const [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final db = ServiceLocator.database;
      final invSvc = ServiceLocator.inventoryService;
      final results = await Future.wait([
        invSvc.calculateInventoryValue(),
        db.productDao.getAll(),
        db.productDao.getBelowMinimumStock(), // تحت الحد الأدنى
        db.productDao.getLowStock(), // <= 0
      ]);
      _inventoryValue = results[0] as num;
      _totalCount = (results[1] as List<Product>).length;
      _lowStock = results[2] as List<Product>;
      _outOfStock = results[3] as List<Product>;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingIndicator(message: 'جارٍ تجهيز تقرير المخزون...');
    }
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // بطاقات الإحمالي
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              StatCard(
                title: 'قيمة المخزون الكلية',
                value: FormatUtils.formatMoneyAr(_inventoryValue),
                icon: Icons.savings_outlined,
                color: AppColors.primary,
              ),
              StatCard(
                title: 'عدد المنتجات',
                value: _totalCount.toString(),
                icon: Icons.category_outlined,
                color: AppColors.info,
              ),
              StatCard(
                title: 'منتجات تحت الحد الأدنى',
                value: _lowStock.length.toString(),
                icon: Icons.warning_amber_outlined,
                color: AppColors.warning,
              ),
              StatCard(
                title: 'منتجات نفدت',
                value: _outOfStock.length.toString(),
                icon: Icons.error_outline,
                color: AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // قائمة المنتجات النافدة
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: 'منتجات نفدت من المخزون (${_outOfStock.length})',
                    icon: Icons.error_outline,
                  ),
                  const Divider(height: 24),
                  if (_outOfStock.isEmpty)
                    const EmptyState(
                      icon: Icons.check_circle_outline,
                      message: 'لا توجد منتجات نافدة',
                    )
                  else
                    ..._outOfStock.map(_buildOutOfStockTile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // قائمة المنتجات تحت الحد الأدنى
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: 'منتجات تحت الحد الأدنى (${_lowStock.length})',
                    icon: Icons.warning_amber_outlined,
                  ),
                  const Divider(height: 24),
                  if (_lowStock.isEmpty)
                    const EmptyState(
                      icon: Icons.check_circle_outline,
                      message: 'جميع المنتجات فوق الحد الأدنى',
                    )
                  else
                    ..._lowStock.map(_buildLowStockTile),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutOfStockTile(Product p) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.error.withValues(alpha: 0.12),
        child: const Icon(Icons.production_quantity_limits_outlined,
            color: AppColors.error, size: 20),
      ),
      title: Text(p.name),
      subtitle: Text(
        'المخزون: ${FormatUtils.formatQuantity(p.currentStock)} • الحد الأدنى: ${FormatUtils.formatQuantity(p.minimumStock)}',
        style: const TextStyle(fontSize: 12, color: AppColors.error),
      ),
      trailing: Text(
        FormatUtils.formatMoneyAr(p.currentStock * p.averageCost),
        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLowStockTile(Product p) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.warning.withValues(alpha: 0.12),
        child: const Icon(Icons.warning_amber_outlined, color: AppColors.warning, size: 20),
      ),
      title: Text(p.name),
      subtitle: Text(
        'المتبقي: ${FormatUtils.formatQuantity(p.currentStock)} • الحد الأدنى: ${FormatUtils.formatQuantity(p.minimumStock)}',
        style: const TextStyle(fontSize: 12, color: AppColors.warning),
      ),
      trailing: Text(
        FormatUtils.formatMoneyAr(p.currentStock * p.averageCost),
        style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ===================================================
// Widgets مشتركة
// ===================================================

/// شريط علوي يحوي عنوان الفترة وأزرار اختيار التاريخ والتحديث.
class _DateRangeBar extends StatelessWidget {
  final String label;
  final VoidCallback? onPick;
  final VoidCallback? onPickSecondary;
  final VoidCallback? onRefresh;
  final String pickLabel;
  final String pickSecondaryLabel;

  const _DateRangeBar({
    required this.label,
    this.onPick,
    this.onPickSecondary,
    this.onRefresh,
    this.pickLabel = 'اختر التاريخ',
    this.pickSecondaryLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.date_range_outlined, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onPick != null)
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(pickLabel),
              ),
            if (onPickSecondary != null)
              TextButton.icon(
                onPressed: onPickSecondary,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(pickSecondaryLabel),
              ),
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

/// عرض خطأ مع زر إعادة.
class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'حدث خطأ أثناء تحميل التقرير',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: AppColors.textSecondaryLight, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

/// خطوة في معادلة احتساب الربح.
class _FormulaStep extends StatelessWidget {
  final String label;
  final num value;
  final IconData icon;
  final Color color;
  final String sign;

  const _FormulaStep({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sign = '',
  });

  @override
  Widget build(BuildContext context) {
    final prefix = sign.isEmpty ? (value.isNegative ? '-' : '+') : sign;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            '$prefix ${FormatUtils.formatMoneyAr(value.abs())}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// نتيجة خطوة في معادلة الربح.
class _FormulaResult extends StatelessWidget {
  final String label;
  final num value;
  final Color color;
  final bool isFinal;

  const _FormulaResult({
    required this.label,
    required this.value,
    required this.color,
    this.isFinal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: isFinal ? 16 : 14,
              ),
            ),
          ),
          Text(
            FormatUtils.formatMoneyAr(value),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: isFinal ? 18 : 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// شارة صغيرة لتسمية نوع الحركة.
class _TypeChip extends StatelessWidget {
  final String label;
  final Color color;
  const _TypeChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// بيانات نوع حركة النقد: تسمية + لون.
class _MovementMeta {
  final String label;
  final Color color;
  const _MovementMeta(this.label, this.color);
}

/// ترجمة رمز نوع حركة النقد إلى نص عربي مألوف.
_MovementMeta _cashTypeMeta(String type) {
  switch (type) {
    case MovementTypes.sourceSale:
      return const _MovementMeta('مبيعات', AppColors.success);
    case MovementTypes.sourcePurchase:
      return const _MovementMeta('مشتريات', AppColors.secondary);
    case MovementTypes.sourceCustomerPayment:
      return const _MovementMeta('سداد عميل', AppColors.success);
    case MovementTypes.sourceSupplierPayment:
      return const _MovementMeta('سداد مورد', AppColors.secondary);
    case MovementTypes.sourceExpense:
      return const _MovementMeta('مصروف', AppColors.error);
    case MovementTypes.sourceWithdrawal:
      return const _MovementMeta('سحب', AppColors.warning);
    case MovementTypes.sourceDeposit:
      return const _MovementMeta('إيداع', AppColors.success);
    case MovementTypes.sourceOpeningBalance:
      return const _MovementMeta('رصيد افتتاحي', AppColors.info);
    case MovementTypes.sourceReturn:
      return const _MovementMeta('مرتجع', AppColors.info);
    case MovementTypes.sourceAdjustment:
      return const _MovementMeta('تسوية', AppColors.warning);
    default:
      return const _MovementMeta('حركة', AppColors.textSecondaryLight);
  }
}

String _cashTypeLabel(String type) => _cashTypeMeta(type).label;
