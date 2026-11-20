// 0.2.1 #4 (MK-12): one account of a Paybill name, the swipeable All time chart, the window words.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';
import 'package:mmogo/domain/paid_to/paid_to_account_view.dart';
import 'package:mmogo/domain/paid_to/paid_to_sheet.dart';

PaidToPayment _p(String account, DateTime at, int ksh, {String cat = 'Bills'}) => PaidToPayment(
  sourceType: 'PAYBILL',
  amountCents: ksh * 100,
  feeCents: 1000,
  occurredAt: at,
  classificationName: cat,
  label: 'DIRECT PAY 04',
  account: account,
);

PaidToRecipient _group(List<PaidToPayment> pays) {
  PaidToGrouping.paybillByName = true;
  final r = groupPaidTo(pays).single;
  PaidToGrouping.paybillByName = false;
  return r;
}

void main() {
  tearDown(() => PaidToGrouping.paybillByName = false);

  final pays = [
    _p('A1', DateTime(2025, 9, 3), 500),
    _p('A1', DateTime(2025, 11, 3), 300, cat: 'Rent'),
    _p('A2', DateTime(2026, 1, 9), 100),
    _p('A1', DateTime(2026, 10, 25), 200),
    _p('A2', DateTime(2026, 10, 2), 50),
  ];
  final range = DayRange(DateTime(2025, 1, 1), DateTime(2026, 10, 31));

  test('one account: figures, categories and bars cover it alone; the axis does not move', () {
    final r = _group(pays);
    expect(r.accounts.map((a) => a.account), ['A1', 'A2']);
    final all = paidToSheetData(r, range: range, month: false, allTime: true);
    final one = paidToSheetData(r, range: range, month: false, allTime: true, account: 1);
    expect(all.count, 5);
    expect(all.totalCents, 115000);
    expect(one.count, 2);
    expect(one.totalCents, 15000);
    expect(one.feeCents, 2000);
    expect(one.first, DateTime(2026, 1, 9));
    expect(one.categories.single.name, 'Bills');
    expect(one.bars.length, all.bars.length);
    expect(one.bars.map((b) => b.label), all.bars.map((b) => b.label));
    // Only that account's segment (index 1) is left in a bar.
    final oct = one.bars.last;
    expect(oct.segments, [(1, 5000)]);
    expect(all.bars.last.segments, [(0, 20000), (1, 5000)]);
  });

  test('All time: months from the name\'s first payment, windows of 4, padded in front', () {
    final r = _group(pays);
    final d = paidToSheetData(r, range: range, month: false, allTime: true);
    // Sep 2025 .. Oct 2026 = 14 months, padded to 16.
    expect(d.bars.length, 16);
    expect(d.window, 4);
    expect(d.bars.take(2).every((b) => b.pad), isTrue);
    expect(d.bars[2].label, 'Sep 25');
    expect(d.bars.firstWhere((b) => b.month?.month == 1 && b.month?.year == 2026).label, 'Jan 26');
    expect(d.bars.last.label, 'Oct');
    expect(d.valueLabels, isTrue);
    expect(paidToWindowLabel(d.bars.sublist(12)), 'Jul to Oct 2026');
    expect(paidToWindowLabel(d.bars.sublist(0, 4)), 'Sep to Oct 2025');
    expect(paidToWindowLabel(d.bars.sublist(4, 8)), 'Nov 2025 to Feb 2026');
  });

  test('All time with 4 months or fewer does not scroll; Year and Month stay as built', () {
    final r = _group([_p('A1', DateTime(2026, 8, 3), 5), _p('A2', DateTime(2026, 10, 3), 6)]);
    final d = paidToSheetData(r, range: range, month: false, allTime: true);
    expect(d.window, 0);
    expect(d.bars.length, 3);
    final y = paidToSheetData(r, range: DayRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)), month: false);
    expect(y.window, 0);
    expect(y.bars.length, 12);
    final m = paidToSheetData(r, range: DayRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)), month: true);
    expect(m.window, 0);
    expect(m.perWeek, isTrue);
    expect(m.bars.length, 5);
  });

  test('party key of one account is the Paybill name + account key', () {
    final r = _group(pays);
    expect(paidToAccountPartyKey(r, 'A2'), paidToPartyKeyOf(sourceType: 'PAYBILL', label: 'DIRECT PAY 04', account: 'A2'));
    expect(paidToAccountPartyKey(r, 'A2'), isNot(paidToAccountPartyKey(r, 'A1')));
    expect(paidToAccountPartyKey(r, 'nope'), isNull);
  });
}
