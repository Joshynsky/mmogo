// Pure-logic tests for lib/domain/cash/cash_code.dart — no DB, no widget.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/cash/cash_code.dart';

void main() {
  test('formats a normal date/time with zero-padded month/day/hour/minute', () {
    final ms = DateTime(2026, 9, 18, 14, 30).millisecondsSinceEpoch;
    expect(generateCashDisplayCode(ms), 'CASH-20260918-1430');
  });

  test('zero-pads single-digit month, day, hour, and minute', () {
    final ms = DateTime(2026, 1, 5, 3, 7).millisecondsSinceEpoch;
    expect(generateCashDisplayCode(ms), 'CASH-20260105-0307');
  });

  test('midnight (00:00) formats correctly, not as 24:00 or empty', () {
    final ms = DateTime(2026, 12, 31, 0, 0).millisecondsSinceEpoch;
    expect(generateCashDisplayCode(ms), 'CASH-20261231-0000');
  });

  test(
    'two same-minute cash entries produce the identical code — expected/schema-safe, '
    'not a collision this function must prevent (display_code is non-unique; '
    'transactions.id is the real primary key)',
    () {
      final ms = DateTime(2026, 9, 18, 14, 30).millisecondsSinceEpoch;
      expect(generateCashDisplayCode(ms), generateCashDisplayCode(ms));
    },
  );
}
