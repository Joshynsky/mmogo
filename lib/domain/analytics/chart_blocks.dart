/// §DOMAIN.CHART_BLOCKS — the pure maths behind the new chart shapes of 0.1.2
/// S6b (PH1 / M10): Month by weeks cut at the month edges, All time in
/// five-year blocks, Custom over 31 days in calendar-week blocks, the compact
/// amount under a Year bar, and the tooltip lines of a tapped bar.
///
/// Pure Dart, DB-free. Tested in `test/domain/analytics/chart_blocks_test.dart`.
library;

import '../format/money.dart';
import '../period_math.dart' as period_math;

/// The Month chart: one month by calendar weeks (default) or by days.
/// Preference `month_chart_style` ('weeks' | 'days').
enum MonthChartStyle { weeks, days }

/// The Year chart's amounts under the months: a quarter total under each
/// group of three (default) or every month's own amount.
/// Preference `year_view_amounts` ('quarters' | 'months').
enum YearViewAmounts { quarters, months }

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
int _between(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

// ---- Month by weeks --------------------------------------------------------

/// One bar of Month-by-weeks: the days of one calendar week that fall INSIDE
/// the month (a part week at either edge holds fewer than seven).
class MonthWeekSegment {
  const MonthWeekSegment({
    required this.start,
    required this.end,
    required this.crossMonth,
  });

  final DateTime start;
  final DateTime end;

  /// The neighbouring month the whole calendar week reaches into, or null.
  final DateTime? crossMonth;

  int get days => _between(start, end) + 1;

  /// Fewer than seven days in this month.
  bool get part => days < 7;

  /// "5-11", or "1" for a one-day segment.
  String get rangeLabel => start.day == end.day ? '${start.day}' : '${start.day}-${end.day}';

  String get daysLabel => _plural(days, 'day');

  /// "Week crosses into August", or null when the week stays in the month.
  String? get crossLine => crossMonth == null ? null : 'Week crosses into ${_monthFull[crossMonth!.month - 1]}';

  /// Days of the segment that have happened (0 when it has not started).
  int elapsed(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    if (start.isAfter(t)) return 0;
    final last = end.isBefore(t) ? end : t;
    return _between(start, last) + 1;
  }
}

/// The segments of the month holding [anyDay]: calendar weeks (first day
/// [firstDay], 1 = Monday ... 7 = Sunday) cut at the first and last day of
/// the month. Four to six segments.
List<MonthWeekSegment> monthWeekSegments(DateTime anyDay, {int firstDay = 1}) {
  final ms = DateTime(anyDay.year, anyDay.month, 1);
  final me = DateTime(anyDay.year, anyDay.month + 1, 0);
  final out = <MonthWeekSegment>[];
  var s = ms;
  while (!s.isAfter(me)) {
    final ws = period_math.calendarWeekStart(s, firstDay: firstDay);
    final wEnd = _addDays(ws, 6);
    final e = wEnd.isAfter(me) ? me : wEnd;
    DateTime? other;
    if (ws.isBefore(ms)) {
      other = DateTime(ms.year, ms.month - 1, 1);
    } else if (wEnd.isAfter(me)) {
      other = DateTime(ms.year, ms.month + 1, 1);
    }
    out.add(MonthWeekSegment(start: s, end: e, crossMonth: other));
    s = _addDays(e, 1);
  }
  return out;
}

/// The x-axis label of one bar in Month-by-days: the 1st, every 5th and the
/// last day; a 5th-day label is dropped when it would touch the last ("30"
/// before "31").
String monthDayLabel(int day, int daysInMonth) =>
    day == 1 || day == daysInMonth || (day % 5 == 0 && daysInMonth - day >= 2) ? '$day' : '';

// ---- All time in five-year blocks ------------------------------------------

/// The first year of the block of five that holds [year]: blocks follow the
/// digits, so a block starts in a year ending in 1 or 6 (2021, 2026, 2031).
int allTimeBlockStart(int year) => year - ((year - 1) % 5);

/// The first year of the block [back] blocks before the one holding today
/// ([back] is 0 or negative; the block is never in the future).
int allTimeBlockStartAt(DateTime today, int back) => allTimeBlockStart(today.year) + 5 * (back > 0 ? 0 : back);

// ---- Custom over 31 days ---------------------------------------------------

/// One block of a Custom range longer than 31 days.
class CustomWeekBlock {
  const CustomWeekBlock(this.start, this.end);

  final DateTime start;
  final DateTime end;

  int get days => _between(start, end) + 1;
  bool get part => days < 7;
}

/// Calendar-week blocks (first day [firstDay]) over [from]..[to]; the first
/// and last block are clipped to the chosen dates.
List<CustomWeekBlock> customWeekBlocks(DateTime from, DateTime to, {int firstDay = 1}) {
  final out = <CustomWeekBlock>[];
  for (var d = period_math.calendarWeekStart(from, firstDay: firstDay); !d.isAfter(to); d = _addDays(d, 7)) {
    final a = d.isBefore(from) ? from : d;
    final wEnd = _addDays(d, 6);
    final b = wEnd.isAfter(to) ? to : wEnd;
    out.add(CustomWeekBlock(a, b));
  }
  return out;
}

// ---- Year amounts ----------------------------------------------------------

/// The compact amount under a Year bar (the mock's `fitAmt`). [ksh] is in
/// whole shillings; [slot] is the bar slot width in chart units. The whole
/// number is used when it fits the slot (a digit is about 4.7 wide), else it
/// is shortened: 48k, 4.8k, 1.2M.
String fitAmount(double ksh, double slot) {
  final whole = ksh.round();
  final s = '$whole';
  if (s.length * 4.7 <= slot - 2) return s;
  if (ksh >= 999500) {
    final m = ksh / 1e6;
    return '${m >= 10 ? '${m.round()}' : m.toStringAsFixed(1).replaceFirst('.0', '')}M';
  }
  final k = ksh / 1000;
  final text = k >= 10 || k.toStringAsFixed(1).endsWith('.0') ? '${k.round()}' : k.toStringAsFixed(1);
  return '${text}k';
}

// ---- Tooltip of a tapped bar -----------------------------------------------

/// The three lines of a tapped Month-by-days bar.
List<String> dayTipLines(DateTime day, int cents) => [
  '${_wd[day.weekday - 1]} ${day.day} ${_mon[day.month - 1]}',
  kshTrim(cents),
  'Tap again to open the day',
];

/// The three lines of a tapped Month-by-weeks bar: its days in this month,
/// the total with the average per day (so far while the segment runs).
List<String> weekTipLines(MonthWeekSegment seg, int cents, DateTime today) {
  final elapsed = seg.elapsed(today);
  final avg = ((cents / 100 / (elapsed < 1 ? 1 : elapsed)).round()) * 100;
  return [
    '${seg.rangeLabel} ${_mon[seg.start.month - 1]} · ${seg.daysLabel}',
    '${kshTrim(cents)} · avg ${kshTrim(avg)}/day${elapsed < seg.days ? ' so far' : ''}',
    'Tap again to open the week',
  ];
}

/// The accessible name of a Month-by-weeks bar ("5-11 Sep, 7 days").
String weekSegmentName(MonthWeekSegment seg) =>
    '${seg.rangeLabel} ${_mon[seg.start.month - 1]}, ${seg.daysLabel}';
