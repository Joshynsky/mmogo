/// §DOMAIN.FULIZA.HOME_ROWS: what the Fuliza block on Home shows for the picked period. Pure: no widgets,
/// no storage, no clock (the caller passes the period's bounds, the same ones Home uses for its totals).
///
/// Up to two rows, neither of which is spending (the Home total and Transaction cost never read them):
///  - owing row: only while something is owed (or the balance is not known); always "now", never per period;
///  - cost row: only when a fee was charged inside the period (a repayment alone adds no cost row).
/// Nothing owed and no fee in the period: no rows, so no block.
/// WORDING-DRAFT: "Fuliza: owing", "Fuliza: owing about", "Fuliza: balance not known",
/// "Fuliza cost (estimated), today / this week / this month".
library;

import '../home/home_period.dart';
import 'fuliza_page_data.dart';

/// One label and, except for "balance not known", its figure.
class FulizaHomeRow {
  const FulizaHomeRow(this.label, [this.value]);
  final String label;
  final String? value;
}

class FulizaHomeRows {
  const FulizaHomeRows({this.owing, this.cost, this.costCents = 0});
  final FulizaHomeRow? owing;
  final FulizaHomeRow? cost;

  /// The fee total behind [cost] (0 when there is no cost row).
  final int costCents;

  /// One sentence for a screen reader.
  String get spoken => [
    for (final r in [owing, cost])
      if (r != null) r.value == null ? r.label : '${r.label} ${r.value}',
  ].join('. ');
}

/// The words that close the cost label for a Home period.
String fulizaPeriodWord(HomePeriod p) => switch (p) {
  HomePeriod.today => 'today',
  HomePeriod.week => 'this week',
  HomePeriod.month => 'this month',
};

/// THE DATE FILTER. Access fees plus estimated daily fees whose message time is inside
/// [startMs]..[endMs], both inclusive epoch milliseconds (the bounds Home already computes from the
/// local calendar). Each fee is dated by its own message, not by the spend it paid for. Over all time
/// this equals [FulizaPageData.costCents].
int fulizaCostBetween(FulizaPageData d, int startMs, int endMs) {
  var sum = 0;
  for (final f in d.feesAt) {
    final ms = f.at.millisecondsSinceEpoch;
    if (ms >= startMs && ms <= endMs) sum += f.cents;
  }
  return sum;
}

/// The rows for [d] over the period bounds, or null when there is nothing to show (no block).
/// [ksh] formats cents; [periodWord] comes from [fulizaPeriodWord].
FulizaHomeRows? fulizaHomeRows(
  FulizaPageData d,
  int startMs,
  int endMs,
  String periodWord,
  String Function(int cents) ksh,
) {
  FulizaHomeRow? owing;
  if (d.owingUnknown) {
    owing = const FulizaHomeRow('Fuliza: balance not known');
  } else if (!d.nothingOwed) {
    owing = FulizaHomeRow('Fuliza: owing${d.owingIsEstimate ? ' about' : ''}', ksh(d.owingCents!));
  }
  final cost = fulizaCostBetween(d, startMs, endMs);
  final costRow = cost > 0 ? FulizaHomeRow('Fuliza cost (estimated), $periodWord', ksh(cost)) : null;
  if (owing == null && costRow == null) return null;
  return FulizaHomeRows(owing: owing, cost: costRow, costCents: costRow == null ? 0 : cost);
}
