import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/home/home_period.dart';

/// §ANALYTICS.ARGS — the route-argument contract and the Home <-> Analytics
/// period mapping (F6).
///
/// Route-argument contract for Analytics' deep-link modes. Paid to (T22, formerly Parties/T15) is its caller:
///  - `type` + `partyKey`: one recipient (the party header card), on
///    [period] (Paid to's period; all time when `null`) with the
///    [classification] filter on when given. The period pill stays visible
///    and stepping is allowed (T22; T21 forced all time with no pill);
///  - `type` alone: an unnamed (classification-fallback) row — [period]
///    with the [classification] filter on (else that type's filter), the F8
///    type shortcut, now period-scoped.
///
/// Home's recent-transaction tap passes a plain `int` (transaction id)
/// instead; `AnalyticsScreen` accepts both shapes, see
/// [AnalyticsResolvedArgs.resolve].
class AnalyticsRouteArgs {
  const AnalyticsRouteArgs({required this.type, this.partyKey, this.partyName, this.period, this.classification});

  /// `'SEND_MONEY' | 'BUY_GOODS' | 'PAYBILL' | 'CASH'`.
  final String type;

  /// The resolved `counterparty_key` (`deriveCounterpartyKey`, the single
  /// authoritative derivation). `null` = type-only mode.
  final String? partyKey;

  /// The recipient's display name for the party card (T22), so it survives
  /// stepping to a period with no payments to them. `null` = taken from the
  /// first row, as in T21.
  final String? partyName;

  /// The period to open on (T22: Paid to's Month / Year / All time, same
  /// anchor). `null` = All time.
  final AnalyticsPeriod? period;

  /// A classification name to filter on (T22: Paid to's active category, or
  /// an unnamed row's classification). `null` = none.
  final String? classification;
}

class AnalyticsResolvedArgs {
  const AnalyticsResolvedArgs({
    this.highlightTransactionId,
    this.type,
    this.partyKey,
    this.partyName,
    this.period,
    this.classification,
  });

  final int? highlightTransactionId;
  final String? type;
  final String? partyKey;
  final String? partyName;
  final AnalyticsPeriod? period;
  final String? classification;

  static AnalyticsResolvedArgs resolve(Object? raw) {
    if (raw is int) return AnalyticsResolvedArgs(highlightTransactionId: raw);
    if (raw is AnalyticsRouteArgs) {
      return AnalyticsResolvedArgs(
        type: raw.type,
        partyKey: raw.partyKey,
        partyName: raw.partyName,
        period: raw.period,
        classification: raw.classification,
      );
    }
    // Unknown (or no) argument: a plain nav-bar visit, never a crash.
    return const AnalyticsResolvedArgs();
  }
}

/// F6: Home's period -> Analytics' (Today -> Day today, This week -> the
/// last 7 days, This month -> this month).
AnalyticsPeriod analyticsPeriodForHome(HomePeriod p, DateTime today) => switch (p) {
  HomePeriod.today => AnalyticsPeriod.day(today),
  HomePeriod.week => AnalyticsPeriod.lastSevenDays(today),
  HomePeriod.month => AnalyticsPeriod.month(today),
};

/// F6: Analytics' length -> Home's; `null` for Year, All time and Custom
/// (Home unchanged).
HomePeriod? homePeriodForAnalytics(AnalyticsGranularity g) => switch (g) {
  AnalyticsGranularity.day => HomePeriod.today,
  AnalyticsGranularity.week => HomePeriod.week,
  AnalyticsGranularity.month => HomePeriod.month,
  _ => null,
};
