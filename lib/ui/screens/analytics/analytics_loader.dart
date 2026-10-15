import 'dart:math' as math;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/analytics/chart_blocks.dart' show MonthChartStyle, YearViewAmounts;
import '../../../domain/period_math.dart' show dayBounds;
import 'analytics_view.dart';
import 'format.dart';

/// §ANALYTICS.LOADER — one fetch, one [AnalyticsView] snapshot (moved out of analytics_screen.dart
/// by 0.1.2 S8c-3 step 0; the logic is unchanged). The fetch covers the
/// period, its prior period and every chart bar.
Future<AnalyticsView> loadAnalyticsView(
  Database db, {
  required AnalyticsPeriod period,
  required DateTime now,
  required DateTime today,
  required DateTime? first,
  required MonthChartStyle monthStyle,
  required YearViewAmounts yearAmounts,
  required bool showHatch,
  required String? partyType,
  required String? partyKey,
  required String? partyName,
}) async {
  final party = partyType != null && partyKey != null;
  final range = period.range(today: today, first: first);
  final prior = party ? null : period.priorRange(today: today, first: first);
  final chart = period.chart(now: now, first: first, monthStyle: monthStyle, yearAmounts: yearAmounts);

  var (startMs, endMs) = range.bounds;
  if (prior != null) {
    startMs = math.min(startMs, prior.bounds.$1);
    endMs = math.max(endMs, prior.bounds.$2);
  }
  for (final b in chart.buckets) {
    startMs = math.min(startMs, b.startMs);
    endMs = math.max(endMs, b.endMs);
  }
  // The week shows all seven days, but its data stops at the end of today.
  if (period.granularity == AnalyticsGranularity.week) endMs = math.min(endMs, dayBounds(today).$2);
  final rows = await AnalyticsDao.itemizedTransactions(
    db,
    startMs: startMs,
    endMs: endMs,
    types: AnalyticsDao.allTypes,
    partyType: partyType,
    partyKey: partyKey,
  );

  final (rs, re) = range.bounds;
  final inc = [
    for (final r in rows)
      if (r.occurredAt.millisecondsSinceEpoch >= rs && r.occurredAt.millisecondsSinceEpoch <= re) r,
  ];
  int? priorCents;
  if (prior != null) {
    final (ps, pe) = prior.bounds;
    priorCents = rows
        .where((r) => r.occurredAt.millisecondsSinceEpoch >= ps && r.occurredAt.millisecondsSinceEpoch <= pe)
        .fold<int>(0, (s, r) => s + r.spent);
  }
  final bucketCents = [
    for (final b in chart.buckets)
      [
        for (final (code, _) in analyticsTypeOrder)
          rows
              .where((r) => r.sourceType == code && b.contains(r.occurredAt.millisecondsSinceEpoch))
              .fold<int>(0, (s, r) => s + r.spent),
      ],
  ];

  return AnalyticsView(
    period: period,
    party: party,
    partyType: party ? partyType : null,
    now: now,
    first: first,
    range: range,
    inc: inc,
    priorCents: priorCents,
    chart: chart,
    bucketCents: bucketCents,
    partyName: party ? (partyName ?? (rows.isEmpty ? null : rows.first.displayName)) : null,
    hatchCents: withdrawnPerWindow([for (final b in chart.buckets) (b.startMs, b.endMs)], rows),
    showHatch: showHatch,
    cashOutCents: cashOutTotal(inc),
  );
}
