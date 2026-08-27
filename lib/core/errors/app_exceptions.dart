/// استثناءات النظام - رسائل خطأ واضحة بالعربية
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const AppException(this.message, {this.code, this.details});

  @override
  String toString() => message;
}

/// خطأ في الصلاحيات
class PermissionDeniedException extends AppException {
  PermissionDeniedException([super.message = 'ليس لديك صلاحية لتنفيذ هذه العملية'])
      : super(code: 'PERMISSION_DENIED');
}

/// مخزون غير كافٍ
class InsufficientStockException extends AppException {
  final String productName;
  final num available;
  final num requested;

  InsufficientStockException(this.productName, this.available, this.requested)
      : super(
          'الكمية المطلوبة من "$productName" ($requested) أكبر من المخزون المتاح ($available)',
          code: 'INSUFFICIENT_STOCK',
        );
}

/// دفع غير صالح
class InvalidPaymentException extends AppException {
  InvalidPaymentException([super.message = 'المبلغ المدفوع غير صالح'])
      : super(code: 'INVALID_PAYMENT');
}

/// خطأ في قاعدة البيانات
class DatabaseException extends AppException {
  DatabaseException([super.message = 'حدث خطأ في قاعدة البيانات'])
      : super(code: 'DATABASE_ERROR');
}

/// خطأ في النسخ الاحتياطي
class BackupRestoreException extends AppException {
  BackupRestoreException([super.message = 'حدث خطأ في عملية النسخ الاحتياطي'])
      : super(code: 'BACKUP_ERROR');
}

/// خطأ في التحقق من البيانات
class ValidationException extends AppException {
  ValidationException(super.message) : super(code: 'VALIDATION_ERROR');
}

/// خطأ في المصادقة
class AuthenticationException extends AppException {
  AuthenticationException([super.message = 'فشل تسجيل الدخول'])
      : super(code: 'AUTH_ERROR');
}

/// خطأ: المستخدم غير نشط
class UserInactiveException extends AppException {
  UserInactiveException([super.message = 'هذا الحساب غير نشط، يرجى مراجعة المسؤول'])
      : super(code: 'USER_INACTIVE');
}

/// خطأ: بيانات مكررة
class DuplicateException extends AppException {
  DuplicateException(String entity, String field)
      : super('يوجد $entity بنفس $field، يرجى استخدام قيمة أخرى', code: 'DUPLICATE');
}

/// خطأ: العملية غير مسموح بها
class OperationNotAllowedException extends AppException {
  OperationNotAllowedException(super.message) : super(code: 'OPERATION_NOT_ALLOWED');
}

/// خطأ: الفاتورة لا يمكن تعديلها
class InvoiceNotEditableException extends AppException {
  InvoiceNotEditableException(String status)
      : super('لا يمكن تعديل الفاتورة بحالة "$status"', code: 'INVOICE_NOT_EDITABLE');
}

/// خطأ: مخزون سالب غير مسموح
class NegativeStockNotAllowedException extends AppException {
  NegativeStockNotAllowedException()
      : super('لا يمكن إتمام العملية لأنها ستؤدي إلى مخزون سالب', code: 'NEGATIVE_STOCK');
}

/// خطأ: دفع أكبر من المديونية
class OverpaymentException extends AppException {
  OverpaymentException(num paid, num debt)
      : super('المبلغ المدفوع ($paid) أكبر من المديونية ($debt)', code: 'OVERPAYMENT');
}
