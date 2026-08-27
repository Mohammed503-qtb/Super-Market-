import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import 'audit_service.dart';

/// خدمة الصندوق - تدير كل الحركات النقدية
/// لا يتم تعديل رصيد الصندوق مباشرة بل من خلال حركات
class CashboxService {
  final AppDatabase _db;
  final AuditService _auditService;

  CashboxService(this._db, this._auditService);

  /// الرصيد الافتتاحي (من الإعدادات)
  Future<num> getOpeningBalance() async {
    final settings = await _db.settingDao.getSettings();
    return settings?.cashboxOpeningBalance ?? 0;
  }

  /// الرصيد المتوقع = افتتاحي + الداخل - الخارج
  Future<num> getExpectedBalance() async {
    final opening = await getOpeningBalance();
    final inbound = await _db.cashTransactionDao.totalInbound();
    final outbound = await _db.cashTransactionDao.totalOutbound();
    return opening + inbound - outbound;
  }

  /// إجمالي المقبوضات (داخل) لفترة
  Future<num> totalInboundInRange(DateTime start, DateTime end) async {
    final txs = await _db.cashTransactionDao.getByDateRange(start, end);
    num total = 0;
    for (final t in txs) {
      if (t.direction == CashDirection.inbound) total += t.amount;
    }
    return total;
  }

  /// إجمالي المدفوعات (خارج) لفترة
  Future<num> totalOutboundInRange(DateTime start, DateTime end) async {
    final txs = await _db.cashTransactionDao.getByDateRange(start, end);
    num total = 0;
    for (final t in txs) {
      if (t.direction == CashDirection.outbound) total += t.amount;
    }
    return total;
  }

  /// قائمة الحركات لفترة
  Future<List<CashTransaction>> getTransactions(
      {DateTime? start, DateTime? end, int limit = 100}) async {
    if (start != null && end != null) {
      return _db.cashTransactionDao.getByDateRange(start, end);
    }
    return _db.cashTransactionDao.getRecent(limit: limit);
  }

  /// تسجيل مصروف
  Future<int> recordExpense({
    required num amount,
    required String category,
    required int userId,
    String paymentMethod = PaymentType.cash,
    String? description,
  }) async {
    if (amount <= 0) {
      throw InvalidPaymentException('المبلغ يجب أن يكون موجباً');
    }

    return _db.runInTransactionSafe(() async {
      final expenseId = await _db.expenseDao.insertExpense(ExpensesCompanion.insert(
        category: category,
        amount: amount.toDouble(),
        description: description != null ? Value(description) : const Value.absent(),
        paymentMethod: Value(paymentMethod),
        userId: userId,
      ));

      // تخفيض الصندوق
      await _db.cashTransactionDao.insertTransaction(
        CashTransactionsCompanion.insert(
          transactionType: MovementTypes.sourceExpense,
          referenceType: Value(MovementTypes.sourceExpense),
          referenceId: Value(expenseId),
          amount: amount.toDouble(),
          direction: CashDirection.outbound,
          description: Value('مصروف: $category - ${description ?? ""}'),
          userId: Value(userId),
        ),
      );

      await _auditService.log(
        userId: userId,
        action: 'EXPENSE_CREATED',
        module: 'cashbox',
        entityType: 'expense',
        entityId: expenseId,
        description: 'تسجيل مصروف $category بقيمة $amount',
      );

      return expenseId;
    });
  }

  /// تسجيل سحب (لا يعتبر مصروف تشغيلي)
  Future<int> recordWithdrawal({
    required num amount,
    required int userId,
    String? reason,
    String withdrawalType = 'OWNER',
  }) async {
    if (amount <= 0) {
      throw InvalidPaymentException('المبلغ يجب أن يكون موجباً');
    }

    return _db.runInTransactionSafe(() async {
      final withdrawalId = await _db.withdrawalDao.insertWithdrawal(
        WithdrawalsCompanion.insert(
          amount: amount.toDouble(),
          reason: reason != null ? Value(reason) : const Value.absent(),
          withdrawalType: Value(withdrawalType),
          userId: userId,
        ),
      );

      // تخفيض الصندوق
      await _db.cashTransactionDao.insertTransaction(
        CashTransactionsCompanion.insert(
          transactionType: MovementTypes.sourceWithdrawal,
          referenceType: Value(MovementTypes.sourceWithdrawal),
          referenceId: Value(withdrawalId),
          amount: amount.toDouble(),
          direction: CashDirection.outbound,
          description: Value('سحب: ${reason ?? withdrawalType}'),
          userId: Value(userId),
        ),
      );

      await _auditService.log(
        userId: userId,
        action: 'WITHDRAWAL_CREATED',
        module: 'cashbox',
        entityType: 'withdrawal',
        entityId: withdrawalId,
        description: 'سحب بقيمة $amount ($withdrawalType)',
      );

      return withdrawalId;
    });
  }

