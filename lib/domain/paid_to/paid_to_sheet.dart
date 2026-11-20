/// §DOMAIN.PAID_TO.SHEET — the figures of Paid to's recipient sheet (0.1.2 S7b,
/// PT1; the signed mock `paidto.html`: `openRecipient`, `buckets`, `compact`).
///
/// Pure: one recipient's payments (already limited to the shown period and the
/// category filter, so every figure equals the row) become the 2x2 grid, the
/// first / last dates, the bar chart and the BY CATEGORY rows.
library;

import '../analytics/analytics_period.dart';
import 'paid_to.dart';

/// One bar: its axis [label] ('' = none drawn) and its [cents].
///
/// [segments] (0.2.1 #4): for a Paybill name with several accounts, the bar's cents split by
/// account as (account index in `PaidToRecipient.accounts`, cents), lowest index first; empty
/// otherwise. [pad] = an empty slot added in front so the last window is full. [month] = the first
/// day of a month bar's month (null for a 7-day block), used for a window's range words.
class PaidToBar {
  const PaidToBar(this.label, this.cents, {this.segments = const [], this.pad = false, this.month});

  final String label;
  final int cents;
  final List<(int, int)> segments;
  final bool pad;
  final DateTime? month;
}

/// 0.2.1 #4 (MK-12): months per window in the swipeable All time chart ("about a quarter").
const int paidToChartWindow = 4;

/// One BY CATEGORY row.
class PaidToCategoryRow {
  const PaidToCategoryRow(this.name, this.count, this.cents);

  final String name;
  final int count;
  final int cents;
}

/// The recipient sheet's numbers.
class PaidToSheetData {
  const PaidToSheetData({
    required this.totalCents,
    required this.count,
    required this.averageCents,
    required this.feeCents,
    required this.first,
    required this.last,
    required this.perWeek,
    required this.bars,
    required this.valueLabels,
    required this.categories,
    this.window = 0,
  });

  final int totalCents;
  final int count;
  final int averageCents;
  final int feeCents;
  final DateTime first;
  final DateTime last;

  /// Month: one bar per 7-day block (PER 7 DAYS); Year and All time: one bar per month (PER MONTH).
  final bool perWeek;
  final List<PaidToBar> bars;

  /// Value labels over the bars only when there are 12 bars or fewer (a swipeable window always has them).
  final bool valueLabels;

  /// Largest total first.
  final List<PaidToCategoryRow> categories;

  /// 0.2.1 #4: bars per swipeable window ([paidToChartWindow]) when All time has more months than
  /// one window holds; 0 = the chart does not scroll. The bar count is then a multiple of it.
  final int window;
}

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Mock `compact`: whole shillings, "1.2k" from 1,000 up ("1k", not "1.0k").
String paidToCompact(int cents) {
  final v = (cents / 100).round();
  if (v < 1000) return '$v';
  final k = ((v / 100).round() / 10).toString();
  return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k}k';
}

