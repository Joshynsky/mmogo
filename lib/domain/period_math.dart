/// Shared day/week/month epoch-millis bounds math, factored out of
/// `home/home_period.dart` (T4) so Analytics (T9) can extend it to
/// Day/Week/Month/Custom granularity + prior/next arrows + Week-tab
/// escalation without reimplementing the same day/week/month formulas a
/// second time — this dispatch's own instruction ("extend/generalize
/// home_period.dart-style period logic ... rather than reimplementing
/// period math from scratch").
///
/// Pure, DB-free — implements the `dayBounds`/`weekBounds`/`monthBounds`
/// behavior exactly as `home_period.dart` (T4) already established and
/// unit-tested.
library;

/// Inclusive `(startMs, endMs)` epoch-millis bounds for the calendar day
/// containing [d]: 00:00:00.000-23:59:59.999.
(int, int) dayBounds(DateTime d) {
  final start = DateTime(d.year, d.month, d.day);
  final end = DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
  return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
}

/// Inclusive `(startMs, endMs)` epoch-millis bounds for a rolling 7-day
/// window ending at [d]'s day-end (d + the 6 preceding days) — NOT a
/// calendar week (e.g. not Mon-Sun), matching the prototype's `weekBounds`
/// exactly.
(int, int) weekBounds(DateTime d) {
  final (_, end) = dayBounds(d);
  const oneDayMs = 86400000;
  final start = end - 6 * oneDayMs - 86399999;
  return (start, end);
}

/// Inclusive `(startMs, endMs)` epoch-millis bounds for the calendar month
/// containing [d]: the 1st 00:00:00.000 to the last day 23:59:59.999.
(int, int) monthBounds(DateTime d) {
  final start = DateTime(d.year, d.month, 1);
  // Day 0 of next month == last day of this month (Dart normalizes the
  // out-of-range day/month components, same idiom as JS's
  // `new Date(year, month + 1, 0)` in the prototype).
  final end = DateTime(d.year, d.month + 1, 0, 23, 59, 59, 999);
  return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
}

/// The immediately preceding period of the same length as `(startMs,
/// endMs)` — e.g. for a 7-day window, the 7 days immediately before it.
/// Generalizes "vs last month" the same way Analytics' period diff
/// line does.
(int, int) priorBoundsOf(int startMs, int endMs) {
  final span = endMs - startMs + 1;
  return (startMs - span, startMs - 1);
}
