// F5 (0.1.2 corrections, closes finding R33): the week-start proof for the
// ANALYTICS page's own views. The real AnalyticsScreen on a fake clock, with
// every first day of the week (7): the Week view and its arrows, Day > Week,
// Week > Month and the Month arrows across the leap February 2028 and the
// year end Dec 2027 > Jan 2028, Year > Month taps, Year arrows, and the
// Custom range (All time > Custom dates > Show) chart by calendar week.
// Every expectation comes from test/support/week_start_oracle.dart.
//
// Sampling note: the UI walks a fixed route of 8 months per first day (all 36
// months x 7 first days are proved in test/domain/week_start_matrix_test.dart,
// which builds the same periods without the widget cost).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_analytics_db.dart';
import '../../support/week_start_oracle.dart';
import '../../support/week_start_probe.dart';

/// Fri 3 Mar 2028: its week crosses the leap February for most first days.
final _now = DateTime(2028, 3, 3, 12);

List<Map<String, Object?>> _rows() => [
  fakeTx(id: 1, at: DateTime(2026, 12, 20, 9), amountCents: 10000),
  fakeTx(id: 2, at: DateTime(2027, 1, 5, 9), amountCents: 20000),
  fakeTx(id: 3, at: DateTime(2027, 12, 20, 9), amountCents: 30000),
  fakeTx(id: 4, at: DateTime(2028, 1, 3, 9), amountCents: 40000),
  fakeTx(id: 5, at: DateTime(2028, 2, 29, 9), amountCents: 50000),
  fakeTx(id: 6, at: DateTime(2028, 3, 1, 9), amountCents: 60000),
];

(int, int) _prevMonth(int y, int m) => m == 1 ? (y - 1, 12) : (y, m - 1);

void main() {
  late SemanticsHandle semantics;
  setUp(() => semantics = TestWidgetsFlutterBinding.ensureInitialized().ensureSemantics());
  tearDown(() => semantics.dispose());

  for (var first = 1; first <= 7; first++) {
    testWidgets('first day $first: Week, arrows, Day > Week, Week > Month, Month arrows, Year > Month, Year arrows', (t) async {
      setFirstDay(first);
      final why = 'first day $first';
      await pumpAnalytics(t, FakeAnalyticsDb(_rows()), _now);

      // The nav-bar default: this week.
      final today = day(2028, 3, 3);
      expectWeekShown(t, today, first, '$why: this week');

      // Week arrow back (across the leap day for most first days).
      await tapKey(t, 'analyticsPrev');
      final lastWeek = day(2028, 2, 25);
      expectWeekShown(t, lastWeek, first, '$why: previous week');
      await tapKey(t, 'analyticsPrev');
      expectWeekShown(t, day(2028, 2, 18), first, '$why: two weeks back');
      await tapKey(t, 'analyticsNext');
      expectWeekShown(t, lastWeek, first, '$why: forward again');

      // Week > tap a day bar > Day > Week again: the week of that day.
      final days = weekDays(lastWeek, first);
      await tapKey(t, 'analyticsBar-2');
      chk(find.byKey(const Key('analyticsPeriodValue')).evaluate().length, 1, reason: '$why: a Day is shown');
      await pickGranularity(t, 'Week');
      expectWeekShown(t, days[2], first, '$why: Day > Week');

      // Week > Month: the month of the week's last day (today at most).
      final weekEnd = days.last;
      final endsAfterToday = weekEnd.isAfter(day(2028, 3, 3));
      final shown = endsAfterToday ? today : weekEnd;
      var (y, m) = (shown.year, shown.month);
      await pickGranularity(t, 'Month');
      expectMonthShown(t, y, m, first, '$why: Week > Month');

      // Month arrows back three times (leap February 2028, Jan 2028, Dec 2027 for a March start).
      for (var i = 0; i < 3; i++) {
        (y, m) = _prevMonth(y, m);
        await tapKey(t, 'analyticsPrev');
        expectMonthShown(t, y, m, first, '$why: month arrow back $i');
      }
      // And forward over the year end: Dec 2027 > Jan 2028.
      if (y == 2027 && m == 12) {
        await tapKey(t, 'analyticsNext');
        expectMonthShown(t, 2028, 1, first, '$why: Dec 2027 > Jan 2028 arrow');
        await tapKey(t, 'analyticsPrev');
        expectMonthShown(t, 2027, 12, first, '$why: and back');
      }

      // Year > tap a month bar (a Month with weeks), then Year arrows.
      await pickGranularity(t, 'Year');
      chk(periodValue(t), '2027', reason: '$why: Year 2027');
      await tapKey(t, 'analyticsBar-0');
      expectMonthShown(t, 2027, 1, first, '$why: Year > January 2027');
      await pickGranularity(t, 'Year');
      await tapKey(t, 'analyticsBar-11');
      expectMonthShown(t, 2027, 12, first, '$why: Year > December 2027');
      await pickGranularity(t, 'Year');
      await tapKey(t, 'analyticsPrev');
      chk(periodValue(t), '2026', reason: '$why: Year arrow back');
      await tapKey(t, 'analyticsBar-11');
      expectMonthShown(t, 2026, 12, first, '$why: Year 2026 > December 2026');
      await tapKey(t, 'analyticsNext');
      expectMonthShown(t, 2027, 1, first, '$why: Dec 2026 > Jan 2027 arrow');
    });
  }

  for (var first = 1; first <= 7; first++) {
    testWidgets('first day $first: Custom range from All time (Custom dates > Show) buckets by calendar week', (t) async {
      setFirstDay(first);
      final why = 'first day $first';
      final now = DateTime(2026, 10, 17, 12); // Saturday
      final rows = [
        fakeTx(id: 1, at: DateTime(2026, 8, 20, 9), amountCents: 10000),
        fakeTx(id: 2, at: DateTime(2026, 10, 16, 9), amountCents: 20000),
      ];
      await pumpAnalytics(t, FakeAnalyticsDb(rows), now);
      await pickGranularity(t, 'All time');
      await tapKey(t, 'analyticsPeriodValue'); // All time opens Custom dates
      await tapKey(t, 'analyticsCustomShow'); // from the first transaction to today
      // 20 Aug .. 17 Oct 2026 = 59 days: calendar-week blocks, ends clipped.
      final from = day(2026, 8, 20);
      final to = day(2026, 10, 17);
      final blocks = <Seg>[];
      var s = from;
      for (var x = nextDay(from); !x.isAfter(to); x = nextDay(x)) {
        if (x.weekday == first) {
          blocks.add(Seg(s, prevDay(x)));
          s = x;
        }
      }
      blocks.add(Seg(s, to));
      String name(Seg b) => '${b.start.day} ${kMonthShort[b.start.month - 1]} to ${b.end.day} ${kMonthShort[b.end.month - 1]}';
      chk(barNames(t).map((l) => l.split(':').first).toList(), [for (final b in blocks) name(b)], reason: '$why: Custom week blocks');
      for (final b in blocks.skip(1).take(blocks.length - 2)) {
        chk(b.start.weekday, first, reason: '$why: inner block starts on the weekday');
        chk(b.days, 7, reason: '$why: inner block is 7 days');
      }
      // Custom > Week: the week holding the end of the range.
      await pickGranularity(t, 'Week');
      expectWeekShown(t, to, first, '$why: Custom > Week');
    });
  }
}
