// CW1 (domain): the calendar week is the only week model. Pure tests over
// invented dates; 2026-10-14 is a Wednesday (Monday 12 Oct to Sunday 18 Oct).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/home/home_period.dart';
import 'package:mmogo/domain/period_math.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);
int ms(DateTime x) => x.millisecondsSinceEpoch;

void main() {
  final wed = d(2026, 10, 14);

  group('week boundaries', () {
    test('Monday first: a Wednesday belongs to Mon 12 - Sun 18 Oct', () {
      expect(calendarWeekStart(wed), d(2026, 10, 12));
      expect(calendarWeekEnd(wed), d(2026, 10, 18));
    });

    test('Sunday first: the same Wednesday belongs to Sun 11 - Sat 17 Oct', () {
      expect(calendarWeekStart(wed, firstDay: 7), d(2026, 10, 11));
      expect(calendarWeekEnd(wed, firstDay: 7), d(2026, 10, 17));
    });

    test('Sunday night to Monday: 23:59 Sunday is the old week, 00:00 Monday the new one', () {
      expect(calendarWeekStart(DateTime(2026, 10, 18, 23, 59)), d(2026, 10, 12));
      expect(calendarWeekStart(DateTime(2026, 10, 19, 0, 0)), d(2026, 10, 19));
      // With Sunday first, Sunday itself opens a week.
      expect(calendarWeekStart(d(2026, 10, 18), firstDay: 7), d(2026, 10, 18));
      expect(calendarWeekStart(d(2026, 10, 17), firstDay: 7), d(2026, 10, 11));
    });

    test('a week can cross a month end and a year end', () {
      expect(calendarWeekStart(d(2026, 11, 1)), d(2026, 10, 26)); // Sunday 1 Nov
      expect(calendarWeekEnd(d(2026, 10, 28)), d(2026, 11, 1));
      expect(calendarWeekStart(d(2027, 1, 1)), d(2026, 12, 28)); // Friday 1 Jan
      expect(calendarWeekEnd(d(2026, 12, 29)), d(2027, 1, 3));
    });

    test('every first day 1..7 gives a start that is that weekday, at most 6 days back', () {
      for (var first = 1; first <= 7; first++) {
        for (var k = 0; k < 14; k++) {
          final day = d(2026, 10, 5 + k);
          final s = calendarWeekStart(day, firstDay: first);
          expect(s.weekday, first, reason: 'first=$first day=$day');
          final back = day.difference(s).inDays;
          expect(back, inInclusiveRange(0, 6));
        }
      }
    });

    test('weekBounds is the week so far; previousWeekBounds the whole earlier week', () {
      final (s, e) = weekBounds(DateTime(2026, 10, 14, 15, 30));
      expect(s, ms(DateTime(2026, 10, 12)));
      expect(e, ms(DateTime(2026, 10, 14, 23, 59, 59, 999)));
      final (ps, pe) = previousWeekBounds(DateTime(2026, 10, 14, 15, 30));
      expect(ps, ms(DateTime(2026, 10, 5)));
      expect(pe, ms(DateTime(2026, 10, 11, 23, 59, 59, 999)));
    });
  });

  group('Home', () {
    test('This week on a Wednesday is Monday to Wednesday; prior is the whole last week', () {
      final now = DateTime(2026, 10, 14, 9);
      expect(HomePeriod.week.bounds(now), (ms(d(2026, 10, 12)), ms(DateTime(2026, 10, 14, 23, 59, 59, 999))));
      expect(HomePeriod.week.priorBounds(now), (ms(d(2026, 10, 5)), ms(DateTime(2026, 10, 11, 23, 59, 59, 999))));
    });

    test('Sunday first moves both windows', () {
      final now = DateTime(2026, 10, 14, 9);
      expect(HomePeriod.week.bounds(now, firstDay: 7).$1, ms(d(2026, 10, 11)));
      expect(HomePeriod.week.priorBounds(now, firstDay: 7), (ms(d(2026, 10, 4)), ms(DateTime(2026, 10, 10, 23, 59, 59, 999))));
    });

    test('on the first day of the week the week so far is just that day', () {
      final monday = DateTime(2026, 10, 12, 8);
      expect(HomePeriod.week.bounds(monday), (ms(d(2026, 10, 12)), ms(DateTime(2026, 10, 12, 23, 59, 59, 999))));
    });

    test('the caption is "vs last week"; today and month keep theirs', () {
      expect(HomePeriod.week.priorSuffix, 'vs last week');
      expect(HomePeriod.today.priorSuffix, 'vs yesterday');
      expect(HomePeriod.month.priorSuffix, 'vs last month');
      expect(HomePeriod.week.label, 'This week');
    });
  });

  group('Analytics week', () {
    test('a Wednesday shows all seven days with the label of the WHOLE week', () {
      final p = AnalyticsPeriod.thisWeek(wed, firstDay: 1);
      final r = p.range(today: wed);
      expect(r.start, d(2026, 10, 12));
      expect(r.end, d(2026, 10, 18));
      expect(r.days, 7);
      final w = p.words(today: wed);
      expect(w.value, '12–18 Oct');
      expect(w.spent, 'Spent this week');
      expect(w.vs, 'vs last week');
      final chart = p.chart(now: DateTime(2026, 10, 14, 10));
      expect(chart.buckets.map((b) => b.label), ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']);
      expect(chart.buckets.map((b) => b.future), [false, false, false, true, true, true, true]);
      expect(chart.buckets.first.startMs, ms(d(2026, 10, 12)));
      expect(chart.buckets.last.endMs, ms(DateTime(2026, 10, 18, 23, 59, 59, 999)));
    });

    test('first day Sunday: the same Wednesday shows Su..Sa, 11-17 Oct', () {
      final p = AnalyticsPeriod.thisWeek(wed, firstDay: 7);
      expect(p.words(today: wed).value, '11–17 Oct');
      final chart = p.chart(now: DateTime(2026, 10, 14, 10));
      expect(chart.buckets.map((b) => b.label), ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']);
      expect(chart.buckets.map((b) => b.future), [false, false, false, false, true, true, true]);
    });

    test('the comparison is the whole previous calendar week', () {
      final p = AnalyticsPeriod.thisWeek(wed, firstDay: 1);
      final prior = p.priorRange(today: wed)!;
      expect(prior.start, d(2026, 10, 5));
      expect(prior.end, d(2026, 10, 11));
      expect(AnalyticsPeriod.thisWeek(wed, firstDay: 7).priorRange(today: wed)!.start, d(2026, 10, 4));
    });

    test('an earlier week reads "Spent that week" and the label is its whole week', () {
      final back = AnalyticsPeriod.thisWeek(wed, firstDay: 1).step(-1, today: wed);
      final w = back.words(today: wed);
      expect(w.value, '5–11 Oct');
      expect(w.spent, 'Spent that week');
      expect(w.vs, 'vs last week');
    });

    test('stepping: back is allowed, forward is off on the current week and returns from the past', () {
      final now = AnalyticsPeriod.thisWeek(wed, firstDay: 1);
      expect(now.canStepForward(today: wed), isFalse);
      final back = now.step(-1, today: wed);
      expect(back.canStepForward(today: wed), isTrue);
      expect(back.step(1, today: wed).range(today: wed), now.range(today: wed));
      // A forward step never passes today.
      expect(back.step(5, today: wed).range(today: wed).end, d(2026, 10, 18));
    });

    test('pull to refresh from an old week shows the whole CURRENT calendar week', () {
      final old = AnalyticsPeriod.thisWeek(d(2026, 8, 5), firstDay: 1); // a Wednesday in August
      expect(old.words(today: wed).value, '3–9 Aug');
      final fresh = old.backToNow(today: wed);
      expect(fresh.range(today: wed).start, d(2026, 10, 12));
      expect(fresh.range(today: wed).end, d(2026, 10, 18));
      expect(fresh.words(today: wed).value, '12–18 Oct');
      // The preference survives the refresh.
      final sun = AnalyticsPeriod.thisWeek(d(2026, 8, 5), firstDay: 7).backToNow(today: wed);
      expect(sun.words(today: wed).value, '11–17 Oct');
    });

    test('pull to refresh keeps the length: a Day goes to today, a Month to this month', () {
      expect(AnalyticsPeriod.day(d(2026, 9, 1), firstDay: 1).backToNow(today: wed).range(today: wed).start, wed);
      expect(AnalyticsPeriod.month(d(2026, 3, 1), firstDay: 1).backToNow(today: wed).range(today: wed).start, d(2026, 10, 1));
    });

    test('switching length to Week from a Month uses the first-day preference', () {
      final m = AnalyticsPeriod.month(wed, firstDay: 1);
      final w = m.withGranularity(AnalyticsGranularity.week, today: wed, firstDay: 7);
      expect(w.range(today: wed).start, d(2026, 10, 11));
      final mon = m.withGranularity(AnalyticsGranularity.week, today: wed, firstDay: 1);
      expect(mon.range(today: wed).start, d(2026, 10, 12));
    });

    test('the Week menu lists whole calendar weeks, this week first', () {
      final opts = AnalyticsPeriod.thisWeek(wed, firstDay: 1).options(today: wed);
      expect(opts, hasLength(6));
      expect(opts[0].label, '12–18 Oct');
      expect(opts[0].note, 'this week');
      expect(opts[0].selected, isTrue);
      expect(opts[1].label, '5–11 Oct');
      expect(opts[1].note, '');
      expect(opts[1].selected, isFalse);
      expect(opts[2].label, '28 Sep – 4 Oct');
      expect(opts[1].period.range(today: wed).days, 7);
      // Choosing the earlier week selects it.
      final picked = opts[1].period;
      expect(picked.options(today: wed)[1].selected, isTrue);
      expect(picked.options(today: wed)[0].selected, isFalse);
    });

    test('no "last 7 days" wording is left in the period words or menus', () {
      final p = AnalyticsPeriod.thisWeek(wed, firstDay: 1);
      final all = [
        p.words(today: wed).spent,
        p.words(today: wed).vs,
        for (final o in p.options(today: wed)) '${o.label} ${o.note}',
        p.chart(now: wed).hint,
      ].join(' | ').toLowerCase();
      expect(all, isNot(contains('last 7 days')));
      expect(all, isNot(contains('prior week')));
    });

    test('regrouping: fixed invented spending gives these totals per calendar week, Monday vs Sunday first', () {
      // (day, cents) across a month end: 28 Sep (Mon) .. 11 Oct (Sun).
      final data = <(DateTime, int)>[
        (d(2026, 9, 28), 1000), // Mon
        (d(2026, 9, 30), 2000), // Wed
        (d(2026, 10, 3), 4000), // Sat
        (d(2026, 10, 4), 8000), // Sun
        (d(2026, 10, 5), 16000), // Mon
        (d(2026, 10, 9), 32000), // Fri
        (d(2026, 10, 11), 64000), // Sun
      ];
      int total(DayRange r) {
        final (a, b) = r.bounds;
        return data.where((e) => ms(e.$1) >= a && ms(e.$1) <= b).fold(0, (s, e) => s + e.$2);
      }

      final today = d(2026, 10, 12); // Monday: both weeks above are complete
      // Monday first: 28 Sep-4 Oct, 5-11 Oct.
      final w1 = AnalyticsPeriod.thisWeek(d(2026, 9, 30), firstDay: 1);
      final w2 = AnalyticsPeriod.thisWeek(d(2026, 10, 7), firstDay: 1);
      expect(total(w1.range(today: today)), 1000 + 2000 + 4000 + 8000);
      expect(total(w2.range(today: today)), 16000 + 32000 + 64000);
      // Sunday first: Sun 27 Sep-Sat 3 Oct, Sun 4 Oct-Sat 10 Oct, Sun 11 Oct-...
      final s1 = AnalyticsPeriod.thisWeek(d(2026, 9, 30), firstDay: 7);
      final s2 = AnalyticsPeriod.thisWeek(d(2026, 10, 7), firstDay: 7);
      final s3 = AnalyticsPeriod.thisWeek(d(2026, 10, 11), firstDay: 7);
      expect(total(s1.range(today: today)), 1000 + 2000 + 4000);
      expect(total(s2.range(today: today)), 8000 + 16000 + 32000);
      expect(total(s3.range(today: today)), 64000);
      // Regrouping moves figures between weeks but loses nothing.
      expect(total(w1.range(today: today)) + total(w2.range(today: today)), 127000);
      expect(total(s1.range(today: today)) + total(s2.range(today: today)) + total(s3.range(today: today)), 127000);
    });
  });
}
