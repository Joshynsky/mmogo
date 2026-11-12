/// §DOMAIN.FULIZA.PAGE — 0.2.0 S9: what the Fuliza page and the Home line show, built from the ledger's
/// [FulizaState] and the stored events. Pure: no widgets, no storage. Fuliza is a loan, so none of this
/// is spending; the Home headline never reads it.
///
/// The mock it follows: `global-mock/plugins/fuliza.js` (V3 Home line, the page with Taken / Repaid /
/// Fuliza cost, History by day, Related transactions, "estimated", "carried in", "owing unknown").
/// WORDING-DRAFT: every label in [fulizaHomeLineLabel] and the page widgets is a plain label for the PM to review.
library;

import 'fuliza_ledger.dart';
import 'fuliza_repository.dart';

/// One line of History: a borrowing or a repayment.
class FulizaHistoryEntry {
  const FulizaHistoryEntry({
    required this.event,
    required this.paired,
    required this.owingAfterCents,
    required this.dailyFeeSeenCents,
    required this.needsReview,
  });

  final FulizaEvent event;
  bool get isDraw => event.kind == FulizaEventKind.draw;
  bool get isFullRepayment => event.kind == FulizaEventKind.repayFull;

  /// A draw with an ordinary payment of the same code (the spend it paid for).
  final bool paired;

  /// "owing X" after this line: the printed total on a draw, 0 on a full repayment, null on a partial one.
  final int? owingAfterCents;

  /// A draw only: the extra since the last message when it is a daily fee (estimated), else 0.
  final int dailyFeeSeenCents;

  /// The printed total did not add up and no later partial explains it: shown, not hidden.
  final bool needsReview;
}

/// One calendar day of History.
class FulizaDay {
  FulizaDay(this.day);

  final DateTime day;
  final List<FulizaHistoryEntry> entries = [];
  int borrowedCents = 0;
  int repaidCents = 0;
}

class FulizaPageData {
  const FulizaPageData({
    required this.owingCents,
    required this.owingIsEstimate,
    required this.takenCents,
    required this.repaidCents,
    required this.accessFeesCents,
    required this.dailyFeesCents,
    required this.drawCount,
    required this.from,
    required this.to,
    required this.carriedInCents,
    required this.days,
    required this.unmatchedCount,
    required this.limitCents,
  });

  /// Null = "owing unknown" (the first message seen was a partial repayment).
  final int? owingCents;
  bool get owingUnknown => owingCents == null;
  bool get nothingOwed => owingCents == 0;
  final bool owingIsEstimate;

  final int takenCents;
  final int repaidCents;

  /// Exact: it is in the message (1% of each borrowing).
  final int accessFeesCents;

  /// Worked out from the next message: always labelled estimated.
  final int dailyFeesCents;
  int get costCents => accessFeesCents + dailyFeesCents;

  final int drawCount;
  final DateTime from;
  final DateTime to;

  /// Owed before the first message seen (above 0), else null.
  final int? carriedInCents;

  /// Newest day first; inside a day, newest first.
  final List<FulizaDay> days;

  /// Borrowings with no ordinary payment of the same code yet.
  final int unmatchedCount;
  final int? limitCents;

  /// "About Ksh N in every Ksh 100 you took went on fees."
  int get costPer100 => takenCents == 0 ? 0 : (costCents * 100 / takenCents).round();

  /// The newest borrowing's code of every borrowing, for the Related list.
  Iterable<String> get drawCodes => [
    for (final d in days)
      for (final e in d.entries)
        if (e.isDraw) e.event.code,
  ];
}

/// The page data for [state] over [events] (the same events the state was computed from), or null when
/// there are no events at all: no Fuliza data, no line, no page.
FulizaPageData? buildFulizaPage(FulizaState state, List<FulizaEvent> events) {
  if (events.isEmpty) return null;
  final sorted = [for (var i = 0; i < events.length; i++) (i, events[i])]
    ..sort((a, b) {
      final c = a.$2.at.compareTo(b.$2.at);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  final byKey = <String, FulizaDrawView>{
    for (final c in state.chains)
      for (final d in c.draws) '${d.event.code}|draw': d,
  };
  final days = <String, FulizaDay>{};
  var taken = 0, repaid = 0, access = 0, draws = 0, unmatched = 0;
  for (final (_, e) in sorted) {
    final isDraw = e.kind == FulizaEventKind.draw;
    final view = isDraw ? byKey['${e.code}|draw'] : null;
    final entry = FulizaHistoryEntry(
      event: e,
      paired: view?.paired ?? false,
      owingAfterCents: isDraw ? e.printedTotalCents : (e.kind == FulizaEventKind.repayFull ? 0 : null),
      dailyFeeSeenCents: view != null && view.residualCents > 0 ? view.residualCents : 0,
      needsReview: view?.needsReview ?? false,
    );
    final k = '${e.at.year}-${e.at.month}-${e.at.day}';
    final day = days.putIfAbsent(k, () => FulizaDay(DateTime(e.at.year, e.at.month, e.at.day)));
    day.entries.add(entry);
    if (isDraw) {
      taken += e.amountCents;
      access += e.feeCents;
      draws += 1;
      day.borrowedCents += e.amountCents;
      if (!entry.paired) unmatched += 1;
    } else {
      repaid += e.amountCents;
      day.repaidCents += e.amountCents;
    }
  }
  final newestFirst = days.values.toList()..sort((a, b) => b.day.compareTo(a.day));
  for (final d in newestFirst) {
    d.entries.sort((a, b) => b.event.at.compareTo(a.event.at));
  }
  final firstChain = state.chains.isEmpty ? null : state.chains.first;
  return FulizaPageData(
    owingCents: state.owingCents,
    owingIsEstimate: state.owingIsEstimate,
    takenCents: taken,
    repaidCents: repaid,
    accessFeesCents: access,
    dailyFeesCents: state.dailyFeeEstimateCents,
    drawCount: draws,
    from: sorted.first.$2.at,
    to: sorted.last.$2.at,
    carriedInCents: firstChain != null && firstChain.carriedIn ? firstChain.openingCents : null,
    days: newestFirst,
    unmatchedCount: unmatched,
    limitCents: state.limitCents,
  );
}

/// The Home line's label (WORDING-DRAFT): "Fuliza · Owing Ksh 1,227", "... Owing about Ksh X" while an
/// estimate, "... Owing unknown" when the balance is not known, "... Nothing owed" at 0. [ksh] formats cents.
String fulizaHomeLineLabel(FulizaPageData d, String Function(int cents) ksh) {
  if (d.owingUnknown) return 'Fuliza · Owing unknown';
  if (d.nothingOwed) return 'Fuliza · Nothing owed';
  return 'Fuliza · Owing ${d.owingIsEstimate ? 'about ' : ''}${ksh(d.owingCents!)}';
}
