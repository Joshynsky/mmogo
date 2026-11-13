// The Fuliza block on Home: which rows exist for each period, and THE DATE FILTER (`fulizaCostBetween`).
// Invented data only. Bounds come from the same period math Home uses for its totals.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/format/money.dart';
import 'package:mmogo/domain/fuliza/fuliza_home_rows.dart';
import 'package:mmogo/domain/fuliza/fuliza_ledger.dart';
import 'package:mmogo/domain/fuliza/fuliza_page_data.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:mmogo/domain/home/home_period.dart';

FulizaPageData _page(List<FulizaEvent> ev) => buildFulizaPage(FulizaCalculator.compute(ev, const {}), ev)!;

FulizaEvent _draw(String code, DateTime at, int amt, int fee, int total) => FulizaEvent(
  kind: FulizaEventKind.draw,
  code: code,
  at: at,
  amountCents: amt,
  feeCents: fee,
  printedTotalCents: total,
);

FulizaEvent _full(String code, DateTime at, int amt) =>
    FulizaEvent(kind: FulizaEventKind.repayFull, code: code, at: at, amountCents: amt);

FulizaEvent _part(String code, DateTime at, int amt) =>
    FulizaEvent(kind: FulizaEventKind.repayPartial, code: code, at: at, amountCents: amt);

/// The mock's invented messages, up to 12 Nov: owing 1,638.00 on the 12th.
List<FulizaEvent> _busy() => [
  _draw('QDMHR00001', DateTime(2026, 10, 28, 9), 30000, 300, 30300),
  _full('QDMHR00002', DateTime(2026, 10, 30, 9), 30300),
  _draw('QDMHR00003', DateTime(2026, 11, 4, 9), 60000, 600, 60600),
  _draw('QDMHR00004', DateTime(2026, 11, 9, 9), 100000, 1000, 162200), // daily fee 6.00
  _draw('QDMHR00005', DateTime(2026, 11, 11, 9), 25000, 250, 188650), // daily fee 12.00
  _part('QDMHR00006', DateTime(2026, 11, 11, 10), 40000),
  _draw('QDMHR00007', DateTime(2026, 11, 12, 9), 15000, 150, 163800),
];

FulizaHomeRows? _rows(List<FulizaEvent> ev, DateTime now, HomePeriod p, {int firstDay = 1}) {
  final (s, e) = p.bounds(now, firstDay: firstDay);
  return fulizaHomeRows(_page(ev), s, e, fulizaPeriodWord(p), formatKsh);
}

