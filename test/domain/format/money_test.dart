import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/format/money.dart';

void main() {
  group('formatKsh', () {
    test('formats zero', () => expect(formatKsh(0), 'Ksh 0.00'));
    test('formats a plain value', () => expect(formatKsh(150000), 'Ksh 1,500.00'));
    test('formats with thousands+cents', () => expect(formatKsh(123456789), 'Ksh 1,234,567.89'));
    test('formats a value under 100 (sub-shilling cents only)', () => expect(formatKsh(5), 'Ksh 0.05'));
  });

  group('formatShortDate', () {
    test('pads single-digit days and abbreviates the month', () {
      expect(formatShortDate(DateTime(2026, 9, 3)), '03 Sep');
    });
    test('double-digit day, December abbreviation', () {
      expect(formatShortDate(DateTime(2026, 12, 25)), '25 Dec');
    });
  });

  group('formatLongDate', () {
    test('adds the year to the short date', () {
      expect(formatLongDate(DateTime(2026, 9, 3)), '03 Sep 2026');
    });
  });
}
