import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../../core/constants/app_constants.dart';
import 'inventory_service.dart';

/// خدمة المحاسبة - تحسب الأرباح، COGS، والتقارير المالية
/// كل رقم يجب أن يكون قابلاً للوصول إلى مصدره
class AccountingService {
  final AppDatabase _db;
  final InventoryService _inventoryService;

  AccountingService(this._db, this._inventoryService);

  /// حساب COGS (تكلفة البضاعة المباعة) لفترة
  /// من خلال جمع costPrice * quantity لكل عناصر الفواتير المكتملة
  Future<num> calculateCOGS(DateTime start, DateTime end) async {
    final result = await _db.customSelect(
      '''SELECT COALESCE(SUM(si.cost_price * si.quantity), 0) AS cogs
         FROM sale_items si
         INNER JOIN sales s ON si.sale_id = s.id
         WHERE s.created_at >= ? AND s.created_at < ? AND s.status = ?''',
      variables: [Variable(start), Variable(end), Variable<String>(InvoiceStatus.completed)],
    ).getSingle();
    return result.read<double>('cogs');
  }

  /// إجمالي المبيعات لفترة
  Future<num> grossSales(DateTime start, DateTime end) async {
    return _db.saleDao.totalSales(start, end);
  }

  /// مرتجعات البيع لفترة (قيمة)
  Future<num> salesReturns(DateTime start, DateTime end) async {
    final result = await _db.customSelect(
      '''SELECT COALESCE(SUM(r.total), 0) AS t FROM returns r
         WHERE r.return_type = ? AND r.created_at >= ? AND r.created_at < ?''',
      variables: [Variable<String>('SALE_RETURN'), Variable(start), Variable(end)],
    ).getSingle();
    return result.read<double>('t');
  }

  /// صافي المبيعات = إجمالي - المرتجعات
  Future<num> netSales(DateTime start, DateTime end) async {
    final gross = await grossSales(start, end);
    final returns = await salesReturns(start, end);
    return gross - returns;
  }

  /// الربح الإجمالي = صافي المبيعات - COGS
  Future<num> grossProfit(DateTime start, DateTime end) async {
    final net = await netSales(start, end);
    final cogs = await calculateCOGS(start, end);
    return net - cogs;
  }

  /// الربح التشغيلي = الربح الإجمالي - المصروفات التشغيلية
  /// السحوبات لا تعتبر مصروفات تشغيلية
  Future<num> operatingProfit(DateTime start, DateTime end) async {
    final gp = await grossProfit(start, end);
    final expenses = await _db.expenseDao.totalExpensesInRange(start, end);
    return gp - expenses;
  }

  /// تقارير اليوم الكاملة
  Future<DailyReport> getDailyReport(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final sales = await _db.saleDao.totalSales(start, end);
    final cashSales = await _db.saleDao.totalCashSales(start, end);
    final purchases = await _db.purchaseDao.totalPurchases(start, end);
    final expenses = await _db.expenseDao.totalExpensesInRange(start, end);
    final withdrawals = await _db.withdrawalDao.totalWithdrawalsInRange(start, end);
    final customerPayments = await _db.customerPaymentDao.totalPaymentsInRange(start, end);
    final supplierPayments = await _db.supplierPaymentDao.totalPaymentsInRange(start, end);
    final cogs = await calculateCOGS(start, end);
    final returns = await salesReturns(start, end);
    final inventoryValue = await _inventoryService.calculateInventoryValue();

    // عد الفواتير
    final salesCount = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM sales WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();

    final settings = await _db.settingDao.getSettings();
    final openingBalance = settings?.cashboxOpeningBalance ?? 0;

    final expectedCash = openingBalance +
        cashSales +
        customerPayments -
        purchases -
        supplierPayments -
        expenses -
        withdrawals;

    return DailyReport(
      day: start,
      salesTotal: sales,
      cashSales: cashSales,
      creditSales: sales - cashSales,
      purchases: purchases,
      expenses: expenses,
      withdrawals: withdrawals,
      customerPayments: customerPayments,
      supplierPayments: supplierPayments,
      cogs: cogs,
      salesReturns: returns,
      netSales: sales - returns,
      grossProfit: (sales - returns) - cogs,
      operatingProfit: (sales - returns) - cogs - expenses,
      inventoryValue: inventoryValue,
      expectedCash: expectedCash,
      invoiceCount: salesCount.read<int>('c'),
    );
  }

  /// تقرير الصندوق التفصيلي
  Future<CashReport> getCashReport(DateTime start, DateTime end) async {
    final txs = await _db.cashTransactionDao.getByDateRange(start, end);
    final settings = await _db.settingDao.getSettings();
    final opening = settings?.cashboxOpeningBalance ?? 0;

    num cashIn = 0;
    num cashOut = 0;
    final byType = <String, num>{};

    for (final t in txs) {
      if (t.direction == CashDirection.inbound) {
        cashIn += t.amount;
        byType[t.transactionType] = (byType[t.transactionType] ?? 0) + t.amount;
      } else {
        cashOut += t.amount;
        byType[t.transactionType] = (byType[t.transactionType] ?? 0) - t.amount;
      }
    }

    return CashReport(
      opening: opening,
      cashIn: cashIn,
      cashOut: cashOut,
      expectedBalance: opening + cashIn - cashOut,
      transactions: txs,
      byType: byType,
    );
  }

