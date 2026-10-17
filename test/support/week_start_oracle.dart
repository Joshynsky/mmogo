// F5 (0.1.2 corrections, finding R33): an INDEPENDENT, deliberately naive
// calculation of "which days make a week" for the week-start matrix tests.
// It must not call any production helper (period_math, chart_blocks,
// AnalyticsPeriod): it walks the calendar one day at a time with DateTime's
// own weekday, so a wrong production formula cannot hide behind itself.
// 1 = Monday ... 7 = Sunday, as the app stores the preference.
//
// All dates here are UTC calendar days on purpose: building a local DateTime
// costs ~80 microseconds on this machine and the matrix builds millions.
// Compare with production dates through [chk], which looks at the calendar
// day only when both sides are dates.

import 'package:flutter_test/flutter_test.dart' show TestFailure;

const kMonthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const kDayInitials = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

DateTime nextDay(DateTime d) => DateTime.utc(d.year, d.month, d.day + 1);
DateTime prevDay(DateTime d) => DateTime.utc(d.year, d.month, d.day - 1);

int lastDayOfMonth(int y, int m) {
  var d = DateTime.utc(y, m, 28);
  while (nextDay(d).month == m) {
    d = nextDay(d);
  }
  return d.day;
}

/// The first day of the week holding [d]: walk back until the weekday matches.
DateTime weekStartOf(DateTime d, int first) {
  var x = DateTime.utc(d.year, d.month, d.day);
  while (x.weekday != first) {
    x = prevDay(x);
  }
  return x;
}

/// The seven days of the week holding [d].
List<DateTime> weekDays(DateTime d, int first) {
  final out = <DateTime>[];
  var x = weekStartOf(d, first);
  for (var i = 0; i < 7; i++) {
    out.add(x);
    x = nextDay(x);
  }
  return out;
}

class Seg {
  Seg(this.start, this.end);
  final DateTime start;
  final DateTime end;
  int get days => countDays(start, end);
  String get label => start.day == end.day ? '${start.day}' : '${start.day}-${end.day}';
}

/// The month cut into weeks: a new piece starts on the 1st and on every
/// [first] weekday; no piece leaves the month.
List<Seg> monthSegments(int y, int m, int first) {
  final out = <Seg>[];
  var segStart = day(y, m, 1);
  final n = lastDayOfMonth(y, m);
  for (var d = 2; d <= n; d++) {
    final x = day(y, m, d);
    if (x.weekday == first) {
      out.add(Seg(segStart, prevDay(x)));
      segStart = x;
    }
  }
  out.add(Seg(segStart, day(y, m, n)));
  return out;
}

/// Number of days in a piece, counted by stepping (no Duration maths, so a
/// daylight-saving change cannot skew it).
int countDays(DateTime a, DateTime b) {
  var n = 1;
  for (var x = a; !(x.year == b.year && x.month == b.month && x.day == b.day); x = nextDay(x)) {
    n++;
  }
  return n;
}

/// "11–17 Oct" within a month, else "28 Sep – 4 Oct" (what the pill shows).
String spanText(DateTime s, DateTime e) => s.month == e.month && s.year == e.year
    ? '${s.day}–${e.day} ${kMonthShort[e.month - 1]}'
    : '${s.day} ${kMonthShort[s.month - 1]} – ${e.day} ${kMonthShort[e.month - 1]}';

/// The 36 months January 2026 to December 2028.
List<(int, int)> allMonths() => [
  for (var y = 2026; y <= 2028; y++)
    for (var m = 1; m <= 12; m++) (y, m),
];

bool sameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// A fast equality check for the big matrices: the stock `expect` costs
/// about a millisecond a call, which adds up over hundreds of thousands of
/// checks. Throws a [TestFailure] with the reason on the first mismatch.
void chk(Object? actual, Object? expected, {String? reason}) {
  final bool same;
  if (actual is DateTime && expected is DateTime) {
    same = actual.year == expected.year && actual.month == expected.month && actual.day == expected.day;
  } else if (actual is List && expected is List) {
    same = actual.join('\n') == expected.join('\n');
  } else {
    same = actual == expected;
  }
  if (!same) throw TestFailure('${reason ?? 'mismatch'}\n  expected: $expected\n  actual:   $actual');
}
