import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_erp/core/constants/app_constants.dart';
import 'package:grocery_erp/core/errors/app_exceptions.dart';
import 'package:grocery_erp/data/database/app_database.dart';
import 'package:grocery_erp/domain/services/inventory_service.dart';

/// اختبارات InventoryService - إدارة المخزون
/// تستخدم قاعدة بيانات في الذاكرة (NativeDatabase.memory)
void main() {
  late AppDatabase db;
  late InventoryService inventoryService;
  late int adminUserId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inventoryService = InventoryService(db);

    // البيانات الافتراضية (admin, roles, units, categories) تُحمّل تلقائياً
    final admin = await db.userDao.findByUsername('admin');
    adminUserId = admin!.id;
  });

  tearDown(() async {
    await db.close();
  });

  /// دالة مساعدة لإنشاء منتج بدون مخزون
  Future<int> createProduct({
    String name = 'Test Product',
    double purchasePrice = 5000,
    double sellingPrice = 8000,
  }) async {
    return db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: name,
        sellingPrice: Value(sellingPrice),
        purchasePrice: Value(purchasePrice),
        currentStock: const Value(0),
        averageCost: const Value(0),
      ),
    );
  }

  group('stockIn', () {
    test('stockIn 100 units at cost 5000 -> currentStock=100, averageCost=5000',
        () async {
      final productId = await createProduct();
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );

      final product = await db.productDao.findById(productId);
      expect(product!.currentStock, 100);
      expect(product.averageCost, 5000);
    });

    test(
        'stockIn 50 more at cost 6000 -> currentStock=150, '
        'averageCost ~ 5333.33 (weighted average)', () async {
      final productId = await createProduct();
      // أول إدخال
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );
      // ثاني إدخال بسعر مختلف
      await inventoryService.stockIn(
        productId: productId,
        quantity: 50,
        unitCost: 6000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );

      final product = await db.productDao.findById(productId);
      expect(product!.currentStock, 150);
      // (100*5000 + 50*6000)/150 = 800000/150 = 5333.33
      expect(product.averageCost, closeTo(5333.33, 0.01));
    });

    test('stockIn records an InventoryMovement with correct fields', () async {
      final productId = await createProduct();
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
        reason: 'شراء أول',
      );

      final movements = await db.inventoryMovementDao.getByProduct(productId);
      expect(movements.length, 1);
      final m = movements.first;
      expect(m.productId, productId);
      expect(m.movementType, MovementTypes.purchaseIn);
      expect(m.quantity, 100);
      expect(m.previousStock, 0);
      expect(m.newStock, 100);
      expect(m.unitCost, 5000);
      expect(m.userId, adminUserId);
      expect(m.reason, 'شراء أول');
    });

    test('stockIn with non-purchase movementType keeps old cost', () async {
      // movementType != PURCHASE_IN / OPENING_STOCK => averageCost unchanged
      final productId = await createProduct();
      // رصيد افتتاحي بسعر 5000
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.openingStock,
      );
      // إدخال تسوية بسعر 6000 - لا يغير التكلفة المرجحة
      await inventoryService.stockIn(
        productId: productId,
        quantity: 10,
        unitCost: 6000,
        userId: adminUserId,
        movementType: MovementTypes.adjustmentIn,
      );

      final product = await db.productDao.findById(productId);
      expect(product!.currentStock, 110);
      // التكلفة المرجحة لم تتغير = 5000
      expect(product.averageCost, 5000);
    });

    test('stockIn with non-positive quantity throws ValidationException',
        () async {
      final productId = await createProduct();
      expect(
        () => inventoryService.stockIn(
          productId: productId,
          quantity: 0,
          unitCost: 5000,
          userId: adminUserId,
          movementType: MovementTypes.purchaseIn,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('stockOut', () {
    test('stockOut 30 -> currentStock reduced by 30, averageCost unchanged',
        () async {
      final productId = await createProduct();
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );
      // التكلفة قبل الإخراج
      var product = await db.productDao.findById(productId);
      final costBefore = product!.averageCost;

      await inventoryService.stockOut(
        productId: productId,
        quantity: 30,
        userId: adminUserId,
        movementType: MovementTypes.saleOut,
      );

      product = await db.productDao.findById(productId);
      expect(product!.currentStock, 70);
      // التكلفة المرجحة لا تتغير عند الإخراج
      expect(product.averageCost, costBefore);
    });

    test('stockOut records an InventoryMovement with SALE_OUT type',
        () async {
      final productId = await createProduct();
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );
      await inventoryService.stockOut(
        productId: productId,
        quantity: 30,
        userId: adminUserId,
        movementType: MovementTypes.saleOut,
        unitCost: 5000,
        referenceType: 'SALE',
        referenceId: 999,
      );

      final movements = await db.inventoryMovementDao.getByProduct(productId);
      // 2 حركات: PURCHASE_IN + SALE_OUT
      expect(movements.length, 2);
      // نفلتر حسب النوع بدلاً من الاعتماد على الترتيب (قد يتساوى createdAt
      // عند إنشاء الحركات في نفس الثانية)
      final outMove = movements.firstWhere(
        (m) => m.movementType == MovementTypes.saleOut,
      );
      expect(outMove.quantity, 30);
      expect(outMove.previousStock, 100);
      expect(outMove.newStock, 70);
      expect(outMove.referenceType, 'SALE');
      expect(outMove.referenceId, 999);
    });

    test(
        'stockOut more than available with preventNegativeStock=true '
        'throws InsufficientStockException', () async {
      final productId = await createProduct();
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );

      // preventNegativeStock=true افتراضياً في الإعدادات
      expect(
        () => inventoryService.stockOut(
          productId: productId,
          quantity: 150,
          userId: adminUserId,
          movementType: MovementTypes.saleOut,
        ),
        throwsA(isA<InsufficientStockException>()),
      );
    });
  });

  group('adjustStock', () {
    test(
        'adjustStock with actualQty < systemQty creates ADJUSTMENT_OUT movement',
        () async {
      final productId = await createProduct();
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );

      // الجرد الفعلي = 95 (عجز 5)
      await inventoryService.adjustStock(
        productId: productId,
        actualQuantity: 95,
        userId: adminUserId,
        reason: 'جرد مخزون',
      );

      final product = await db.productDao.findById(productId);
      expect(product!.currentStock, 95);

      final movements = await db.inventoryMovementDao.getByProduct(productId);
      // نفلتر حسب النوع لتفادي مشكلة ترتيب createdAt المتساوي
      final lastMove = movements.firstWhere(
        (m) => m.movementType == MovementTypes.adjustmentOut,
      );
      expect(lastMove.quantity, 5);
      expect(lastMove.previousStock, 100);
      expect(lastMove.newStock, 95);
    });

    test(
        'adjustStock with actualQty > systemQty creates ADJUSTMENT_IN movement',
        () async {
      final productId = await createProduct();
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );

      // الجرد الفعلي = 110 (زيادة 10)
      await inventoryService.adjustStock(
        productId: productId,
        actualQuantity: 110,
        userId: adminUserId,
      );

      final product = await db.productDao.findById(productId);
      expect(product!.currentStock, 110);

      final movements = await db.inventoryMovementDao.getByProduct(productId);
      final lastMove = movements.firstWhere(
        (m) => m.movementType == MovementTypes.adjustmentIn,
      );
      expect(lastMove.quantity, 10);
      expect(lastMove.previousStock, 100);
      expect(lastMove.newStock, 110);
    });

    test('adjustStock with no difference does nothing', () async {
      final productId = await createProduct();
      await inventoryService.stockIn(
        productId: productId,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );

      await inventoryService.adjustStock(
        productId: productId,
        actualQuantity: 100,
        userId: adminUserId,
      );

      // لا تتأثر الكمية ولا تضاف حركة جديدة
      final product = await db.productDao.findById(productId);
      expect(product!.currentStock, 100);
      final movements = await db.inventoryMovementDao.getByProduct(productId);
      // PURCHASE_IN فقط
      expect(movements.length, 1);
      expect(movements.first.movementType, MovementTypes.purchaseIn);
    });
  });

  group('calculateInventoryValue', () {
    test('returns sum of currentStock * averageCost for all products', () async {
      // منتج 1: 100 وحدة × 5000 = 500000
      final p1 = await createProduct(name: 'P1', purchasePrice: 5000);
      await inventoryService.stockIn(
        productId: p1,
        quantity: 100,
        unitCost: 5000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );

      // منتج 2: 50 وحدة × 6000 = 300000
      final p2 = await createProduct(name: 'P2', purchasePrice: 6000);
      await inventoryService.stockIn(
        productId: p2,
        quantity: 50,
        unitCost: 6000,
        userId: adminUserId,
        movementType: MovementTypes.purchaseIn,
      );

      final total = await inventoryService.calculateInventoryValue();
      expect(total, 800000);
    });

    test('returns 0 for empty inventory (no products with stock)', () async {
      // قاعدة بيانات جديدة بدون منتجات
      final total = await inventoryService.calculateInventoryValue();
      expect(total, 0);
    });
  });
}
