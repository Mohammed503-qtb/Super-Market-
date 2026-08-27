import 'dart:convert';
import 'package:crypto/crypto.dart';

/// خدمة تشفير كلمات المرور باستخدام SHA-256 + salt
class PasswordHasher {
  PasswordHasher._();

  /// توليد salt عشوائي
  static String _generateSalt() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final randomBytes = utf8.encode('$random${DateTime.now().millisecondsSinceEpoch}');
    return sha256.convert(randomBytes).toString().substring(0, 32);
  }

  /// تشفير كلمة المرور
  /// النتيجة بصيغة: salt$hash
  static String hash(String password) {
    final salt = _generateSalt();
    final hashValue = _hashWithSalt(password, salt);
    return '$salt\$$hashValue';
  }

  /// التحقق من كلمة المرور
  static bool verify(String password, String storedHash) {
    final parts = storedHash.split(r'$');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final hash = parts[1];
    final computedHash = _hashWithSalt(password, salt);
    return computedHash == hash;
  }

  static String _hashWithSalt(String password, String salt) {
    final bytes = utf8.encode('$salt$password$salt');
    return sha256.convert(bytes).toString();
  }
}
