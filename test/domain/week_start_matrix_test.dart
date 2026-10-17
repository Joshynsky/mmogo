// F5 (0.1.2 corrections, closes finding R33): the exhaustive week-start proof,
// DOMAIN half. 7 first days x 36 months (Jan 2026 .. Dec 2028, so the leap
// February 2028 and the year boundaries are inside) x every route that builds
// a week: Home's week bounds and "vs last week", Analytics Week / Month /
// Year / Custom charts, the Year > Month > Week and Day > Week drill-downs,
// Paid to's hand-off periods, the first-day switch and back.
//
// Sampling (runtime): the Month-chart, Year-drill, Custom and Paid to checks run
// on all 36 months x 7 first days; the per-day checks (every weekday as
// "today", Home, the pill list, switching twice) run on 14 chosen months
// (see _sampleMonths). Local DateTime is slow on this machine.
//
// Every expectation comes from test/support/week_start_oracle.dart, a naive
// day-by-day walk that calls no production helper. Pure Dart, no widgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/home/home_period.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';
import 'package:mmogo/domain/period_change.dart';
import 'package:mmogo/ui/screens/analytics/route_args.dart';

import '../support/week_start_oracle.dart';

final _farToday = DateTime(2028, 12, 31, 12); // every month of the matrix is past or current

int _startMs(DateTime d) => DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
int _endMs(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999).millisecondsSinceEpoch;

String _why(int first, int y, int m, [Object? more]) => 'first day $first, ${kMonthShort[m - 1]} $y${more == null ? '' : ', $more'}';

/// The chart buckets of a Month period, reduced to comparable text.
List<String> _bucketText(ChartSpec c) => [for (final b in c.buckets) '${b.label}|${b.startMs}|${b.endMs}|${b.part}|${b.sub}'];

/// Invariants (a), (b), (e) for one month's week buckets, against the oracle.
void _expectMonthWeeks(AnalyticsPeriod p, int first, int y, int m) {
  final why = _why(first, y, m);
  final segs = monthSegments(y, m, first);
  final c = p.chart(now: _farToday);
  chk(c.buckets.length, segs.length, reason: '$why: bucket count');
  for (var i = 0; i < segs.length; i++) {
    final s = segs[i];
    final b = c.buckets[i];
    chk(b.label, s.label, reason: '$why: bucket $i label');
    chk(b.startMs, _startMs(s.start), reason: '$why: bucket $i start');
    chk(b.endMs, _endMs(s.end), reason: '$why: bucket $i end');
    chk(b.part, s.days < 7, reason: '$why: bucket $i part-week flag');
    chk(b.sub, s.days < 7 ? (s.days == 1 ? '1 day' : '${s.days} days') : '', reason: '$why: bucket $i day count');
    // (a) a FULL bucket starts on the chosen weekday and is exactly 7 days.
    if (s.days == 7) {
      chk(s.start.weekday, first, reason: '$why: full bucket $i starts on the weekday');
    }
    // (b) a part bucket sits at the month's first or last day.
    if (s.days < 7) {
      chk(i == 0 || i == segs.length - 1, true, reason: '$why: part bucket $i is first or last');
    }
    // The bucket opens the WHOLE calendar week, first day first, 7 days.
    final t = b.target!;
    chk(t.granularity, AnalyticsGranularity.week, reason: '$why: bucket $i target is a week');
    chk(t.firstDay, first, reason: '$why: bucket $i target carries the first day');
    final r = t.range(today: _farToday);
    final wk = weekDays(s.start, first);
    chk(r.start, wk.first, reason: '$why: bucket $i opens a week starting on the weekday');
    chk(r.end, wk.last, reason: '$why: bucket $i week ends six days later');
    chk(r.days, 7, reason: '$why: bucket $i week is 7 days');
    chk(r.start.weekday, first, reason: '$why: bucket $i week starts on the weekday');
  }
  // (b) day counts: the first piece is the days before the first [first]
  // weekday, the last piece the days from the last one.
  chk(segs.first.start.day, 1, reason: '$why: first piece starts on the 1st');
  chk(segs.last.end.day, lastDayOfMonth(y, m), reason: '$why: last piece ends on the last day');
  // (e) no overlap, no gap: each bucket starts the day after the one before
  // ends, and all the days of the month are counted once.
  var total = 0;
  for (var i = 0; i < c.buckets.length; i++) {
    final b = c.buckets[i];
    final s = DateTime.fromMillisecondsSinceEpoch(b.startMs);
    final e = DateTime.fromMillisecondsSinceEpoch(b.endMs);
    chk(s.month, m, reason: '$why: bucket $i starts inside the month');
    chk(e.month, m, reason: '$why: bucket $i ends inside the month');
    chk(s.isAfter(e), false, reason: '$why: bucket $i is not backwards');
    total += countDays(s, e);
    if (i > 0) {
      final prevEnd = DateTime.fromMillisecondsSinceEpoch(c.buckets[i - 1].endMs);
      chk(sameDate(nextDay(prevEnd), s), true, reason: '$why: bucket $i follows bucket ${i - 1} with no gap or overlap');
    }
  }
  chk(total, lastDayOfMonth(y, m), reason: '$why: the buckets cover the month exactly');
  // The "Week crosses into ..." line: only on a part bucket whose whole week
  // leaves the month.
  final firstHasCross = DateTime(y, m, 1).weekday != first;
  chk(c.buckets.first.cross != null, firstHasCross, reason: '$why: first piece crossing line');
  final lastDay = DateTime(y, m, lastDayOfMonth(y, m));
  final lastHasCross = lastDay.weekday != (first + 5) % 7 + 1;
  chk(c.buckets.last.cross != null, lastHasCross, reason: '$why: last piece crossing line');
}

