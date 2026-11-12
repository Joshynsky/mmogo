// 0.2.0 S9: the numbers the Fuliza page and the Home line show (invented data only).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/format/money.dart';
import 'package:mmogo/domain/fuliza/fuliza_demo.dart';
import 'package:mmogo/domain/fuliza/fuliza_ledger.dart';
import 'package:mmogo/domain/fuliza/fuliza_page_data.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';

FulizaPageData? _page(List<FulizaEvent> ev, {Set<String> codes = const {}}) =>
    buildFulizaPage(FulizaCalculator.compute(ev, codes), ev);

FulizaEvent _draw(String code, DateTime at, int amt, int fee, int total) => FulizaEvent(
  kind: FulizaEventKind.draw,
  code: code,
  at: at,
  amountCents: amt,
  feeCents: fee,
  printedTotalCents: total,
);

void main() {
  final now = DateTime(2026, 11, 3, 12);

  test('no events: no data (no line, no page)', () {
    expect(_page(const []), isNull);
  });

  test('the demo cycle: owing about 1,227 (estimate), carried in 200, cost 27', () {
    final d = _page(demoFulizaEvents(now), codes: {'QDMFL00001', 'QDMFL00002', 'QDMFL00004'})!;
    expect(d.owingCents, 122700);
    expect(d.owingIsEstimate, isTrue);
    expect(d.owingUnknown, isFalse);
    expect(d.takenCents, 150000);
    expect(d.repaidCents, 50000);
    expect(d.accessFeesCents, 1500);
    expect(d.dailyFeesCents, 1200);
    expect(d.costCents, 2700);
    expect(d.drawCount, 3);
    expect(d.carriedInCents, 20000);
    expect(d.unmatchedCount, 0);
    expect(d.costPer100, 2); // 27 of 1,500 taken
    expect(fulizaHomeLineLabel(d, formatKsh), 'Fuliza · Owing about Ksh 1,227.00');
  });

  test('history is by day, newest first, newest entry first inside a day', () {
    final d = _page(demoFulizaEvents(now))!;
    final days = [for (final x in d.days) x.day];
    expect([...days]..sort((a, b) => b.compareTo(a)), days);
    expect(d.days.first.entries.last.event.code, 'QDMFL00004');
    expect(d.days.first.borrowedCents, 50000);
    expect(d.days.first.entries.first.event.code, 'QDMFL00005'); // newest first inside the day
    expect(d.days.first.repaidCents, 20000);
    final part = d.days.firstWhere((x) => x.entries.any((e) => e.event.code == 'QDMFL00003'));
    expect(part.repaidCents, 30000);
    expect(part.entries.single.owingAfterCents, isNull);
  });

  test('a draw shows the daily fee seen (estimated) and owing after; the first draw shows none', () {
    final d = _page(demoFulizaEvents(now))!;
    final all = [for (final x in d.days) ...x.entries];
    final second = all.firstWhere((e) => e.event.code == 'QDMFL00002');
    expect(second.dailyFeeSeenCents, 600);
    expect(second.owingAfterCents, 121600);
    final first = all.firstWhere((e) => e.event.code == 'QDMFL00001');
    expect(first.dailyFeeSeenCents, 0);
  });

  test('borrowings without a spend of the same code are counted as not matched', () {
    final d = _page(demoFulizaEvents(now), codes: {'QDMFL00001'})!;
    expect(d.unmatchedCount, 2);
    expect(d.days.expand((x) => x.entries).where((e) => e.isDraw && e.paired).length, 1);
  });

  test('owing unknown: the first message seen is a part repayment', () {
    final ev = [FulizaEvent(kind: FulizaEventKind.repayPartial, code: 'QDMFL00009', at: now, amountCents: 20000)];
    final d = _page(ev)!;
    expect(d.owingUnknown, isTrue);
    expect(d.owingCents, isNull);
    expect(fulizaHomeLineLabel(d, formatKsh), 'Fuliza · Owing unknown');
    expect(d.drawCount, 0);
    expect(d.costPer100, 0); // nothing taken: no division by zero
  });

  test('nothing owed after a full repayment; the label says so', () {
    final ev = [
      _draw('QDMFL00001', DateTime(2026, 10, 30, 9), 50000, 500, 50500),
      FulizaEvent(kind: FulizaEventKind.repayFull, code: 'QDMFL00005', at: DateTime(2026, 11, 1, 9), amountCents: 50500),
    ];
    final d = _page(ev)!;
    expect(d.nothingOwed, isTrue);
    expect(d.carriedInCents, isNull);
    expect(fulizaHomeLineLabel(d, formatKsh), 'Fuliza · Nothing owed');
    expect(d.days.first.entries.single.owingAfterCents, 0);
  });

  test('owing exact (no estimate): "Owing Ksh X" without "about"', () {
    final d = _page([_draw('QDMFL00001', DateTime(2026, 11, 1, 9), 50000, 500, 50500)])!;
    expect(d.owingIsEstimate, isFalse);
    expect(d.carriedInCents, isNull);
    expect(fulizaHomeLineLabel(d, formatKsh), 'Fuliza · Owing Ksh 505.00');
  });

  test('demo switch is off unless the define is given (this test run has none)', () {
    expect(fulizaDemoOn, isFalse);
  });
}