void main() {
  final thu12 = DateTime(2026, 11, 12, 14);

  group('rows per period (owing, busy week)', () {
    test('today: owing and the 1.50 fee of today', () {
      final r = _rows(_busy(), thu12, HomePeriod.today)!;
      expect(r.owing!.label, 'Fuliza: owing');
      expect(r.owing!.value, 'Ksh 1,638.00');
      expect(r.cost!.label, 'Fuliza cost (estimated), today');
      expect(r.cost!.value, 'Ksh 1.50');
    });

    test('this week (Monday 9 Nov): 10 + 6 + 2.50 + 12 + 1.50 = 32.00', () {
      final r = _rows(_busy(), thu12, HomePeriod.week)!;
      expect(r.costCents, 3200);
      expect(r.cost!.label, 'Fuliza cost (estimated), this week');
      expect(r.cost!.value, 'Ksh 32.00');
    });

    test('this month: adds the 4 Nov fee, not October: 38.00', () {
      final r = _rows(_busy(), thu12, HomePeriod.month)!;
      expect(r.costCents, 3800);
      expect(r.cost!.label, 'Fuliza cost (estimated), this month');
      expect(r.owing!.value, 'Ksh 1,638.00', reason: 'the owing row never changes with the period');
    });

    test('week start follows the setting: Sunday-first week of Thu 12 Nov starts 8 Nov', () {
      // Nothing happened on the 8th, so the total is the same; a Thursday-first week starts today.
      expect(_rows(_busy(), thu12, HomePeriod.week, firstDay: 7)!.costCents, 3200);
      expect(_rows(_busy(), thu12, HomePeriod.week, firstDay: 4)!.costCents, 150);
    });
  });

  group('which rows exist', () {
    test('owing with no fee in the period: owing row only', () {
      final sat21 = DateTime(2026, 11, 21, 10);
      final week = _rows(_busy(), sat21, HomePeriod.week)!;
      expect(week.owing, isNotNull);
      expect(week.cost, isNull);
      expect(week.costCents, 0);
      expect(_rows(_busy(), sat21, HomePeriod.month)!.costCents, 3800);
    });

    test('nothing owed but a fee in the period: cost row only', () {
      final ev = [..._busy(), _full('QDMHR00008', DateTime(2026, 11, 13, 9), 164400)]; // daily fee 6.00
      final fri13 = DateTime(2026, 11, 13, 18);
      final today = _rows(ev, fri13, HomePeriod.today)!;
      expect(today.owing, isNull);
      expect(today.cost!.value, 'Ksh 6.00');
      expect(_rows(ev, fri13, HomePeriod.week)!.costCents, 3800);
      expect(_rows(ev, fri13, HomePeriod.month)!.costCents, 4400);
    });

    test('nothing owed and nothing in the period: no rows at all (block hidden)', () {
      final ev = [..._busy(), _full('QDMHR00008', DateTime(2026, 11, 13, 9), 164400)];
      final dec3 = DateTime(2026, 12, 3, 10);
      for (final p in HomePeriod.values) {
        expect(_rows(ev, dec3, p), isNull, reason: '$p');
      }
    });

    test('a repayment alone is not a cost: repaid with no excess shows no cost row', () {
      final ev = [
        _draw('QDMHR00001', DateTime(2026, 11, 2, 9), 50000, 500, 50500),
        _full('QDMHR00002', DateTime(2026, 11, 5, 9), 50500), // exact: no daily fee
      ];
      expect(_rows(ev, DateTime(2026, 11, 5, 12), HomePeriod.today), isNull);
      expect(_rows(ev, DateTime(2026, 11, 5, 12), HomePeriod.month)!.costCents, 500);
    });

    test('a part payment alone today with owing: owing row only (no cost row)', () {
      final ev = [..._busy(), _part('QDMHR00009', DateTime(2026, 11, 13, 8), 10000)];
      final r = _rows(ev, DateTime(2026, 11, 13, 12), HomePeriod.today)!;
      expect(r.cost, isNull);
      expect(r.owing!.label, 'Fuliza: owing about');
      expect(r.owing!.value, 'Ksh 1,538.00');
    });

    test('owing about (after a part payment) keeps the word about', () {
      final ev = _busy().sublist(0, 6); // ends with the 400 part payment
      final r = _rows(ev, DateTime(2026, 11, 11, 12), HomePeriod.today)!;
      expect(r.owing!.label, 'Fuliza: owing about');
      expect(r.owing!.value, 'Ksh 1,486.50');
      expect(r.costCents, 1450); // 2.50 + 12.00
    });

    test('balance not known: that sentence, no figure; a fee still adds the cost row', () {
      final ev = [_part('QDMHR00001', DateTime(2026, 11, 12, 9), 20000)];
      final r = _rows(ev, thu12, HomePeriod.today)!;
      expect(r.owing!.label, 'Fuliza: balance not known');
      expect(r.owing!.value, isNull);
      expect(r.cost, isNull);
      expect(r.spoken, 'Fuliza: balance not known');
    });

    test('long figures keep their full text', () {
      final ev = [_draw('QDMHR00001', DateTime(2026, 11, 12, 9), 9600000, 96000, 9828000)];
      final r = _rows(ev, thu12, HomePeriod.today)!;
      expect(r.owing!.value, 'Ksh 98,280.00');
      expect(r.cost!.value, 'Ksh 960.00');
    });

    test('spoken label reads the rows in order', () {
      final r = _rows(_busy(), thu12, HomePeriod.week)!;
      expect(r.spoken, 'Fuliza: owing Ksh 1,638.00. Fuliza cost (estimated), this week Ksh 32.00');
    });
  });

  group('THE DATE FILTER: fulizaCostBetween', () {
    // One draw with an access fee at a time we control, in local time.
    FulizaPageData one(DateTime at) => _page([_draw('QDMHR00001', at, 10000, 100, 10100)]);

    test('summing every fee over all time equals the page cost (same maths as the page)', () {
      final d = _page(_busy());
      expect(fulizaCostBetween(d, 0, 9999999999999), d.costCents);
      expect(d.feesAt.fold<int>(0, (a, f) => a + f.cents), d.costCents);
      expect(d.costCents, 300 + 600 + 1000 + 600 + 250 + 1200 + 150); // access 23.00 + daily 18.00
    });

    test('boundaries: first and last millisecond of a day are in, the next and previous are out', () {
      final (s, e) = HomePeriod.today.bounds(DateTime(2026, 11, 12, 12));
      expect(s, DateTime(2026, 11, 12).millisecondsSinceEpoch);
      expect(fulizaCostBetween(one(DateTime(2026, 11, 12)), s, e), 100);
      expect(fulizaCostBetween(one(DateTime(2026, 11, 12, 23, 59, 59, 999)), s, e), 100);
      expect(fulizaCostBetween(one(DateTime(2026, 11, 13)), s, e), 0);
      expect(fulizaCostBetween(one(DateTime(2026, 11, 11, 23, 59, 59, 999)), s, e), 0);
    });

    test('month rollover: 30 Nov 23:59:59.999 is November, 1 Dec 00:00 is December', () {
      final nov = HomePeriod.month.bounds(DateTime(2026, 11, 15));
      final dec = HomePeriod.month.bounds(DateTime(2026, 12, 15));
      final last = one(DateTime(2026, 11, 30, 23, 59, 59, 999));
      final first = one(DateTime(2026, 12, 1));
      expect(fulizaCostBetween(last, nov.$1, nov.$2), 100);
      expect(fulizaCostBetween(last, dec.$1, dec.$2), 0);
      expect(fulizaCostBetween(first, nov.$1, nov.$2), 0);
      expect(fulizaCostBetween(first, dec.$1, dec.$2), 100);
    });

    test('week edges: Monday 00:00 is in, the Sunday before at 23:59:59.999 is out', () {
      final w = HomePeriod.week.bounds(DateTime(2026, 11, 12, 14)); // Mon 9 Nov
      expect(fulizaCostBetween(one(DateTime(2026, 11, 9)), w.$1, w.$2), 100);
      expect(fulizaCostBetween(one(DateTime(2026, 11, 8, 23, 59, 59, 999)), w.$1, w.$2), 0);
      expect(fulizaCostBetween(one(DateTime(2026, 11, 12, 23, 59, 59, 999)), w.$1, w.$2), 100);
      expect(fulizaCostBetween(one(DateTime(2026, 11, 13)), w.$1, w.$2), 0, reason: 'a week is the week so far');
    });

    test('local time: an event is dated by its local calendar day, whatever the zone (instant compare)', () {
      // 00:30 local on the 12th is the 12th even where UTC is still the 11th.
      final at = DateTime(2026, 11, 12, 0, 30);
      final today = HomePeriod.today.bounds(DateTime(2026, 11, 12, 9));
      final yesterday = HomePeriod.today.bounds(DateTime(2026, 11, 11, 9));
      expect(fulizaCostBetween(one(at), today.$1, today.$2), 100);
      expect(fulizaCostBetween(one(at), yesterday.$1, yesterday.$2), 0);
      // A UTC-built instant is the same instant: filtering compares epoch milliseconds, not calendar fields.
      expect(fulizaCostBetween(one(at.toUtc()), today.$1, today.$2), 100);
    });

    test('a fee is dated by its own message: the daily fee of a draw counts on the draw day', () {
      final d = _page(_busy());
      final nine = HomePeriod.today.bounds(DateTime(2026, 11, 9, 12));
      expect(fulizaCostBetween(d, nine.$1, nine.$2), 1600); // access 10.00 + daily 6.00
    });

    test('a full repayment excess is dated by the repayment', () {
      final ev = [..._busy(), _full('QDMHR00008', DateTime(2026, 11, 13, 9), 164400)];
      final d = _page(ev);
      final b = HomePeriod.today.bounds(DateTime(2026, 11, 13, 12));
      expect(fulizaCostBetween(d, b.$1, b.$2), 600);
    });
  });
}
