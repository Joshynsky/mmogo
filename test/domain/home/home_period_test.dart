// Unit tests for lib/domain/home/home_period.dart — pure Dart, no
// database, no Flutter widget tree. Verifies the period bounds/prior-
// bounds math this slice's diff line and donut breakdown depend on,
// mirroring the earlier prototype's reference
// dayBounds/weekBounds/monthBounds/getPriorHomeRange behavior.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/home/home_period.dart';

void main() {
  group('HomePeriod.bounds', () {
    test('today spans exactly the calendar day containing now', () {
      final now = DateTime(2026, 9, 18, 14, 30);
      final (start, end) = HomePeriod.today.bounds(now);
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2026, 9, 18, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2026, 9, 18, 23, 59, 59, 999));
    });

    test('week is a rolling 7-day window ending today (today + 6 preceding days)', () {
      final now = DateTime(2026, 9, 18, 14, 30);
      final (start, end) = HomePeriod.week.bounds(now);
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2026, 9, 12, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2026, 9, 18, 23, 59, 59, 999));
    });

    test('month spans the full calendar month containing now', () {
      final now = DateTime(2026, 9, 18, 14, 30);
      final (start, end) = HomePeriod.month.bounds(now);
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2026, 9, 1, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2026, 9, 30, 23, 59, 59, 999));
    });

    test('month correctly rolls a December anchor into a 31-day bound, not into next year', () {
      final now = DateTime(2026, 12, 5);
      final (start, end) = HomePeriod.month.bounds(now);
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2026, 12, 1, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2026, 12, 31, 23, 59, 59, 999));
    });
  });

  group('HomePeriod.priorBounds', () {
    test('today\'s prior period is exactly yesterday', () {
      final now = DateTime(2026, 9, 18, 14, 30);
      final (start, end) = HomePeriod.today.priorBounds(now);
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2026, 9, 17, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2026, 9, 17, 23, 59, 59, 999));
    });

    test('week\'s prior period is the 7 days immediately preceding the current window', () {
      final now = DateTime(2026, 9, 18, 14, 30);
      final (start, end) = HomePeriod.week.priorBounds(now);
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2026, 9, 5, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2026, 9, 11, 23, 59, 59, 999));
    });

    test('month\'s prior period is the previous calendar month', () {
      // QA fix F2: was a same-length window (Aug 2-31 for September).
      final now = DateTime(2026, 9, 18, 14, 30);
      final (start, end) = HomePeriod.month.priorBounds(now);
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2026, 8, 1, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2026, 8, 31, 23, 59, 59, 999));
    });

    test('March compares to February 1-28 (not a same-length window)', () {
      final (start, end) = HomePeriod.month.priorBounds(DateTime(2027, 3, 15));
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2027, 2, 1, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2027, 2, 28, 23, 59, 59, 999));
    });

    test('March in a leap year compares to February 1-29', () {
      final (start, end) = HomePeriod.month.priorBounds(DateTime(2028, 3, 15));
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2028, 2, 1, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2028, 2, 29, 23, 59, 59, 999));
    });

    test('January compares to the previous December (year rolls back)', () {
      final (start, end) = HomePeriod.month.priorBounds(DateTime(2027, 1, 10));
      expect(DateTime.fromMillisecondsSinceEpoch(start), DateTime(2026, 12, 1, 0, 0, 0, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(end), DateTime(2026, 12, 31, 23, 59, 59, 999));
    });
  });

  group('HomePeriod.next / label / priorSuffix', () {
    test('cycles Today -> This week -> This month -> Today', () {
      expect(HomePeriod.today.next(), HomePeriod.week);
      expect(HomePeriod.week.next(), HomePeriod.month);
      expect(HomePeriod.month.next(), HomePeriod.today);
    });

    test('labels and prior-suffixes match the spec exactly', () {
      expect(HomePeriod.today.label, 'Today');
      expect(HomePeriod.week.label, 'This week');
      expect(HomePeriod.month.label, 'This month');
      expect(HomePeriod.today.priorSuffix, 'vs yesterday');
      expect(HomePeriod.week.priorSuffix, 'vs prior week');
      expect(HomePeriod.month.priorSuffix, 'vs last month');
    });
  });
}
