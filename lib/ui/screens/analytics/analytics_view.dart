import '../../../data/db/analytics_dao.dart';
import '../../../domain/analytics/analytics_period.dart';

/// §ANALYTICS.VIEW — everything one load derives from the data, for one
/// period. The screen renders from this snapshot, so the pill, the totals and
/// the chart always describe the same period (a new period appears once its
/// rows are in).
class AnalyticsView {
  AnalyticsView({
    required this.period,
    required this.party,
    required this.partyType,
    required this.now,
    required this.first,
    required this.range,
    required this.inc,
    required this.priorCents,
    required this.chart,
    required this.bucketCents,
    required this.partyName,
  });

  final AnalyticsPeriod period;
  final bool party;

  /// The party's type when [party] (F7: the card is built from this
  /// snapshot, never from state a handler may already have cleared).
  final String? partyType;
  final DateTime now;
  final DateTime? first;
  final DayRange range;

  /// The period's transactions (party-filtered), newest first.
  final List<AnalyticsTransactionRow> inc;

  /// The prior period's total; `null` when there is no prior (All time, the
  /// Paid to recipient view).
  final int? priorCents;

  final ChartSpec chart;

  /// Per bucket, per type (analyticsTypeOrder), in cents.
  final List<List<int>> bucketCents;

  final String? partyName;

  DateTime get today => dateOnly(now);

  int get totalCents => inc.fold(0, (s, r) => s + r.amountCents);
}

/// What Analytics looked like just before it entered the recipient (Paid to)
/// view; the
/// party card's close button puts it back (F5).
class AnalyticsBeforeParty {
  const AnalyticsBeforeParty({
    required this.period,
    required this.typeFilter,
    required this.classFilter,
    required this.whereTab,
    required this.showAllClasses,
    required this.scroll,
  });

  final AnalyticsPeriod period;
  final String? typeFilter;
  final String? classFilter;
  final bool whereTab;
  final bool showAllClasses;
  final double scroll;
}
