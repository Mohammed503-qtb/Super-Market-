import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة الصندوق
/// --------------
/// تعرض ملخص الصندوق (افتتاحي / مقبوضات / مدفوعات / رصيد متوقع) ثم ثلاثة تبويبات:
///  1) الحركات: كشف كامل بحركات النقد (IN/OUT) مع نوع الحركة مترجماً.
///  2) المصروفات: قائمة المصروفات مع زر إضافة (يتطلب cashbox.create).
///  3) السحب والإيداع: قائمتان منفصلتان (سحوبات + إيداعات) مع زر إضافة لكل.
/// زر "إغلاق اليوم" في الـ AppBar يتطلب cashbox.close، يفتح نافذة تُظهر ملخص اليوم
/// من CashboxService.closeDay() مع إمكانية إدخال النقد الفعلي ورؤية الفرق
/// وتسويته (يتطلب cashbox.adjust).
/// التخطيط متجاوب: رأس ملخص يتراص أفقياً على الشاشات العريضة ورأسياً على الهواتف.
class CashboxScreen extends StatefulWidget {
  const CashboxScreen({super.key});

  @override
  State<CashboxScreen> createState() => _CashboxScreenState();
}

class _CashboxScreenState extends State<CashboxScreen> {
  // ===== ملخص الصندوق =====
  num _opening = 0;
  num _totalIn = 0;
  num _totalOut = 0;
  num _expected = 0;

  // ===== قوائم البيانات =====
  List<CashTransaction> _transactions = [];
  List<Expense> _expenses = [];
  List<Withdrawal> _withdrawals = [];
  List<CashTransaction> _deposits = []; // subset of _transactions

  // ===== حالة الواجهة =====
  bool _isLoading = true;

  // ===== الصلاحيات =====
  bool _canCreate = false;
  bool _canClose = false;
  bool _canAdjust = false;

