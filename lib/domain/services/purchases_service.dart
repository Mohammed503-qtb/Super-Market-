import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/format_utils.dart';
import 'inventory_service.dart';
import 'audit_service.dart';
import 'sales_service.dart';

/// عنصر سلة الشراء
class PurchaseItemInput {
  final Product product;
  final num quantity;
  final num unitCost;

  PurchaseItemInput({
    required this.product,
    required this.quantity,
    required this.unitCost,
  });

  num get total => quantity * unitCost;
}

/// نتيجة عملية الشراء
class PurchaseResult {
  final Purchase purchase;
  final List<PurchaseItem> items;

  PurchaseResult({required this.purchase, required this.items});
}

/// خدمة المشتريات - تنفذ دورة الشراء الكاملة
class PurchasesService {
  final AppDatabase _db;
  final InventoryService _inventoryService;
  final AuditService _auditService;

  PurchasesService(this._db, this._inventoryService, this._auditService);

  /// إنشاء فاتورة شراء
  Future<PurchaseResult> createPurchase({
    required int userId,
    required List<PurchaseItemInput> items,
    int? supplierId,
    num discount = 0,
    required String paymentType, // CASH / CREDIT / MIXED
    required num paidAmount,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ValidationException('لا يمكن إنشاء فاتورة شراء فارغة');
    }
    if (paidAmount < 0) {
      throw InvalidPaymentException('المبلغ المدفوع لا يمكن أن يكون سالباً');
    }

    return _db.runInTransactionSafe(() async {
      // حساب الإجماليات
      num subtotal = 0;
      for (final item in items) {
        subtotal += item.total;
      }
      final finalTotal = subtotal - discount;

      // التحقق من المبلغ المدفوع
      num remaining = 0;
      if (paymentType == PaymentType.cash) {
        if (paidAmount < finalTotal) {
          throw InvalidPaymentException(
              'المبلغ المدفوع ($paidAmount) أقل من الإجمالي ($finalTotal)');
        }
        remaining = 0;
      } else if (paymentType == PaymentType.credit) {
        remaining = finalTotal;
      } else if (paymentType == PaymentType.mixed) {
        remaining = finalTotal - paidAmount;
      }

      // الشراء الآجل يتطلب مورد
      if (remaining > 0 && supplierId == null) {
        throw ValidationException('الشراء الآجل يتطلب اختيار مورد');
      }

      // توليد رقم الفاتورة
      final now = DateTime.now();
      final sequence = await _db.purchaseDao.getNextSequenceForToday(now);
      final invoiceNumber = CommonUtils.generateInvoiceNumber(
          AppConstants.invoicePrefixPurchase, now, sequence);

      // 1) إنشاء الفاتورة
      final purchaseId = await _db.purchaseDao.insertPurchase(PurchasesCompanion.insert(
        invoiceNumber: invoiceNumber,
        supplierId: supplierId != null ? Value(supplierId) : const Value.absent(),
        userId: userId,
        subtotal: Value(subtotal.toDouble()),
        discount: Value(discount.toDouble()),
        total: Value(finalTotal.toDouble()),
        paidAmount: Value(paidAmount.toDouble()),
        remainingAmount: Value(remaining.toDouble()),
        paymentType: Value(paymentType),
        status: Value(InvoiceStatus.completed),
        notes: notes != null ? Value(notes) : const Value.absent(),
      ));

      // 2) إنشاء عناصر الفاتورة + إدخال للمخزون + تحديث الأسعار
      final purchaseItems = <PurchaseItemsCompanion>[];
      for (final item in items) {
        purchaseItems.add(PurchaseItemsCompanion.insert(
          purchaseId: purchaseId,
          productId: item.product.id,
          quantity: item.quantity.toDouble(),
          unitCost: item.unitCost.toDouble(),
          total: item.total.toDouble(),
        ));

        // إدخال للمخزون مع تحديث التكلفة المرجحة
        await _inventoryService.stockIn(
          productId: item.product.id,
          quantity: item.quantity,
          unitCost: item.unitCost,
          userId: userId,
          movementType: MovementTypes.purchaseIn,
          referenceType: MovementTypes.sourcePurchase,
          referenceId: purchaseId,
        );

        // تحديث سعر الشراء للمنتج
        await _db.productDao.updatePrices(
          item.product.id,
          purchasePrice: item.unitCost,
        );
      }
      await _db.purchaseDao.insertItems(purchaseItems);
      final savedItems = await _db.purchaseDao.getItems(purchaseId);

      // 3) حركة النقد للجزء المدفوع
      if (paidAmount > 0) {
        await _db.cashTransactionDao.insertTransaction(
          CashTransactionsCompanion.insert(
            transactionType: MovementTypes.sourcePurchase,
            referenceType: Value(MovementTypes.sourcePurchase),
            referenceId: Value(purchaseId),
            amount: paidAmount.toDouble(),
            direction: CashDirection.outbound,
            description: Value('مشتريات - فاتورة $invoiceNumber'),
            userId: Value(userId),
          ),
        );
      }

      // 4) تحديث مديونية المورد
      if (remaining > 0 && supplierId != null) {
        final supplier = await _db.supplierDao.findById(supplierId);
        if (supplier != null) {
          await _db.supplierDao.updateBalance(
              supplierId, supplier.currentBalance + remaining);
        }
      }

      // 5) Audit Log
      await _auditService.log(
        userId: userId,
        action: 'PURCHASE_CREATED',
        module: 'purchases',
        entityType: 'purchase',
        entityId: purchaseId,
        description: 'إنشاء فاتورة شراء $invoiceNumber بقيمة $finalTotal',
      );

      final purchase = await _db.purchaseDao.findById(purchaseId);
      AppLogger.accounting(
          'Purchase created: $invoiceNumber total=$finalTotal paid=$paidAmount remaining=$remaining');

      return PurchaseResult(purchase: purchase!, items: savedItems);
    });
  }

