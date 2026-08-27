import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// أدوات تنسيق الأرقام والعملة
/// تستخدم Decimal لتفادي أخطاء الـ floating-point في الحسابات المالية
class FormatUtils {
  FormatUtils._();

  /// تنسيق المبلغ المالي مع فواصل الآلاف
  static String formatMoney(num value, {int decimals = 0, String currency = ''}) {
    final formatter = NumberFormat.decimalPatternDigits(
      locale: 'en_US',
      decimalDigits: decimals,
    );
    final formatted = formatter.format(value.abs());
    final sign = value.isNegative ? '-' : '';
    final cur = currency.isEmpty ? '' : ' $currency';
    return '$sign$formatted$cur';
  }

  /// تنسيق المبلغ كنص عربي مع العملة
  static String formatMoneyAr(num value, {int decimals = 0}) {
    return formatMoney(value, decimals: decimals, currency: 'ر.ي');
  }

  /// تنسيق الكمية
  static String formatQuantity(num value) {
    if (value == value.toInt()) {
      return NumberFormat.decimalPattern('en_US').format(value.toInt());
    }
    return value.toStringAsFixed(2);
  }

  /// تنسيق التاريخ
  static String formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// تنسيق التاريخ والوقت
  static String formatDateTime(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  /// تنسيق الوقت فقط
  static String formatTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  /// تنسيق التاريخ بالعربية
  static String formatDateAr(DateTime date) {
    return DateFormat('yyyy/MM/dd', 'ar').format(date);
  }
}

/// أدوات الحساب المالي باستخدام Decimal للأمان
class MoneyUtils {
  MoneyUtils._();

  /// تحويل إلى Decimal بأمان
  static Decimal toDecimal(num value) {
    return Decimal.parse(value.toString());
  }

  /// جمع مبالغ
  static Decimal add(num a, num b) {
    return toDecimal(a) + toDecimal(b);
  }

  /// طرح مبالغ
  static Decimal subtract(num a, num b) {
    return toDecimal(a) - toDecimal(b);
  }

  /// ضرب (سعر × كمية)
  static Decimal multiply(num price, num qty) {
    return toDecimal(price) * toDecimal(qty);
  }

  /// حساب التكلفة المرجحة (Weighted Average Cost)
  /// NewAverage = (oldStock * oldCost + newQty * newCost) / (oldStock + newQty)
  /// نستخدم Decimal للأمان ثم نحول لنص بدقة 6 خانات عشرية
  static num weightedAverageCost(
    num oldStock,
    num oldCost,
    num newQty,
    num newCost,
  ) {
    final totalQty = oldStock + newQty;
    if (totalQty == 0) return 0;
    final old = toDecimal(oldStock) * toDecimal(oldCost);
    final newPart = toDecimal(newQty) * toDecimal(newCost);
    final totalCost = old + newPart;
    // نحسب كـ نص ثم نحوله لرقم
    final rational = totalCost / toDecimal(totalQty);
    // تقريب يدوي بدقة 6 خانات
    final str = rational.toString();
    // التحويل لـ double بأمان
    final d = double.tryParse(str);
    if (d == null) {
      return (oldStock * oldCost + newQty * newCost) / totalQty;
    }
    return double.parse(d.toStringAsFixed(6));
  }

  /// حساب خصم نسبة
  static num calculateDiscountPercent(num amount, num percent) {
    if (percent <= 0 || percent > 100) return 0;
    final rational = toDecimal(amount) * toDecimal(percent) / Decimal.fromInt(100);
    final str = rational.toString();
    final d = double.tryParse(str);
    if (d == null) {
      return amount * percent / 100;
    }
    return double.parse(d.toStringAsFixed(6));
  }

  /// تقريب إلى أقرب رقم صحيح
  static int roundToInt(num value) {
    return value.round();
  }
}

/// أدوات عامة
class CommonUtils {
  CommonUtils._();

  /// توليد رقم فاتورة فريد
  /// مثال: SAL-20260810-00001
  static String generateInvoiceNumber(String prefix, DateTime date, int sequence) {
    final dateStr = DateFormat('yyyyMMdd').format(date);
    final seqStr = sequence.toString().padLeft(5, '0');
    return '$prefix-$dateStr-$seqStr';
  }

  /// توليد معرف فريد
  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// التحقق من عدم الفراغ
  static bool isNotEmpty(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  /// اقتطاع النص
  static String truncate(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }
}
