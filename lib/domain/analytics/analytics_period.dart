/// Analytics' period model (T21, v0.1.0 rework): the two-part period pill
/// (length: All time / Year / Month / Week / Day, plus "which one"), the
/// Custom date range, stepping with ‹ › / swipe, "back to now", and the
/// period-aware chart buckets.
///
/// Re-derived as real Dart from the approved analytics mock (v4, view B:
/// range, prior-range, wording, buckets, stepping and the pill menus) and
/// the onboarding mock (v7, "back to now"). It supersedes T9's
/// Yesterday/Today/Week tabs and the Week-tab escalation ladder.
///
/// All dates here are calendar days (local midnight). "Week" is the CALENDAR
/// week containing the anchor, from the first day of the week (Monday by
/// default, a preference) for seven days; the old moving window is gone.
///
/// Pure and DB-free: every method takes "today" (and, where it matters, the
/// first transaction's day) as an argument. Tested in
/// `test/domain/analytics/analytics_period_test.dart`.
library;

import 'dart:math' as math;

import '../period_math.dart' as period_math;
import 'chart_blocks.dart';

enum AnalyticsGranularity { all, year, month, week, day, custom }

/// The pill's left-half menu, in the mock's order (`GRANS`).
const analyticsGranularityMenu = [
  (AnalyticsGranularity.all, 'All time'),
  (AnalyticsGranularity.year, 'Year'),
  (AnalyticsGranularity.month, 'Month'),
  (AnalyticsGranularity.week, 'Week'),
  (AnalyticsGranularity.day, 'Day'),
];

const _weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdayFull = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
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

