import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_erp/core/constants/app_constants.dart';
import 'package:grocery_erp/core/errors/app_exceptions.dart';
import 'package:grocery_erp/data/database/app_database.dart';
import 'package:grocery_erp/domain/services/audit_service.dart';
import 'package:grocery_erp/domain/services/inventory_service.dart';
import 'package:grocery_erp/domain/services/sales_service.dart';

/// اختبارات SalesService - دورة البيع الكاملة (فاتورة + مخزون + نقد + دين + audit)
void main() {
  late AppDatabase db;
  late AuditService auditService;
  late InventoryService inventoryService;
  late SalesService salesService;
  late int adminUserId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auditService = AuditService(db);
    inventoryService = InventoryService(db);
    salesService = SalesService(db, inventoryService, auditService);

    final admin = await db.userDao.findByUsername('admin');
    adminUserId = admin!.id;
  });

  tearDown(() async {
    await db.close();
  });

  /// إنشاء منتج مع مخزون جاهز للبيع
  Future<Product> setupProduct({
    String name = 'Sale Product',
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
    // نرجع المنتج بعد تحديث المخزون
    return (await db.productDao.findById(id))!;
  }

  Future<int> createCustomer({double openingBalance = 0}) async {
    // نمرر currentBalance=openingBalance مباشرة كما يفعل customers_screen.dart
    return db.customerDao.insertCustomer(
      CustomersCompanion.insert(
        name: 'Customer Test',
        phone: const Value('0501234567'),
        openingBalance: Value(openingBalance),
        currentBalance: Value(openingBalance),
      ),
    );
  }

  group('SalesService.createSale - cash sale', () {
    test('cash sale reduces product stock by sold quantity', () async {
      final product = await setupProduct(qty: 10);
      final cart = [
        CartItem(
          product: product,
          quantity: 5,
          unitPrice: product.sellingPrice,
        ),
      ];

      final result = await salesService.createSale(
        userId: adminUserId,
        cart: cart,
        paymentType: PaymentType.cash,
        paidAmount: 5 * product.sellingPrice, // 40000
      );

      expect(result.sale.id, greaterThan(0));

      final updated = await db.productDao.findById(product.id);
      expect(updated!.currentStock, 5,
          reason: 'stock should be reduced by 5');
    });

    test('cash sale: paidAmount = total, remainingAmount = 0', () async {
      final product = await setupProduct(qty: 10);
      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      final result = await salesService.createSale(
        userId: adminUserId,
        cart: cart,
        paymentType: PaymentType.cash,
        paidAmount: 40000,
      );

      final sale = result.sale;
      expect(sale.subtotal, 40000);
      expect(sale.discount, 0);
      expect(sale.tax, 0);
      expect(sale.total, 40000);
      expect(sale.paidAmount, 40000);
      expect(sale.remainingAmount, 0);
      expect(sale.paymentType, PaymentType.cash);
      expect(sale.status, InvoiceStatus.completed);
    });

    test('cash sale creates a CashTransaction with direction IN for paid amount',
        () async {
      final product = await setupProduct(qty: 10);
      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      await salesService.createSale(
        userId: adminUserId,
        cart: cart,
        paymentType: PaymentType.cash,
        paidAmount: 40000,
      );

      final cashTx = await db.cashTransactionDao.getRecent(limit: 50);
      // نبحث عن حركة الدخل الخاصة بالبيع
      final saleIn = cashTx.where((t) =>
          t.transactionType == MovementTypes.sourceSale &&
          t.direction == CashDirection.inbound);
      expect(saleIn.length, greaterThanOrEqualTo(1));
      final tx = saleIn.first;
      expect(tx.amount, 40000);
      expect(tx.direction, CashDirection.inbound);
    });

    test('cash sale with paidAmount < total throws InvalidPaymentException',
        () async {
      final product = await setupProduct(qty: 10);
      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      expect(
        () => salesService.createSale(
          userId: adminUserId,
          cart: cart,
          paymentType: PaymentType.cash,
          paidAmount: 30000, // أقل من 40000
        ),
        throwsA(isA<InvalidPaymentException>()),
      );
    });

    test('cash sale creates an AuditLog with action SALE_CREATED', () async {
      final product = await setupProduct(qty: 10);
      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      final result = await salesService.createSale(
        userId: adminUserId,
        cart: cart,
        paymentType: PaymentType.cash,
        paidAmount: 40000,
      );

      final logs = await db.auditLogDao.getRecent(limit: 50);
      final saleLog = logs.firstWhere(
        (l) => l.action == 'SALE_CREATED' && l.entityId == result.sale.id,
      );
      expect(saleLog.action, 'SALE_CREATED');
      expect(saleLog.module, 'sales');
      expect(saleLog.userId, adminUserId);
    });

    test(
        'trying to sell more than stock throws InsufficientStockException',
        () async {
      final product = await setupProduct(qty: 3);
      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      expect(
        () => salesService.createSale(
          userId: adminUserId,
          cart: cart,
          paymentType: PaymentType.cash,
          paidAmount: 5 * product.sellingPrice,
        ),
        throwsA(isA<InsufficientStockException>()),
      );
    });

    test('empty cart throws ValidationException', () async {
      expect(
        () => salesService.createSale(
          userId: adminUserId,
          cart: const [],
          paymentType: PaymentType.cash,
          paidAmount: 0,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('SalesService.createSale - credit sale with customer', () {
    test(
        'credit sale: remainingAmount = total, customer.currentBalance '
        'increases by total', () async {
      final product = await setupProduct(qty: 10);
      // عميل برصيد افتتاحي 50000
      final customerId = await createCustomer(openingBalance: 50000);

      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      final result = await salesService.createSale(
        userId: adminUserId,
        cart: cart,
        customerId: customerId,
        paymentType: PaymentType.credit,
        paidAmount: 0,
      );

      final sale = result.sale;
      expect(sale.total, 40000);
      expect(sale.paidAmount, 0);
      expect(sale.remainingAmount, 40000);

      // العميل: 50000 (افتتاحي) + 40000 (دين جديد) = 90000
      final customer = await db.customerDao.findById(customerId);
      expect(customer!.currentBalance, 90000);
    });

    test('credit sale with no customer throws ValidationException', () async {
      final product = await setupProduct(qty: 10);
      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      expect(
        () => salesService.createSale(
          userId: adminUserId,
          cart: cart,
          // بدون customerId
          paymentType: PaymentType.credit,
          paidAmount: 0,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('credit sale does NOT create a CashTransaction (paidAmount == 0)',
        () async {
      final product = await setupProduct(qty: 10);
      final customerId = await createCustomer(openingBalance: 0);

      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      await salesService.createSale(
        userId: adminUserId,
        cart: cart,
        customerId: customerId,
        paymentType: PaymentType.credit,
        paidAmount: 0,
      );

      // لا توجد حركات نقد (الصندوق لم يتغير)
      final cashTx = await db.cashTransactionDao.getRecent(limit: 10);
      expect(cashTx, isEmpty);
    });
  });

  group('SalesService.createSale - mixed sale', () {
    test(
        'mixed sale: customer.currentBalance = total - paidAmount, '
        'CashTransaction created for paid amount', () async {
      final product = await setupProduct(qty: 10);
      final customerId = await createCustomer(openingBalance: 0);

      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      final result = await salesService.createSale(
        userId: adminUserId,
        cart: cart,
        customerId: customerId,
        paymentType: PaymentType.mixed,
        paidAmount: 15000, // نصف السعر تقريباً
      );

      final sale = result.sale;
      expect(sale.total, 40000);
      expect(sale.paidAmount, 15000);
      expect(sale.remainingAmount, 25000);

      // العميل: 0 + 25000 = 25000
      final customer = await db.customerDao.findById(customerId);
      expect(customer!.currentBalance, 25000);

      // حركة نقد بقيمة 15000 دخل
      final cashTx = await db.cashTransactionDao.getRecent(limit: 50);
      final saleTx = cashTx.firstWhere(
        (t) => t.transactionType == MovementTypes.sourceSale,
      );
      expect(saleTx.amount, 15000);
      expect(saleTx.direction, CashDirection.inbound);
    });

    test(
        'mixed sale with paidAmount > total throws OverpaymentException '
        'when allowOverpayment=false', () async {
      final product = await setupProduct(qty: 10);
      final customerId = await createCustomer(openingBalance: 0);

      final cart = [
        CartItem(
            product: product, quantity: 5, unitPrice: product.sellingPrice),
      ];

      expect(
        () => salesService.createSale(
          userId: adminUserId,
          cart: cart,
          customerId: customerId,
          paymentType: PaymentType.mixed,
          paidAmount: 50000, // أكثر من 40000
        ),
        throwsA(isA<OverpaymentException>()),
      );
    });
  });
}
