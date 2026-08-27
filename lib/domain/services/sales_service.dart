import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/format_utils.dart';
import 'inventory_service.dart';
import 'audit_service.dart';

/// عنصر سلة البيع
class CartItem {
  final Product product;
  num quantity;
  num unitPrice;
  num discount; // خصم على البند

  CartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
  });

  num get total => (unitPrice * quantity) - discount;

  CartItem copyWith({
    num? quantity,
    num? unitPrice,
    num? discount,
  }) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
    );
  }
}

/// نتيجة عملية البيع
class SaleResult {
  final Sale sale;
  final List<SaleItem> items;

  SaleResult({required this.sale, required this.items});
}

/// خدمة المبيعات - تنفذ دورة البيع الكاملة كمعاملة ذرية
class SalesService {
  final AppDatabase _db;
  final InventoryService _inventoryService;
  final AuditService _auditService;

  SalesService(this._db, this._inventoryService, this._auditService);

  /// إنشاء فاتورة بيع
  /// دورة البيع:
  /// 1. التحقق من الصلاحيات
  /// 2. التحقق من المنتجات والمخزون
  /// 3. حساب الإجماليات والتكلفة
  /// 4. إنشاء الفاتورة + العناصر + حركات المخزون + النقد/الدين + Audit Log
  /// 5. Commit (Rollback عند الفشل)
  Future<SaleResult> createSale({
    required int userId,
    List<CartItem> cart = const [],
    int? customerId,
    num discount = 0,
    num tax = 0,
    required String paymentType, // CASH / CREDIT / MIXED
    required num paidAmount,
    String? notes,
    bool requireStock = true,
  }) async {
    if (cart.isEmpty) {
      throw ValidationException('لا يمكن إنشاء فاتورة فارغة');
    }

    // التحقق من نوع الدفع
    if (paymentType != PaymentType.cash &&
        paymentType != PaymentType.credit &&
        paymentType != PaymentType.mixed) {
      throw ValidationException('نوع الدفع غير صالح');
    }

    if (paidAmount < 0) {
      throw InvalidPaymentException('المبلغ المدفوع لا يمكن أن يكون سالباً');
    }

    return _db.runInTransactionSafe(() async {
      // حساب الإجماليات
      num subtotal = 0;
      num totalCost = 0;
      for (final item in cart) {
        subtotal += item.total;
        // تكلفة البند = الكمية × متوسط التكلفة
        totalCost += item.quantity * item.product.averageCost;
      }

      final totalAfterDiscount = subtotal - discount;
      final totalWithTax = totalAfterDiscount + tax;
      final finalTotal = totalWithTax;

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
        if (paidAmount > finalTotal) {
          // التحقق من الإعداد
          final settings = await _db.settingDao.getSettings();
          if (!(settings?.allowOverpayment ?? false)) {
            throw OverpaymentException(paidAmount, finalTotal);
          }
        }
        remaining = finalTotal - paidAmount;
      }

      // التحقق من العميل للبيع الآجل
      if (remaining > 0 && customerId == null) {
        throw ValidationException('البيع الآجل يتطلب اختيار عميل');
      }

      // التحقق من حد الائتمان
      if (remaining > 0 && customerId != null) {
        final customer = await _db.customerDao.findById(customerId);
        if (customer != null && customer.creditLimit != null) {
          if (customer.currentBalance + remaining > customer.creditLimit!) {
            throw OperationNotAllowedException(
                'البيع يتجاوز حد الائتمان المسموح للعميل');
          }
        }
      }

      // توليد رقم الفاتورة
      final now = DateTime.now();
      final sequence = await _db.saleDao.getNextSequenceForToday(now);
      final invoiceNumber = CommonUtils.generateInvoiceNumber(
          AppConstants.invoicePrefixSale, now, sequence);

      // 1) إنشاء الفاتورة
      final saleId = await _db.saleDao.insertSale(SalesCompanion.insert(
        invoiceNumber: invoiceNumber,
        customerId: customerId != null ? Value(customerId) : const Value.absent(),
        userId: userId,
        subtotal: Value(subtotal.toDouble()),
        discount: Value(discount.toDouble()),
        tax: Value(tax.toDouble()),
        total: Value(finalTotal.toDouble()),
        paidAmount: Value(paidAmount.toDouble()),
        remainingAmount: Value(remaining.toDouble()),
        paymentType: Value(paymentType),
        status: Value(InvoiceStatus.completed),
        notes: notes != null ? Value(notes) : const Value.absent(),
      ));

      // 2) إنشاء عناصر الفاتورة + حركات المخزون
      final saleItems = <SaleItemsCompanion>[];
      for (final item in cart) {
        // التحقق من المخزون مسبقاً
        if (requireStock) {
          final product = await _db.productDao.findById(item.product.id);
          if (product == null) {
            throw ValidationException('المنتج "${item.product.name}" غير موجود');
          }
          if (product.currentStock < item.quantity) {
            throw InsufficientStockException(
                product.name, product.currentStock, item.quantity);
          }
        }

        // حفظ تكلفة البند وقت البيع
        saleItems.add(SaleItemsCompanion.insert(
          saleId: saleId,
          productId: item.product.id,
          quantity: item.quantity.toDouble(),
          unitPrice: item.unitPrice.toDouble(),
          costPrice: Value(item.product.averageCost.toDouble()),
          discount: Value(item.discount.toDouble()),
          total: item.total.toDouble(),
        ));

        // إخراج من المخزون
        await _inventoryService.stockOut(
          productId: item.product.id,
          quantity: item.quantity,
          userId: userId,
          movementType: MovementTypes.saleOut,
          unitCost: item.product.averageCost,
          referenceType: MovementTypes.sourceSale,
          referenceId: saleId,
        );
      }

      await _db.saleDao.insertItems(saleItems);
      final savedItems = await _db.saleDao.getItems(saleId);

      // 3) حركة النقد للجزء المدفوع
      if (paidAmount > 0) {
        await _db.cashTransactionDao.insertTransaction(
          CashTransactionsCompanion.insert(
            transactionType: MovementTypes.sourceSale,
            referenceType: Value(MovementTypes.sourceSale),
            referenceId: Value(saleId),
            amount: paidAmount.toDouble(),
            direction: CashDirection.inbound,
            description: Value('مبيعات - فاتورة $invoiceNumber'),
            userId: Value(userId),
          ),
        );
      }

      // 4) تحديث مديونية العميل للجزء المتبقي
      if (remaining > 0 && customerId != null) {
        final customer = await _db.customerDao.findById(customerId);
        if (customer != null) {
          await _db.customerDao.updateBalance(
              customerId, customer.currentBalance + remaining);
        }
      }

      // 5) Audit Log
      await _auditService.log(
        userId: userId,
        action: 'SALE_CREATED',
        module: 'sales',
        entityType: 'sale',
        entityId: saleId,
        description: 'إنشاء فاتورة بيع $invoiceNumber بقيمة $finalTotal',
      );

      final sale = await _db.saleDao.findById(saleId);
      AppLogger.accounting(
          'Sale created: $invoiceNumber total=$finalTotal paid=$paidAmount remaining=$remaining cost=$totalCost');

      return SaleResult(sale: sale!, items: savedItems);
    });
  }

  /// مرتجع بيع - يعكس كل الحركات
  Future<int> returnSale({
    required int originalSaleId,
    required int userId,
    required List<ReturnItemInput> items,
    num cashReturn = 0,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ValidationException('لا يمكن إنشاء مرتجع فارغ');
    }

    return _db.runInTransactionSafe(() async {
      final sale = await _db.saleDao.findById(originalSaleId);
      if (sale == null) {
        throw ValidationException('الفاتورة الأصلية غير موجودة');
      }
      if (sale.status == InvoiceStatus.cancelled) {
        throw InvoiceNotEditableException(sale.status);
      }

      final now = DateTime.now();
      final sequence = await _db.returnDao.getNextSequenceForToday(now, 'RET');
      final returnNumber = CommonUtils.generateInvoiceNumber('RET', now, sequence);

      // حساب الإجمالي
      num subtotal = 0;
      for (final item in items) {
        subtotal += item.total;
      }

      // إنشاء سجل المرتجع
      final returnId = await _db.returnDao.insertReturn(ReturnsCompanion.insert(
        returnNumber: returnNumber,
        returnType: 'SALE_RETURN',
        referenceInvoiceId: originalSaleId,
        customerId: sale.customerId != null ? Value(sale.customerId!) : const Value.absent(),
        userId: userId,
        subtotal: Value(subtotal.toDouble()),
        total: Value(subtotal.toDouble()),
        cashReturn: Value(cashReturn.toDouble()),
        notes: notes != null ? Value(notes) : const Value.absent(),
      ));

      // إدخال عناصر المرتجع + إرجاع للمخزون
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

        // إرجاع الكمية للمخزون
        await _inventoryService.stockIn(
          productId: item.productId,
          quantity: item.quantity,
          unitCost: item.costPrice,
          userId: userId,
          movementType: MovementTypes.saleReturnIn,
          referenceType: 'RETURN',
          referenceId: returnId,
          reason: 'مرتجع بيع $returnNumber',
        );
      }
      await _db.returnDao.insertItems(returnItems);

      // إرجاع النقد للعميل (إذا كان الدفع نقدياً)
      if (cashReturn > 0) {
        await _db.cashTransactionDao.insertTransaction(
          CashTransactionsCompanion.insert(
            transactionType: MovementTypes.sourceReturn,
            referenceType: const Value('RETURN'),
            referenceId: Value(returnId),
            amount: cashReturn.toDouble(),
            direction: CashDirection.outbound,
            description: Value('مرتجع بيع - $returnNumber'),
            userId: Value(userId),
          ),
        );
      }

      // تعديل مديونية العميل (إذا كان البيع آجلاً)
      num customerAdjustment = subtotal - cashReturn;
      if (customerAdjustment > 0 && sale.customerId != null) {
        final customer = await _db.customerDao.findById(sale.customerId!);
        if (customer != null) {
          await _db.customerDao.updateBalance(
              customer.id, customer.currentBalance - customerAdjustment);
        }
      }

      // Audit Log
      await _auditService.log(
        userId: userId,
        action: 'SALE_RETURNED',
        module: 'sales',
        entityType: 'return',
        entityId: returnId,
        description: 'مرتجع بيع $returnNumber للفاتورة ${sale.invoiceNumber} بقيمة $subtotal',
      );

      AppLogger.accounting('Sale returned: $returnNumber value=$subtotal');
      return returnId;
    });
  }

  /// إلغاء فاتورة بيع (للفواتير المسودة فقط)
  Future<void> cancelSale(int saleId, int userId) async {
    await _db.runInTransactionSafe(() async {
      final sale = await _db.saleDao.findById(saleId);
      if (sale == null) {
        throw ValidationException('الفاتورة غير موجودة');
      }
      if (sale.status != InvoiceStatus.draft) {
        throw OperationNotAllowedException(
            'لا يمكن إلغاء فاتورة بحالة ${sale.status}');
      }

      await _db.saleDao.updateSale(sale.copyWith(status: InvoiceStatus.cancelled));

      await _auditService.log(
        userId: userId,
        action: 'SALE_CANCELLED',
        module: 'sales',
        entityType: 'sale',
        entityId: saleId,
        description: 'إلغاء فاتورة ${sale.invoiceNumber}',
      );
    });
  }
}

/// مدخل لعنصر مرتجع
class ReturnItemInput {
  final int productId;
  final num quantity;
  final num unitPrice;
  final num costPrice;
  final num total;

  ReturnItemInput({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.costPrice,
    required this.total,
  });
}