// ---- calendar-day helpers (DST-safe: built from y/m/d, never Durations) ----

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
DateTime monthStart(DateTime d) => DateTime(d.year, d.month, 1);
DateTime monthLastDay(DateTime d) => DateTime(d.year, d.month + 1, 0);
DateTime addMonths(DateTime d, int n) => DateTime(d.year, d.month + n, 1);
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
bool sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;
DateTime _minDay(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

/// Whole calendar days from [a] to [b] (UTC dates, so DST can't skew it).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// "24 Sep" (the mock's `fmtD`).
String fmtDayMonth(DateTime d) => '${d.day} ${_mon[d.month - 1]}';

/// "Thu" (the mock's `WD`).
String weekdayShort(DateTime d) => _weekday[d.weekday - 1];

String monthShort(DateTime d) => _mon[d.month - 1];

/// "18–24 Sep" within one month, else "28 Aug – 3 Sep" (the mock's `span`).
String fmtSpan(DateTime s, DateTime e) => s.month == e.month && s.year == e.year
    ? '${s.day}–${e.day} ${_mon[e.month - 1]}'
    : '${fmtDayMonth(s)} – ${fmtDayMonth(e)}';

/// An inclusive range of calendar days.
class DayRange {
  DayRange(DateTime start, DateTime end) : start = dateOnly(start), end = dateOnly(end);

  final DateTime start;
  final DateTime end;

  int get days => daysBetween(start, end) + 1;

  /// Inclusive epoch-millis bounds: [start] 00:00:00.000 to [end] 23:59:59.999.
  (int, int) get bounds => (period_math.dayBounds(start).$1, period_math.dayBounds(end).$2);

  bool containsDay(DateTime t) {
    final d = dateOnly(t);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  @override
  bool operator ==(Object other) => other is DayRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DayRange($start – $end)';
}

/// The pill wording for a period: the right half's value, the fuller
/// "Spent …" description (the label's tooltip / screen-reader text), and the
/// change pill's "vs …" suffix (the mock's `words`).
class PeriodWords {
  const PeriodWords({required this.value, required this.spent, required this.vs});

  final String value;
  final String spent;
  final String vs;
}

/// One entry of the pill's right-half menu.
class PeriodOption {
  const PeriodOption({required this.label, this.note = '', required this.selected, required this.period});

  final String label;
  final String note;
  final bool selected;
  final AnalyticsPeriod period;
}

/// One bar of the chart: a time window, its axis label, and where tapping it
/// goes ([target], `null` = not tappable).
class ChartBucket {
  const ChartBucket({
    required this.label,
    required this.startMs,
    required this.endMs,
    this.selected = true,
    this.future = false,
    this.target,
    this.sub = '',
    this.name,
    this.part = false,
    this.tipLines,
    this.cross,
  });

  final String label;
  final int startMs;
  final int endMs;

  /// `false` = drawn dimmed (the months before the first transaction on the
  /// party view's by-month chart).
  final bool selected;

  /// Faded, never tappable (a future block/month, or before the start).
  final bool future;

  final AnalyticsPeriod? target;

  /// A second small line under the label (a part week's "3 days", the date
  /// under a Week day).
  final String sub;

  /// What a screen reader says for the bar; `null` = the label.
  final String? name;

  /// A part week (fewer than seven days): drawn with a striped fill.
  final bool part;

  /// Month: the first tap shows these three lines for the bar's total, the
  /// second tap opens [target]. `null` = the bar opens at once.
  final List<String> Function(int cents)? tipLines;

  /// "Week crosses into August", shown on the week this bar opens.
  final String? cross;

  bool get tappable => target != null && !future;

  /// First tap = tooltip, second tap = open.
  bool get hasTip => tipLines != null && !future;

  bool contains(int ms) => ms >= startMs && ms <= endMs;
}

/// What the Year chart draws under the twelve month labels.
enum ChartUnder { none, quarters, months }

class ChartSpec {
  const ChartSpec({
    required this.buckets,
    required this.title,
    required this.hint,
    required this.showAverage,
    required this.labelSelected,
    this.legend = '',
    this.futureStubs = false,
    this.under = ChartUnder.none,
  });

  final List<ChartBucket> buckets;
  final String title;
  final String hint;

  /// The dashed daily-average line (Week, Month by days and Custom).
  final bool showAverage;

  /// Bold axis label and a value above the bar of the selected bucket.
  /// Unused since Month became one month (kept off everywhere).
  final bool labelSelected;

  /// The line under the chart ("Striped bar = part week ..."), or ''.
  final String legend;

  /// Future buckets draw a faint stub where the bar would be.
  final bool futureStubs;

  /// The amount lines under the month labels (Year).
  final ChartUnder under;
}

(int, int) _dayMs(DateTime d) => period_math.dayBounds(d);
(int, int) _rangeMs(DateTime s, DateTime e) => (_dayMs(s).$1, _dayMs(e).$2);

/// Immutable period state. Every transition returns a new instance.
class AnalyticsPeriod {
  AnalyticsPeriod._({
    required this.granularity,
    required DateTime anchor,
    this.custom,
    this.blockBack = 0,
    required this.firstDay,
  }) : anchor = dateOnly(anchor);

  final AnalyticsGranularity granularity;

  /// Week: any day inside that calendar week. Day/Month/Year: any day
  /// inside that day/month/year.
  final DateTime anchor;

  /// The first day of the calendar week, 1 = Monday ... 7 = Sunday.
  final int firstDay;

  /// Custom only: the chosen days.
  final DayRange? custom;

  /// All time only: how many five-year blocks back from the one holding
  /// today (0 = that block, never positive).
  final int blockBack;

  /// The nav-bar default: the whole calendar week containing [today].
  factory AnalyticsPeriod.thisWeek(DateTime today, {required int firstDay}) =>
      AnalyticsPeriod._(granularity: AnalyticsGranularity.week, anchor: today, firstDay: firstDay);

  /// One day (Home's row hand-off, a Week/Custom bar tap, the Day menu).
  factory AnalyticsPeriod.day(DateTime day, {required int firstDay}) =>
      AnalyticsPeriod._(granularity: AnalyticsGranularity.day, anchor: day, firstDay: firstDay);

  factory AnalyticsPeriod.month(DateTime anyDay, {required int firstDay}) =>
      AnalyticsPeriod._(granularity: AnalyticsGranularity.month, anchor: monthStart(anyDay), firstDay: firstDay);

  /// One month as the Month menu picks it. Used by the menu and by Paid to's
  /// hand-off (T22). Since S6b the Month chart shows that one month only, so
  /// [today] no longer matters; the parameter stays for the callers.
  factory AnalyticsPeriod.monthShown(DateTime anyDay, {required DateTime today, required int firstDay}) =>
      AnalyticsPeriod.month(anyDay, firstDay: firstDay);

  factory AnalyticsPeriod.year(int year, {required DateTime today, required int firstDay}) => AnalyticsPeriod._(
    granularity: AnalyticsGranularity.year,
    anchor: year == today.year ? today : DateTime(year, 1, 1),
    firstDay: firstDay,
  );

  factory AnalyticsPeriod.allTime(DateTime today, {required int firstDay}) =>
      AnalyticsPeriod._(granularity: AnalyticsGranularity.all, anchor: today, firstDay: firstDay);

  /// The Custom sheet's "Show": swapped dates are put in order and both are
  /// clamped to today.
  factory AnalyticsPeriod.custom(DateTime from, DateTime to, {required DateTime today, required int firstDay}) {
    var a = dateOnly(from);
    var b = dateOnly(to);
    if (a.isAfter(b)) (a, b) = (b, a);
    final t = dateOnly(today);
    if (b.isAfter(t)) b = t;
    if (a.isAfter(b)) a = b;
    return AnalyticsPeriod._(
      granularity: AnalyticsGranularity.custom,
      anchor: b,
      custom: DayRange(a, b),
      firstDay: firstDay,
    );
  }

  /// The same period under another first day of the week (1..7).
  AnalyticsPeriod withFirstDay(int day) =>
      AnalyticsPeriod._(granularity: granularity, anchor: anchor, custom: custom, blockBack: blockBack, firstDay: day);

  /// The first day of the calendar week containing [d] under this period's
  /// first-day-of-week.
  DateTime _weekStart(DateTime d) => period_math.calendarWeekStart(d, firstDay: firstDay);

  // ---- range ---------------------------------------------------------------

  /// The days this period covers. [first] is the first transaction's day
  /// (All time starts there; `null` = no transactions = today).
  DayRange range({required DateTime today, DateTime? first}) {
    final a = anchor;
    return switch (granularity) {
      AnalyticsGranularity.day => DayRange(a, a),
      AnalyticsGranularity.week => DayRange(_weekStart(a), addDays(_weekStart(a), 6)),
      AnalyticsGranularity.month => DayRange(monthStart(a), monthLastDay(a)),
      AnalyticsGranularity.year => DayRange(DateTime(a.year, 1, 1), DateTime(a.year, 12, 31)),
      AnalyticsGranularity.all => DayRange(_minDay(first ?? today, today), today),
      AnalyticsGranularity.custom => custom ?? DayRange(a, a),
    };
  }

  /// The equally long period just before (`null` on All time): the previous
  /// month / year, else the N days immediately before.
  DayRange? priorRange({required DateTime today, DateTime? first}) {
    if (granularity == AnalyticsGranularity.all) return null;
    final r = range(today: today, first: first);
    if (granularity == AnalyticsGranularity.month) {
      final s = addMonths(r.start, -1);
      return DayRange(s, monthLastDay(s));
    }
    if (granularity == AnalyticsGranularity.year) {
      return DayRange(DateTime(r.start.year - 1, 1, 1), DateTime(r.start.year - 1, 12, 31));
    }
    final n = r.days;
    return DayRange(addDays(r.start, -n), addDays(r.start, -1));
  }

  /// Days of the range that have happened (for "avg Ksh X/day").
  int elapsedDays({required DateTime today, DateTime? first}) {
    final r = range(today: today, first: first);
    final end = _minDay(r.end, dateOnly(today));
    return daysBetween(r.start, end) + 1;
  }

  // ---- wording -------------------------------------------------------------

  String get granularityLabel => granularity == AnalyticsGranularity.custom
      ? 'Custom'
      : analyticsGranularityMenu.firstWhere((g) => g.$1 == granularity).$2;

  PeriodWords words({required DateTime today, DateTime? first}) {
    final r = range(today: today, first: first);
    final s = r.start;
    final e = r.end;
    final t = dateOnly(today);
    switch (granularity) {
      case AnalyticsGranularity.day:
        final isToday = sameDay(s, t);
        final isYesterday = sameDay(s, addDays(t, -1));
        final v = isToday
            ? 'Today'
            : isYesterday
            ? 'Yesterday'
            : '${weekdayShort(s)} ${fmtDayMonth(s)}';
        return PeriodWords(
          value: v,
          spent: isToday || isYesterday
              ? 'Spent ${v.toLowerCase()}'
              : 'Spent on ${_weekdayFull[s.weekday - 1]}, ${fmtDayMonth(s)}',
          vs: 'vs day before',
        );
      case AnalyticsGranularity.week:
        return PeriodWords(
          value: fmtSpan(s, e),
          spent: !t.isBefore(s) && !t.isAfter(e) ? 'Spent this week' : 'Spent that week',
          vs: 'vs last week',
        );
      case AnalyticsGranularity.month:
        return PeriodWords(
          value: '${monthShort(s)} ${s.year}',
          spent: sameMonth(s, t) ? 'Spent this month' : 'Spent in ${_monthFull[s.month - 1]}',
          vs: 'vs last month',
        );
      case AnalyticsGranularity.year:
        return PeriodWords(
          value: '${s.year}',
          spent: s.year == t.year ? 'Spent this year' : 'Spent in ${s.year}',
          vs: 'vs last year',
        );
      case AnalyticsGranularity.all:
        return PeriodWords(value: 'since ${monthShort(s)} ${s.year}', spent: 'Spent since you started', vs: '');
      case AnalyticsGranularity.custom:
        final n = r.days;
        return PeriodWords(value: fmtSpan(s, e), spent: 'Spent over $n days', vs: 'vs previous $n days');
    }
  }

  // ---- the pill ------------------------------------------------------------

  /// The pill's left half: switch the length, keeping the end of the current
  /// range (clamped to today) as the new anchor.
  /// [firstDay] (1..7, required) is the first day of the week the new period
  /// uses, so a switch to Week uses the preference even from a Day or Month
  /// period.
  AnalyticsPeriod withGranularity(
    AnalyticsGranularity g, {
    required DateTime today,
    DateTime? first,
    required int firstDay,
  }) {
    final r = range(today: today, first: first);
    final end = _minDay(r.end, dateOnly(today));
    return AnalyticsPeriod._(
      granularity: g,
      anchor: g == AnalyticsGranularity.month ? monthStart(end) : end,
      firstDay: firstDay,
    );
  }

  /// The pill's right half. Empty for All time and Custom (they open the
  /// Custom sheet instead).
  List<PeriodOption> options({required DateTime today, DateTime? first}) {
    final t = dateOnly(today);
    switch (granularity) {
      case AnalyticsGranularity.day:
        return [
          for (var k = 0; k < 7; k++)
            PeriodOption(
              label: k == 0
                  ? 'Today'
                  : k == 1
                  ? 'Yesterday'
                  : '${weekdayShort(addDays(t, -k))} ${fmtDayMonth(addDays(t, -k))}',
              selected: sameDay(addDays(t, -k), anchor),
              period: AnalyticsPeriod.day(addDays(t, -k), firstDay: firstDay),
            ),
        ];
      case AnalyticsGranularity.week:
        // Whole calendar weeks, this week first; the label is the whole week.
        final thisStart = _weekStart(t);
        return [
          for (var k = 0; k < 6; k++)
            PeriodOption(
              label: fmtSpan(addDays(thisStart, -7 * k), addDays(thisStart, -7 * k + 6)),
              note: k == 0 ? 'this week' : '',
              selected: sameDay(_weekStart(anchor), addDays(thisStart, -7 * k)),
              period: AnalyticsPeriod._(
                granularity: AnalyticsGranularity.week,
                anchor: k == 0 ? t : addDays(thisStart, -7 * k),
                firstDay: firstDay,
              ),
            ),
        ];
      case AnalyticsGranularity.month:
        return [
          for (var k = 0; k < 8; k++)
            () {
              final m = addMonths(monthStart(t), -k);
              return PeriodOption(
                label: '${_monthFull[m.month - 1]} ${m.year}',
                selected: sameMonth(m, anchor),
                period: AnalyticsPeriod.monthShown(m, today: t, firstDay: firstDay),
              );
            }(),
        ];
      case AnalyticsGranularity.year:
        final firstYear = (first ?? t).year - 1;
        return [
          for (var y = t.year; y >= firstYear; y--)
            PeriodOption(
              label: '$y',
              selected: anchor.year == y,
              period: AnalyticsPeriod.year(y, today: t, firstDay: firstDay),
            ),
        ];
      case AnalyticsGranularity.all:
      case AnalyticsGranularity.custom:
        return const [];
    }
  }

  // ---- stepping (‹ › and swipe) ---------------------------------------------

  bool get _steppable => switch (granularity) {
    AnalyticsGranularity.day ||
    AnalyticsGranularity.week ||
    AnalyticsGranularity.month ||
    AnalyticsGranularity.year ||
    AnalyticsGranularity.all => true,
    _ => false,
  };

  /// The first year of the All-time block this period shows.
  int allTimeBlockFirstYear(DateTime today) => allTimeBlockStartAt(today, blockBack);

  /// Previous. Month stops a year before the first transaction; All time only
  /// while a transaction exists before the shown block (nothing exists before
  /// 2026, so the first block cannot step back).
  bool canStepBack({required DateTime today, DateTime? first}) {
    if (!_steppable) return false;
    if (granularity == AnalyticsGranularity.month) {
      final floor = monthStart(addMonths(first ?? today, -12));
      return monthStart(anchor).isAfter(floor);
    }
    if (granularity == AnalyticsGranularity.all) {
      return first != null && first.year < allTimeBlockFirstYear(dateOnly(today));
    }
    return true;
  }

  /// Next is disabled at the present (All time: on the block holding today).
  bool canStepForward({required DateTime today}) {
    if (!_steppable) return false;
    final t = dateOnly(today);
    if (granularity == AnalyticsGranularity.month) return monthStart(anchor).isBefore(monthStart(t));
    if (granularity == AnalyticsGranularity.all) return blockBack < 0;
    return range(today: t).end.isBefore(t);
  }

  /// One step earlier (-1) or later (+1): a day, a calendar week, a month, a
  /// year, or (All time) a five-year block. Never steps past today.
  AnalyticsPeriod step(int dir, {required DateTime today}) {
    final t = dateOnly(today);
    var a = anchor;
    var back = blockBack;
    switch (granularity) {
      case AnalyticsGranularity.day:
        a = addDays(a, dir);
      case AnalyticsGranularity.week:
        a = addDays(a, 7 * dir);
      case AnalyticsGranularity.month:
        a = addMonths(a, dir);
        if (a.isAfter(monthStart(t))) a = monthStart(t);
      case AnalyticsGranularity.year:
        a = DateTime(a.year + dir, 1, 1);
      case AnalyticsGranularity.all:
        back = math.min(0, back + dir);
      case AnalyticsGranularity.custom:
        return this;
    }
    if (granularity != AnalyticsGranularity.month && a.isAfter(t)) a = t;
    if (granularity == AnalyticsGranularity.year && a.year == t.year) a = t;
    return AnalyticsPeriod._(granularity: granularity, anchor: a, custom: custom, blockBack: back, firstDay: firstDay);
  }

  /// Pull to refresh: the WHOLE current calendar period of the same length.
  /// Day → today, Week → the whole current calendar week (its label shows
  /// the whole week; data stops at today), Month → this month, Year → this
  /// year, Custom of N days → the last N days ending today; All time stays
  /// as it is.
  AnalyticsPeriod backToNow({required DateTime today}) {
    final t = dateOnly(today);
    if (granularity == AnalyticsGranularity.custom && custom != null) {
      final n = custom!.days;
      return AnalyticsPeriod.custom(addDays(t, -(n - 1)), t, today: t, firstDay: firstDay);
    }
    return AnalyticsPeriod._(granularity: granularity, anchor: t, custom: custom, firstDay: firstDay);
  }

  // ---- chart buckets (the mock's `buckets()`) --------------------------------

  /// The chart's bars for this period. [now] is the current time (Day's
  /// future blocks); [party] = T21's Parties entry (always all time, by month,
  /// no tap-through). [monthStyle] and [yearAmounts] are the two S6b
  /// preferences (Month by weeks or days; Year quarter totals or monthly
  /// amounts).
  ChartSpec chart({
    required DateTime now,
    DateTime? first,
    bool party = false,
    MonthChartStyle monthStyle = MonthChartStyle.weeks,
    YearViewAmounts yearAmounts = YearViewAmounts.quarters,
  }) {
    final t = dateOnly(now);
    final g = party ? AnalyticsGranularity.all : granularity;
    final out = <ChartBucket>[];
    final a = anchor;

    if (g == AnalyticsGranularity.day) {
      const labels = ['12a', '4a', '8a', '12p', '4p', '8p'];
      for (var k = 0; k < 6; k++) {
        final s = DateTime(a.year, a.month, a.day, 4 * k);
        final e = DateTime(a.year, a.month, a.day, 4 * k + 4).subtract(const Duration(milliseconds: 1));
        out.add(
          ChartBucket(
            label: labels[k],
            startMs: s.millisecondsSinceEpoch,
            endMs: e.millisecondsSinceEpoch,
            future: sameDay(a, t) && k * 4 > now.hour,
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By time of day',
        hint: 'Swipe for the day before',
        showAverage: false,
        labelSelected: false,
      );
    }

    if (g == AnalyticsGranularity.week) {
      // The whole calendar week, first day first; days after today are
      // drawn faded and hold no data.
      final weekStart = _weekStart(a);
      for (var k = 0; k < 7; k++) {
        final d = addDays(weekStart, k);
        final (s, e) = _dayMs(d);
        out.add(
          ChartBucket(
            label: weekdayShort(d).substring(0, 2),
            sub: d.day == 1 ? monthShort(d) : '${d.day}',
            startMs: s,
            endMs: e,
            future: d.isAfter(t),
            target: AnalyticsPeriod.day(d, firstDay: firstDay),
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By day',
        hint: 'Tap a day to open it · swipe for other weeks',
        showAverage: true,
        labelSelected: false,
        futureStubs: true,
      );
    }

    if (g == AnalyticsGranularity.month) {
      // One month only (M10): by calendar weeks cut at the month edges, or
      // by days. Never the days of another month.
      final ms = monthStart(a);
      final me = monthLastDay(a);
      if (monthStyle == MonthChartStyle.days) {
        for (var k = 1; k <= me.day; k++) {
          final d = DateTime(ms.year, ms.month, k);
          final (s, e) = _dayMs(d);
          out.add(
            ChartBucket(
              label: monthDayLabel(k, me.day),
              startMs: s,
              endMs: e,
              future: d.isAfter(t),
              name: '${weekdayShort(d)} ${fmtDayMonth(d)}',
              target: AnalyticsPeriod.day(d, firstDay: firstDay),
              tipLines: (cents) => dayTipLines(d, cents),
            ),
          );
        }
        return ChartSpec(
          buckets: out,
          title: 'By day',
          hint: 'Tap a day for its amount, tap again to open it · swipe for other months',
          showAverage: true,
          labelSelected: false,
          futureStubs: true,
        );
      }
      final segments = monthWeekSegments(ms, firstDay: firstDay);
      for (final seg in segments) {
        final (s, e) = _rangeMs(seg.start, seg.end);
        out.add(
          ChartBucket(
            label: seg.rangeLabel,
            sub: seg.part ? seg.daysLabel : '',
            startMs: s,
            endMs: e,
            part: seg.part,
            future: seg.start.isAfter(t),
            name: weekSegmentName(seg),
            target: AnalyticsPeriod._(granularity: AnalyticsGranularity.week, anchor: seg.start, firstDay: firstDay),
            tipLines: (cents) => weekTipLines(seg, cents, t),
            cross: seg.crossLine,
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By week of the month',
        hint: 'Tap a segment for its total and daily average, tap again to open the week',
        showAverage: false,
        labelSelected: false,
        futureStubs: true,
        legend: segments.any((x) => x.part) ? 'Striped bar = part week (fewer than 7 days in this month)' : '',
      );
    }

    if (g == AnalyticsGranularity.year) {
      for (var m = 1; m <= 12; m++) {
        final d = DateTime(a.year, m, 1);
        final (s, e) = _rangeMs(d, monthLastDay(d));
        out.add(
          ChartBucket(
            label: _mon[m - 1][0],
            startMs: s,
            endMs: e,
            future: d.isAfter(t),
            name: _monthFull[m - 1],
            target: AnalyticsPeriod.month(d, firstDay: firstDay),
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By month',
        hint: 'Tap a month to open it',
        showAverage: false,
        labelSelected: false,
        under: yearAmounts == YearViewAmounts.months ? ChartUnder.months : ChartUnder.quarters,
      );
    }

    if (g == AnalyticsGranularity.all && !party) {
      // Five-year blocks that follow the digits (2021-2025, 2026-2030, ...):
      // five year bars, data only, no comparison between blocks.
      final s0 = allTimeBlockStartAt(t, blockBack);
      final firstYear = (first ?? t).year;
      for (var k = 0; k < 5; k++) {
        final y = s0 + k;
        final (s, e) = _rangeMs(DateTime(y, 1, 1), DateTime(y, 12, 31));
        // Only years that can hold data (the first transaction's year up to
        // this year) are tappable.
        final empty = y < firstYear || y > t.year;
        out.add(
          ChartBucket(
            label: '$y',
            startMs: s,
            endMs: e,
            future: empty,
            name: '$y',
            target: AnalyticsPeriod.year(y, today: t, firstDay: firstDay),
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By year, $s0 to ${s0 + 4}',
        hint: 'Tap a year with data to open it',
        showAverage: false,
        labelSelected: false,
        futureStubs: true,
      );
    }

    if (g == AnalyticsGranularity.all) {
      // The Paid to recipient view: all time, by month (by year past two
      // years), no tap-through.
      final f = _minDay(first ?? t, t);
      final months = (t.year - f.year) * 12 + t.month - f.month + 1;
      if (months > 24) {
        for (var y = f.year; y <= t.year; y++) {
          final (s, e) = _rangeMs(DateTime(y, 1, 1), DateTime(y, 12, 31));
          out.add(ChartBucket(label: "'${'$y'.substring(2)}", startMs: s, endMs: e));
        }
        return ChartSpec(buckets: out, title: 'By year', hint: '', showAverage: false, labelSelected: false);
      }
      final n = math.max(months, 6);
      for (var k = n - 1; k >= 0; k--) {
        final m = addMonths(monthStart(t), -k);
        final before = m.isBefore(monthStart(f));
        final (s, e) = _rangeMs(m, monthLastDay(m));
        out.add(ChartBucket(label: monthShort(m), startMs: s, endMs: e, selected: !before, future: before));
      }
      return ChartSpec(buckets: out, title: 'By month · all time', hint: '', showAverage: false, labelSelected: false);
    }

    // Custom: per day up to 31 days, per calendar-week block beyond (the
    // first and last block clipped to the chosen dates).
    final r = range(today: t, first: first);
    final days = r.days;
    if (days <= 31) {
      for (var i = 0; i < days; i++) {
        final d = addDays(r.start, i);
        final (s, e) = _dayMs(d);
        out.add(
          ChartBucket(
            label: days > 10 ? (d.day % 5 == 0 ? '${d.day}' : '') : weekdayShort(d).substring(0, 2),
            startMs: s,
            endMs: e,
            target: AnalyticsPeriod.day(d, firstDay: firstDay),
          ),
        );
      }
      return ChartSpec(buckets: out, title: 'By day', hint: 'Tap a day to open it', showAverage: true, labelSelected: false);
    }
    final blocks = customWeekBlocks(r.start, r.end, firstDay: firstDay);
    for (final blk in blocks) {
      final (s, e) = _rangeMs(blk.start, blk.end);
      out.add(
        ChartBucket(
          label: '${blk.start.day}',
          sub: blk.part ? '${blk.days}d' : '',
          startMs: s,
          endMs: e,
          part: blk.part,
          name: '${fmtDayMonth(blk.start)} to ${fmtDayMonth(blk.end)}',
        ),
      );
    }
    return ChartSpec(
      buckets: out,
      title: 'By week',
      hint: '',
      showAverage: true,
      labelSelected: false,
      legend: blocks.any((x) => x.part) ? 'Striped bar = part week (fewer than 7 days in this period)' : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPeriod &&
      other.granularity == granularity &&
      other.anchor == anchor &&
      other.custom == custom &&
      other.blockBack == blockBack &&
      other.firstDay == firstDay;

  @override
  int get hashCode => Object.hash(granularity, anchor, custom, blockBack, firstDay);

  @override
  String toString() => 'AnalyticsPeriod($granularity, $anchor, custom: $custom, blockBack: $blockBack)';
}

// ---- chart value helpers ------------------------------------------------------

/// The y-axis top: the smallest of 1, 2, 3, 4, 5, 6, 8, 10 × 10^k that is
/// at least [max] (the mock's `nice`). [max] is in Ksh and at least 1.
double niceAxisMax(double max) {
  final m = math.max(max, 1.0);
  final p = math.pow(10, (math.log(m) / math.ln10).floor()).toDouble();
  for (final k in const [1, 2, 3, 4, 5, 6, 8, 10]) {
    if (k * p >= m - 1e-9) return k * p;
  }
  return 10 * p;
}

/// Short axis labels: 1500 → "1.5k", 2000 → "2k", 750 → "750" (the mock's
/// `kshShort`). [ksh] is in Ksh.
String kshShort(double ksh) {
  if (ksh >= 1000) {
    final whole = ksh % 1000 == 0;
    return '${(ksh / 1000).toStringAsFixed(whole ? 0 : 1)}k';
  }
  return ksh == ksh.roundToDouble() ? '${ksh.round()}' : '$ksh';
}

/// One "Where it went" row: spending under one classification NAME.
class NamedSpend {
  const NamedSpend({required this.name, required this.cents, required this.count});

  final String name;
  final int cents;
  final int count;
}

/// Groups spending by classification name — so "Shopping" under Paybill and
/// "Shopping" under Buy Goods are one row — largest first (ties by name).
List<NamedSpend> groupSpendByName(Iterable<(String name, int cents)> rows) {
  final cents = <String, int>{};
  final count = <String, int>{};
  for (final (name, c) in rows) {
    cents[name] = (cents[name] ?? 0) + c;
    count[name] = (count[name] ?? 0) + 1;
  }
  final out = [for (final n in cents.keys) NamedSpend(name: n, cents: cents[n]!, count: count[n]!)];
  out.sort((a, b) {
    final c = b.cents.compareTo(a.cents);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return out;
}
