import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_erp/data/database/app_database.dart';

/// اختبارات PasswordHasher - تشفير كلمات المرور بـ SHA-256 + salt
/// لا تحتاج DB - اختبارات للدوال الساكنة فقط
void main() {
  group('PasswordHasher.hash', () {
    test('produces a string with \$ separator', () {
      final hashed = PasswordHasher.hash('admin123');
      // النتيجة: salt$hash
      expect(hashed.contains(r'$'), isTrue);
      final parts = hashed.split(r'$');
      expect(parts.length, 2);
      expect(parts[0].isNotEmpty, isTrue, reason: 'salt should not be empty');
      expect(parts[1].isNotEmpty, isTrue, reason: 'hash should not be empty');
    });

    test('different invocations produce different hashes for same password',
        () async {
      final h1 = PasswordHasher.hash('secret');
      // نوقف قليلاً لضمان اختلاف الـ microseconds
      await Future.delayed(const Duration(milliseconds: 5));
      final h2 = PasswordHasher.hash('secret');
      expect(h1, isNot(equals(h2)),
          reason: 'salts should differ for same password');
    });

    test('salt is 32 chars (sha256 hex truncated)', () {
      final hashed = PasswordHasher.hash('x');
      final salt = hashed.split(r'$')[0];
      expect(salt.length, 32);
    });

    test('hash part is 64 chars (full sha256 hex)', () {
      final hashed = PasswordHasher.hash('x');
      final hashPart = hashed.split(r'$')[1];
      expect(hashPart.length, 64);
    });
  });

  group('PasswordHasher.verify', () {
    test('returns true for correct password', () {
      final hashed = PasswordHasher.hash('mySecret123');
      expect(PasswordHasher.verify('mySecret123', hashed), isTrue);
    });

    test('returns false for wrong password', () {
      final hashed = PasswordHasher.hash('correct');
      expect(PasswordHasher.verify('wrong', hashed), isFalse);
    });

    test('returns false for empty stored hash', () {
      expect(PasswordHasher.verify('anything', ''), isFalse);
    });

    test('returns false for malformed stored hash (no separator)', () {
      expect(PasswordHasher.verify('anything', 'justastring'), isFalse);
    });

    test('returns false for malformed stored hash (too many separators)', () {
      expect(
        PasswordHasher.verify('anything', 'a\$b\$c'),
        isFalse,
      );
    });

    test('verifies default admin password after seeding (hash + verify round trip)',
        () {
      // التأكد أن كلمة مرور متعارف عليها يمكن التحقق منها
      const password = 'admin123';
      final hashed = PasswordHasher.hash(password);
      expect(PasswordHasher.verify(password, hashed), isTrue);
    });
  });
}
