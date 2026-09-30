import '../period_math.dart' as period_math;

/// Home's period selector — Today → This week → This month, cycling.
///
/// Implements the `dayBounds`/`weekBounds`/`monthBounds`/`getPriorHomeRange`
/// behavior of the earlier HTML/JS prototype as real, unit-tested Dart
/// (reference behavior only, not ported code). Pure, DB-free logic so it can
/// be tested in isolation from the query layer — see
/// `test/domain/home/home_period_test.dart`.
///
/// **Refactor note (T9):** the actual day/week/month bounds formulas now
/// live in `lib/domain/period_math.dart`, shared with
/// `lib/domain/analytics/analytics_period.dart` (T9's own Day/Week/Month/
/// Custom + arrows + escalation control) — extending/generalizing this
/// file's math rather than reimplementing it a second time, per T9's own
/// dispatch instruction. This enum's public API (`bounds`/`priorBounds`/
/// `next`/`label`/`priorSuffix`) is unchanged; only the internal
/// implementation was factored out.
enum HomePeriod {
  today,
  week,
  month;

  String get label => switch (this) {
        HomePeriod.today => 'Today',
        HomePeriod.week => 'This week',
        HomePeriod.month => 'This month',
      };

  String get priorSuffix => switch (this) {
        HomePeriod.today => 'vs yesterday',
        HomePeriod.week => 'vs prior week',
        HomePeriod.month => 'vs last month',
      };

  /// Cycles Today -> This week -> This month -> Today (wraps).
  HomePeriod next() => switch (this) {
        HomePeriod.today => HomePeriod.week,
        HomePeriod.week => HomePeriod.month,
        HomePeriod.month => HomePeriod.today,
      };

  /// Inclusive `(startMs, endMs)` epoch-millis bounds for this period,
  /// anchored at [now]:
  ///   - today: the calendar day containing [now], 00:00:00.000–23:59:59.999
  ///   - week: a rolling 7-day window ending at today's day-end (today +
  ///     the 6 preceding days) — NOT a calendar week (e.g. not Mon–Sun),
  ///     matching the prototype's `weekBounds` exactly
  ///   - month: the calendar month containing [now], 1st 00:00:00.000 to
  ///     the last day 23:59:59.999
  (int, int) bounds(DateTime now) => switch (this) {
        HomePeriod.today => period_math.dayBounds(now),
        HomePeriod.week => period_math.weekBounds(now),
        HomePeriod.month => period_math.monthBounds(now),
      };

  /// The immediately preceding period of the same length — e.g. for
  /// `week`, the 7 days immediately before the current week's start.
  /// Generalizes "vs last month" the same way Analytics'
  /// period diff line does.
  (int, int) priorBounds(DateTime now) {
    final (start, end) = bounds(now);
    return period_math.priorBoundsOf(start, end);
  }
}
