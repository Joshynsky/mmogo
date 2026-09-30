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
/// All dates here are calendar days (local midnight). "Week" is a rolling
/// 7 days ending on the anchor, like Home's "This week" — never Mon–Sun.
///
/// Pure and DB-free: every method takes "today" (and, where it matters, the
/// first transaction's day) as an argument. Tested in
/// `test/domain/analytics/analytics_period_test.dart`.
library;

import 'dart:math' as math;

import '../period_math.dart' as period_math;

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
  });

  final String label;
  final int startMs;
  final int endMs;

  /// `false` = drawn dimmed (the months around the chosen one on Month, the
  /// months before the first transaction on All time).
  final bool selected;

  /// Faded, never tappable (a future block/month, or before the start).
  final bool future;

  final AnalyticsPeriod? target;

  bool get tappable => target != null && !future;

  bool contains(int ms) => ms >= startMs && ms <= endMs;
}

class ChartSpec {
  const ChartSpec({
    required this.buckets,
    required this.title,
    required this.hint,
    required this.showAverage,
    required this.labelSelected,
  });

  final List<ChartBucket> buckets;
  final String title;
  final String hint;

  /// The dashed daily-average line (Week and Custom only).
  final bool showAverage;

  /// Month: the chosen month's bar is labelled with its value and its axis
  /// label is bold.
  final bool labelSelected;
}

(int, int) _dayMs(DateTime d) => period_math.dayBounds(d);
(int, int) _rangeMs(DateTime s, DateTime e) => (_dayMs(s).$1, _dayMs(e).$2);

/// Immutable period state. Every transition returns a new instance.
class AnalyticsPeriod {
  AnalyticsPeriod._({required this.granularity, required DateTime anchor, this.custom, DateTime? monthWindowEnd})
    : anchor = dateOnly(anchor),
      monthWindowEnd = monthWindowEnd == null ? null : monthStart(monthWindowEnd);

  final AnalyticsGranularity granularity;

  /// Week: the last day of the rolling 7 days. Day/Month/Year: any day
  /// inside that day/month/year.
  final DateTime anchor;

  /// Custom only: the chosen days.
  final DayRange? custom;

  /// Month only: the newest month of the chart's 6-month window (`null` =
  /// the current month).
  final DateTime? monthWindowEnd;

  /// The nav-bar default: the last 7 days ending today.
  factory AnalyticsPeriod.lastSevenDays(DateTime today) =>
      AnalyticsPeriod._(granularity: AnalyticsGranularity.week, anchor: today);

  /// One day (Home's row hand-off, a Week/Custom bar tap, the Day menu).
  factory AnalyticsPeriod.day(DateTime day) => AnalyticsPeriod._(granularity: AnalyticsGranularity.day, anchor: day);

  factory AnalyticsPeriod.month(DateTime anyDay) =>
      AnalyticsPeriod._(granularity: AnalyticsGranularity.month, anchor: monthStart(anyDay));

  /// One month as the Month menu picks it: the chart's 6-month window is
  /// moved so [anyDay]'s month is on it (the window ends 2 months later, or
  /// at the current month). Used by the menu and by Paid to's hand-off (T22).
  factory AnalyticsPeriod.monthShown(DateTime anyDay, {required DateTime today}) {
    final m = monthStart(anyDay);
    final windowEnd = addMonths(m, 2);
    return AnalyticsPeriod._(
      granularity: AnalyticsGranularity.month,
      anchor: m,
      monthWindowEnd: windowEnd.isAfter(monthStart(today)) ? null : windowEnd,
    );
  }

  factory AnalyticsPeriod.year(int year, {required DateTime today}) => AnalyticsPeriod._(
    granularity: AnalyticsGranularity.year,
    anchor: year == today.year ? today : DateTime(year, 1, 1),
  );

  factory AnalyticsPeriod.allTime(DateTime today) =>
      AnalyticsPeriod._(granularity: AnalyticsGranularity.all, anchor: today);

  /// The Custom sheet's "Show": swapped dates are put in order and both are
  /// clamped to today.
  factory AnalyticsPeriod.custom(DateTime from, DateTime to, {required DateTime today}) {
    var a = dateOnly(from);
    var b = dateOnly(to);
    if (a.isAfter(b)) (a, b) = (b, a);
    final t = dateOnly(today);
    if (b.isAfter(t)) b = t;
    if (a.isAfter(b)) a = b;
    return AnalyticsPeriod._(granularity: AnalyticsGranularity.custom, anchor: b, custom: DayRange(a, b));
  }

