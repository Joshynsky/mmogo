// 0.1.2 S6b (P-Analytics-02, P-Home-06): the ONE rule for when the change
// pill shows and the progress cue that stands in for it (lib/domain/
// period_change.dart). Week and Month compare with the whole previous period;
// the pill is hidden while the current period is less than half over.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/period_change.dart';

PeriodProgress week(DateTime start, DateTime today) => periodProgress(ProgressKind.week, start, today);
PeriodProgress month(DateTime anyDay, DateTime today) =>
    periodProgress(ProgressKind.month, DateTime(anyDay.year, anyDay.month, 1), today);

void main() {
  group('Week (Monday 21 Sep 2026 to Sunday 27 Sep)', () {
    final start = DateTime(2026, 9, 21);

    test('days 1-3 are hidden, day 4 shows (the day before the middle, the middle day)', () {
      expect(week(start, DateTime(2026, 9, 21)).hide, isTrue);
      expect(week(start, DateTime(2026, 9, 22)).hide, isTrue);
      final d3 = week(start, DateTime(2026, 9, 23));
      expect(d3.hide, isTrue);
      expect(d3.n, 3);
      expect(d3.cue, '3/7');
      final d4 = week(start, DateTime(2026, 9, 24));
      expect(d4.hide, isFalse);
      expect(d4.n, 4);
    });

    test('the last day and a finished week always show the pill', () {
      final d7 = week(start, DateTime(2026, 9, 27));
      expect(d7.hide, isFalse);
      expect(d7.n, 7);
      final past = week(start, DateTime(2026, 9, 28));
      expect(past.cur, isFalse);
      expect(past.hide, isFalse);
      expect(past.n, 7, reason: 'a finished period counts all its days');
    });

    test('compares with the WHOLE previous week', () {
      final p = week(start, DateTime(2026, 9, 24));
      expect(p.priorStart, DateTime(2026, 9, 14));
      expect(p.priorEnd, DateTime(2026, 9, 20));
    });

    test('works for a Sunday-first week', () {
      // Sunday 20 Sep 2026 starts the week; Tuesday 22 Sep is day 3.
      final p = week(DateTime(2026, 9, 20), DateTime(2026, 9, 22));
      expect(p.hide, isTrue);
      expect(p.cue, '3/7');
      expect(p.priorStart, DateTime(2026, 9, 13));
    });

    test('words: Analytics and Home', () {
      final p = week(start, DateTime(2026, 9, 23));
      expect(p.analyticsLabel, 'Day 3 of 7. The change shows from day 4');
      expect(p.analyticsTooltip, 'Day 3 of 7; the change shows from day 4');
      expect(p.homeLabel, 'Day 3 of 7. The change shows from the middle of the period');
    });
  });

  group('Month thresholds, ceil(len / 2)', () {
    test('31 days (Aug 2026): hidden through day 15, shows from day 16', () {
      expect(month(DateTime(2026, 8, 1), DateTime(2026, 8, 15)).hide, isTrue);
      expect(month(DateTime(2026, 8, 1), DateTime(2026, 8, 16)).hide, isFalse);
      expect(month(DateTime(2026, 8, 1), DateTime(2026, 8, 8)).cue, '8/31');
      expect(month(DateTime(2026, 8, 1), DateTime(2026, 8, 8)).half, 16);
    });

    test('30 days (Sep 2026): hidden through day 14, shows from day 15', () {
      expect(month(DateTime(2026, 9, 1), DateTime(2026, 9, 14)).hide, isTrue);
      expect(month(DateTime(2026, 9, 1), DateTime(2026, 9, 15)).hide, isFalse);
    });

    test('29 days (Feb 2028, leap): hidden through day 14, shows from day 15', () {
      expect(month(DateTime(2028, 2, 1), DateTime(2028, 2, 14)).hide, isTrue);
      expect(month(DateTime(2028, 2, 1), DateTime(2028, 2, 15)).hide, isFalse);
      expect(month(DateTime(2028, 2, 1), DateTime(2028, 2, 15)).len, 29);
    });

    test('28 days (Feb 2027): hidden through day 13, shows from day 14', () {
      expect(month(DateTime(2027, 2, 1), DateTime(2027, 2, 13)).hide, isTrue);
      expect(month(DateTime(2027, 2, 1), DateTime(2027, 2, 14)).hide, isFalse);
      expect(month(DateTime(2027, 2, 1), DateTime(2027, 2, 14)).len, 28);
    });

    test('the last day and a past month always show; the prior is the whole previous month', () {
      expect(month(DateTime(2026, 8, 1), DateTime(2026, 8, 31)).hide, isFalse);
      final past = month(DateTime(2026, 8, 1), DateTime(2026, 9, 3));
      expect(past.cur, isFalse);
      expect(past.hide, isFalse);
      expect(past.n, 31);
      final p = month(DateTime(2026, 3, 1), DateTime(2026, 3, 2));
      expect(p.priorStart, DateTime(2026, 2, 1));
      expect(p.priorEnd, DateTime(2026, 2, 28), reason: 'March compares with February, not 31 days before');
    });

    test('a month that has not started yet is not "current"', () {
      final future = month(DateTime(2026, 11, 1), DateTime(2026, 10, 14));
      expect(future.cur, isFalse);
      expect(future.hide, isFalse);
    });
  });

  group('Year', () {
    test('normal year: 183 is the first day that shows (2 Jul), day 182 (1 Jul) is hidden', () {
      final d182 = yearProgress(2026, DateTime(2026, 7, 1));
      expect(d182.n, 182);
      expect(d182.len, 365);
      expect(d182.hide, isTrue);
      final d183 = yearProgress(2026, DateTime(2026, 7, 2));
      expect(d183.n, 183);
      expect(d183.hide, isFalse);
    });

    test('leap year: ceil(366 / 2) is also 183, which is 1 Jul', () {
      final d182 = yearProgress(2028, DateTime(2028, 6, 30));
      expect(d182.n, 182);
      expect(d182.len, 366);
      expect(d182.hide, isTrue);
      expect(yearProgress(2028, DateTime(2028, 7, 1)).hide, isFalse);
    });

    test('the cue is the MONTH number, the words name July', () {
      final p = yearProgress(2026, DateTime(2026, 5, 20));
      expect(p.hide, isTrue);
      expect(p.cue, '5/12');
      expect(p.label, 'Month 5 of 12. The change shows from July');
      expect(p.tooltip, 'Month 5 of 12; the change shows from July');
      expect(yearProgress(2026, DateTime(2026, 10, 14)).cue, '10/12');
    });

    test('a past year always shows the pill', () {
      final p = yearProgress(2025, DateTime(2026, 1, 3));
      expect(p.cur, isFalse);
      expect(p.hide, isFalse);
      expect(p.n, 365);
    });
  });
}
