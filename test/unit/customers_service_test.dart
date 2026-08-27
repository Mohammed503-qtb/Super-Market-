import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_erp/core/constants/app_constants.dart';
import 'package:grocery_erp/core/errors/app_exceptions.dart';
import 'package:grocery_erp/data/database/app_database.dart';
import 'package:grocery_erp/domain/services/audit_service.dart';
import 'package:grocery_erp/domain/services/customers_service.dart';
import 'package:grocery_erp/domain/services/inventory_service.dart';
import 'package:grocery_erp/domain/services/sales_service.dart';

/// اختبارات CustomersService - الأرصدة، المدفوعات، كشوف الحساب
void main() {
  late AppDatabase db;
  late AuditService auditService;
  late InventoryService inventoryService;
  late SalesService salesService;
  late CustomersService customersService;
  late int adminUserId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auditService = AuditService(db);
    inventoryService = InventoryService(db);
    salesService = SalesService(db, inventoryService, auditService);
    customersService = CustomersService(db, auditService);

    final admin = await db.userDao.findByUsername('admin');
    adminUserId = admin!.id;
  });

  tearDown(() async {
    await db.close();
  });

  /// إنشاء منتج مع مخزون جاهز للبيع
  Future<Product> setupProduct({
    String name = 'Product',
    double purchasePrice = 5000,
    double sellingPrice = 8000,
    double qty = 10,
  }) async {
    final id = await db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: name,
        sellingPrice: Value(sellingPrice),
        purchasePrice: Value(purchasePrice),
        currentStock: const Value(0),
        averageCost: const Value(0),
      ),
    );
    await inventoryService.stockIn(
      productId: id,
      quantity: qty,
      unitCost: purchasePrice,
      userId: adminUserId,
      movementType: MovementTypes.purchaseIn,
    );
    return (await db.productDao.findById(id))!;
  }

  group('CustomersService.createCustomer', () {
    test(
        'creating customer with openingBalance 50000 sets currentBalance '
        'to 50000', () async {
      final id = await customersService.createCustomer(
        CustomersCompanion.insert(
          name: 'Test Customer',
          phone: const Value('0501234567'),
          openingBalance: const Value(50000),
        ),
        adminUserId,
      );

      final customer = await db.customerDao.findById(id);
      expect(customer, isNotNull);
      expect(customer!.openingBalance, 50000);
      expect(customer.currentBalance, 50000);
    });

    test('creating customer with no openingBalance has currentBalance 0',
        () async {
      final id = await customersService.createCustomer(
        CustomersCompanion.insert(name: 'Zero Customer'),
        adminUserId,
      );

      final customer = await db.customerDao.findById(id);
      expect(customer!.currentBalance, 0);
    });

    test('creating customer emits a CUSTOMER_CREATED audit log', () async {
      final id = await customersService.createCustomer(
        CustomersCompanion.insert(name: 'Audit Customer'),
        adminUserId,
      );

      final logs = await db.auditLogDao.getRecent(limit: 10);
      final log = logs.firstWhere(
        (l) => l.action == 'CUSTOMER_CREATED' && l.entityId == id,
      );
      expect(log.module, 'customers');
      expect(log.userId, adminUserId);
    });
  });

  group('CustomersService.receivePayment', () {
    test(
        'credit sale for 30000 on customer with openingBalance 50000 '
        '-> currentBalance = 80000', () async {
      final product = await setupProduct(qty: 10);
      final customerId = await customersService.createCustomer(
        CustomersCompanion.insert(
          name: 'Credit Customer',
          openingBalance: const Value(50000),
        ),
        adminUserId,
      );

      // نستخدم unitPrice=10000 و qty=3 => total = 30000
      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 3, unitPrice: 10000)],
        customerId: customerId,
        paymentType: PaymentType.credit,
        paidAmount: 0,
      );

      final customer = await db.customerDao.findById(customerId);
      // 50000 افتتاحي + 30000 دين جديد
      expect(customer!.currentBalance, 80000);
    });

    test(
        'receivePayment of 20000 reduces balance and creates a '
        'CashTransaction with direction IN', () async {
      final product = await setupProduct(qty: 10);
      final customerId = await customersService.createCustomer(
        CustomersCompanion.insert(
          name: 'Paying Customer',
          openingBalance: const Value(50000),
        ),
        adminUserId,
      );

      // نضع دين جديد 30000 (10000×3)
      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 3, unitPrice: 10000)],
        customerId: customerId,
        paymentType: PaymentType.credit,
        paidAmount: 0,
      );
      var customer = await db.customerDao.findById(customerId);
      expect(customer!.currentBalance, 80000);

      // سداد 20000
      final paymentId = await customersService.receivePayment(
        customerId: customerId,
        amount: 20000,
        userId: adminUserId,
      );

      expect(paymentId, greaterThan(0));

      customer = await db.customerDao.findById(customerId);
      // 80000 - 20000 = 60000
      expect(customer!.currentBalance, 60000);

      // يجب وجود حركة نقد دخل بقيمة 20000
      final txs = await db.cashTransactionDao.getRecent(limit: 50);
      final paymentTx = txs.firstWhere(
        (t) => t.transactionType == MovementTypes.sourceCustomerPayment,
      );
      expect(paymentTx.amount, 20000);
      expect(paymentTx.direction, CashDirection.inbound);
      expect(paymentTx.referenceId, paymentId);
    });

    test(
        'receivePayment with amount > currentBalance and '
        'allowOverpayment=false throws OverpaymentException', () async {
      final customerId = await customersService.createCustomer(
        CustomersCompanion.insert(
          name: 'Small Debt Customer',
          openingBalance: const Value(5000), // دين صغير
        ),
        adminUserId,
      );

      // محاولة سداد 20000 على دين 5000
      expect(
        () => customersService.receivePayment(
          customerId: customerId,
          amount: 20000,
          userId: adminUserId,
        ),
        throwsA(isA<OverpaymentException>()),
      );
    });

    test('receivePayment with non-positive amount throws InvalidPayment',
        () async {
      final customerId = await customersService.createCustomer(
        CustomersCompanion.insert(
          name: 'Zero Payment Customer',
          openingBalance: const Value(1000),
        ),
        adminUserId,
      );

      expect(
        () => customersService.receivePayment(
          customerId: customerId,
          amount: 0,
          userId: adminUserId,
        ),
        throwsA(isA<InvalidPaymentException>()),
      );
    });

    test('receivePayment on non-existing customer throws ValidationException',
        () async {
      expect(
        () => customersService.receivePayment(
          customerId: 99999,
          amount: 100,
          userId: adminUserId,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('CustomersService.getStatement', () {
    test(
        'statement includes OPENING, SALE (debit), and PAYMENT (credit) '
        'entries with running balance', () async {
      final product = await setupProduct(qty: 10);
      final customerId = await customersService.createCustomer(
        CustomersCompanion.insert(
          name: 'Statement Customer',
          openingBalance: const Value(50000),
        ),
        adminUserId,
      );

      // دين جديد 30000
      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 3, unitPrice: 10000)],
        customerId: customerId,
        paymentType: PaymentType.credit,
        paidAmount: 0,
      );

      // سداد 20000
      await customersService.receivePayment(
        customerId: customerId,
        amount: 20000,
        userId: adminUserId,
      );

      final statement = await customersService.getStatement(customerId);

      // على الأقل 3 إدخالات: OPENING, SALE, PAYMENT
      expect(statement.length, greaterThanOrEqualTo(3));

      final types = statement.map((e) => e['type'] as String).toList();
      expect(types, contains('OPENING'));
      expect(types, contains('SALE'));
      expect(types, contains('PAYMENT'));

      // الرصيد النهائي = 50000 + 30000 - 20000 = 60000
      final lastBalance = statement.last['balance'] as num;
      expect(lastBalance, 60000);

      // افتتاحي بقيمة 50000
      final opening = statement.firstWhere((e) => e['type'] == 'OPENING');
      expect(opening['balance'], 50000);

      // البيع (مدين)
      final saleEntry = statement.firstWhere((e) => e['type'] == 'SALE');
      expect(saleEntry['debit'], 30000);
      expect(saleEntry['credit'], 0);

      // الدفع (دائن)
      final paymentEntry = statement.firstWhere((e) => e['type'] == 'PAYMENT');
      expect(paymentEntry['credit'], 20000);
      expect(paymentEntry['debit'], 0);
    });

    test('statement for non-existing customer returns empty list', () async {
      final stmt = await customersService.getStatement(99999);
      expect(stmt, isEmpty);
    });
  });
}