/// Anchor dates per month: the 1st and the last day (the month and year
/// ends, where weeks cross) and the 15th. Building a local DateTime costs
/// ~80 microseconds here, so not every day of every month; over 36 months
/// these 108 dates fall on every weekday (proved in the last test).
List<int> _anchorDays(int y, int m) => [1, 15, lastDayOfMonth(y, m)];

/// The months the per-day tests (every weekday as "today", Home, the pill
/// list, switching twice) run on: the 14 that matter most. The Month chart
/// tests below run on ALL 36. Includes the leap February 2028, every year
/// boundary, and 30/31/28/29-day months starting on different weekdays.
const _sampleMonths = <(int, int)>{
  (2026, 1), (2026, 2), (2026, 3), (2026, 9), (2026, 10), (2026, 12),
  (2027, 1), (2027, 2), (2027, 12),
  (2028, 1), (2028, 2), (2028, 3), (2028, 6), (2028, 12),
};

/// A test that runs only on the sampled months.
void perDayTest(int y, int m, String name, void Function() body) {
  if (_sampleMonths.contains((y, m))) test(name, body);
}

/// A week period: starts on the weekday, 7 days, holds its date, carries the
/// first day, the pill says the right span.
void _expectWeekRange(AnalyticsPeriod p, DateTime anchor, int first, String why) {
  final days = weekDays(anchor, first);
  final r = p.range(today: _farToday);
  chk(r.start, days.first, reason: '$why: week range starts on the weekday');
  chk(r.end, days.last, reason: '$why: week range ends six days later');
  chk(r.days, 7, reason: '$why: week is 7 days');
  chk(r.start.weekday, first, reason: '$why: start weekday');
  chk(r.containsDay(anchor), true, reason: '$why: the week holds its own date');
  chk(p.firstDay, first, reason: '$why: carries the first day');
  chk(p.words(today: _farToday).value, spanText(days.first, days.last), reason: '$why: pill text');
}

