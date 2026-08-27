import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_erp/core/constants/app_constants.dart';
import 'package:grocery_erp/core/errors/app_exceptions.dart';
import 'package:grocery_erp/data/database/app_database.dart';
import 'package:grocery_erp/domain/services/audit_service.dart';
import 'package:grocery_erp/domain/services/cashbox_service.dart';

/// اختبارات CashboxService - الحركات النقدية (مصروفات، سحوبات، إيداعات، رصيد متوقع)
void main() {
  late AppDatabase db;
  late AuditService auditService;
  late CashboxService cashboxService;
  late int adminUserId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auditService = AuditService(db);
    cashboxService = CashboxService(db, auditService);

    final admin = await db.userDao.findByUsername('admin');
    adminUserId = admin!.id;
  });

  tearDown(() async {
    await db.close();
  });

  Future<num> totalInbound() async => db.cashTransactionDao.totalInbound();
  Future<num> totalOutbound() async => db.cashTransactionDao.totalOutbound();

  group('CashboxService.recordExpense', () {
    test('records a CashTransaction with direction OUT, amount 5000', () async {
      final expenseId = await cashboxService.recordExpense(
        amount: 5000,
        category: 'إيجار',
        userId: adminUserId,
        description: 'إيجار المحل',
      );

      expect(expenseId, greaterThan(0));

      final txs = await db.cashTransactionDao.getRecent(limit: 10);
      final expenseTx = txs.firstWhere(
        (t) => t.transactionType == MovementTypes.sourceExpense,
      );
      expect(expenseTx.direction, CashDirection.outbound);
      expect(expenseTx.amount, 5000);
      expect(expenseTx.referenceId, expenseId);
      expect(expenseTx.userId, adminUserId);
    });

    test('rejects non-positive amount', () async {
      expect(
        () => cashboxService.recordExpense(
          amount: 0,
          category: 'X',
          userId: adminUserId,
        ),
        throwsA(isA<InvalidPaymentException>()),
      );
    });
  });

  group('CashboxService.recordWithdrawal', () {
    test('records a CashTransaction with direction OUT, amount 10000',
        () async {
      final withdrawalId = await cashboxService.recordWithdrawal(
        amount: 10000,
        userId: adminUserId,
        reason: 'سحب مالك',
      );

      expect(withdrawalId, greaterThan(0));

      final txs = await db.cashTransactionDao.getRecent(limit: 10);
      final wTx = txs.firstWhere(
        (t) => t.transactionType == MovementTypes.sourceWithdrawal,
      );
      expect(wTx.direction, CashDirection.outbound);
      expect(wTx.amount, 10000);
      expect(wTx.referenceId, withdrawalId);
    });

    test('rejects non-positive amount', () async {
      expect(
        () => cashboxService.recordWithdrawal(
          amount: -5,
          userId: adminUserId,
        ),
        throwsA(isA<InvalidPaymentException>()),
      );
    });
  });

  group('CashboxService.recordDeposit', () {
    test('records a CashTransaction with direction IN, amount 20000', () async {
      final txId = await cashboxService.recordDeposit(
        amount: 20000,
        userId: adminUserId,
        reason: 'إيداع رأس مال',
      );

      expect(txId, greaterThan(0));

      final txs = await db.cashTransactionDao.getRecent(limit: 10);
      final dTx = txs.firstWhere(
        (t) => t.transactionType == MovementTypes.sourceDeposit,
      );
      expect(dTx.direction, CashDirection.inbound);
      expect(dTx.amount, 20000);
      expect(dTx.id, txId);
    });

    test('rejects non-positive amount', () async {
      expect(
        () => cashboxService.recordDeposit(
          amount: 0,
          userId: adminUserId,
        ),
        throwsA(isA<InvalidPaymentException>()),
      );
    });
  });

  group('CashboxService.getExpectedBalance', () {
    test(
        'getExpectedBalance = opening + IN - OUT (verified with multiple '
        'transactions)', () async {
      // افتتاحي من الإعدادات = 0 افتراضياً
      final opening0 = await cashboxService.getOpeningBalance();
      expect(opening0, 0);

      // إيداع 20000 (دخل)
      await cashboxService.recordDeposit(
        amount: 20000,
        userId: adminUserId,
      );
      // مصروف 5000 (خارج)
      await cashboxService.recordExpense(
        amount: 5000,
        category: 'كهرباء',
        userId: adminUserId,
      );
      // سحب 10000 (خارج)
      await cashboxService.recordWithdrawal(
        amount: 10000,
        userId: adminUserId,
      );
      // إيداع آخر 3000 (دخل)
      await cashboxService.recordDeposit(
        amount: 3000,
        userId: adminUserId,
      );

      // المتوقع = 0 + (20000 + 3000) - (5000 + 10000) = 23000 - 15000 = 8000
      final expected = await cashboxService.getExpectedBalance();
      expect(expected, 8000);

      // مطابقة مع المجاميع المنفصلة
      final inb = await totalInbound();
      final outb = await totalOutbound();
      expect(inb, 23000);
      expect(outb, 15000);
    });

    test('getExpectedBalance returns opening when no transactions', () async {
      final opening = await cashboxService.getOpeningBalance();
      final expected = await cashboxService.getExpectedBalance();
      expect(expected, opening);
    });
  });

  group('CashboxService.recordAdjustment', () {
    test('rejects adjustment of 0', () async {
      expect(
        () => cashboxService.recordAdjustment(
          difference: 0,
          userId: adminUserId,
          reason: 'لا يوجد فرق',
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
        'positive difference (expected > actual) creates OUTBOUND transaction',
        () async {
      final txId = await cashboxService.recordAdjustment(
        difference: 500, // المتوقع أكبر من الفعلي بنقص 500
        userId: adminUserId,
        reason: 'عجز صندوق',
      );

      expect(txId, greaterThan(0));
      final txs = await db.cashTransactionDao.getRecent(limit: 10);
      final adjTx = txs.firstWhere(
        (t) => t.transactionType == MovementTypes.sourceAdjustment,
      );
      expect(adjTx.direction, CashDirection.outbound);
      expect(adjTx.amount, 500);
    });

    test(
        'negative difference (actual > expected) creates INBOUND transaction',
        () async {
      final txId = await cashboxService.recordAdjustment(
        difference: -300, // الفعلي أكبر من المتوقع بـ 300
        userId: adminUserId,
        reason: 'فائض صندوق',
      );

      expect(txId, greaterThan(0));
      final txs = await db.cashTransactionDao.getRecent(limit: 10);
      final adjTx = txs.firstWhere(
        (t) => t.transactionType == MovementTypes.sourceAdjustment,
      );
      expect(adjTx.direction, CashDirection.inbound);
      expect(adjTx.amount, 300);
    });
  });
}
