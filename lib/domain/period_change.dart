/// §DOMAIN.PERIOD_CHANGE — when the change pill shows, and the progress cue
/// that stands in for it early in a period (0.1.2 S6b, PH1 / M10 / M11b).
///
/// ONE rule for Home and Analytics (the signed mock's `Shell.week.mid`):
/// Week and Month compare with the WHOLE previous period. While the current
/// period is less than half over the pill is hidden and a muted progress cue
/// ("3/7", "8/31") shows in its place. Year has its own small rule beside it
/// (the cue is the month number, "10/12"). A past period always shows its pill.
///
/// Pure Dart, DB-free. Tested in `test/domain/period_change_test.dart`.
library;

const _monthFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

enum ProgressKind { week, month }

int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// What the Week / Month rule says about one period against [today].
class PeriodProgress {
  const PeriodProgress({
    required this.cur,
    required this.n,
    required this.len,
    required this.hide,
    required this.priorStart,
    required this.priorEnd,
  });

  /// Today is inside the period.
  final bool cur;

  /// Days elapsed in the period, today counting as day 1 of its own day
  /// (`len` for a finished period).
  final int n;

  /// Days in the period: 7 for a week, 28 to 31 for a month.
  final int len;

  /// The pill is hidden and the cue shows: the period is the current one and
  /// fewer than half of it (rounded up) has elapsed.
  final bool hide;

  /// The WHOLE previous period (calendar days, local midnight).
  final DateTime priorStart;
  final DateTime priorEnd;

  /// The first day the change shows: `ceil(len / 2)`. Week: day 4. Month: 14
  /// (28 days), 15 (29 or 30 days), 16 (31 days).
  int get half => (len + 1) ~/ 2;

  /// "3/7", "8/31".
  String get cue => '$n/$len';

  /// Analytics' screen-reader text, also its tooltip text (with a semicolon).
  String get analyticsLabel => 'Day $n of $len. The change shows from day $half';
  String get analyticsTooltip => 'Day $n of $len; the change shows from day $half';

  /// Home's screen-reader text (and tooltip).
  String get homeLabel => 'Day $n of $len. The change shows from the middle of the period';
}

/// The Week / Month rule. [start] is the period's first day (a week's first
/// day, or the 1st of the month); [today] is the current day.
PeriodProgress periodProgress(ProgressKind kind, DateTime start, DateTime today) {
  final s = DateTime(start.year, start.month, start.day);
  final t = DateTime(today.year, today.month, today.day);
  final DateTime end;
  final DateTime pStart;
  final DateTime pEnd;
  final int len;
  if (kind == ProgressKind.month) {
    end = DateTime(s.year, s.month + 1, 0);
    pStart = DateTime(s.year, s.month - 1, 1);
    pEnd = DateTime(s.year, s.month, 0);
    len = end.day;
  } else {
    end = DateTime(s.year, s.month, s.day + 6);
    pStart = DateTime(s.year, s.month, s.day - 7);
    pEnd = DateTime(s.year, s.month, s.day - 1);
    len = 7;
  }
  final cur = !t.isBefore(s) && !t.isAfter(end);
  final n = cur ? _daysBetween(s, t) + 1 : len;
  return PeriodProgress(
    cur: cur,
    n: n,
    len: len,
    hide: cur && n < (len + 1) ~/ 2,
    priorStart: pStart,
    priorEnd: pEnd,
  );
}

/// Analytics Year: the same rule against the WHOLE previous year, with the
/// MONTH number as the cue.
class YearProgress {
  const YearProgress({
    required this.cur,
    required this.n,
    required this.len,
    required this.hide,
    required this.cue,
    required this.month,
    required this.fromMonth,
  });

  final bool cur;

  /// Days elapsed in the year (today counted), `len` for a past year.
  final int n;

  /// 365 or 366.
  final int len;
  final bool hide;

  /// "10/12": today's month number over 12.
  final String cue;

  /// Today's month number (1..12).
  final int month;

  /// The name of the month that holds day `ceil(len / 2)` of the year
  /// (July in every year).
  final String fromMonth;

  int get half => (len + 1) ~/ 2;

  String get label => 'Month $month of 12. The change shows from $fromMonth';
  String get tooltip => 'Month $month of 12; the change shows from $fromMonth';
}

YearProgress yearProgress(int year, DateTime today) {
  final first = DateTime(year, 1, 1);
  final len = _daysBetween(first, DateTime(year, 12, 31)) + 1;
  final t = DateTime(today.year, today.month, today.day);
  final cur = year == t.year;
  final n = cur ? _daysBetween(first, t) + 1 : len;
  final half = (len + 1) ~/ 2;
  final midDay = DateTime(year, 1, half);
  return YearProgress(
    cur: cur,
    n: n,
    len: len,
    hide: cur && n < half,
    cue: '${t.month}/12',
    month: t.month,
    fromMonth: _monthFull[midDay.month - 1],
  );
}
