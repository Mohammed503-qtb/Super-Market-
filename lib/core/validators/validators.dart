/// أدوات التحقق من صحة المدخلات
class Validators {
  Validators._();

  /// التحقق من النص المطلوب
  static String? required(String? value, {String fieldName = 'هذا الحقل'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName مطلوب';
    }
    return null;
  }

  /// التحقق من رقم موجب
  static String? positiveNumber(String? value, {String fieldName = 'القيمة'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName مطلوب';
    final num? parsed = num.tryParse(value.trim());
    if (parsed == null) return '$fieldName يجب أن يكون رقماً';
    if (parsed < 0) return '$fieldName يجب أن يكون موجباً';
    return null;
  }

  /// التحقق من رقم أكبر من صفر
  static String? positiveNonZero(String? value, {String fieldName = 'القيمة'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName مطلوب';
    final num? parsed = num.tryParse(value.trim());
    if (parsed == null) return '$fieldName يجب أن يكون رقماً';
    if (parsed <= 0) return '$fieldName يجب أن يكون أكبر من صفر';
    return null;
  }

  /// التحقق من رقم الهاتف
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return null; // اختياري
    final clean = value.replaceAll(RegExp(r'[\s\-+]'), '');
    if (!RegExp(r'^[0-9]{8,15}$').hasMatch(clean)) {
      return 'رقم الهاتف غير صالح';
    }
    return null;
  }

  /// التحقق من الباركود
  static String? barcode(String? value) {
    if (value == null || value.trim().isEmpty) return null; // اختياري
    if (!RegExp(r'^[A-Za-z0-9\-]+$').hasMatch(value.trim())) {
      return 'الباركود يجب أن يحتوي على أحرف وأرقام فقط';
    }
    return null;
  }

  /// التحقق من طول النص
  static String? minLength(String? value, int min, {String fieldName = 'هذا الحقل'}) {
    if (value == null || value.trim().length < min) {
      return '$fieldName يجب أن يكون $min أحرف على الأقل';
    }
    return null;
  }

  /// التحقق من كلمة المرور
  static String? password(String? value) {
    if (value == null || value.trim().isEmpty) return 'كلمة المرور مطلوبة';
    if (value.length < 4) return 'كلمة المرور يجب أن تكون 4 أحرف على الأقل';
    return null;
  }

  /// التحقق من اسم المستخدم
  static String? username(String? value) {
    if (value == null || value.trim().isEmpty) return 'اسم المستخدم مطلوب';
    if (value.trim().length < 3) return 'اسم المستخدم يجب أن يكون 3 أحرف على الأقل';
    if (!RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(value.trim())) {
      return 'اسم المستخدم يجب أن يحتوي على أحرف إنجليزية وأرقام فقط';
    }
    return null;
  }

  /// التحقق من نسبة الخصم (0-100)
  static String? discountPercent(String? value) {
    if (value == null || value.trim().isEmpty) return null; // اختياري
    final num? parsed = num.tryParse(value.trim());
    if (parsed == null) return 'النسبة يجب أن تكون رقماً';
    if (parsed < 0 || parsed > 100) return 'النسبة يجب أن تكون بين 0 و 100';
    return null;
  }
}