  /// تقرير الديون
  Future<DebtsReport> getDebtsReport() async {
    final customers = await _db.customerDao.getAll();
    final suppliers = await _db.supplierDao.getAll();

    num totalCustomerDebt = 0;
    num totalSupplierDebt = 0;

    for (final c in customers) {
      totalCustomerDebt += c.currentBalance;
    }
    for (final s in suppliers) {
      totalSupplierDebt += s.currentBalance;
    }

    return DebtsReport(
      totalCustomerDebt: totalCustomerDebt,
      totalSupplierDebt: totalSupplierDebt,
      customersWithDebt: customers.where((c) => c.currentBalance > 0).toList(),
      suppliersWithDebt: suppliers.where((s) => s.currentBalance > 0).toList(),
    );
  }

  /// ملخص لوحة التحكم
  Future<DashboardSummary> getDashboardSummary() async {
    final now = DateTime.now();

    final daily = await getDailyReport(now);
    final debts = await getDebtsReport();
    final settings = await _db.settingDao.getSettings();
    final lowStock = await _db.productDao.getLowStock();

    final totalSales = await _db.saleDao.totalSales(DateTime(2000), now);
    final totalPurchases = await _db.purchaseDao.totalPurchases(DateTime(2000), now);

    return DashboardSummary(
      dailySales: daily.salesTotal,
      dailyPurchases: daily.purchases,
      dailyExpenses: daily.expenses,
      dailyCashIn: daily.cashSales + daily.customerPayments,
      dailyCashOut: daily.purchases + daily.supplierPayments + daily.expenses + daily.withdrawals,
      expectedCash: daily.expectedCash,
      totalCustomerDebt: debts.totalCustomerDebt,
      totalSupplierDebt: debts.totalSupplierDebt,
      inventoryValue: daily.inventoryValue,
      netProfit: daily.operatingProfit,
      invoiceCount: daily.invoiceCount,
      totalSalesAllTime: totalSales,
      totalPurchasesAllTime: totalPurchases,
      lowStockCount: lowStock.length,
      openingBalance: settings?.cashboxOpeningBalance ?? 0,
    );
  }
}

class DailyReport {
  final DateTime day;
  final num salesTotal;
  final num cashSales;
  final num creditSales;
  final num purchases;
  final num expenses;
  final num withdrawals;
  final num customerPayments;
  final num supplierPayments;
  final num cogs;
  final num salesReturns;
  final num netSales;
  final num grossProfit;
  final num operatingProfit;
  final num inventoryValue;
  final num expectedCash;
  final int invoiceCount;

  DailyReport({
    required this.day,
    required this.salesTotal,
    required this.cashSales,
    required this.creditSales,
    required this.purchases,
    required this.expenses,
    required this.withdrawals,
    required this.customerPayments,
    required this.supplierPayments,
    required this.cogs,
    required this.salesReturns,
    required this.netSales,
    required this.grossProfit,
    required this.operatingProfit,
    required this.inventoryValue,
    required this.expectedCash,
    required this.invoiceCount,
  });
}

class CashReport {
  final num opening;
  final num cashIn;
  final num cashOut;
  final num expectedBalance;
  final List<CashTransaction> transactions;
  final Map<String, num> byType;

  CashReport({
    required this.opening,
    required this.cashIn,
    required this.cashOut,
    required this.expectedBalance,
    required this.transactions,
    required this.byType,
  });
}

class DebtsReport {
  final num totalCustomerDebt;
  final num totalSupplierDebt;
  final List<Customer> customersWithDebt;
  final List<Supplier> suppliersWithDebt;

  DebtsReport({
    required this.totalCustomerDebt,
    required this.totalSupplierDebt,
    required this.customersWithDebt,
    required this.suppliersWithDebt,
  });
}

class DashboardSummary {
  final num dailySales;
  final num dailyPurchases;
  final num dailyExpenses;
  final num dailyCashIn;
  final num dailyCashOut;
  final num expectedCash;
  final num totalCustomerDebt;
  final num totalSupplierDebt;
  final num inventoryValue;
  final num netProfit;
  final int invoiceCount;
  final num totalSalesAllTime;
  final num totalPurchasesAllTime;
  final int lowStockCount;
  final num openingBalance;

  DashboardSummary({
    required this.dailySales,
    required this.dailyPurchases,
    required this.dailyExpenses,
    required this.dailyCashIn,
    required this.dailyCashOut,
    required this.expectedCash,
    required this.totalCustomerDebt,
    required this.totalSupplierDebt,
    required this.inventoryValue,
    required this.netProfit,
    required this.invoiceCount,
    required this.totalSalesAllTime,
    required this.totalPurchasesAllTime,
    required this.lowStockCount,
    required this.openingBalance,
  });
}