  // =====================
  // دورة الحياة
  // =====================

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _loadData();
  }

  void _initPermissions() {
    final auth = context.read<AuthProvider>();
    _canCreate = auth.hasPermission(PermissionCodes.cashboxCreate);
    _canClose = auth.hasPermission(PermissionCodes.cashboxClose);
    _canAdjust = auth.hasPermission(PermissionCodes.cashboxAdjust);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final svc = ServiceLocator.cashboxService;
      final db = ServiceLocator.database;
      final now = DateTime.now();
      // نطاق واسع لجلب كل السجلات التاريخية (الـ DAO يدعم فقط getByDateRange).
      final historyStart = now.subtract(const Duration(days: 3650));
      final historyEnd = now.add(const Duration(days: 1));

      final results = await Future.wait([
        svc.getOpeningBalance(),
        db.cashTransactionDao.totalInbound(),
        db.cashTransactionDao.totalOutbound(),
        svc.getExpectedBalance(),
        svc.getTransactions(limit: 500),
        db.expenseDao.getByDateRange(historyStart, historyEnd),
        db.withdrawalDao.getByDateRange(historyStart, historyEnd),
      ]);

      _opening = results[0] as num;
      _totalIn = results[1] as num;
      _totalOut = results[2] as num;
      _expected = results[3] as num;
      _transactions = results[4] as List<CashTransaction>;
      _expenses = results[5] as List<Expense>;
      _withdrawals = results[6] as List<Withdrawal>;
      _deposits = _transactions
          .where((t) => t.transactionType == MovementTypes.sourceDeposit)
          .toList();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل بيانات الصندوق: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // =====================
  // فتح النماذج
  // =====================

  Future<void> _openExpenseForm() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ExpenseFormDialog(),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _openWithdrawalForm() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _WithdrawalFormDialog(),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _openDepositForm() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DepositFormDialog(),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _openCloseDayDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CloseDayDialog(canAdjust: _canAdjust),
    );
    if (result == true) {
      await _loadData();
    }
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الصندوق'),
          actions: [
            if (_canClose)
              IconButton(
                tooltip: 'إغلاق اليوم',
                icon: const Icon(Icons.lock_outline),
                onPressed: _openCloseDayDialog,
              ),
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadData,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.swap_vert), text: 'الحركات'),
              Tab(icon: Icon(Icons.money_off_outlined), text: 'المصروفات'),
              Tab(icon: Icon(Icons.savings_outlined), text: 'السحب والإيداع'),
            ],
          ),
        ),
        body: _isLoading
            ? const LoadingIndicator(message: 'جارٍ تحميل بيانات الصندوق...')
            : Column(
                children: [
                  _buildSummaryHeader(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTransactionsTab(),
                        _buildExpensesTab(),
                        _buildWithdrawalsDepositsTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ===== رأس الملخص =====

  Widget _buildSummaryHeader() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            final stats = <_StatItem>[
              _StatItem(
                'الرصيد الافتتاحي',
                _opening,
                Icons.account_balance_wallet_outlined,
                AppColors.info,
              ),
              _StatItem(
                'إجمالي المقبوضات',
                _totalIn,
                Icons.south_west,
                AppColors.success,
              ),
              _StatItem(
                'إجمالي المدفوعات',
                _totalOut,
                Icons.north_east,
                AppColors.error,
              ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < stats.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: _miniStat(stats[i])),
                        ],
                      ],
                    ),
                  )
                else
                  Column(
                    children: [
                      for (int i = 0; i < stats.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _miniStat(stats[i]),
                      ],
                    ],
                  ),
                const SizedBox(height: 12),
                _expectedBanner(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _miniStat(_StatItem s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: s.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(s.icon, color: s.color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    FormatUtils.formatMoneyAr(s.value),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: s.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _expectedBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'الرصيد المتوقع',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
          Text(
            FormatUtils.formatMoneyAr(_expected),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ===== تبويب الحركات =====

  Widget _buildTransactionsTab() {
    if (_transactions.isEmpty) {
      return const EmptyState(
        message: 'لا توجد حركات نقدية بعد',
        icon: Icons.swap_horiz,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _transactions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
        itemBuilder: (context, i) {
          final t = _transactions[i];
          final meta = _movementTypeMeta(t.transactionType);
          final isInbound = t.direction == CashDirection.inbound;
          final color = isInbound ? AppColors.success : AppColors.error;
          final sign = isInbound ? '+' : '-';
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(
                isInbound ? Icons.south_west : Icons.north_east,
                color: color,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    (t.description?.isNotEmpty ?? false)
                        ? t.description!
                        : meta.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                _TypeChip(label: meta.label, color: meta.color),
              ],
            ),
            subtitle: Text(
              FormatUtils.formatDateTime(t.createdAt),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondaryLight,
              ),
            ),
            trailing: Text(
              '$sign ${FormatUtils.formatMoneyAr(t.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 14,
              ),
            ),
          );
        },
      ),
    );
  }

  // ===== تبويب المصروفات =====

  Widget _buildExpensesTab() {
    return Scaffold(
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              heroTag: 'add_expense',
              onPressed: _openExpenseForm,
              icon: const Icon(Icons.add),
              label: const Text('مصروف جديد'),
            )
          : null,
      body: _expenses.isEmpty
          ? const EmptyState(
              message: 'لا توجد مصروفات مسجلة',
              icon: Icons.money_off_outlined,
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _expenses.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (context, i) {
                  final e = _expenses[i];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.error.withValues(alpha: 0.12),
                      child: const Icon(Icons.money_off,
                          color: AppColors.error, size: 20),
                    ),
                    title: Text(
                      e.category,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      (e.description?.isNotEmpty ?? false)
                          ? '${FormatUtils.formatDateTime(e.createdAt)} · ${e.description}'
                          : FormatUtils.formatDateTime(e.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    trailing: Text(
                      '- ${FormatUtils.formatMoneyAr(e.amount)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  // ===== تبويب السحوبات والإيداعات =====

  Widget _buildWithdrawalsDepositsTab() {
    return Scaffold(
      floatingActionButton: _canCreate
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'add_withdrawal',
                  onPressed: _openWithdrawalForm,
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('سحب'),
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                ),
                const SizedBox(width: 8),
                FloatingActionButton.extended(
                  heroTag: 'add_deposit',
                  onPressed: _openDepositForm,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('إيداع'),
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SectionHeader(
              title: 'السحوبات (${_withdrawals.length})',
              icon: Icons.upload_outlined,
              action: _canCreate
                  ? TextButton.icon(
                      onPressed: _openWithdrawalForm,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('سحب جديد'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.warning,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            if (_withdrawals.isEmpty)
              _emptyInline('لا توجد سحوبات مسجلة')
            else
              ..._withdrawals.map(_withdrawalTile),
            const SizedBox(height: 24),
            SectionHeader(
              title: 'الإيداعات (${_deposits.length})',
              icon: Icons.download_outlined,
              action: _canCreate
                  ? TextButton.icon(
                      onPressed: _openDepositForm,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('إيداع جديد'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.success,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            if (_deposits.isEmpty)
              _emptyInline('لا توجد إيداعات مسجلة')
            else
              ..._deposits.map(_depositTile),
          ],
        ),
      ),
    );
  }

  Widget _withdrawalTile(Withdrawal w) {
    final typeLabel = _withdrawalTypeLabel(w.withdrawalType);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.dividerLight),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        leading: CircleAvatar(
          backgroundColor: AppColors.warning.withValues(alpha: 0.12),
          child: const Icon(Icons.upload_outlined,
              color: AppColors.warning, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                (w.reason?.isNotEmpty ?? false) ? w.reason! : typeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            _TypeChip(label: typeLabel, color: AppColors.warning),
          ],
        ),
        subtitle: Text(
          FormatUtils.formatDateTime(w.createdAt),
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondaryLight,
          ),
        ),
        trailing: Text(
          '- ${FormatUtils.formatMoneyAr(w.amount)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.warning,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _depositTile(CashTransaction d) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.dividerLight),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        leading: CircleAvatar(
          backgroundColor: AppColors.success.withValues(alpha: 0.12),
          child: const Icon(Icons.download_outlined,
              color: AppColors.success, size: 20),
        ),
        title: Text(
          (d.description?.isNotEmpty ?? false) ? d.description! : 'إيداع',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          FormatUtils.formatDateTime(d.createdAt),
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondaryLight,
          ),
        ),
        trailing: Text(
          '+ ${FormatUtils.formatMoneyAr(d.amount)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.success,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _emptyInline(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.textSecondaryLight.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              size: 18, color: AppColors.textSecondaryLight),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                color: AppColors.textSecondaryLight,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _withdrawalTypeLabel(String type) {
    switch (type) {
      case 'OWNER':
        return 'المالك';
      case 'STAFF':
        return 'موظف';
      case 'PERSONAL':
        return 'شخصي';
      case 'OTHER':
        return 'أخرى';
      default:
        return type;
    }
  }
}

// =====================================================
// أنواع مساعدة
// =====================================================

class _StatItem {
  final String label;
  final num value;
  final IconData icon;
  final Color color;
  const _StatItem(this.label, this.value, this.icon, this.color);
}

class _MovementMeta {
  final String label;
  final Color color;
  const _MovementMeta(this.label, this.color);
}

/// يرجع تسمية ولون نوع الحركة المالية حسب الكود المخزن في transactionType.
_MovementMeta _movementTypeMeta(String type) {
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

// =====================================================
// نموذج إضافة مصروف
// =====================================================
class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog();

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  static const _categories = <String>[
    'إيجار',
    'كهرباء',
    'ماء',
    'رواتب',
    'نقل',
    'صيانة',
    'اتصالات',
    'مصاريف تشغيلية',
    'أخرى',
  ];

  String _category = _categories.first;
  String _paymentMethod = PaymentType.cash;
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final userId = context.read<AuthProvider>().currentUser!.id;
      final amount = num.tryParse(_amountCtrl.text.trim()) ?? 0;
      final desc = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();

      await ServiceLocator.cashboxService.recordExpense(
        amount: amount,
        category: _category,
        userId: userId,
        paymentMethod: _paymentMethod,
        description: desc,
      );
      if (mounted) {
        showSuccessSnackBar(context, 'تم تسجيل المصروف بنجاح');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تسجيل المصروف: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 500;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 500 : double.infinity),
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
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child:
                            const Icon(Icons.money_off, color: AppColors.error),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'تسجيل مصروف',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        icon: const Icon(Icons.close),
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'فئة المصروف *',
                      prefixIcon: Icon(Icons.category_outlined),
                      isDense: true,
                    ),
                    items: _categories
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c),
                            ))
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _category = v);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ *',
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
                          value: PaymentType.cash, child: Text('نقدي')),
                      DropdownMenuItem(value: 'CARD', child: Text('بطاقة')),
                      DropdownMenuItem(
                          value: 'BANK', child: Text('تحويل بنكي')),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _paymentMethod = v);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'وصف',
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
                          label: const Text('حفظ'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
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

// =====================================================
// نموذج إضافة سحب
// =====================================================
class _WithdrawalFormDialog extends StatefulWidget {
  const _WithdrawalFormDialog();

  @override
  State<_WithdrawalFormDialog> createState() => _WithdrawalFormDialogState();
}

class _WithdrawalFormDialogState extends State<_WithdrawalFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  String _withdrawalType = 'OWNER';
  bool _saving = false;

  static const _types = <(String, String)>[
    ('OWNER', 'المالك'),
    ('STAFF', 'موظف'),
    ('PERSONAL', 'شخصي'),
    ('OTHER', 'أخرى'),
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final userId = context.read<AuthProvider>().currentUser!.id;
      final amount = num.tryParse(_amountCtrl.text.trim()) ?? 0;
      final reason =
          _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim();

      await ServiceLocator.cashboxService.recordWithdrawal(
        amount: amount,
        userId: userId,
        reason: reason,
        withdrawalType: _withdrawalType,
      );
      if (mounted) {
        showSuccessSnackBar(context, 'تم تسجيل السحب بنجاح');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تسجيل السحب: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 500;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 500 : double.infinity),
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
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.upload_outlined,
                            color: AppColors.warning),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'تسجيل سحب من الصندوق',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        icon: const Icon(Icons.close),
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ *',
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
                    value: _withdrawalType,
                    decoration: const InputDecoration(
                      labelText: 'نوع السحب',
                      prefixIcon: Icon(Icons.person_outline),
                      isDense: true,
                    ),
                    items: _types
                        .map((t) => DropdownMenuItem(
                              value: t.$1,
                              child: Text(t.$2),
                            ))
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _withdrawalType = v);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'السبب',
                      hintText: 'اختياري',
                      prefixIcon: Icon(Icons.note_outlined),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            size: 16, color: AppColors.warning),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'السحب يقلل رصيد الصندوق. لا يُعتبر مصروف تشغيلي.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                              : const Icon(Icons.upload_outlined),
                          label: const Text('تأكيد السحب'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.warning,
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

// =====================================================
// نموذج إضافة إيداع
// =====================================================
class _DepositFormDialog extends StatefulWidget {
  const _DepositFormDialog();

  @override
  State<_DepositFormDialog> createState() => _DepositFormDialogState();
}

class _DepositFormDialogState extends State<_DepositFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final userId = context.read<AuthProvider>().currentUser!.id;
      final amount = num.tryParse(_amountCtrl.text.trim()) ?? 0;
      final reason =
          _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim();

      await ServiceLocator.cashboxService.recordDeposit(
        amount: amount,
        userId: userId,
        reason: reason,
      );
      if (mounted) {
        showSuccessSnackBar(context, 'تم تسجيل الإيداع بنجاح');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تسجيل الإيداع: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 500;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 500 : double.infinity),
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
                        child: const Icon(Icons.download_outlined,
                            color: AppColors.success),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'تسجيل إيداع في الصندوق',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        icon: const Icon(Icons.close),
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ *',
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
                  TextFormField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'السبب',
                      hintText: 'مثال: إيداع رأس مال',
                      prefixIcon: Icon(Icons.note_outlined),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: AppColors.info),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'الإيداع يزيد رصيد الصندوق (مثل زيادة رأس المال).',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                              : const Icon(Icons.download_outlined),
                          label: const Text('تأكيد الإيداع'),
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

