// S7b (PT1) — the recipient sheet's figures (lib/domain/paid_to/paid_to_sheet.dart):
// mock `buckets` (per week for Month, per month for Year and All time), `compact`,
// the 2x2 numbers, first / last, BY CATEGORY.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';
import 'package:mmogo/domain/paid_to/paid_to_sheet.dart';

PaidToPayment _p(DateTime at, int ksh, {String cls = 'Rent', int fee = 0, String phone = '0722114455'}) =>
    PaidToPayment(
      sourceType: 'SEND_MONEY',
      amountCents: ksh * 100,
      feeCents: fee * 100,
      occurredAt: at,
      classificationName: cls,
      label: 'ANN',
      phone: phone,
    );

PaidToRecipient _ann(List<PaidToPayment> ps) => groupPaidTo(ps).single;

void main() {
  group('paidToCompact (mock compact)', () {
    test('whole shillings under 1,000; "1.2k" from 1,000; "1k" not "1.0k"', () {
      expect(paidToCompact(0), '0');
      expect(paidToCompact(99900), '999');
      expect(paidToCompact(100000), '1k');
      expect(paidToCompact(120000), '1.2k');
      expect(paidToCompact(125000), '1.3k');
      expect(paidToCompact(1550000), '15.5k');
    });
  });

  group('bars', () {
    test('Month: one bar per 7-day block (1-7, 8-14 ...), the last one short', () {
      final r = _ann([_p(DateTime(2026, 9, 3), 1000), _p(DateTime(2026, 9, 10), 500), _p(DateTime(2026, 9, 30), 200)]);
      final d = paidToSheetData(r, range: DayRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)), month: true);
      expect(d.perWeek, isTrue);
      expect([for (final b in d.bars) b.label], ['1–7', '8–14', '15–21', '22–28', '29–30']);
      expect([for (final b in d.bars) b.cents], [100000, 50000, 0, 0, 20000]);
      expect(d.valueLabels, isTrue);
    });

    test('Month lengths: February has 4 blocks, a 31-day month has 5 ("29–31")', () {
      final r = _ann([_p(DateTime(2026, 2, 3), 10)]);
      final feb = paidToSheetData(r, range: DayRange(DateTime(2026, 2, 1), DateTime(2026, 2, 28)), month: true);
      expect(feb.bars.map((b) => b.label), ['1–7', '8–14', '15–21', '22–28']);
      final jan = paidToSheetData(r, range: DayRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31)), month: true);
      expect(jan.bars.last.label, '29–31');
    });

    test('Year: one bar per month, Jan to Dec, named; value labels on', () {
      final r = _ann([_p(DateTime(2026, 8, 15), 700), _p(DateTime(2026, 9, 3), 1500)]);
      final d = paidToSheetData(r, range: DayRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)), month: false);
      expect(d.perWeek, isFalse);
      expect(d.bars, hasLength(12));
      expect(d.bars.first.label, 'Jan');
      expect(d.bars[7].cents, 70000);
      expect(d.bars[8].cents, 150000);
      expect(d.valueLabels, isTrue);
    });

    test('All time over more than 12 months: axis names only every quarter ("Jan 26"), no value labels', () {
      final r = _ann([_p(DateTime(2025, 2, 3), 100), _p(DateTime(2026, 9, 3), 100)]);
      final d = paidToSheetData(r, range: DayRange(DateTime(2025, 2, 3), DateTime(2026, 9, 24)), month: false);
      expect(d.bars, hasLength(20)); // Feb 2025 .. Sep 2026
      expect(d.valueLabels, isFalse);
      expect([for (final b in d.bars) b.label].where((l) => l.isNotEmpty), [
        'Apr 25',
        'Jul 25',
        'Oct 25',
        'Jan 26',
        'Apr 26',
        'Jul 26',
      ]);
      expect(d.bars.first.label, '', reason: 'Feb is not a quarter start');
    });

    test('All time of 12 months or fewer names every month and keeps the value labels', () {
      final r = _ann([_p(DateTime(2026, 4, 3), 100)]);
      final d = paidToSheetData(r, range: DayRange(DateTime(2026, 4, 3), DateTime(2026, 9, 24)), month: false);
      expect(d.bars.map((b) => b.label), ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep']);
      expect(d.valueLabels, isTrue);
    });
  });

  test('the numbers: total, count, average (rounded), cost, first, last, categories largest first', () {
    final r = _ann([
      _p(DateTime(2026, 9, 10), 400, cls: 'Gift', fee: 10),
      _p(DateTime(2026, 9, 3), 1200, cls: 'Rent', fee: 20),
      _p(DateTime(2026, 9, 20), 400, cls: 'Gift', fee: 0),
    ]);
    final d = paidToSheetData(r, range: DayRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30)), month: true);
    expect(d.totalCents, 200000);
    expect(d.count, 3);
    expect(d.averageCents, 66667); // 2,000 / 3 = 666.67: rounded, not cut
    expect(d.feeCents, 3000);
    expect(d.first, DateTime(2026, 9, 3));
    expect(d.last, DateTime(2026, 9, 20));
    expect([for (final c in d.categories) (c.name, c.count, c.cents)], [('Rent', 1, 120000), ('Gift', 2, 80000)]);
    expect(d.totalCents, d.bars.fold<int>(0, (s, b) => s + b.cents), reason: 'the bars add up to the total');
  });
}
