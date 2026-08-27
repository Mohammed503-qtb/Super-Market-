import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_erp/core/utils/format_utils.dart';

/// اختبارات أدوات الحساب المالي - دوال نقية بدون DB
/// تتحقق من صحة حسابات التكلفة المرجحة والخصم والمقابلات الأساسية
void main() {
  group('MoneyUtils.weightedAverageCost', () {
    test(
        'old stock 0, new qty 100, cost 5000 -> average cost should be 5000',
        () {
      final result = MoneyUtils.weightedAverageCost(0, 0, 100, 5000);
      expect(result, 5000);
    });

    test(
        'old stock 100 cost 5000, new qty 50 cost 6000 -> weighted average '
        '(100*5000 + 50*6000)/150 = 5333.333...', () {
      final result = MoneyUtils.weightedAverageCost(100, 5000, 50, 6000);
      // (500000 + 300000) / 150 = 5333.333...
      expect(result, closeTo(5333.33, 0.01));
    });

    test('total quantity 0 -> returns 0 (avoid division by zero)', () {
      final result = MoneyUtils.weightedAverageCost(0, 0, 0, 0);
      expect(result, 0);
    });

    test('weighted average when both stock and new qty > 0 produces correct '
        'decimal value to 6 places', () {
      // 200 units @ 1000 + 100 units @ 1300 = 200000 + 130000 = 330000
      // / 300 = 1100
      final result = MoneyUtils.weightedAverageCost(200, 1000, 100, 1300);
      expect(result, 1100);
    });
  });

  group('MoneyUtils.calculateDiscountPercent', () {
    test('amount 100000, percent 10 -> discount 10000', () {
      final result = MoneyUtils.calculateDiscountPercent(100000, 10);
      expect(result, 10000);
    });

    test('percent 0 -> discount 0', () {
      final result = MoneyUtils.calculateDiscountPercent(100000, 0);
      expect(result, 0);
    });

    test('percent 150 (over 100) -> discount 0', () {
      final result = MoneyUtils.calculateDiscountPercent(100000, 150);
      expect(result, 0);
    });

    test('percent negative -> discount 0', () {
      final result = MoneyUtils.calculateDiscountPercent(100000, -5);
      expect(result, 0);
    });

    test('50% discount on 1000 = 500', () {
      final result = MoneyUtils.calculateDiscountPercent(1000, 50);
      expect(result, 500);
    });
  });

  group('MoneyUtils basic arithmetic', () {
    test('toDecimal converts int to Decimal correctly', () {
      final d = MoneyUtils.toDecimal(100);
      expect(d, Decimal.parse('100'));
    });

    test('toDecimal converts double to Decimal correctly', () {
      final d = MoneyUtils.toDecimal(123.45);
      expect(d, Decimal.parse('123.45'));
    });

    test('add returns Decimal sum of two numbers', () {
      final result = MoneyUtils.add(100, 250);
      expect(result, Decimal.parse('350'));
    });

    test('add works with fractional values', () {
      final result = MoneyUtils.add(10.5, 0.25);
      expect(result, Decimal.parse('10.75'));
    });

    test('subtract returns Decimal difference', () {
      final result = MoneyUtils.subtract(500, 175);
      expect(result, Decimal.parse('325'));
    });

    test('subtract with negative result', () {
      final result = MoneyUtils.subtract(100, 250);
      expect(result, Decimal.parse('-150'));
    });

    test('multiply (price x qty) returns Decimal product', () {
      final result = MoneyUtils.multiply(8000, 10);
      expect(result, Decimal.parse('80000'));
    });

    test('multiply with fractional price', () {
      final result = MoneyUtils.multiply(12.5, 4);
      expect(result, Decimal.parse('50'));
    });
  });

  group('MoneyUtils.roundToInt', () {
    test('rounds 5333.6 to 5334', () {
      expect(MoneyUtils.roundToInt(5333.6), 5334);
    });

    test('rounds 5333.4 to 5333', () {
      expect(MoneyUtils.roundToInt(5333.4), 5333);
    });
  });
}
