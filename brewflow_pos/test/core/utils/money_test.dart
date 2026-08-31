import 'package:brewflow_pos/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parseRupeesToPaise', () {
    test('parses whole rupees', () {
      expect(Money.parseRupeesToPaise('12'), 1200);
      expect(Money.parseRupeesToPaise('0'), 0);
      expect(Money.parseRupeesToPaise('1'), 100);
    });

    test('parses rupees with paise', () {
      expect(Money.parseRupeesToPaise('149.5'), 14950);
      expect(Money.parseRupeesToPaise('149.50'), 14950);
      expect(Money.parseRupeesToPaise('0.05'), 5);
      expect(Money.parseRupeesToPaise('99999999.99'), 9999999999);
    });

    test('accepts surrounding whitespace', () {
      expect(Money.parseRupeesToPaise('  149.50  '), 14950);
    });

    test('rejects empty input', () {
      expect(Money.parseRupeesToPaise(''), isNull);
      expect(Money.parseRupeesToPaise('   '), isNull);
    });

    test('rejects malformed input', () {
      expect(Money.parseRupeesToPaise('abc'), isNull);
      expect(Money.parseRupeesToPaise('1.234'), isNull);
      expect(Money.parseRupeesToPaise('149.'), isNull);
      expect(Money.parseRupeesToPaise('-1'), isNull);
      expect(Money.parseRupeesToPaise('1,000'), isNull);
    });

    test('rejects values above the safe ceiling', () {
      expect(Money.parseRupeesToPaise('100000000'), isNull);
      expect(Money.parseRupeesToPaise('99999999.99'), 9999999999);
    });
  });

  group('Money.paiseToRupeesInput', () {
    test('round-trips rupeee input', () {
      expect(Money.paiseToRupeesInput(14950), '149.50');
      expect(Money.paiseToRupeesInput(1200), '12.00');
      expect(Money.paiseToRupeesInput(5), '0.05');
      expect(Money.paiseToRupeesInput(0), '0.00');
    });
  });

  group('Money.formatPaise', () {
    test('always shows two fraction digits', () {
      expect(Money.formatPaise(0), '₹0.00');
      expect(Money.formatPaise(5), '₹0.05');
      expect(Money.formatPaise(100), '₹1.00');
    });

    test('formats with Indian digit grouping', () {
      expect(Money.formatPaise(14950), '₹149.50');
      expect(Money.formatPaise(1234567), '₹12,345.67');
      expect(Money.formatPaise(123456789), '₹12,34,567.89');
      expect(Money.formatPaise(9999999999), '₹9,99,99,999.99');
    });
  });

  group('Money.multiplyPaise', () {
    test('multiplies unit price by quantity', () {
      expect(Money.multiplyPaise(14950, 3), 44850);
      expect(Money.multiplyPaise(1, 1), 1);
      expect(Money.multiplyPaise(0, 7), 0);
      expect(Money.multiplyPaise(9999999999, 1), 9999999999);
    });

    test('rejects negative prices', () {
      expect(Money.multiplyPaise(-1, 2), isNull);
    });

    test('rejects zero and negative quantities', () {
      expect(Money.multiplyPaise(100, 0), isNull);
      expect(Money.multiplyPaise(100, -1), isNull);
    });

    test('rejects results above the safe ceiling', () {
      expect(Money.multiplyPaise(9999999999, 2), isNull);
      expect(Money.multiplyPaise(5000000000, 2), isNull);
      expect(Money.multiplyPaise(100, 100000001), isNull);
    });
  });

  group('Money.sumPaise', () {
    test('sums paise values', () {
      expect(Money.sumPaise(const [100, 200, 300]), 600);
      expect(Money.sumPaise(const []), 0);
      expect(Money.sumPaise(const [0, 0]), 0);
    });

    test('rejects negative values', () {
      expect(Money.sumPaise(const [100, -5]), isNull);
    });

    test('rejects sums above the safe ceiling', () {
      expect(Money.sumPaise(const [6000000000, 5000000000]), isNull);
      expect(Money.sumPaise(const [9999999999, 1]), isNull);
    });
  });
}