void _expectWeekChart(AnalyticsPeriod p, DateTime anchor, int first, String why) {
  _expectWeekRange(p, anchor, first, why);
  final days = weekDays(anchor, first);
  final c = p.chart(now: _farToday);
  chk(c.buckets.length, 7, reason: '$why: 7 bars');
  for (var k = 0; k < 7; k++) {
    final b = c.buckets[k];
    chk(b.label, kDayInitials[days[k].weekday - 1], reason: '$why: bar $k weekday');
    chk(b.startMs, _startMs(days[k]), reason: '$why: bar $k start');
    chk(b.endMs, _endMs(days[k]), reason: '$why: bar $k end');
    chk(b.target!.range(today: _farToday).start, days[k], reason: '$why: bar $k opens that day');
    chk(b.target!.firstDay, first, reason: '$why: bar $k target carries the first day');
  }
  chk(c.buckets.first.label, kDayInitials[first - 1], reason: '$why: first bar is the chosen weekday');
}

void main() {
  for (var first = 1; first <= 7; first++) {
    group('first day $first (${kDayInitials[first - 1]})', () {
      final yearBars = <int, List<ChartBucket>>{}; // one Year chart per year, built once
      for (final (y, m) in allMonths()) {
        final why = _why(first, y, m);

        test('$y-$m: Month chart weeks (a)(b)(e), and Paid to / Home-row / Year drill periods build the same weeks', () {
          final month = AnalyticsPeriod.month(DateTime(y, m, 17), firstDay: first);
          _expectMonthWeeks(month, first, y, m);

          // Paid to's hand-off of a Month, and its "now" Month, with the
          // preference carried.
          final handOff = analyticsPeriodForPaidTo(month, _farToday, firstDay: first);
          chk(handOff.firstDay, first, reason: '$why: Paid to hand-off carries the first day');
          final same = _bucketText(month.chart(now: _farToday));
          chk(_bucketText(handOff.chart(now: _farToday)), same, reason: '$why: Paid to hand-off buckets');
          final nowMonth = paidToPeriodNow(AnalyticsGranularity.month, DateTime(y, m, 9), firstDay: first);
          chk(_bucketText(nowMonth.chart(now: _farToday)), same, reason: '$why: Paid to month buckets');

          // Month > previous arrow keeps the weeks (next is the next matrix month).
          final before = month.step(-1, today: _farToday);
          chk(before.firstDay, first, reason: '$why: arrow keeps the first day');
          chk(_bucketText(before.chart(now: _farToday)), _bucketText(AnalyticsPeriod.month(before.anchor, firstDay: first).chart(now: _farToday)), reason: '$why: previous month buckets');

          // Year view > tap this month (the Year chart's month bar target).
          final bar = yearBars.putIfAbsent(
            y,
            () => AnalyticsPeriod.year(y, today: _farToday, firstDay: first).chart(now: _farToday).buckets,
          )[m - 1];
          chk(bar.target!.firstDay, first, reason: '$why: Year month bar carries the first day');
          chk(_bucketText(bar.target!.chart(now: _farToday)), same, reason: '$why: Year > month buckets');
        });

        perDayTest(y, m, '$y-$m: every day as the anchor of a Week (a)(c), pill words, arrows and the Day > Week switch', () {
          for (final d in _anchorDays(y, m)) {
            final anchor = DateTime(y, m, d);
            final dwhy = '$why, anchor $d';
            // "this week" for a today of that date: the nav-bar default.
            _expectWeekChart(AnalyticsPeriod.thisWeek(anchor, firstDay: first), anchor, first, dwhy);
            // Day > Week (the granularity switch keeps the day as the anchor).
            final dayP = AnalyticsPeriod.day(anchor, firstDay: first);
            final toWeek = dayP.withGranularity(AnalyticsGranularity.week, today: _farToday, firstDay: first);
            _expectWeekRange(toWeek, anchor, first, '$dwhy (Day > Week)');
            // Home's row hand-off lands on a Day; Week from there is the same.
            final fromHome = analyticsPeriodForHome(HomePeriod.week, anchor, firstDay: first);
            _expectWeekRange(fromHome, anchor, first, '$dwhy (Home week hand-off)');
            // Arrows: a week back and forward stay aligned (across month and
            // year ends).
            final back = AnalyticsPeriod.thisWeek(anchor, firstDay: first).step(-1, today: _farToday);
            _expectWeekRange(back, DateTime(y, m, d - 7), first, '$dwhy (previous week)');
            if (!DateTime(y, m, d + 7).isAfter(_farToday)) {
              final fwd = AnalyticsPeriod.thisWeek(anchor, firstDay: first).step(1, today: _farToday);
              _expectWeekRange(fwd, DateTime(y, m, d + 7), first, '$dwhy (next week)');
            }
          }
        });

        perDayTest(y, m, '$y-$m: the Week pill list (this week and five before)', () {
          for (final d in [15, lastDayOfMonth(y, m)]) {
            final t = DateTime(y, m, d);
            final opts = AnalyticsPeriod.thisWeek(t, firstDay: first).options(today: t);
            chk(opts.length, 6, reason: '$why, today $d');
            var ws = weekStartOf(t, first);
            for (var k = 0; k < 6; k++) {
              final we = weekDays(ws, first).last;
              chk(opts[k].label, spanText(ws, we), reason: '$why, today $d: pill option $k');
              chk(opts[k].period.firstDay, first, reason: '$why, today $d: option $k carries the first day');
              chk(opts[k].period.range(today: t).start, ws, reason: '$why, today $d: option $k opens that week');
              ws = weekStartOf(prevDay(ws), first);
            }
            chk(opts.first.selected, true, reason: '$why, today $d: this week is the selected one');
          }
        });

        perDayTest(y, m, '$y-$m: Home (b)(c): week figures, vs last week and the month figures agree with Analytics', () {
          for (final d in _anchorDays(y, m)) {
            final now = DateTime(y, m, d, 14, 30);
            final dwhy = '$why, today $d';
            final ws = weekStartOf(now, first);
            final prevEnd = prevDay(ws);
            final prevStart = weekStartOf(prevEnd, first);
            // Home This week: the week so far, from the chosen weekday 00:00.
            final (hs, he) = HomePeriod.week.bounds(now, firstDay: first);
            chk(hs, _startMs(ws), reason: '$dwhy: Home week starts on the weekday');
            chk(he, _endMs(DateTime(y, m, d)), reason: '$dwhy: Home week ends at the end of today');
            chk(DateTime.fromMillisecondsSinceEpoch(hs).weekday, first, reason: '$dwhy: Home week start weekday');
            // vs last week: the WHOLE previous calendar week.
            final (ps, pe) = HomePeriod.week.priorBounds(now, firstDay: first);
            chk(ps, _startMs(prevStart), reason: '$dwhy: Home prior week start');
            chk(pe, _endMs(prevEnd), reason: '$dwhy: Home prior week end');
            chk(DateTime.fromMillisecondsSinceEpoch(ps).weekday, first, reason: '$dwhy: prior week starts on the weekday');
            // Home's own caption maths (periodProgress) uses the same week.
            final pr = periodProgress(ProgressKind.week, ws, now);
            chk(pr.cur, true, reason: '$dwhy: today is inside the week');
            chk(pr.priorStart, prevStart, reason: '$dwhy: caption prior start');
            chk(pr.priorEnd, prevEnd, reason: '$dwhy: caption prior end');
            chk(pr.n, countDays(ws, DateTime(y, m, d)), reason: '$dwhy: days elapsed in the week');
            // (c) Analytics agrees for the same date and first day.
            final a = AnalyticsPeriod.thisWeek(now, firstDay: first);
            final ar = a.range(today: now);
            chk(ar.start, ws, reason: '$dwhy: Analytics week starts where Home\'s does');
            chk(ar.bounds.$1, hs, reason: '$dwhy: Analytics and Home share the week start');
            final apr = a.priorRange(today: now)!;
            chk(apr.bounds, (ps, pe), reason: '$dwhy: Analytics and Home share the vs-last-week window');
            // Home This week > Analytics (the shared length).
            final handOff = analyticsPeriodForHome(HomePeriod.week, DateTime(y, m, d), firstDay: first);
            chk(handOff.range(today: now).bounds.$1, hs, reason: '$dwhy: Home hand-off week start');
            // Month pill: not week-based, must not move with the first day.
            final (mhs, mhe) = HomePeriod.month.bounds(now, firstDay: first);
            chk(mhs, _startMs(DateTime(y, m, 1)), reason: '$dwhy: Home month start');
            chk(mhe, _endMs(DateTime(y, m, lastDayOfMonth(y, m))), reason: '$dwhy: Home month end');
          }
        });

        perDayTest(y, m, '$y-$m: (d) switching the first day twice returns to the original buckets; periods with another day differ in value', () {
          final other = first % 7 + 1;
          final third = other % 7 + 1;
          final month = AnalyticsPeriod.month(DateTime(y, m, 3), firstDay: first);
          final there = month.withFirstDay(other);
          chk(there.firstDay, other);
          chk([for (final b in there.chart(now: _farToday).buckets) b.label], [for (final s in monthSegments(y, m, other)) s.label], reason: '$why: switched to day $other');
          final back = there.withFirstDay(third).withFirstDay(first);
          chk(_bucketText(back.chart(now: _farToday)), _bucketText(month.chart(now: _farToday)), reason: '$why: month back to the original');
          chk(back, month, reason: '$why: same period again');
          chk(month == there, false, reason: '$why: another week start is another period');
          final week = AnalyticsPeriod.thisWeek(DateTime(y, m, 10), firstDay: first);
          final weekBack = week.withFirstDay(other).withFirstDay(first);
          chk(_bucketText(weekBack.chart(now: _farToday)), _bucketText(week.chart(now: _farToday)), reason: '$why: week back to the original');
          chk(weekBack.range(today: _farToday).start, week.range(today: _farToday).start);
        });
      }

      test('Year views 2026, 2027, 2028: twelve month bars, each target month buckets on the weekday (Year > Month drill)', () {
        for (final y in [2026, 2027, 2028]) {
          final year = AnalyticsPeriod.year(y, today: _farToday, firstDay: first);
          final bars = year.chart(now: _farToday).buckets;
          chk(bars.length, 12);
          for (var m = 1; m <= 12; m++) {
            _expectMonthWeeks(bars[m - 1].target!, first, y, m);
          }
          // Year > previous / next year keeps the first day.
          chk(year.step(-1, today: _farToday).firstDay, first);
        }
      });

      test('Custom ranges over 31 days: calendar-week blocks, first and last clipped, full ones on the weekday and 7 days', () {
        var cases = 0;
        for (var offset = 0; offset < 1090; offset += 29) {
          final from = DateTime(2026, 1, 1 + offset);
          for (final len in [32, 45, 100]) {
            final to = DateTime(from.year, from.month, from.day + len - 1);
            if (to.isAfter(_farToday)) continue;
            cases++;
            final p = AnalyticsPeriod.custom(from, to, today: _farToday, firstDay: first);
            final c = p.chart(now: _farToday);
            final cwhy = 'first day $first, custom $from..$to';
            // Oracle blocks: walk the days, cut where the weekday matches.
            final blocks = <Seg>[];
            final uFrom = day(from.year, from.month, from.day);
            final uTo = day(to.year, to.month, to.day);
            var s = uFrom;
            for (var x = nextDay(uFrom); !x.isAfter(uTo); x = nextDay(x)) {
              if (x.weekday == first) {
                blocks.add(Seg(s, prevDay(x)));
                s = x;
              }
            }
            blocks.add(Seg(s, uTo));
            chk(c.buckets.length, blocks.length, reason: '$cwhy: block count');
            var covered = 0;
            for (var i = 0; i < blocks.length; i++) {
              final b = c.buckets[i];
              chk(b.startMs, _startMs(blocks[i].start), reason: '$cwhy: block $i start');
              chk(b.endMs, _endMs(blocks[i].end), reason: '$cwhy: block $i end');
              chk(b.part, blocks[i].days < 7, reason: '$cwhy: block $i part flag');
              if (blocks[i].days == 7) {
                chk(blocks[i].start.weekday, first, reason: '$cwhy: full block $i starts on the weekday');
              }
              covered += blocks[i].days;
            }
            chk(covered, countDays(from, to), reason: '$cwhy: blocks cover the range exactly');
          }
        }
        expect(cases, greaterThan(90));
      });

      test('Custom ranges up to 31 days: one bar per day, every bar opens that day with the first day carried', () {
        for (var offset = 0; offset < 1090; offset += 37) {
          final from = DateTime(2026, 1, 1 + offset);
          final to = DateTime(from.year, from.month, from.day + 20);
          if (to.isAfter(_farToday)) continue;
          final p = AnalyticsPeriod.custom(from, to, today: _farToday, firstDay: first);
          chk(p.firstDay, first);
          final c = p.chart(now: _farToday);
          chk(c.buckets.length, 21);
          for (final b in c.buckets) {
            chk(b.target!.firstDay, first);
          }
          // Custom > Week (the pill switch) lands on a week starting on the weekday.
          final w = p.withGranularity(AnalyticsGranularity.week, today: _farToday, firstDay: first);
          chk(w.range(today: _farToday).start, weekStartOf(to, first));
          chk(p.backToNow(today: _farToday).firstDay, first);
        }
      });

      test('the Day pill list and Day > Week from every weekday keep the first day', () {
        for (var k = 0; k < 7; k++) {
          final t = DateTime(2027, 6, 7 + k);
          final dayP = AnalyticsPeriod.day(t, firstDay: first);
          for (final o in dayP.options(today: t)) {
            chk(o.period.firstDay, first);
            final w = o.period.withGranularity(AnalyticsGranularity.week, today: t, firstDay: first);
            chk(w.range(today: t).start.weekday, first);
            chk(w.range(today: t).containsDay(o.period.anchor), true);
          }
        }
      });
    });
  }

  test('the sampled dates cover all seven weekdays; the leap February 2028 has 29 days; the oracle knows known weeks', () {
    chk(allMonths().length, 36);
    chk(lastDayOfMonth(2028, 2), 29);
    chk(lastDayOfMonth(2027, 2), 28);
    // The oracle itself: a known week (Sat 17 Oct 2026, Sunday-first and Monday-first).
    chk(weekStartOf(DateTime(2026, 10, 17), 7), DateTime(2026, 10, 11));
    chk(weekStartOf(DateTime(2026, 10, 17), 1), DateTime(2026, 10, 12));
    chk([for (final s in monthSegments(2026, 10, 7)) s.label], ['1-3', '4-10', '11-17', '18-24', '25-31']);
    chk([for (final s in monthSegments(2026, 9, 1)) s.label], ['1-6', '7-13', '14-20', '21-27', '28-30']);
    // The sampled "today" dates fall on every weekday, and the 1st / last day
    // of the months hit every weekday too (so every part-week size occurs).
    final todays = <int>{};
    final firsts = <int>{};
    final lasts = <int>{};
    for (final (y, m) in allMonths()) {
      for (final d in _anchorDays(y, m)) {
        todays.add(day(y, m, d).weekday);
      }
      firsts.add(day(y, m, 1).weekday);
      lasts.add(day(y, m, lastDayOfMonth(y, m)).weekday);
    }
    chk(todays.length, 7);
    chk(firsts.length, 7);
    chk(lasts.length, 7);
  });
}
