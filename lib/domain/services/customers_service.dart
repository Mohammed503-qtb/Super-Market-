import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import 'audit_service.dart';

/// خدمة العملاء - تدير الأرصدة والمدفوعات وكشوف الحساب
class CustomersService {
  final AppDatabase _db;
  final AuditService _auditService;

  CustomersService(this._db, this._auditService);

  /// إنشاء عميل جديد
  Future<int> createCustomer(CustomersCompanion customer, int userId) async {
    final id = await _db.customerDao.insertCustomer(customer);
    await _auditService.log(
      userId: userId,
      action: 'CUSTOMER_CREATED',
      module: 'customers',
      entityType: 'customer',
      entityId: id,
      description: 'إنشاء عميل جديد: ${customer.name.value}',
    );

    // إذا كان هناك رصيد افتتاحي، نسجل حركة نقد
    if (customer.openingBalance.present && customer.openingBalance.value > 0) {
      // الرصيد الافتتاحي = مديونية للعميل (إذا كان له دين سابق)
      await _db.customerDao.updateBalance(id, customer.openingBalance.value);
    }

    return id;
  }

  /// تعديل عميل
  Future<void> updateCustomer(Customer customer, int userId) async {
    final old = await _db.customerDao.findById(customer.id);
    await _db.customerDao.updateCustomer(customer);
    await _auditService.log(
      userId: userId,
      action: 'CUSTOMER_UPDATED',
      module: 'customers',
      entityType: 'customer',
      entityId: customer.id,
      oldValue: old != null ? '${old.name}|${old.phone}' : null,
      newValue: '${customer.name}|${customer.phone}',
      description: 'تعديل بيانات العميل: ${customer.name}',
    );
  }

  /// حذف عميل (لا يمكن حذف عميل له معاملات)
  Future<void> deleteCustomer(int id, int userId) async {
    final sales = await _db.saleDao.getByCustomer(id);
    if (sales.isNotEmpty) {
      throw OperationNotAllowedException(
          'لا يمكن حذف عميل له فواتير بيع، استخدم خيار التعطيل بدلاً من ذلك');
    }
    await _db.customerDao.deleteCustomer(id);
    await _auditService.log(
      userId: userId,
      action: 'CUSTOMER_DELETED',
      module: 'customers',
      entityType: 'customer',
      entityId: id,
      description: 'حذف عميل',
    );
  }

  /// تسجيل دفعة من العميل
  /// - يزيد الصندوق
  /// - يقلل مديونية العميل
  /// - ينشئ Audit Log
  Future<int> receivePayment({
    required int customerId,
    required num amount,
    required int userId,
    String paymentMethod = PaymentType.cash,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw InvalidPaymentException('المبلغ يجب أن يكون موجباً');
    }

    final customer = await _db.customerDao.findById(customerId);
    if (customer == null) {
      throw ValidationException('العميل غير موجود');
    }

    // التحقق من عدم الدفع الزائد
    final settings = await _db.settingDao.getSettings();
    final allowOverpayment = settings?.allowOverpayment ?? false;
    if (!allowOverpayment && amount > customer.currentBalance) {
      throw OverpaymentException(amount, customer.currentBalance);
    }

    return _db.runInTransactionSafe(() async {
      // 1) إنشاء سجل الدفع
      final paymentId = await _db.customerPaymentDao.insertPayment(
        CustomerPaymentsCompanion.insert(
          customerId: customerId,
          amount: amount.toDouble(),
          paymentMethod: Value(paymentMethod),
          userId: userId,
          notes: notes != null ? Value(notes) : const Value.absent(),
        ),
      );

      // 2) تحديث رصيد العميل (تخفيض المديونية)
      await _db.customerDao.updateBalance(
          customerId, customer.currentBalance - amount);

      // 3) زيادة الصندوق
      await _db.cashTransactionDao.insertTransaction(
        CashTransactionsCompanion.insert(
          transactionType: MovementTypes.sourceCustomerPayment,
          referenceType: Value(MovementTypes.sourceCustomerPayment),
          referenceId: Value(paymentId),
          amount: amount.toDouble(),
          direction: CashDirection.inbound,
          description: Value('سداد من العميل ${customer.name}'),
          userId: Value(userId),
        ),
      );

      // 4) Audit Log
      await _auditService.log(
        userId: userId,
        action: 'PAYMENT_RECEIVED',
        module: 'customers',
        entityType: 'customer_payment',
        entityId: paymentId,
        description: 'سداد من العميل ${customer.name} بقيمة $amount',
      );

      AppLogger.accounting(
          'Customer payment: customer=$customerId amount=$amount');
      return paymentId;
    });
  }

  /// كشف حساب العميل
  /// التاريخ | الوصف | مدين | دائن | الرصيد | المرجع
  Future<List<Map<String, dynamic>>> getStatement(int customerId,
      {DateTime? startDate, DateTime? endDate}) async {
    final customer = await _db.customerDao.findById(customerId);
    if (customer == null) return [];

    final opening = customer.openingBalance;
    final entries = <Map<String, dynamic>>[];

    // رصيد افتتاحي
    entries.add({
      'date': customer.createdAt,
      'description': 'رصيد افتتاحي',
      'debit': 0.0,
      'credit': 0.0,
      'balance': opening,
      'reference': '-',
      'type': 'OPENING',
    });

    num runningBalance = opening;

    // المبيعات (مدين = زيادة الدين)
    final sales = await _db.saleDao.getByCustomer(customerId);
    for (final s in sales) {
      if (s.remainingAmount > 0) {
        if (startDate != null && s.createdAt.isBefore(startDate)) continue;
        if (endDate != null && s.createdAt.isAfter(endDate)) continue;
        runningBalance += s.remainingAmount;
        entries.add({
          'date': s.createdAt,
          'description': 'فاتورة بيع ${s.invoiceNumber}',
          'debit': s.remainingAmount,
          'credit': 0.0,
          'balance': runningBalance,
          'reference': s.invoiceNumber,
          'type': 'SALE',
        });
      }
    }

    // المدفوعات (دائن = تخفيض الدين)
    final payments = await _db.customerPaymentDao.getByCustomer(customerId);
    for (final p in payments) {
      if (startDate != null && p.createdAt.isBefore(startDate)) continue;
      if (endDate != null && p.createdAt.isAfter(endDate)) continue;
      runningBalance -= p.amount;
      entries.add({
        'date': p.createdAt,
        'description': 'سداد',
        'debit': 0.0,
        'credit': p.amount,
        'balance': runningBalance,
        'reference': '#${p.id}',
        'type': 'PAYMENT',
      });
    }

    // ترتيب حسب التاريخ
    entries.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // إعادة حساب الأرصدة بترتيب التسلسلي
    num bal = opening;
    for (final e in entries) {
      bal += (e['debit'] as num) - (e['credit'] as num);
      e['balance'] = bal;
    }

    return entries;
  }

  /// ملخص العميل
  Future<Map<String, num>> getSummary(int customerId) async {
    final customer = await _db.customerDao.findById(customerId);
    final payments = await _db.customerPaymentDao.totalPaymentsByCustomer(customerId);

    final sales = await _db.saleDao.getByCustomer(customerId);
    num totalCredit = 0;
    for (final s in sales) {
      totalCredit += s.remainingAmount;
    }

    return {
      'openingBalance': customer?.openingBalance ?? 0,
      'totalCredit': totalCredit,
      'totalPaid': payments,
      'currentBalance': customer?.currentBalance ?? 0,
    };
  }
}