// =====================================================
// نافذة إغلاق اليوم
// =====================================================
class _CloseDayDialog extends StatefulWidget {
  final bool canAdjust;
  const _CloseDayDialog({required this.canAdjust});

  @override
  State<_CloseDayDialog> createState() => _CloseDayDialogState();
}

class _CloseDayDialogState extends State<_CloseDayDialog> {
  Map<String, num>? _summary;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _actualCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _actualCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = context.read<AuthProvider>().currentUser!.id;
      final svc = ServiceLocator.cashboxService;
      // نستدعي closeDay دون actualCash للحصول على ملخص اليوم المتوقع.
      // ملاحظة: closeDay يكتب سجل تدقيق 'DAY_CLOSED' في كل مرة.
      final summary = await svc.closeDay(userId, DateTime.now());
      _summary = summary;
      _actualCtrl.text = _formatNum(summary['expectedCash'] ?? 0);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatNum(num v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toString();
  }

  num get _expected => _summary?['expectedCash'] ?? 0;

  num get _actual {
    final v = num.tryParse(_actualCtrl.text.trim());
    return v ?? _expected;
  }

  /// فرق العد الفعلي عن المتوقع: موجب = زيادة، سالب = عجز.
  num get _countedDifference => _actual - _expected;

  bool get _hasDiff => _countedDifference != 0;