  AnalyticsPeriod _copy({DateTime? anchor, DateTime? monthWindowEnd, bool clearWindow = false}) => AnalyticsPeriod._(
    granularity: granularity,
    anchor: anchor ?? this.anchor,
    custom: custom,
    monthWindowEnd: clearWindow ? null : (monthWindowEnd ?? this.monthWindowEnd),
  );

  // ---- range ---------------------------------------------------------------

  /// The days this period covers. [first] is the first transaction's day
  /// (All time starts there; `null` = no transactions = today).
  DayRange range({required DateTime today, DateTime? first}) {
    final a = anchor;
    return switch (granularity) {
      AnalyticsGranularity.day => DayRange(a, a),
      AnalyticsGranularity.week => DayRange(addDays(a, -6), a),
      AnalyticsGranularity.month => DayRange(monthStart(a), monthLastDay(a)),
      AnalyticsGranularity.year => DayRange(DateTime(a.year, 1, 1), DateTime(a.year, 12, 31)),
      AnalyticsGranularity.all => DayRange(_minDay(first ?? today, today), today),
      AnalyticsGranularity.custom => custom ?? DayRange(addDays(a, -6), a),
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
          spent: sameDay(e, t) ? 'Spent in the last 7 days' : 'Spent that week',
          vs: 'vs prior week',
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
  AnalyticsPeriod withGranularity(AnalyticsGranularity g, {required DateTime today, DateTime? first}) {
    final r = range(today: today, first: first);
    final end = _minDay(r.end, dateOnly(today));
    return AnalyticsPeriod._(granularity: g, anchor: g == AnalyticsGranularity.month ? monthStart(end) : end);
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
              period: AnalyticsPeriod.day(addDays(t, -k)),
            ),
        ];
      case AnalyticsGranularity.week:
        return [
          for (var k = 0; k < 6; k++)
            PeriodOption(
              label: '${fmtDayMonth(addDays(t, -7 * k - 6))} – ${fmtDayMonth(addDays(t, -7 * k))}',
              note: k == 0 ? 'last 7 days' : '',
              selected: sameDay(addDays(t, -7 * k), anchor),
              period: AnalyticsPeriod._(granularity: AnalyticsGranularity.week, anchor: addDays(t, -7 * k)),
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
                period: AnalyticsPeriod.monthShown(m, today: t),
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
              period: AnalyticsPeriod.year(y, today: t),
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
    AnalyticsGranularity.year => true,
    _ => false,
  };

  DateTime _windowEnd(DateTime today) => monthWindowEnd ?? monthStart(today);

  bool canStepBack({required DateTime today, DateTime? first}) {
    if (!_steppable) return false;
    if (granularity == AnalyticsGranularity.month) {
      final floor = monthStart(addMonths(first ?? today, -12));
      return addMonths(_windowEnd(today), -5).isAfter(floor);
    }
    return true;
  }

  /// Next is disabled at the present.
  bool canStepForward({required DateTime today}) {
    if (!_steppable) return false;
    final t = dateOnly(today);
    if (granularity == AnalyticsGranularity.month) return !sameMonth(_windowEnd(t), t);
    return range(today: t).end.isBefore(t);
  }

  /// One step earlier (-1) or later (+1). Month pages the 6-month window;
  /// the chosen month follows the window's edge if it would drop off. Never
  /// steps past today.
  AnalyticsPeriod step(int dir, {required DateTime today}) {
    final t = dateOnly(today);
    var a = anchor;
    DateTime? windowEnd = monthWindowEnd;
    switch (granularity) {
      case AnalyticsGranularity.day:
        a = addDays(a, dir);
      case AnalyticsGranularity.week:
        a = addDays(a, 7 * dir);
      case AnalyticsGranularity.month:
        final end = addMonths(_windowEnd(t), dir);
        windowEnd = end.isAfter(monthStart(t)) ? monthStart(t) : end;
        final start = addMonths(windowEnd, -5);
        if (a.isBefore(start)) a = start;
        if (a.isAfter(monthLastDay(windowEnd))) a = windowEnd;
      case AnalyticsGranularity.year:
        a = DateTime(a.year + dir, 1, 1);
      case AnalyticsGranularity.all:
      case AnalyticsGranularity.custom:
        return this;
    }
    if (granularity != AnalyticsGranularity.month && a.isAfter(t)) a = t;
    if (granularity == AnalyticsGranularity.year && a.year == t.year) a = t;
    return AnalyticsPeriod._(granularity: granularity, anchor: a, custom: custom, monthWindowEnd: windowEnd);
  }

  /// Pull to refresh: the current period of the same length. Day → today,
  /// Week → the last 7 days, Month → this month, Year → this year, Custom of
  /// N days → the last N days ending today; All time stays as it is.
  AnalyticsPeriod backToNow({required DateTime today}) {
    final t = dateOnly(today);
    if (granularity == AnalyticsGranularity.custom && custom != null) {
      final n = custom!.days;
      return AnalyticsPeriod.custom(addDays(t, -(n - 1)), t, today: t);
    }
    return AnalyticsPeriod._(granularity: granularity, anchor: t, custom: custom);
  }

  // ---- chart buckets (the mock's `buckets()`) --------------------------------

  /// The chart's bars for this period. [now] is the current time (Day's
  /// future blocks); [party] = T21's Parties entry (always all time, by month,
  /// no tap-through).
  ChartSpec chart({required DateTime now, DateTime? first, bool party = false}) {
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
      for (var k = 6; k >= 0; k--) {
        final d = addDays(a, -k);
        final (s, e) = _dayMs(d);
        out.add(
          ChartBucket(
            label: weekdayShort(d).substring(0, 2),
            startMs: s,
            endMs: e,
            future: d.isAfter(t),
            target: AnalyticsPeriod.day(d),
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By day',
        hint: 'Tap a day to open it · swipe for other weeks',
        showAverage: true,
        labelSelected: false,
      );
    }

    if (g == AnalyticsGranularity.month) {
      final end = _windowEnd(t);
      for (var k = 5; k >= 0; k--) {
        final m = addMonths(end, -k);
        final (s, e) = _rangeMs(m, monthLastDay(m));
        out.add(
          ChartBucket(
            label: monthShort(m),
            startMs: s,
            endMs: e,
            selected: sameMonth(m, a),
            future: m.isAfter(t),
            target: _copy(anchor: m),
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By month',
        hint: 'Tap a month to pick it · swipe for earlier months',
        showAverage: false,
        labelSelected: true,
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
            target: AnalyticsPeriod.month(d),
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By month',
        hint: 'Tap a month to open it',
        showAverage: false,
        labelSelected: false,
      );
    }

    if (g == AnalyticsGranularity.all) {
      final f = _minDay(first ?? t, t);
      final months = (t.year - f.year) * 12 + t.month - f.month + 1;
      if (months > 24) {
        for (var y = f.year; y <= t.year; y++) {
          final (s, e) = _rangeMs(DateTime(y, 1, 1), DateTime(y, 12, 31));
          out.add(
            ChartBucket(
              label: "'${'$y'.substring(2)}",
              startMs: s,
              endMs: e,
              target: party ? null : AnalyticsPeriod.year(y, today: t),
            ),
          );
        }
        return ChartSpec(
          buckets: out,
          title: 'By year',
          hint: party ? '' : 'Tap a year to open it',
          showAverage: false,
          labelSelected: false,
        );
      }
      final n = math.max(months, 6);
      for (var k = n - 1; k >= 0; k--) {
        final m = addMonths(monthStart(t), -k);
        final before = m.isBefore(monthStart(f));
        final (s, e) = _rangeMs(m, monthLastDay(m));
        out.add(
          ChartBucket(
            label: monthShort(m),
            startMs: s,
            endMs: e,
            selected: !before,
            future: before,
            target: party ? null : AnalyticsPeriod.month(m),
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: party ? 'By month · all time' : 'By month since you started',
        hint: party ? '' : 'Tap a month to open it',
        showAverage: false,
        labelSelected: false,
      );
    }

    // Custom: per day up to 31 days, per 7-day block beyond.
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
            target: AnalyticsPeriod.day(d),
          ),
        );
      }
      return ChartSpec(
        buckets: out,
        title: 'By day',
        hint: 'Tap a day to open it',
        showAverage: true,
        labelSelected: false,
      );
    }
    for (var d = r.start; !d.isAfter(r.end); d = addDays(d, 7)) {
      final last = addDays(d, 6).isAfter(r.end) ? r.end : addDays(d, 6);
      final (s, e) = _rangeMs(d, last);
      out.add(ChartBucket(label: '${d.day}', startMs: s, endMs: e));
    }
    return ChartSpec(buckets: out, title: 'By week', hint: '', showAverage: true, labelSelected: false);
  }

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPeriod &&
      other.granularity == granularity &&
      other.anchor == anchor &&
      other.custom == custom &&
      other.monthWindowEnd == monthWindowEnd;

  @override
  int get hashCode => Object.hash(granularity, anchor, custom, monthWindowEnd);

  @override
  String toString() => 'AnalyticsPeriod($granularity, $anchor, custom: $custom, window: $monthWindowEnd)';
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