  /// مرتجع شراء - يعكس الحركة
  Future<int> returnPurchase({
    required int originalPurchaseId,
    required int userId,
    required List<ReturnItemInput> items,
    num cashReturn = 0,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ValidationException('لا يمكن إنشاء مرتجع فارغ');
    }

    return _db.runInTransactionSafe(() async {
      final purchase = await _db.purchaseDao.findById(originalPurchaseId);
      if (purchase == null) {
        throw ValidationException('الفاتورة الأصلية غير موجودة');
      }

      final now = DateTime.now();
      final sequence = await _db.returnDao.getNextSequenceForToday(now, 'PRET');
      final returnNumber = CommonUtils.generateInvoiceNumber('PRET', now, sequence);

      num subtotal = 0;
      for (final item in items) {
        subtotal += item.total;
      }

      final returnId = await _db.returnDao.insertReturn(ReturnsCompanion.insert(
        returnNumber: returnNumber,
        returnType: 'PURCHASE_RETURN',
        referenceInvoiceId: originalPurchaseId,
        supplierId: purchase.supplierId != null ? Value(purchase.supplierId!) : const Value.absent(),
        userId: userId,
        subtotal: Value(subtotal.toDouble()),
        total: Value(subtotal.toDouble()),
        cashReturn: Value(cashReturn.toDouble()),
        notes: notes != null ? Value(notes) : const Value.absent(),
      ));

      final returnItems = <ReturnItemsCompanion>[];
      for (final item in items) {
        returnItems.add(ReturnItemsCompanion.insert(
          returnId: returnId,
          productId: item.productId,
          quantity: item.quantity.toDouble(),
          unitPrice: item.unitPrice.toDouble(),
          costPrice: Value(item.costPrice.toDouble()),
          total: item.total.toDouble(),
        ));

        // إخراج من المخزون
        await _inventoryService.stockOut(
          productId: item.productId,
          quantity: item.quantity,
          userId: userId,
          movementType: MovementTypes.purchaseReturnOut,
          unitCost: item.costPrice,
          referenceType: 'RETURN',
          referenceId: returnId,
          reason: 'مرتجع شراء $returnNumber',
        );
      }
      await _db.returnDao.insertItems(returnItems);

      // استرجاع النقد من المورد
      if (cashReturn > 0) {
        await _db.cashTransactionDao.insertTransaction(
          CashTransactionsCompanion.insert(
            transactionType: MovementTypes.sourceReturn,
            referenceType: const Value('RETURN'),
            referenceId: Value(returnId),
            amount: cashReturn.toDouble(),
            direction: CashDirection.inbound,
            description: Value('مرتجع شراء - $returnNumber'),
            userId: Value(userId),
          ),
        );
      }

      // تعديل مديونية المورد
      num supplierAdjustment = subtotal - cashReturn;
      if (supplierAdjustment > 0 && purchase.supplierId != null) {
        final supplier = await _db.supplierDao.findById(purchase.supplierId!);
        if (supplier != null) {
          await _db.supplierDao.updateBalance(
              supplier.id, supplier.currentBalance - supplierAdjustment);
        }
      }

      await _auditService.log(
        userId: userId,
        action: 'PURCHASE_RETURNED',
        module: 'purchases',
        entityType: 'return',
        entityId: returnId,
        description: 'مرتجع شراء $returnNumber بقيمة $subtotal',
      );

      AppLogger.accounting('Purchase returned: $returnNumber value=$subtotal');
      return returnId;
    });
  }
}
