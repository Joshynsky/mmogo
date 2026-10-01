// QA fix F5: the integer-cents amount parser shared by the Add screen and the
// Analytics edit sheet.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/format/ksh_amount.dart';

void main() {
  group('parseKshCents', () {
    test('plain amounts parse to integer cents', () {
      expect(parseKshCents('500'), 50000);
      expect(parseKshCents('1500.5'), 150050);
      expect(parseKshCents('1500.50'), 150050);
      expect(parseKshCents('0.05'), 5);
      expect(parseKshCents('.5'), 50);
      expect(parseKshCents('5.'), 500);
      expect(parseKshCents('  22.00 '), 2200);
    });

    test('0.004 is invalid, never 0 cents', () {
      expect(parseKshCents('0.004'), isNull);
      expect(parseKshCents('0.004', allowZero: true), isNull);
    });

    test('exponents, Infinity, NaN, negatives and junk are invalid', () {
      for (final bad in ['1e5', '1E5', '1e30', 'Infinity', 'NaN', '-5', '+5', '1,000', '1.2.3', 'abc', '', ' ', '.', '5 0']) {
        expect(parseKshCents(bad), isNull, reason: bad);
        expect(parseKshCents(bad, allowZero: true), isNull, reason: bad);
      }
    });

    test('zero is invalid for an amount but valid for a fee', () {
      expect(parseKshCents('0'), isNull);
      expect(parseKshCents('0.00'), isNull);
      expect(parseKshCents('0', allowZero: true), 0);
      expect(parseKshCents('0.00', allowZero: true), 0);
    });

    test('the cap is Ksh 10,000,000.00 inclusive', () {
      expect(parseKshCents('10000000.00'), maxKshCents);
      expect(parseKshCents('10000000.01'), isNull);
      expect(parseKshCents('99999999999999999999'), isNull);
    });
  });

  test('the typing shape allows partial input but not bad shapes', () {
    for (final ok in ['', '1', '12345678', '1.', '1.5', '1.50', '.5']) {
      expect(kshTypingShape.hasMatch(ok), isTrue, reason: ok);
    }
    for (final bad in ['1e5', '1.505', '-1', 'Infinity', '123456789', '1..2', '1,0']) {
      expect(kshTypingShape.hasMatch(bad), isFalse, reason: bad);
    }
  });
}
