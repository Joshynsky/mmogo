// 0.1.2 S6b (PH1, H3, P-Analytics-02/05/15): Month by weeks or days, Year
// quarters or months, All time five-year blocks, Custom over 31 days, the
// stepping that goes with them, and the change pill built on the one shared
// rule. Sample "today" is Thu 24 Sep 2026, first transaction 15 Aug 2026.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_change.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/analytics/chart_blocks.dart';
import 'package:mmogo/domain/home/home_period.dart';
import 'package:mmogo/domain/period_change.dart';
import 'package:mmogo/domain/period_math.dart' as pm;

final today = DateTime(2026, 9, 24);
final now = DateTime(2026, 9, 24, 13, 30);
final first = DateTime(2026, 8, 15);

DayRange d(DateTime s, DateTime e) => DayRange(s, e);
List<String> labels(ChartSpec s) => [for (final b in s.buckets) b.label];
DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

ChangeDisplay? change(AnalyticsPeriod p, DateTime t, int total, int? prior) => analyticsChange(
  granularity: p.granularity,
  range: p.range(today: t, first: first),
  today: t,
  totalCents: total,
  priorCents: prior,
  vs: p.words(today: t, first: first).vs,
);

void main() {
  group('Month: one month, by weeks (default)', () {
    final month = AnalyticsPeriod.month(today, firstDay: 1);

    test('Sep 2026: five segments, the first and last are part weeks with their day counts', () {
      final s = month.chart(now: now, first: first);
      expect(labels(s), ['1-6', '7-13', '14-20', '21-27', '28-30']);
      expect([for (final b in s.buckets) b.sub], ['6 days', '', '', '', '3 days']);
      expect([for (final b in s.buckets) b.part], [true, false, false, false, true]);
      expect(s.title, 'By week of the month');
      expect(s.legend, 'Striped bar = part week (fewer than 7 days in this month)');
      expect(s.showAverage, isFalse);
      expect(s.futureStubs, isTrue);
      // Only that month's days: nothing before the 1st or after the 30th.
      expect(at(s.buckets.first.startMs), DateTime(2026, 9, 1));
      expect(at(s.buckets.last.endMs), DateTime(2026, 9, 30, 23, 59, 59, 999));
    });

    test('a month with no part week has no legend (Feb 2027 starts on a Monday)', () {
      final s = AnalyticsPeriod.month(DateTime(2027, 2, 1), firstDay: 1).chart(now: now, first: first);
      expect(s.legend, '');
      expect(s.buckets.any((b) => b.part), isFalse);
    });

    test('a segment that has not started is future and cannot be tapped', () {
      final s = month.chart(now: now, first: first);
      expect([for (final b in s.buckets) b.future], [false, false, false, false, true]);
      expect(s.buckets[4].tappable, isFalse);
      expect(s.buckets[4].hasTip, isFalse);
    });

    test('a segment has a tooltip first and opens the WHOLE calendar week after', () {
      final s = month.chart(now: now, first: first);
      final b = s.buckets.first; // 1-6 Sep
      expect(b.hasTip, isTrue);
      expect(b.tipLines!(60000), ['1-6 Sep · 6 days', 'Ksh 600 · avg Ksh 100/day', 'Tap again to open the week']);
      final target = b.target!;
      expect(target.granularity, AnalyticsGranularity.week);
      expect(target.range(today: today), d(DateTime(2026, 8, 31), DateTime(2026, 9, 6)), reason: 'the whole week');
      expect(b.cross, 'Week crosses into August');
      expect(s.buckets[1].cross, isNull, reason: 'a full week inside the month crosses nothing');
      expect(s.buckets.last.cross, 'Week crosses into October');
    });

    test('Sunday-first weeks cut the month differently', () {
      final s = AnalyticsPeriod.month(today, firstDay: 1).withFirstDay(7).chart(now: now, first: first);
      expect(labels(s), ['1-5', '6-12', '13-19', '20-26', '27-30']);
    });
  });

  group('Month: by days (preference)', () {
    test('every day of that month and no other, the 1st / 5th / last labelled', () {
      final s = AnalyticsPeriod.month(DateTime(2026, 8, 1), firstDay: 1).chart(now: now, first: first, monthStyle: MonthChartStyle.days);
      expect(s.buckets, hasLength(31));
      expect(s.buckets.where((b) => b.label.isNotEmpty).map((b) => b.label), ['1', '5', '10', '15', '20', '25', '31']);
      expect(at(s.buckets.first.startMs), DateTime(2026, 8, 1));
      expect(at(s.buckets.last.endMs), DateTime(2026, 8, 31, 23, 59, 59, 999));
      expect(s.title, 'By day');
      expect(s.showAverage, isTrue);
      expect(s.legend, '');
      expect(s.buckets.every((b) => b.hasTip), isTrue);
      expect(s.buckets[2].tipLines!(50000), ['Mon 3 Aug', 'Ksh 500', 'Tap again to open the day']);
      expect(s.buckets[2].target, AnalyticsPeriod.day(DateTime(2026, 8, 3), firstDay: 1));
    });

    test('days after today are future (the current month)', () {
      final s = AnalyticsPeriod.month(today, firstDay: 1).chart(now: now, first: first, monthStyle: MonthChartStyle.days);
      expect(s.buckets.where((b) => !b.future), hasLength(24));
      expect(s.buckets[24].tappable, isFalse);
    });

    test('February incl. a leap day: 29 bars', () {
      final s = AnalyticsPeriod.month(DateTime(2028, 2, 5), firstDay: 1).chart(now: now, first: first, monthStyle: MonthChartStyle.days);
      expect(s.buckets, hasLength(29));
    });
  });

  group('Month stepping: one month at a time', () {
    test('Previous and Next move one month and stop at the current one', () {
      final m = AnalyticsPeriod.month(today, firstDay: 1);
      expect(m.canStepForward(today: today), isFalse);
      final aug = m.step(-1, today: today);
      expect(aug.range(today: today), d(DateTime(2026, 8, 1), DateTime(2026, 8, 31)));
      expect(aug.canStepForward(today: today), isTrue);
      expect(aug.step(1, today: today).anchor, DateTime(2026, 9, 1));
      expect(aug.step(1, today: today).step(1, today: today).anchor, DateTime(2026, 9, 1));
    });

    test('Previous stops at a year before the first transaction', () {
      var p = AnalyticsPeriod.month(today, firstDay: 1);
      var steps = 0;
      while (p.canStepBack(today: today, first: first) && steps < 100) {
        p = p.step(-1, today: today);
        steps++;
      }
      expect(p.anchor, DateTime(2025, 8, 1));
      expect(steps, 13);
    });

    test('the Month menu entries are plain months; picking one keeps its anchor', () {
      final o = AnalyticsPeriod.month(today, firstDay: 1).options(today: today);
      expect(o[5].period.anchor, DateTime(2026, 4, 1));
      expect(o[5].period.step(1, today: today).anchor, DateTime(2026, 5, 1));
    });
  });

  group('Year: twelve months with quarter totals or monthly amounts', () {
    final year = AnalyticsPeriod.year(2026, today: today, firstDay: 1);

    test('quarters (default): 12 bars, a spanning line per three months, no Q1-Q4 text', () {
      final s = year.chart(now: now, first: first);
      expect(s.buckets, hasLength(12));
      expect(s.under, ChartUnder.quarters);
      expect(s.title, 'By month');
      expect(s.buckets.map((b) => b.label).join(), 'JFMAMJJASOND');
      expect(s.buckets.any((b) => b.label.contains('Q')), isFalse);
      expect(s.legend, '');
    });

    test('months: each month has its own amount line', () {
      expect(year.chart(now: now, first: first, yearAmounts: YearViewAmounts.months).under, ChartUnder.months);
    });
  });

  group('All time: five-year blocks, no comparison', () {
    final all = AnalyticsPeriod.allTime(today, firstDay: 1);

    test('2026: five year bars 2026-2030; only years that can hold data are tappable', () {
      final s = all.chart(now: now, first: first);
      expect(labels(s), ['2026', '2027', '2028', '2029', '2030']);
      expect(s.title, 'By year, 2026 to 2030');
      expect([for (final b in s.buckets) b.tappable], [true, false, false, false, false]);
      expect(s.buckets.first.target, AnalyticsPeriod.year(2026, today: today, firstDay: 1));
      expect(s.hint, 'Tap a year with data to open it');
    });

    test('Previous is disabled when nothing exists before the block (first block 2026)', () {
      expect(all.canStepBack(today: today, first: first), isFalse);
      expect(all.canStepBack(today: today), isFalse, reason: 'no transactions at all');
      expect(all.canStepForward(today: today), isFalse, reason: 'Next is disabled on the current block');
    });

    test('with older data Previous steps to 2021-2025 and Next comes back; 2021 is the end', () {
      final early = DateTime(2022, 3, 1);
      expect(all.canStepBack(today: today, first: early), isTrue);
      final back = all.step(-1, today: today);
      expect(back.chart(now: now, first: early).title, 'By year, 2021 to 2025');
      expect(labels(back.chart(now: now, first: early)), ['2021', '2022', '2023', '2024', '2025']);
      expect([for (final b in back.chart(now: now, first: early).buckets) b.tappable], [false, true, true, true, true]);
      expect(back.canStepForward(today: today), isTrue);
      expect(back.canStepBack(today: today, first: early), isFalse, reason: 'first transaction is inside this block');
      expect(back.step(1, today: today), all);
      expect(all.step(1, today: today), all, reason: 'never past the current block');
    });

    test('block boundaries: 2025 sits in 2021-2025, 2031 starts a new block', () {
      expect(AnalyticsPeriod.allTime(DateTime(2025, 12, 31), firstDay: 1).chart(now: DateTime(2025, 12, 31), first: DateTime(2025, 1, 1)).title,
          'By year, 2021 to 2025');
      expect(AnalyticsPeriod.allTime(DateTime(2031, 1, 1), firstDay: 1).chart(now: DateTime(2031, 1, 1), first: DateTime(2026, 1, 1)).title,
          'By year, 2031 to 2035');
    });

    test('no comparison between blocks: no prior range, no change pill', () {
      expect(all.priorRange(today: today, first: first), isNull);
      expect(change(all, today, 5000, null), isNull);
      expect(change(all, today, 5000, 100), isNull, reason: 'even if a prior total were handed in');
    });

    test('the recipient (party) view keeps its by-month all-time chart', () {
      final s = all.chart(now: now, first: first, party: true);
      expect(s.title, 'By month · all time');
      expect(s.buckets.every((b) => b.target == null), isTrue);
    });
  });

  group('Custom: days up to 31, calendar-week blocks beyond', () {
    test('31 days stays days, 32 days becomes weeks', () {
      final days31 = AnalyticsPeriod.custom(DateTime(2026, 8, 25), today, today: today, firstDay: 1).chart(now: now);
      expect(days31.title, 'By day');
      expect(days31.buckets, hasLength(31));
      final days32 = AnalyticsPeriod.custom(DateTime(2026, 8, 24), today, today: today, firstDay: 1).chart(now: now);
      expect(days32.title, 'By week');
      expect(days32.buckets, hasLength(5));
    });

    test('blocks align to calendar weeks (Monday), clipped and striped at both ends', () {
      final s = AnalyticsPeriod.custom(DateTime(2026, 8, 20), today, today: today, firstDay: 1).chart(now: now);
      expect(labels(s), ['20', '24', '31', '7', '14', '21']);
      expect([for (final b in s.buckets) b.part], [true, false, false, false, false, true]);
      expect(at(s.buckets.first.startMs), DateTime(2026, 8, 20), reason: 'clipped to the chosen start');
      expect(at(s.buckets.first.endMs), DateTime(2026, 8, 23, 23, 59, 59, 999));
      expect(at(s.buckets.last.endMs), DateTime(2026, 9, 24, 23, 59, 59, 999), reason: 'clipped to the chosen end');
      expect(s.legend, 'Striped bar = part week (fewer than 7 days in this period)');
      expect(s.showAverage, isTrue);
    });

    test('first day Sunday', () {
      final s = AnalyticsPeriod.custom(DateTime(2026, 8, 20), today, today: today, firstDay: 1).withFirstDay(7).chart(now: now);
      expect(labels(s), ['20', '23', '30', '6', '13', '20']);
      expect(s.buckets.map((b) => b.part), [true, false, false, false, false, true]);
    });

    test('whole weeks only: no legend', () {
      // Mon 3 Aug to Sun 6 Sep: 35 days, five whole weeks; today is later so no clip.
      final s = AnalyticsPeriod.custom(DateTime(2026, 8, 3), DateTime(2026, 9, 6), today: today, firstDay: 1).chart(now: now);
      expect(s.buckets, hasLength(5));
      expect(s.legend, '');
    });
  });

  group('the change pill (Analytics)', () {
    final week = AnalyticsPeriod.thisWeek(today, firstDay: 1);

    test('Week days 1-3 show the cue "3/7" with its words, day 4 shows the change', () {
      final w = AnalyticsPeriod.thisWeek(DateTime(2026, 9, 23), firstDay: 1);
      final c = change(w, DateTime(2026, 9, 23), 9000, 1000)!;
      expect(c.look, ChangeLook.cue);
      expect(c.text, '3/7');
      expect(c.label, 'Day 3 of 7. The change shows from day 4');
      expect(c.tooltip, 'Day 3 of 7; the change shows from day 4');
      final d4 = change(week, today, 9000, 5000)!;
      expect(d4.look, ChangeLook.up);
      expect(d4.text, '▲ 80% vs last week');
    });

    test('Month cue and the first day it shows', () {
      final aug = AnalyticsPeriod.month(DateTime(2026, 8, 1), firstDay: 1);
      expect(change(aug, DateTime(2026, 8, 8), 100, 50)!.text, '8/31');
      expect(change(aug, DateTime(2026, 8, 15), 100, 50)!.look, ChangeLook.cue);
      expect(change(aug, DateTime(2026, 8, 16), 100, 50)!.look, ChangeLook.up);
      final sep = AnalyticsPeriod.month(DateTime(2026, 9, 1), firstDay: 1);
      expect(change(sep, DateTime(2026, 9, 14), 100, 50)!.look, ChangeLook.cue);
      expect(change(sep, DateTime(2026, 9, 15), 100, 50)!.look, ChangeLook.up);
      expect(change(sep, DateTime(2026, 9, 14), 100, 50)!.label, 'Day 14 of 30. The change shows from day 15');
    });

    test('a past week or month always shows the change', () {
      final lastWeek = AnalyticsPeriod.thisWeek(DateTime(2026, 9, 16), firstDay: 1);
      expect(change(lastWeek, DateTime(2026, 9, 22), 100, 50)!.look, ChangeLook.up);
      expect(change(AnalyticsPeriod.month(DateTime(2026, 8, 1), firstDay: 1), DateTime(2026, 9, 2), 100, 50)!.look, ChangeLook.up);
    });

    test('Year: the cue is the month number until day 183, then the change', () {
      final y = AnalyticsPeriod.year(2026, today: today, firstDay: 1);
      final c = change(y, DateTime(2026, 5, 20), 100, 50)!;
      expect(c.look, ChangeLook.cue);
      expect(c.text, '5/12');
      expect(c.label, 'Month 5 of 12. The change shows from July');
      expect(c.tooltip, 'Month 5 of 12; the change shows from July');
      expect(change(y, DateTime(2026, 7, 1), 100, 50)!.look, ChangeLook.cue);
      expect(change(y, DateTime(2026, 7, 2), 100, 50)!.look, ChangeLook.up);
      expect(change(y, DateTime(2026, 7, 2), 100, 50)!.text, '▲ 100% vs last year');
      expect(change(AnalyticsPeriod.year(2025, today: today, firstDay: 1), DateTime(2026, 1, 3), 100, 50)!.look, ChangeLook.up, reason: 'a past year');
    });

    test('prior total 0: "nothing before to compare" with spending, "no spending" without', () {
      expect(change(week, today, 500, 0)!.text, 'nothing before to compare');
      expect(change(week, today, 0, 0)!.text, 'no spending');
      expect(change(week, today, 500, 0)!.look, ChangeLook.flat);
    });

    test('equal totals: Week and Month say "—" (never "= 0%"), the others keep "▲ 0%"', () {
      expect(change(week, today, 700, 700)!.text, '—');
      expect(change(AnalyticsPeriod.month(today, firstDay: 1), today, 700, 700)!.text, '—');
      expect(change(AnalyticsPeriod.day(today, firstDay: 1), today, 700, 700)!.text, '▲ 0% vs day before');
      expect(change(AnalyticsPeriod.year(2025, today: today, firstDay: 1), today, 700, 700)!.text, '▲ 0% vs last year');
    });

    test('percent rounds |this - prior| / prior; down is green; the captions are kept', () {
      expect(change(week, today, 4000, 5000)!.text, '▼ 20% vs last week');
      expect(change(week, today, 4000, 5000)!.look, ChangeLook.down);
      expect(change(AnalyticsPeriod.month(DateTime(2026, 8, 1), firstDay: 1), DateTime(2026, 9, 2), 1, 3)!.text, '▼ 67% vs last month');
      expect(change(AnalyticsPeriod.day(today, firstDay: 1), today, 150, 100)!.text, '▲ 50% vs day before');
      final custom = AnalyticsPeriod.custom(DateTime(2026, 9, 18), today, today: today, firstDay: 1);
      expect(change(custom, today, 150, 100)!.text, '▲ 50% vs previous 7 days');
    });
  });

  group('Home and Analytics use the same rule', () {
    test('for every day of a month, Home and Analytics hide on the same day with the same cue and prior', () {
      for (var day = 1; day <= 31; day++) {
        final t = DateTime(2026, 8, day);
        final home = periodProgress(ProgressKind.month, DateTime(t.year, t.month, 1), t);
        final an = change(AnalyticsPeriod.month(t, firstDay: 1), t, 100, 50)!;
        expect(an.look == ChangeLook.cue, home.hide, reason: 'day $day');
        if (home.hide) expect(an.text, home.cue);
        // Home's prior window is the same whole previous month.
        expect(pm.dayBounds(home.priorStart).$1, HomePeriod.month.priorBounds(t).$1);
        expect(pm.dayBounds(home.priorEnd).$2, HomePeriod.month.priorBounds(t).$2);
      }
    });

    test('for every day of a week (either first day), the same', () {
      for (final fd in [1, 7]) {
        for (var k = 0; k < 7; k++) {
          final start = pm.calendarWeekStart(DateTime(2026, 9, 24), firstDay: fd);
          final t = DateTime(start.year, start.month, start.day + k);
          final home = periodProgress(ProgressKind.week, pm.calendarWeekStart(t, firstDay: fd), t);
          final p = AnalyticsPeriod.thisWeek(t, firstDay: fd);
          final an = change(p, t, 100, 50)!;
          expect(an.look == ChangeLook.cue, home.hide, reason: 'first day $fd, day ${k + 1}');
          expect(home.hide, k < 3);
          expect(pm.dayBounds(home.priorStart).$1, HomePeriod.week.priorBounds(t, firstDay: fd).$1);
          expect(pm.dayBounds(home.priorEnd).$2, HomePeriod.week.priorBounds(t, firstDay: fd).$2);
          expect(p.priorRange(today: t)!.start, home.priorStart);
        }
      }
    });
  });
}