  /// تسجيل إيداع (زيادة رأس المال)
  Future<int> recordDeposit({
    required num amount,
    required int userId,
    String? reason,
  }) async {
    if (amount <= 0) {
      throw InvalidPaymentException('المبلغ يجب أن يكون موجباً');
    }

    return _db.runInTransactionSafe(() async {
      final txId = await _db.cashTransactionDao.insertTransaction(
        CashTransactionsCompanion.insert(
          transactionType: MovementTypes.sourceDeposit,
          amount: amount.toDouble(),
          direction: CashDirection.inbound,
          description: Value('إيداع: ${reason ?? ""}'),
          userId: Value(userId),
        ),
      );

      await _auditService.log(
        userId: userId,
        action: 'DEPOSIT_CREATED',
        module: 'cashbox',
        entityType: 'cash_transaction',
        entityId: txId,
        description: 'إيداع بقيمة $amount',
      );

      return txId;
    });
  }

  /// تسوية فرق الصندوق
  /// إذا كان هناك فرق بين المتوقع والفعلي، نسجل تسوية
  Future<int> recordAdjustment({
    required num difference, // المتوقع - الفعلي
    required int userId,
    required String reason,
  }) async {
    if (difference == 0) {
      throw ValidationException('لا يوجد فرق للتسوية');
    }

    return _db.runInTransactionSafe(() async {
      final txId = await _db.cashTransactionDao.insertTransaction(
        CashTransactionsCompanion.insert(
          transactionType: MovementTypes.sourceAdjustment,
          amount: difference.abs().toDouble(),
          direction: difference > 0 ? CashDirection.outbound : CashDirection.inbound,
          description: Value('تسوية صندوق: $reason'),
          userId: Value(userId),
        ),
      );

      await _auditService.log(
        userId: userId,
        action: 'CASHBOX_ADJUSTED',
        module: 'cashbox',
        entityType: 'cash_transaction',
        entityId: txId,
        description: 'تسوية صندوق بقيمة $difference: $reason',
      );

      AppLogger.accounting('Cashbox adjusted: diff=$difference');
      return txId;
    });
  }

  /// إغلاق اليوم - ينتج تقريراً يومياً
  Future<Map<String, num>> closeDay(int userId, DateTime day, {num? actualCash}) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    return _db.runInTransactionSafe(() async {
      // حساب كل المجاميع لليوم
      final openingForDay = await getExpectedBalance();
      final salesTotal = await _db.saleDao.totalCashSales(start, end);
      final purchasesTotal = await _db.purchaseDao.totalPurchases(start, end);
      final customerPayments = await _db.customerPaymentDao.totalPaymentsInRange(start, end);
      final supplierPayments = await _db.supplierPaymentDao.totalPaymentsInRange(start, end);
      final expenses = await _db.expenseDao.totalExpensesInRange(start, end);
      final withdrawals = await _db.withdrawalDao.totalWithdrawalsInRange(start, end);

      // الرصيد المتوقع في نهاية اليوم
      final expectedCash = openingForDay +
          salesTotal +
          customerPayments -
          purchasesTotal -
          supplierPayments -
          expenses -
          withdrawals;

      // تسجيل إغلاق اليوم
      await _auditService.log(
        userId: userId,
        action: 'DAY_CLOSED',
        module: 'cashbox',
        description: 'إغلاق يوم $day - مبيعات: $salesTotal، مشتريات: $purchasesTotal، مصروفات: $expenses',
      );

      return {
        'opening': openingForDay,
        'salesTotal': salesTotal,
        'purchasesTotal': purchasesTotal,
        'customerPayments': customerPayments,
        'supplierPayments': supplierPayments,
        'expenses': expenses,
        'withdrawals': withdrawals,
        'expectedCash': expectedCash,
        'actualCash': actualCash ?? expectedCash,
        'difference': (actualCash ?? expectedCash) - expectedCash,
      };
    });
  }
}
