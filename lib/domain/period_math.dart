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

/// The first day of the calendar week containing [d] (local midnight).
/// [firstDay] is 1 = Monday ... 7 = Sunday (default Monday). Built from
/// y/m/d, never from Durations, so a clock change cannot skew it.
DateTime calendarWeekStart(DateTime d, {int firstDay = 1}) {
  final back = (d.weekday - firstDay + 7) % 7;
  return DateTime(d.year, d.month, d.day - back);
}

/// The last day of the calendar week containing [d] (local midnight).
DateTime calendarWeekEnd(DateTime d, {int firstDay = 1}) {
  final s = calendarWeekStart(d, firstDay: firstDay);
  return DateTime(s.year, s.month, s.day + 6);
}

/// Inclusive `(startMs, endMs)` epoch-millis bounds for the calendar week
/// SO FAR: the week's first day 00:00:00.000 up to the end of [d]'s own day
/// (data only up to today). The whole week (Monday to Sunday by default) is
/// [calendarWeekStart] to [calendarWeekEnd].
(int, int) weekBounds(DateTime d, {int firstDay = 1}) {
  final s = calendarWeekStart(d, firstDay: firstDay);
  return (dayBounds(s).$1, dayBounds(d).$2);
}

/// Inclusive epoch-millis bounds of the WHOLE calendar week before the one
/// containing [d].
(int, int) previousWeekBounds(DateTime d, {int firstDay = 1}) {
  final s = calendarWeekStart(d, firstDay: firstDay);
  final prevStart = DateTime(s.year, s.month, s.day - 7);
  final prevEnd = DateTime(s.year, s.month, s.day - 1);
  return (dayBounds(prevStart).$1, dayBounds(prevEnd).$2);
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
/// endMs)` — e.g. for a 3-day window, the 3 days immediately before it.
/// Generalizes "vs last month" the same way Analytics' period diff
/// line does.
(int, int) priorBoundsOf(int startMs, int endMs) {
  final span = endMs - startMs + 1;
  return (startMs - span, startMs - 1);
}
