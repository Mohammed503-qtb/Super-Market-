import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/format_utils.dart';

/// خدمة المخزون - تدير كل تغيرات المخزون عبر Inventory Movements
/// لا يتم تعديل currentStock مباشرة بل من خلال هذه الخدمة
class InventoryService {
  final AppDatabase _db;

  InventoryService(this._db);

  /// إدخال بضاعة (شراء أو تسوية موجبة)
  /// يحدث: المخزون، التكلفة المرجحة، وحركة المخزون
  Future<void> stockIn({
    required int productId,
    required num quantity,
    required num unitCost,
    required int userId,
    required String movementType,
    String? referenceType,
    int? referenceId,
    String? reason,
  }) async {
    if (quantity <= 0) {
      throw ValidationException('الكمية يجب أن تكون موجبة');
    }
    if (unitCost < 0) {
      throw ValidationException('التكلفة لا يمكن أن تكون سالبة');
    }

    await _db.runInTransactionSafe(() async {
      final product = await _db.productDao.findById(productId);
      if (product == null) {
        throw ValidationException('المنتج غير موجود');
      }

      final oldStock = product.currentStock;
      final oldCost = product.averageCost;
      final newStock = oldStock + quantity;

      // حساب التكلفة المرجحة
      final newAvgCost = (movementType == MovementTypes.purchaseIn ||
              movementType == MovementTypes.openingStock)
          ? MoneyUtils.weightedAverageCost(oldStock, oldCost, quantity, unitCost)
          : oldCost;

      // تحديث المنتج
      await _db.productDao.updateStock(productId, newStock, newAvgCost);

      // تسجيل حركة المخزون
      await _db.inventoryMovementDao.insertMovement(
        InventoryMovementsCompanion.insert(
          productId: productId,
          movementType: movementType,
          referenceType: referenceType != null ? Value(referenceType) : const Value.absent(),
          referenceId: referenceId != null ? Value(referenceId) : const Value.absent(),
          quantity: quantity.toDouble(),
          previousStock: Value(oldStock.toDouble()),
          newStock: Value(newStock.toDouble()),
          unitCost: Value(unitCost.toDouble()),
          userId: Value(userId),
          reason: reason != null ? Value(reason) : const Value.absent(),
        ),
      );

      AppLogger.inventory(
          'Stock IN: product=$productId qty=$quantity type=$movementType newStock=$newStock');
    });
  }

  /// إخراج بضاعة (بيع أو تسوية سالبة)
  Future<void> stockOut({
    required int productId,
    required num quantity,
    required int userId,
    required String movementType,
    num? unitCost, // تكلفة الوحدة (من averageCost للمنتج)
    String? referenceType,
    int? referenceId,
    String? reason,
  }) async {
    if (quantity <= 0) {
      throw ValidationException('الكمية يجب أن تكون موجبة');
    }

    await _db.runInTransactionSafe(() async {
      final product = await _db.productDao.findById(productId);
      if (product == null) {
        throw ValidationException('المنتج غير موجود');
      }

      final settings = await _db.settingDao.getSettings();
      final preventNegative = settings?.preventNegativeStock ?? true;

      final oldStock = product.currentStock;
      final newStock = oldStock - quantity;

      if (newStock < 0 && preventNegative) {
        throw InsufficientStockException(product.name, oldStock, quantity);
      }

      // تكلفة الإخراج = التكلفة المرجحة الحالية
      final usedCost = unitCost ?? product.averageCost;

      // تحديث المنتج (لا نغير التكلفة عند الإخراج)
      await _db.productDao.updateStock(productId, newStock, product.averageCost);

      // تسجيل حركة المخزون
      await _db.inventoryMovementDao.insertMovement(
        InventoryMovementsCompanion.insert(
          productId: productId,
          movementType: movementType,
          referenceType: referenceType != null ? Value(referenceType) : const Value.absent(),
          referenceId: referenceId != null ? Value(referenceId) : const Value.absent(),
          quantity: quantity.toDouble(),
          previousStock: Value(oldStock.toDouble()),
          newStock: Value(newStock.toDouble()),
          unitCost: Value(usedCost.toDouble()),
          userId: Value(userId),
          reason: reason != null ? Value(reason) : const Value.absent(),
        ),
      );

      AppLogger.inventory(
          'Stock OUT: product=$productId qty=$quantity type=$movementType newStock=$newStock');
    });
  }

  /// تسوية مخزون (يدوياً من شاشة الجرد)
  Future<void> adjustStock({
    required int productId,
    required num actualQuantity,
    required int userId,
    String? reason,
  }) async {
    await _db.runInTransactionSafe(() async {
      final product = await _db.productDao.findById(productId);
      if (product == null) {
        throw ValidationException('المنتج غير موجود');
      }

      final systemQty = product.currentStock;
      final diff = actualQuantity - systemQty;

      if (diff == 0) return; // لا يوجد فرق

      if (diff > 0) {
        await stockIn(
          productId: productId,
          quantity: diff.abs(),
          unitCost: product.averageCost,
          userId: userId,
          movementType: MovementTypes.adjustmentIn,
          reason: reason ?? 'تسوية مخزون موجبة',
        );
      } else {
        await stockOut(
          productId: productId,
          quantity: diff.abs(),
          userId: userId,
          movementType: MovementTypes.adjustmentOut,
          unitCost: product.averageCost,
          reason: reason ?? 'تسوية مخزون سالبة',
        );
      }
    });
  }

  /// إدخال رصيد افتتاحي للمنتج
  Future<void> setOpeningStock({
    required int productId,
    required num quantity,
    required num unitCost,
    required int userId,
  }) async {
    await stockIn(
      productId: productId,
      quantity: quantity,
      unitCost: unitCost,
      userId: userId,
      movementType: MovementTypes.openingStock,
      reason: 'رصيد افتتاحي',
    );
  }

  /// حساب قيمة المخزون الكلية (current stock * average cost)
  Future<num> calculateInventoryValue() async {
    final products = await _db.productDao.getAll();
    num total = 0;
    for (final p in products) {
      total += p.currentStock * p.averageCost;
    }
    return total;
  }

  /// كشف حركة صنف لفترة معينة
  Future<List<InventoryMovement>> getProductMovements(
    int productId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (startDate != null && endDate != null) {
      final moves = await _db.inventoryMovementDao.getByDateRange(startDate, endDate);
      return moves.where((m) => m.productId == productId).toList();
    }
    return _db.inventoryMovementDao.getByProduct(productId);
  }

  /// جرد كامل للمخزون
  Future<List<Map<String, dynamic>>> getStocktakeData() async {
    final products = await _db.productDao.getActive();
    return products.map((p) {
      return {
        'product': p,
        'systemQuantity': p.currentStock,
        'unitCost': p.averageCost,
        'totalValue': p.currentStock * p.averageCost,
      };
    }).toList();
  }
}
