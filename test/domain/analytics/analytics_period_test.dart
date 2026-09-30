// T21 — lib/domain/analytics/analytics_period.dart: the reworked period
// model (All time / Year / Month / Week / Day / Custom), stepping, the Month
// window, "back to now" and the chart buckets, checked against the
// approved analytics mock (v4 view B,
// whose sample "today" is Thu 24 Sep 2026 with the first transaction on
// 15 Aug 2026).
//
// Replaces T9's tests of the Yesterday/Today/Week tabs, the Week-tab
// escalation ladder, the "Month · Custom" link and AnalyticsPeriod.containing
// (all removed by T21).
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/domain/analytics/analytics_period.dart';

final today = DateTime(2026, 9, 24);
final now = DateTime(2026, 9, 24, 13, 30);
final first = DateTime(2026, 8, 15);

DayRange d(DateTime s, DateTime e) => DayRange(s, e);

AnalyticsPeriod week([DateTime? anchor]) => AnalyticsPeriod.lastSevenDays(anchor ?? today);

void main() {
  group('ranges, prior ranges and labels', () {
    test('Day: one day; prior = the day before; Today / Yesterday / "Tue 22 Sep"', () {
      final p = AnalyticsPeriod.day(today);
      expect(p.range(today: today), d(today, today));
      expect(p.priorRange(today: today), d(DateTime(2026, 9, 23), DateTime(2026, 9, 23)));
      final w = p.words(today: today);
      expect(w.value, 'Today');
      expect(w.spent, 'Spent today');
      expect(w.vs, 'vs day before');
      expect(AnalyticsPeriod.day(DateTime(2026, 9, 23)).words(today: today).value, 'Yesterday');
      final tue = AnalyticsPeriod.day(DateTime(2026, 9, 22)).words(today: today);
      expect(tue.value, 'Tue 22 Sep');
      expect(tue.spent, 'Spent on Tuesday, 22 Sep');
    });

    test('Week is a rolling 7 days ending on the anchor (not Mon–Sun)', () {
      final p = week();
      expect(p.range(today: today), d(DateTime(2026, 9, 18), today));
      expect(p.priorRange(today: today), d(DateTime(2026, 9, 11), DateTime(2026, 9, 17)));
      final w = p.words(today: today);
      expect(w.value, '18–24 Sep');
      expect(w.spent, 'Spent in the last 7 days');
      expect(w.vs, 'vs prior week');
      // Across a month boundary.
      final older = week(DateTime(2026, 9, 3));
      expect(older.words(today: today).value, '28 Aug – 3 Sep');
      expect(older.words(today: today).spent, 'Spent that week');
    });

    test('Month: the calendar month; prior = the previous month', () {
      final p = AnalyticsPeriod.month(today);
      expect(p.range(today: today), d(DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
      expect(p.priorRange(today: today), d(DateTime(2026, 8, 1), DateTime(2026, 8, 31)));
      expect(p.words(today: today).value, 'Sep 2026');
      expect(p.words(today: today).spent, 'Spent this month');
      expect(p.words(today: today).vs, 'vs last month');
      expect(AnalyticsPeriod.month(DateTime(2026, 3, 9)).words(today: today).spent, 'Spent in March');
      // March's prior is February (28 days), not "the 31 days before".
      expect(
        AnalyticsPeriod.month(DateTime(2026, 3, 9)).priorRange(today: today),
        d(DateTime(2026, 2, 1), DateTime(2026, 2, 28)),
      );
    });

    test('Year: Jan–Dec; prior = the previous year', () {
      final p = AnalyticsPeriod.year(2026, today: today);
      expect(p.range(today: today), d(DateTime(2026, 1, 1), DateTime(2026, 12, 31)));
      expect(p.priorRange(today: today), d(DateTime(2025, 1, 1), DateTime(2025, 12, 31)));
      expect(p.words(today: today).value, '2026');
      expect(p.words(today: today).spent, 'Spent this year');
      expect(p.words(today: today).vs, 'vs last year');
      expect(AnalyticsPeriod.year(2025, today: today).words(today: today).spent, 'Spent in 2025');
    });

    test('All time: from the first transaction to today; no prior', () {
      final p = AnalyticsPeriod.allTime(today);
      expect(p.range(today: today, first: first), d(first, today));
      expect(p.priorRange(today: today, first: first), isNull);
      expect(p.words(today: today, first: first).value, 'since Aug 2026');
      expect(p.words(today: today, first: first).spent, 'Spent since you started');
      // No transactions yet: just today.
      expect(p.range(today: today), d(today, today));
    });

    test('Custom: its days; prior = the N days before; "vs previous N days"', () {
      final p = AnalyticsPeriod.custom(DateTime(2026, 9, 10), DateTime(2026, 9, 24), today: today);
      expect(p.range(today: today), d(DateTime(2026, 9, 10), today));
      expect(p.priorRange(today: today), d(DateTime(2026, 8, 26), DateTime(2026, 9, 9)));
      final w = p.words(today: today);
      expect(w.value, '10–24 Sep');
      expect(w.spent, 'Spent over 15 days');
      expect(w.vs, 'vs previous 15 days');
      expect(p.granularityLabel, 'Custom');
    });

    test('Custom: swapped dates are put in order and To is clamped to today', () {
      final swapped = AnalyticsPeriod.custom(DateTime(2026, 9, 20), DateTime(2026, 9, 5), today: today);
      expect(swapped.range(today: today), d(DateTime(2026, 9, 5), DateTime(2026, 9, 20)));
      final future = AnalyticsPeriod.custom(DateTime(2026, 9, 20), DateTime(2026, 10, 30), today: today);
      expect(future.range(today: today), d(DateTime(2026, 9, 20), today));
    });

    test('bounds run from 00:00:00.000 of the first day to 23:59:59.999 of the last', () {
      final (s, e) = week().range(today: today).bounds;
      expect(DateTime.fromMillisecondsSinceEpoch(s), DateTime(2026, 9, 18));
      expect(DateTime.fromMillisecondsSinceEpoch(e), DateTime(2026, 9, 24, 23, 59, 59, 999));
    });

    test('elapsed days stop at today (avg per day)', () {
      expect(AnalyticsPeriod.month(today).elapsedDays(today: today), 24);
      expect(week().elapsedDays(today: today), 7);
      expect(AnalyticsPeriod.allTime(today).elapsedDays(today: today, first: first), 41);
    });
  });

  group('the pill', () {
    test('the length menu is All time / Year / Month / Week / Day', () {
      expect(analyticsGranularityMenu.map((g) => g.$2), ['All time', 'Year', 'Month', 'Week', 'Day']);
    });

    test('switching the length keeps the end of the current range, clamped to today', () {
      final m = week().withGranularity(AnalyticsGranularity.month, today: today);
      expect(m.granularity, AnalyticsGranularity.month);
      expect(m.range(today: today), d(DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
      // From this month (ends 30 Sep) to Day: today, not 30 Sep.
      expect(m.withGranularity(AnalyticsGranularity.day, today: today).range(today: today), d(today, today));
      // From an older week to Day: that week's last day.
      final day = week(DateTime(2026, 9, 3)).withGranularity(AnalyticsGranularity.day, today: today);
      expect(day.range(today: today), d(DateTime(2026, 9, 3), DateTime(2026, 9, 3)));
    });

    test('Day lists the last 7 days: Today, Yesterday, then "Tue 22 Sep"…', () {
      final o = AnalyticsPeriod.day(today).options(today: today);
      expect(o.map((x) => x.label), [
        'Today',
        'Yesterday',
        'Tue 22 Sep',
        'Mon 21 Sep',
        'Sun 20 Sep',
        'Sat 19 Sep',
        'Fri 18 Sep',
      ]);
      expect(o.first.selected, isTrue);
      expect(o[2].period, AnalyticsPeriod.day(DateTime(2026, 9, 22)));
    });

    test('Week lists the last 6 rolling windows; the first is noted "last 7 days"', () {
      final o = week().options(today: today);
      expect(o, hasLength(6));
      expect(o.first.label, '18 Sep – 24 Sep');
      expect(o.first.note, 'last 7 days');
      expect(o.first.selected, isTrue);
      expect(o[1].label, '11 Sep – 17 Sep');
      expect(o[1].note, '');
      expect(o.last.label, '14 Aug – 20 Aug');
      expect(o[1].period.range(today: today), d(DateTime(2026, 9, 11), DateTime(2026, 9, 17)));
    });

    test('Month lists the last 8 months', () {
      final o = AnalyticsPeriod.month(today).options(today: today);
      expect(o.map((x) => x.label), [
        'September 2026',
        'August 2026',
        'July 2026',
        'June 2026',
        'May 2026',
        'April 2026',
        'March 2026',
        'February 2026',
      ]);
      // Picking an older month moves the chart window so it sits 2 from the right.
      expect(o[5].period.monthWindowEnd, DateTime(2026, 6, 1));
      expect(o[1].period.monthWindowEnd, isNull);
    });

    test("Year lists this year back to the first transaction's year minus 1", () {
      final o = AnalyticsPeriod.year(2026, today: today).options(today: today, first: DateTime(2024, 5, 1));
      expect(o.map((x) => x.label), ['2026', '2025', '2024', '2023']);
      expect(o.first.selected, isTrue);
    });

    test('All time and Custom have no list (they open the Custom sheet)', () {
      expect(AnalyticsPeriod.allTime(today).options(today: today), isEmpty);
      expect(AnalyticsPeriod.custom(DateTime(2026, 9, 1), today, today: today).options(today: today), isEmpty);
    });
  });

  group('stepping and clamping', () {
    test('Day and Week step by 1 and 7 days; Next is disabled at the present', () {
      final day = AnalyticsPeriod.day(today);
      expect(day.canStepForward(today: today), isFalse);
      expect(day.canStepBack(today: today), isTrue);
      final yesterday = day.step(-1, today: today);
      expect(yesterday.range(today: today).start, DateTime(2026, 9, 23));
      expect(yesterday.canStepForward(today: today), isTrue);
      expect(week().step(-1, today: today).range(today: today), d(DateTime(2026, 9, 11), DateTime(2026, 9, 17)));
      expect(week().canStepForward(today: today), isFalse);
    });

    test('stepping forward never passes today', () {
      final w = week(DateTime(2026, 9, 20)).step(1, today: today);
      expect(w.range(today: today).end, today);
      expect(AnalyticsPeriod.day(today).step(1, today: today).range(today: today).start, today);
    });

    test('Year steps a year; back at this year it anchors on today', () {
      final y = AnalyticsPeriod.year(2026, today: today).step(-1, today: today);
      expect(y.range(today: today), d(DateTime(2025, 1, 1), DateTime(2025, 12, 31)));
      expect(y.canStepForward(today: today), isTrue);
      final back = y.step(1, today: today);
      expect(back.anchor, today);
      expect(back.canStepForward(today: today), isFalse);
    });

    test('All time and Custom do not step', () {
      final all = AnalyticsPeriod.allTime(today);
      expect(all.canStepBack(today: today), isFalse);
      expect(all.canStepForward(today: today), isFalse);
      expect(all.step(-1, today: today), all);
      final c = AnalyticsPeriod.custom(DateTime(2026, 9, 1), today, today: today);
      expect(c.canStepBack(today: today), isFalse);
    });
  });

  group('the Month window', () {
    test('Month pages the 6-month window; the chosen month follows its edge', () {
      final m = AnalyticsPeriod.month(today);
      expect(m.canStepForward(today: today), isFalse);
      var p = m.step(-1, today: today);
      expect(p.monthWindowEnd, DateTime(2026, 8, 1));
      // September dropped off the right edge: the chosen month follows (Aug).
      expect(p.range(today: today).start, DateTime(2026, 8, 1));
      expect(p.canStepForward(today: today), isTrue);
      p = AnalyticsPeriod.month(DateTime(2026, 4, 1)).step(-1, today: today);
      // April is still inside Mar..Aug: it stays chosen.
      expect(p.range(today: today).start, DateTime(2026, 4, 1));
      // Forward is clamped to the current month.
      expect(p.step(1, today: today).step(1, today: today).monthWindowEnd, DateTime(2026, 9, 1));
    });

    test('Back stops once the window reaches a year before the first transaction', () {
      var p = AnalyticsPeriod.month(today);
      var steps = 0;
      while (p.canStepBack(today: today, first: first) && steps < 100) {
        p = p.step(-1, today: today);
        steps++;
      }
      // The window's first month may not go below Aug 2025 (first - 12 months).
      expect(addMonths(p.monthWindowEnd!, -5), DateTime(2025, 8, 1));
      expect(steps, 8);
    });
  });

  group('back to now (pull to refresh)', () {
    test('Day → today, Week → last 7 days, Month → this month, Year → this year', () {
      expect(AnalyticsPeriod.day(DateTime(2026, 9, 2)).backToNow(today: today), AnalyticsPeriod.day(today));
      expect(week(DateTime(2026, 8, 30)).backToNow(today: today), week());
      final month = AnalyticsPeriod.month(DateTime(2026, 3, 1)).step(-1, today: today).backToNow(today: today);
      expect(month.range(today: today), d(DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
      expect(month.monthWindowEnd, isNull);
      final year = AnalyticsPeriod.year(2024, today: today).backToNow(today: today);
      expect(year.range(today: today), d(DateTime(2026, 1, 1), DateTime(2026, 12, 31)));
    });

    test('Custom of N days → the last N days ending today', () {
      final c = AnalyticsPeriod.custom(DateTime(2026, 8, 1), DateTime(2026, 8, 10), today: today);
      final back = c.backToNow(today: today);
      expect(back.granularity, AnalyticsGranularity.custom);
      expect(back.range(today: today), d(DateTime(2026, 9, 15), today));
      expect(back.range(today: today).days, 10);
    });

    test('All time stays all time', () {
      final all = AnalyticsPeriod.allTime(today);
      expect(all.backToNow(today: today).range(today: today, first: first), d(first, today));
    });
  });

  group('chart buckets', () {
    List<String> labels(ChartSpec s) => [for (final b in s.buckets) b.label];

    test('Day: 6 four-hour blocks at 0/4/8/12/16/20, labelled 12a…8p; later blocks are future', () {
      final s = AnalyticsPeriod.day(today).chart(now: now);
      expect(labels(s), ['12a', '4a', '8a', '12p', '4p', '8p']);
      expect([for (final b in s.buckets) DateTime.fromMillisecondsSinceEpoch(b.startMs).hour], [0, 4, 8, 12, 16, 20]);
      expect(DateTime.fromMillisecondsSinceEpoch(s.buckets.last.endMs), DateTime(2026, 9, 24, 23, 59, 59, 999));
      // 13:30: the 4p and 8p blocks haven't started.
      expect([for (final b in s.buckets) b.future], [false, false, false, false, true, true]);
      expect(s.buckets.every((b) => b.target == null), isTrue);
      expect(s.title, 'By time of day');
      expect(s.hint, 'Swipe for the day before');
      expect(s.showAverage, isFalse);
      // An earlier day has no future blocks.
      expect(AnalyticsPeriod.day(DateTime(2026, 9, 23)).chart(now: now).buckets.any((b) => b.future), isFalse);
    });

    test('Week: its 7 days (two-letter weekday), each opening that Day; avg line on', () {
      final s = week().chart(now: now);
      expect(labels(s), ['Fr', 'Sa', 'Su', 'Mo', 'Tu', 'We', 'Th']);
      expect(s.buckets.first.target, AnalyticsPeriod.day(DateTime(2026, 9, 18)));
      expect(s.title, 'By day');
      expect(s.hint, 'Tap a day to open it · swipe for other weeks');
      expect(s.showAverage, isTrue);
    });

    test('Month: a 6-month window, newest on the right, the chosen month lit', () {
      final s = AnalyticsPeriod.month(DateTime(2026, 7, 1)).chart(now: now);
      expect(labels(s), ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep']);
      expect([for (final b in s.buckets) b.selected], [false, false, false, true, false, false]);
      expect(s.labelSelected, isTrue);
      expect(s.buckets[4].target!.range(today: today).start, DateTime(2026, 8, 1));
      expect(s.buckets[4].target!.granularity, AnalyticsGranularity.month);
      expect(s.hint, 'Tap a month to pick it · swipe for earlier months');
    });

    test('Year: its 12 months (J F M …), later ones future, each opening that Month', () {
      final s = AnalyticsPeriod.year(2026, today: today).chart(now: now);
      expect(labels(s), ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D']);
      expect(s.buckets.where((b) => b.future).length, 3);
      expect(s.buckets[8].tappable, isTrue);
      expect(s.buckets[9].tappable, isFalse);
      expect(s.buckets[2].target, AnalyticsPeriod.month(DateTime(2026, 3, 1)));
    });

    test('All time: one bar per month since the first transaction, at least 6', () {
      final s = AnalyticsPeriod.allTime(today).chart(now: now, first: first);
      expect(labels(s), ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep']);
      // Months before the first transaction are dimmed and not tappable.
      expect([for (final b in s.buckets) b.tappable], [false, false, false, false, true, true]);
      expect(s.title, 'By month since you started');

      final long = AnalyticsPeriod.allTime(today).chart(now: now, first: DateTime(2025, 1, 10));
      expect(long.buckets, hasLength(21));
      expect(long.buckets.every((b) => b.tappable), isTrue);
    });

    test('All time switches from months to years past 24 months', () {
      final at24 = AnalyticsPeriod.allTime(today).chart(now: now, first: DateTime(2024, 10, 1));
      expect(at24.buckets, hasLength(24));
      expect(at24.title, 'By month since you started');
      final at25 = AnalyticsPeriod.allTime(today).chart(now: now, first: DateTime(2024, 9, 1));
      expect(labels(at25), ["'24", "'25", "'26"]);
      expect(at25.title, 'By year');
      expect(at25.buckets.first.target, AnalyticsPeriod.year(2024, today: today));
    });

    test('Parties (all time): "By month · all time", no tap-through', () {
      final s = week().chart(now: now, first: first, party: true);
      expect(s.title, 'By month · all time');
      expect(s.hint, '');
      expect(s.buckets.every((b) => b.target == null), isTrue);
      expect(s.showAverage, isFalse);
    });

    test('Custom switches from days to weeks past 31 days', () {
      final short = AnalyticsPeriod.custom(DateTime(2026, 9, 18), today, today: today).chart(now: now);
      expect(labels(short), ['Fr', 'Sa', 'Su', 'Mo', 'Tu', 'We', 'Th']);
      expect(short.buckets.first.target, AnalyticsPeriod.day(DateTime(2026, 9, 18)));
      final month = AnalyticsPeriod.custom(DateTime(2026, 8, 25), today, today: today).chart(now: now);
      expect(month.buckets, hasLength(31));
      expect(month.title, 'By day');
      // Over 10 days: only every 5th date is labelled.
      expect(month.buckets.where((b) => b.label.isNotEmpty).map((b) => b.label), ['25', '30', '5', '10', '15', '20']);
      final long = AnalyticsPeriod.custom(DateTime(2026, 8, 24), today, today: today).chart(now: now);
      expect(long.title, 'By week');
      expect(long.buckets, hasLength(5));
      expect(labels(long), ['24', '31', '7', '14', '21']);
      expect(DateTime.fromMillisecondsSinceEpoch(long.buckets.last.endMs), DateTime(2026, 9, 24, 23, 59, 59, 999));
      expect(long.buckets.every((b) => b.target == null), isTrue);
      expect(long.showAverage, isTrue);
    });
  });

  group('chart values', () {
    test('a "nice" axis max: 1, 2, 3, 4, 5, 6, 8, 10 × 10^k', () {
      expect(niceAxisMax(1), 1);
      expect(niceAxisMax(1500), 2000);
      expect(niceAxisMax(2000), 2000);
      expect(niceAxisMax(2350), 3000);
      expect(niceAxisMax(7000), 8000);
      expect(niceAxisMax(850), 1000);
      expect(niceAxisMax(0), 1);
    });

    test('short labels: 1.5k, 2k, 750', () {
      expect(kshShort(1500), '1.5k');
      expect(kshShort(2000), '2k');
      expect(kshShort(750), '750');
      expect(kshShort(0), '0');
      expect(kshShort(0.5), '0.5');
    });
  });

  group('Where it went', () {
    test('merges by name across types, largest first, with counts', () {
      final g = groupSpendByName([
        ('Shopping', 120000), // Paybill
        ('Shopping', 85000), // Buy Goods
        ('Rent', 200000),
        ('Groceries', 50000),
      ]);
      expect(g.map((x) => x.name), ['Shopping', 'Rent', 'Groceries']);
      expect(g.first.cents, 205000);
      expect(g.first.count, 2);
    });
  });
}
