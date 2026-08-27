import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_erp/core/constants/app_constants.dart';
import 'package:grocery_erp/data/database/app_database.dart';
import 'package:grocery_erp/domain/services/accounting_service.dart';
import 'package:grocery_erp/domain/services/audit_service.dart';
import 'package:grocery_erp/domain/services/cashbox_service.dart';
import 'package:grocery_erp/domain/services/inventory_service.dart';
import 'package:grocery_erp/domain/services/sales_service.dart';

/// اختبارات AccountingService - COGS، الربح الإجمالي، صافي المبيعات، الربح التشغيلي
void main() {
  late AppDatabase db;
  late AuditService auditService;
  late InventoryService inventoryService;
  late SalesService salesService;
  late AccountingService accountingService;
  late CashboxService cashboxService;
  late int adminUserId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auditService = AuditService(db);
    inventoryService = InventoryService(db);
    salesService = SalesService(db, inventoryService, auditService);
    accountingService = AccountingService(db, inventoryService);
    cashboxService = CashboxService(db, auditService);

    final admin = await db.userDao.findByUsername('admin');
    adminUserId = admin!.id;
  });

  tearDown(() async {
    await db.close();
  });

  /// نطاق تاريخ اليوم (يبدأ من 00:00 اليوم إلى 00:00 الغد)
  DateTime getDayStart() =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime getDayEnd() => getDayStart().add(const Duration(days: 1));

  /// إعداد منتج متوسط التكلفة 5000 وسعر البيع 8000
  Future<Product> setupProduct({
    double purchasePrice = 5000,
    double sellingPrice = 8000,
    double qty = 10,
  }) async {
    final id = await db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: 'Accounting Product',
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

  group('AccountingService.calculateCOGS', () {
    test(
        'sale of 10 units @ cost 5000/unit -> COGS = 50000', () async {
      final product = await setupProduct(qty: 10);

      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 10, unitPrice: 8000)],
        paymentType: PaymentType.cash,
        paidAmount: 80000,
      );

      final cogs = await accountingService.calculateCOGS(getDayStart(), getDayEnd());
      expect(cogs, 50000);
    });

    test('COGS = 0 when there are no sales in range', () async {
      final cogs = await accountingService.calculateCOGS(getDayStart(), getDayEnd());
      expect(cogs, 0);
    });
  });

  group('AccountingService.grossSales', () {
    test('sale of 10 units @ 8000/unit -> grossSales = 80000', () async {
      final product = await setupProduct(qty: 10);

      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 10, unitPrice: 8000)],
        paymentType: PaymentType.cash,
        paidAmount: 80000,
      );

      final gross = await accountingService.grossSales(getDayStart(), getDayEnd());
      expect(gross, 80000);
    });
  });

  group('AccountingService.netSales', () {
    test('netSales = grossSales - returns = 80000 when no returns', () async {
      final product = await setupProduct(qty: 10);

      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 10, unitPrice: 8000)],
        paymentType: PaymentType.cash,
        paidAmount: 80000,
      );

      final net = await accountingService.netSales(getDayStart(), getDayEnd());
      // لا مرتجعات => net = gross
      expect(net, 80000);

      final returns = await accountingService.salesReturns(getDayStart(), getDayEnd());
      expect(returns, 0);
    });
  });

  group('AccountingService.grossProfit', () {
    test(
        'sale of 10 units @ cost 5000 sold at 8000 -> grossProfit = 30000',
        () async {
      final product = await setupProduct(qty: 10);

      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 10, unitPrice: 8000)],
        paymentType: PaymentType.cash,
        paidAmount: 80000,
      );

      final cogs = await accountingService.calculateCOGS(getDayStart(), getDayEnd());
      final net = await accountingService.netSales(getDayStart(), getDayEnd());
      final gp = await accountingService.grossProfit(getDayStart(), getDayEnd());

      expect(cogs, 50000);
      expect(net, 80000);
      expect(gp, 30000);
    });

    test('grossProfit = 0 when no sales', () async {
      final gp = await accountingService.grossProfit(getDayStart(), getDayEnd());
      expect(gp, 0);
    });
  });

  group('AccountingService.operatingProfit', () {
    test(
        'operatingProfit = grossProfit - expenses '
        '(verified: 30000 - 10000 = 20000)', () async {
      final product = await setupProduct(qty: 10);

      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 10, unitPrice: 8000)],
        paymentType: PaymentType.cash,
        paidAmount: 80000,
      );

      // مصروف تشغيلي 10000
      await cashboxService.recordExpense(
        amount: 10000,
        category: 'كهرباء',
        userId: adminUserId,
      );

      final op = await accountingService.operatingProfit(getDayStart(), getDayEnd());
      // grossProfit (30000) - expenses (10000) = 20000
      expect(op, 20000);
    });

    test(
        'operatingProfit = grossProfit when no expenses '
        '(verified: 30000 - 0 = 30000)', () async {
      final product = await setupProduct(qty: 10);

      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 10, unitPrice: 8000)],
        paymentType: PaymentType.cash,
        paidAmount: 80000,
      );

      final op = await accountingService.operatingProfit(getDayStart(), getDayEnd());
      expect(op, 30000);
    });
  });

  group('AccountingService multi-sale scenario', () {
    test(
        'multiple sales aggregate correctly: 2 sales of 5 units each '
        '-> total gross=80000, COGS=50000, grossProfit=30000', () async {
      final product = await setupProduct(qty: 20);

      // أول بيع: 5 وحدات
      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 5, unitPrice: 8000)],
        paymentType: PaymentType.cash,
        paidAmount: 40000,
      );
      // ثاني بيع: 5 وحدات
      await salesService.createSale(
        userId: adminUserId,
        cart: [CartItem(product: product, quantity: 5, unitPrice: 8000)],
        paymentType: PaymentType.cash,
        paidAmount: 40000,
      );

      final gross = await accountingService.grossSales(getDayStart(), getDayEnd());
      final cogs = await accountingService.calculateCOGS(getDayStart(), getDayEnd());
      final gp = await accountingService.grossProfit(getDayStart(), getDayEnd());

      expect(gross, 80000);
      expect(cogs, 50000);
      expect(gp, 30000);
    });
  });
}
