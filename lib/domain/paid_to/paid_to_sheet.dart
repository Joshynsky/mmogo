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
class PaidToBar {
  const PaidToBar(this.label, this.cents);

  final String label;
  final int cents;
}

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

  /// Value labels over the bars only when there are 12 bars or fewer (all-time over more than 12 months: none).
  final bool valueLabels;

  /// Largest total first.
  final List<PaidToCategoryRow> categories;
}

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Mock `compact`: whole shillings, "1.2k" from 1,000 up ("1k", not "1.0k").
String paidToCompact(int cents) {
  final v = (cents / 100).round();
  if (v < 1000) return '$v';
  final k = ((v / 100).round() / 10).toString();
  return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k}k';
}

/// Mock `buckets`: Month = 7-day blocks (1-7, 8-14, ...); Year / All time = one bar per month of
/// [range]; with more than 12 months the axis names only every quarter ("Jan 26").
List<PaidToBar> paidToBars(Iterable<PaidToPayment> payments, {required DayRange range, required bool month}) {
  final cents = <int>[];
  final labels = <String>[];
  if (month) {
    final days = range.end.day;
    for (var s = 1; s <= days; s += 7) {
      labels.add('$s–${s + 6 < days ? s + 6 : days}');
      cents.add(0);
    }
  } else {
    final n = (range.end.year - range.start.year) * 12 + range.end.month - range.start.month + 1;
    for (var i = 0; i < n; i++) {
      final m = DateTime(range.start.year, range.start.month + i, 1);
      labels.add(
        n <= 12
            ? _mon[m.month - 1]
            : (m.month - 1) % 3 == 0
            ? '${_mon[m.month - 1]} ${(m.year % 100).toString().padLeft(2, '0')}'
            : '',
      );
      cents.add(0);
    }
  }
  for (final p in payments) {
    final d = p.occurredAt;
    final i = month ? (d.day - 1) ~/ 7 : (d.year - range.start.year) * 12 + d.month - range.start.month;
    if (i >= 0 && i < cents.length) cents[i] += p.amountCents;
  }
  return [for (var i = 0; i < cents.length; i++) PaidToBar(labels[i], cents[i])];
}

/// The sheet for [r] over [range] (the shown period's days); [month] = the Month length.
PaidToSheetData paidToSheetData(PaidToRecipient r, {required DayRange range, required bool month}) {
  final pays = [...r.payments]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final bars = paidToBars(pays, range: range, month: month);
  final cats = <String, (int, int)>{};
  for (final p in pays) {
    final c = cats[p.classificationName] ?? (0, 0);
    cats[p.classificationName] = (c.$1 + 1, c.$2 + p.amountCents);
  }
  final rows = [for (final e in cats.entries) PaidToCategoryRow(e.key, e.value.$1, e.value.$2)]
    ..sort((a, b) => b.cents != a.cents ? b.cents.compareTo(a.cents) : a.name.compareTo(b.name));
  return PaidToSheetData(
    totalCents: r.totalCents,
    count: r.count,
    averageCents: (r.totalCents / r.count).round(),
    feeCents: r.feeCents,
    first: pays.first.occurredAt,
    last: pays.last.occurredAt,
    perWeek: month,
    bars: bars,
    valueLabels: bars.length <= 12,
    categories: rows,
  );
}