  Future<void> _confirmClose() async {
    setState(() => _saving = true);
    try {
      final userId = context.read<AuthProvider>().currentUser!.id;
      final svc = ServiceLocator.cashboxService;
      await svc.closeDay(userId, DateTime.now(), actualCash: _actual);
      if (mounted) {
        showSuccessSnackBar(context, 'تم إغلاق اليوم بنجاح');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل إغلاق اليوم: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _adjustAndClose() async {
    setState(() => _saving = true);
    try {
      final userId = context.read<AuthProvider>().currentUser!.id;
      final svc = ServiceLocator.cashboxService;
      final reason = _reasonCtrl.text.trim().isEmpty
          ? 'تسوية فرق إغلاق يوم ${FormatUtils.formatDate(DateTime.now())}'
          : _reasonCtrl.text.trim();
      // recordAdjustment يتوقع difference = المتوقع - الفعلي.
      await svc.recordAdjustment(
        difference: _expected - _actual,
        userId: userId,
        reason: reason,
      );
      await svc.closeDay(userId, DateTime.now(), actualCash: _actual);
      if (mounted) {
        showSuccessSnackBar(context, 'تم تسوية الفرق وإغلاق اليوم بنجاح');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل التسوية: $e');
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
          maxWidth: wide ? 600 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('إغلاق اليوم'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close),
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          body: _loading
              ? const LoadingIndicator(message: 'جارٍ تجميع بيانات اليوم...')
              : _error != null
                  ? EmptyState(
                      icon: Icons.error_outline,
                      message: 'فشل تحميل البيانات: $_error',
                      actionLabel: 'إعادة المحاولة',
                      onAction: _loadSummary,
                    )
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final s = _summary!;
    return StatefulBuilder(
      builder: (context, setState) {
        final isSurplus = _countedDifference > 0;
        return RefreshIndicator(
          onRefresh: _loadSummary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.dividerLight),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(
                          title: 'ملخص اليوم', icon: Icons.today),
                      const SizedBox(height: 8),
                      InfoRow(
                        label: 'الرصيد الافتتاحي',
                        value: FormatUtils.formatMoneyAr(s['opening'] ?? 0),
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                      InfoRow(
                        label: 'مبيعات نقدية',
                        value: FormatUtils.formatMoneyAr(s['salesTotal'] ?? 0),
                        icon: Icons.point_of_sale_outlined,
                        valueColor: AppColors.success,
                      ),
                      InfoRow(
                        label: 'مشتريات',
                        value:
                            FormatUtils.formatMoneyAr(s['purchasesTotal'] ?? 0),
                        icon: Icons.shopping_cart_outlined,
                        valueColor: AppColors.secondary,
                      ),
                      InfoRow(
                        label: 'سداد عملاء',
                        value: FormatUtils.formatMoneyAr(
                            s['customerPayments'] ?? 0),
                        icon: Icons.people_alt_outlined,
                        valueColor: AppColors.success,
                      ),
                      InfoRow(
                        label: 'سداد موردين',
                        value: FormatUtils.formatMoneyAr(
                            s['supplierPayments'] ?? 0),
                        icon: Icons.local_shipping_outlined,
                        valueColor: AppColors.secondary,
                      ),
                      InfoRow(
                        label: 'مصروفات',
                        value: FormatUtils.formatMoneyAr(s['expenses'] ?? 0),
                        icon: Icons.money_off_outlined,
                        valueColor: AppColors.error,
                      ),
                      InfoRow(
                        label: 'سحوبات',
                        value: FormatUtils.formatMoneyAr(s['withdrawals'] ?? 0),
                        icon: Icons.upload_outlined,
                        valueColor: AppColors.warning,
                      ),
                      const Divider(),
                      InfoRow(
                        label: 'الرصيد المتوقع',
                        value:
                            FormatUtils.formatMoneyAr(s['expectedCash'] ?? 0),
                        icon: Icons.account_balance,
                        valueColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader(
                  title: 'العد الفعلي', icon: Icons.calculate_outlined),
              const SizedBox(height: 8),
              TextFormField(
                controller: _actualCtrl,
                decoration: const InputDecoration(
                  labelText: 'النقد الفعلي في الصندوق',
                  hintText: '0',
                  prefixIcon: Icon(Icons.attach_money),
                  isDense: true,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _differenceRow(isSurplus),
              if (_hasDiff && widget.canAdjust) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'سبب التسوية (اختياري)',
                    hintText: 'مثال: عجز نقدي',
                    prefixIcon: Icon(Icons.note_outlined),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ],
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
                      onPressed: _saving ? null : _confirmClose,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_outline),
                      label: const Text('إغلاق اليوم'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              if (_hasDiff && widget.canAdjust) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _adjustAndClose,
                    icon: const Icon(Icons.balance_outlined),
                    label: const Text('تسوية الفرق وإغلاق'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
              if (_hasDiff && !widget.canAdjust) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_outlined,
                          size: 18, color: AppColors.warning),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'يوجد فرق بين المتوقع والفعلي. لا تملك صلاحية تسوية الصندوق.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _differenceRow(bool isSurplus) {
    final color = !_hasDiff
        ? AppColors.success
        : (isSurplus ? AppColors.success : AppColors.error);
    final label = !_hasDiff
        ? 'لا يوجد فرق — الصندوق متوازن'
        : (isSurplus
            ? 'زيادة في الصندوق: ${FormatUtils.formatMoneyAr(_countedDifference)}'
            : 'عجز في الصندوق: ${FormatUtils.formatMoneyAr(_countedDifference.abs())}');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            !_hasDiff
                ? Icons.check_circle_outline
                : (isSurplus
                    ? Icons.add_circle_outline
                    : Icons.remove_circle_outline),
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
