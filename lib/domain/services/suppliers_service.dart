import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import 'audit_service.dart';

/// خدمة الموردين - تدير الأرصدة والمدفوعات وكشوف الحساب
class SuppliersService {
  final AppDatabase _db;
  final AuditService _auditService;

  SuppliersService(this._db, this._auditService);

  /// إنشاء مورد جديد
  Future<int> createSupplier(SuppliersCompanion supplier, int userId) async {
    final id = await _db.supplierDao.insertSupplier(supplier);
    await _auditService.log(
      userId: userId,
      action: 'SUPPLIER_CREATED',
      module: 'suppliers',
      entityType: 'supplier',
      entityId: id,
      description: 'إنشاء مورد جديد: ${supplier.name.value}',
    );

    if (supplier.openingBalance.value > 0) {
      await _db.supplierDao.updateBalance(id, supplier.openingBalance.value);
    }

    return id;
  }

  /// تعديل مورد
  Future<void> updateSupplier(Supplier supplier, int userId) async {
    final old = await _db.supplierDao.findById(supplier.id);
    await _db.supplierDao.updateSupplier(supplier);
    await _auditService.log(
      userId: userId,
      action: 'SUPPLIER_UPDATED',
      module: 'suppliers',
      entityType: 'supplier',
      entityId: supplier.id,
      oldValue: old != null ? '${old.name}|${old.phone}' : null,
      newValue: '${supplier.name}|${supplier.phone}',
      description: 'تعديل بيانات المورد: ${supplier.name}',
    );
  }

  /// حذف مورد
  Future<void> deleteSupplier(int id, int userId) async {
    final purchases = await _db.purchaseDao.getBySupplier(id);
    if (purchases.isNotEmpty) {
      throw OperationNotAllowedException(
          'لا يمكن حذف مورد له فواتير شراء، استخدم خيار التعطيل');
    }
    await _db.supplierDao.deleteSupplier(id);
    await _auditService.log(
      userId: userId,
      action: 'SUPPLIER_DELETED',
      module: 'suppliers',
      entityType: 'supplier',
      entityId: id,
      description: 'حذف مورد',
    );
  }

  /// سداد للمورد
  Future<int> paySupplier({
    required int supplierId,
    required num amount,
    required int userId,
    String paymentMethod = PaymentType.cash,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw InvalidPaymentException('المبلغ يجب أن يكون موجباً');
    }

    final supplier = await _db.supplierDao.findById(supplierId);
    if (supplier == null) {
      throw ValidationException('المورد غير موجود');
    }

    final settings = await _db.settingDao.getSettings();
    final allowOverpayment = settings?.allowOverpayment ?? false;
    if (!allowOverpayment && amount > supplier.currentBalance) {
      throw OverpaymentException(amount, supplier.currentBalance);
    }

    return _db.runInTransactionSafe(() async {
      final paymentId = await _db.supplierPaymentDao.insertPayment(
        SupplierPaymentsCompanion.insert(
          supplierId: supplierId,
          amount: amount.toDouble(),
          paymentMethod: Value(paymentMethod),
          userId: userId,
          notes: notes != null ? Value(notes) : const Value.absent(),
        ),
      );

      // تخفيض مديونية المورد
      await _db.supplierDao.updateBalance(
          supplierId, supplier.currentBalance - amount);

      // تخفيض الصندوق
      await _db.cashTransactionDao.insertTransaction(
        CashTransactionsCompanion.insert(
          transactionType: MovementTypes.sourceSupplierPayment,
          referenceType: Value(MovementTypes.sourceSupplierPayment),
          referenceId: Value(paymentId),
          amount: amount.toDouble(),
          direction: CashDirection.outbound,
          description: Value('سداد للمورد ${supplier.name}'),
          userId: Value(userId),
        ),
      );

      await _auditService.log(
        userId: userId,
        action: 'PAYMENT_SENT',
        module: 'suppliers',
        entityType: 'supplier_payment',
        entityId: paymentId,
        description: 'سداد للمورد ${supplier.name} بقيمة $amount',
      );

      AppLogger.accounting(
          'Supplier payment: supplier=$supplierId amount=$amount');
      return paymentId;
    });
  }

  /// كشف حساب المورد
  Future<List<Map<String, dynamic>>> getStatement(int supplierId,
      {DateTime? startDate, DateTime? endDate}) async {
    final supplier = await _db.supplierDao.findById(supplierId);
    if (supplier == null) return [];

    final opening = supplier.openingBalance;
    final entries = <Map<String, dynamic>>[];

    entries.add({
      'date': supplier.createdAt,
      'description': 'رصيد افتتاحي',
      'debit': 0.0,
      'credit': 0.0,
      'balance': opening,
      'reference': '-',
      'type': 'OPENING',
    });

    // المشتريات (دائن = زيادة المديونية للمورد)
    final purchases = await _db.purchaseDao.getBySupplier(supplierId);
    for (final p in purchases) {
      if (p.remainingAmount > 0) {
        if (startDate != null && p.createdAt.isBefore(startDate)) continue;
        if (endDate != null && p.createdAt.isAfter(endDate)) continue;
        entries.add({
          'date': p.createdAt,
          'description': 'فاتورة شراء ${p.invoiceNumber}',
          'debit': 0.0,
          'credit': p.remainingAmount,
          'balance': 0.0, // سيُحسب لاحقاً
          'reference': p.invoiceNumber,
          'type': 'PURCHASE',
        });
      }
    }

    // المدفوعات (مدين = تخفيض المديونية)
    final payments = await _db.supplierPaymentDao.getBySupplier(supplierId);
    for (final p in payments) {
      if (startDate != null && p.createdAt.isBefore(startDate)) continue;
      if (endDate != null && p.createdAt.isAfter(endDate)) continue;
      entries.add({
        'date': p.createdAt,
        'description': 'سداد',
        'debit': p.amount,
        'credit': 0.0,
        'balance': 0.0,
        'reference': '#${p.id}',
        'type': 'PAYMENT',
      });
    }

    entries.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // حساب الأرصدة المتتابعة
    num bal = opening;
    for (final e in entries) {
      bal += (e['credit'] as num) - (e['debit'] as num);
      e['balance'] = bal;
    }

    return entries;
  }

  /// ملخص المورد
  Future<Map<String, num>> getSummary(int supplierId) async {
    final supplier = await _db.supplierDao.findById(supplierId);
    final payments = await _db.supplierPaymentDao.totalPaymentsBySupplier(supplierId);

    final purchases = await _db.purchaseDao.getBySupplier(supplierId);
    num totalCredit = 0;
    for (final p in purchases) {
      totalCredit += p.remainingAmount;
    }

    return {
      'openingBalance': supplier?.openingBalance ?? 0,
      'totalCredit': totalCredit,
      'totalPaid': payments,
      'currentBalance': supplier?.currentBalance ?? 0,
    };
  }
}