/// Mock `buckets`: Month = 7-day blocks (1-7, 8-14, ...); Year = one bar per month of [range];
/// with more than 12 months the axis names only every quarter ("Jan 26").
///
/// 0.2.1 #4 (MK-12): [allTime] = months in windows of [paidToChartWindow] (padded in front, the
/// first bar and every January named with the year). [accountIndex] (trimmed account -> index)
/// makes each bar carry per-account [PaidToBar.segments] for the stacked chart.
List<PaidToBar> paidToBars(
  Iterable<PaidToPayment> payments, {
  required DayRange range,
  required bool month,
  bool allTime = false,
  Map<String, int>? accountIndex,
}) {
  final cents = <int>[];
  final labels = <String>[];
  final months = <DateTime?>[];
  if (month) {
    final days = range.end.day;
    for (var s = 1; s <= days; s += 7) {
      labels.add('$s–${s + 6 < days ? s + 6 : days}');
      months.add(null);
      cents.add(0);
    }
  } else {
    final n = (range.end.year - range.start.year) * 12 + range.end.month - range.start.month + 1;
    for (var i = 0; i < n; i++) {
      final m = DateTime(range.start.year, range.start.month + i, 1);
      months.add(m);
      labels.add(
        allTime
            ? (i == 0 || m.month == 1 ? '${_mon[m.month - 1]} ${(m.year % 100).toString().padLeft(2, '0')}' : _mon[m.month - 1])
            : n <= 12
            ? _mon[m.month - 1]
            : (m.month - 1) % 3 == 0
            ? '${_mon[m.month - 1]} ${(m.year % 100).toString().padLeft(2, '0')}'
            : '',
      );
      cents.add(0);
    }
  }
  final seg = [for (var i = 0; i < cents.length; i++) <int, int>{}];
  for (final p in payments) {
    final d = p.occurredAt;
    final i = month ? (d.day - 1) ~/ 7 : (d.year - range.start.year) * 12 + d.month - range.start.month;
    if (i >= 0 && i < cents.length) {
      cents[i] += p.amountCents;
      final a = accountIndex?[(p.account ?? '').trim()];
      if (a != null) seg[i][a] = (seg[i][a] ?? 0) + p.amountCents;
    }
  }
  final bars = [
    for (var i = 0; i < cents.length; i++)
      PaidToBar(
        labels[i],
        cents[i],
        month: months[i],
        segments: [for (final k in (seg[i].keys.toList()..sort())) (k, seg[i][k]!)],
      ),
  ];
  if (allTime && bars.length > paidToChartWindow) {
    while (bars.length % paidToChartWindow != 0) {
      bars.insert(0, const PaidToBar('', 0, pad: true));
    }
  }
  return bars;
}

/// The sheet for [r] over [range] (the shown period's days); [month] = the Month length.
///
/// 0.2.1 #4: [allTime] = the All time length (the axis then starts at the name's first payment and
/// is windowed); [account] = an index into `r.accounts` (a Paybill name with several accounts):
/// every figure, the bars and BY CATEGORY then cover that account alone, while the axis stays the
/// same so choosing an account never moves the bars.
PaidToSheetData paidToSheetData(
  PaidToRecipient r, {
  required DayRange range,
  required bool month,
  bool allTime = false,
  int? account,
}) {
  final all = [...r.payments]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final accs = r.hasManyAccounts ? r.accounts : const <PaidToAccount>[];
  final chosen = account != null && account >= 0 && account < accs.length ? accs[account].account : null;
  final pays = chosen == null
      ? all
      : [
          for (final p in all)
            if ((p.account ?? '').trim() == chosen) p,
        ];
  final byMonths = allTime && !month;
  var axis = range;
  if (byMonths && all.isNotEmpty) {
    final last = all.last.occurredAt;
    axis = DayRange(all.first.occurredAt, range.end.isBefore(last) ? last : range.end);
  }
  final bars = paidToBars(
    pays,
    range: axis,
    month: month,
    allTime: byMonths,
    accountIndex: accs.isEmpty ? null : {for (final (i, a) in accs.indexed) a.account: i},
  );
  final windowed = byMonths && bars.length > paidToChartWindow;
  final cats = <String, (int, int)>{};
  var total = 0;
  var fee = 0;
  for (final p in pays) {
    final c = cats[p.classificationName] ?? (0, 0);
    cats[p.classificationName] = (c.$1 + 1, c.$2 + p.amountCents);
    total += p.amountCents;
    fee += p.feeCents;
  }
  final rows = [for (final e in cats.entries) PaidToCategoryRow(e.key, e.value.$1, e.value.$2)]
    ..sort((a, b) => b.cents != a.cents ? b.cents.compareTo(a.cents) : a.name.compareTo(b.name));
  return PaidToSheetData(
    totalCents: total,
    count: pays.length,
    averageCents: (total / pays.length).round(),
    feeCents: fee,
    first: pays.first.occurredAt,
    last: pays.last.occurredAt,
    perWeek: month,
    bars: bars,
    valueLabels: windowed || bars.length <= 12,
    categories: rows,
    window: windowed ? paidToChartWindow : 0,
  );
}
