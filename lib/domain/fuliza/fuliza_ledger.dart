/// §DOMAIN.FULIZA.LEDGER — pairing, opening balance, "owing unknown" and the
/// daily-fee estimate (0.2.0 slice 3, pure Dart over [FulizaRepository]).
///
/// The nine rules of fuliza-cycle-study section 3, where they live:
///  1. exact wording only                -> [FulizaParser] (slice 2)
///  2. draw pairs with its payment by code, either arrival order, lazily
///                                        -> [FulizaCalculator] `paired`
///  3. opening = printed total - draw - fee from the first draw seen; never 0
///     assumed; "carried in" when above 0 -> [FulizaChain.openingCents]
///  4. printed total always wins; the residual is kept as "extra since last
///     message": 0 < r is a daily fee (estimated), r < 0 is flagged for review
///  5. partial: running - amount, labelled about; unknown if running unknown
///  6. full: balance 0; amount above running = fees; below = unreconciled
///  7. a partial that arrives after a draw whose printed total already
///     includes it is not subtracted twice
///  8. a gap of more than [kChainGap] with no message starts a new chain
///  9. limit notice, failed notices, refusals, adverts: no ledger effect
///     (a limit notice only updates the shown limit)
library;

import '../parsing/fuliza_parser.dart';
import 'fuliza_repository.dart';

/// No message for longer than this: the next draw starts a new chain (rule 8).
const Duration kChainGap = Duration(days: 30);

/// A partial repayment stamped this soon after a draw can be one the network
/// had already applied before the draw (rule 7).
const Duration kOutOfOrderWindow = Duration(hours: 1);

/// One draw as the page shows it.
class FulizaDrawView {
  FulizaDrawView(this.event);

  final FulizaEvent event;

  /// True when an ordinary payment with the same code exists.
  bool paired = false;

  /// Printed total - (running + draw + fee). 0 for the first draw of a chain.
  int residualCents = 0;

  /// Residual that is neither a daily fee nor explained: show for review.
  bool needsReview = false;

  /// A negative residual explained by a partial repayment that arrived later.
  bool explainedByLaterPartial = false;
}

/// One run from the first draw seen to the full repayment (or the present).
class FulizaChain {
  FulizaChain({required this.openingCents});

  /// printed total - draw - fee of the first draw. Above 0 = "carried in".
  final int openingCents;
  bool get carriedIn => openingCents > 0;

  final List<FulizaDrawView> draws = [];
  int drawnCents = 0;
  int feeCents = 0;
  int repaidCents = 0;

  /// Sum of positive residuals and of full-repayment excess: estimated.
  int dailyFeeEstimateCents = 0;

  /// Full repayment below the running balance, or an unexplained negative
  /// residual: a message is missing or out of order. Shown, not invented.
  int unreconciledCents = 0;
  bool closed = false;
}

class FulizaState {
  FulizaState({
    required this.owingCents,
    required this.owingIsEstimate,
    required this.chains,
    required this.limitCents,
  });

  /// Null = "owing unknown": the first message seen was a partial and no draw
  /// or full repayment has re-based it yet.
  final int? owingCents;
  bool get owingUnknown => owingCents == null;

  /// "about": after a partial, or while fees since the last message are unseen.
  final bool owingIsEstimate;
  final List<FulizaChain> chains;
  final int? limitCents;

  FulizaChain? get current => chains.isEmpty ? null : chains.last;

  int get dailyFeeEstimateCents => chains.fold(0, (a, c) => a + c.dailyFeeEstimateCents);
}

/// Pure: events + payment codes in, state out. Nothing is stored.
class FulizaCalculator {
  FulizaCalculator._();

  static FulizaState compute(List<FulizaEvent> events, Set<String> paymentCodes, {int? limitCents}) {
    // Time order; equal times keep insertion order (List.sort is not stable).
    final indexed = [for (var i = 0; i < events.length; i++) (i, events[i])];
    indexed.sort((a, b) {
      final c = a.$2.at.compareTo(b.$2.at);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });

    final chains = <FulizaChain>[];
    FulizaChain? chain; // open chain, or null
    int? balance; // running balance; null = unknown
    var estimate = false;
    DateTime? prevAt;
    FulizaDrawView? lastDraw;
    int? balanceBeforeLastDraw;

    for (final (_, e) in indexed) {
      if (prevAt != null && e.at.difference(prevAt) > kChainGap) {
        chain = null;
        balance = null;
        estimate = false;
        lastDraw = null;
      }
      prevAt = e.at;

      switch (e.kind) {
        case FulizaEventKind.draw:
          final total = e.printedTotalCents ?? ((balance ?? 0) + e.amountCents + e.feeCents);
          final view = FulizaDrawView(e)..paired = paymentCodes.contains(e.code);
          if (chain == null || balance == null) {
            // Rule 3: first draw seen sets the balance to the printed total.
            chain = FulizaChain(openingCents: total - e.amountCents - e.feeCents);
            chains.add(chain);
          } else {
            // Rule 4: printed total wins; keep the residual.
            final residual = total - (balance + e.amountCents + e.feeCents);
            view.residualCents = residual;
            if (residual > 0) {
              chain.dailyFeeEstimateCents += residual;
            } else if (residual < 0) {
              view.needsReview = true; // may be cleared by rule 7 below
            }
          }
          chain.draws.add(view);
          chain.drawnCents += e.amountCents;
          chain.feeCents += e.feeCents;
          balanceBeforeLastDraw = balance;
          balance = total;
          estimate = false;
          lastDraw = view;
        case FulizaEventKind.repayPartial:
          final ld = lastDraw;
          final alreadyIncluded =
              ld != null &&
              chain != null &&
              ld.needsReview &&
              ld.residualCents == -e.amountCents &&
              balanceBeforeLastDraw != null &&
              e.at.difference(ld.event.at) <= kOutOfOrderWindow &&
              e.at.difference(ld.event.at) >= Duration.zero;
          chain?.repaidCents += e.amountCents;
          if (alreadyIncluded) {
            // Rule 7: the draw's printed total already holds this partial.
            ld.needsReview = false;
            ld.explainedByLaterPartial = true;
          } else if (balance == null) {
            // Rule 5: nothing known to subtract from.
          } else {
            balance = balance - e.amountCents;
            estimate = true;
            if (balance < 0) {
              chain?.unreconciledCents += -balance;
              balance = null; // more repaid than known owed: unknown, not invented
            }
          }
          lastDraw = null;
        case FulizaEventKind.repayFull:
          if (chain != null) {
            chain.repaidCents += e.amountCents;
            if (balance != null) {
              final diff = e.amountCents - balance;
              if (diff > 1) {
                chain.dailyFeeEstimateCents += diff; // rule 6: shown as fees, estimated
              } else if (diff < -1) {
                chain.unreconciledCents += -diff; // rule 6: do not invent
              }
            }
            chain.closed = true;
          }
          chain = null;
          balance = 0;
          estimate = false;
          lastDraw = null;
      }
    }

    return FulizaState(owingCents: balance, owingIsEstimate: estimate, chains: chains, limitCents: limitCents);
  }
}

/// Reads parsed messages into the repository and answers "what is owed".
class FulizaLedger {
  FulizaLedger(this._repo);
  final FulizaRepository _repo;

  /// Records one parsed message received at [at]. Returns true when it changed
  /// the ledger. Notices, refusals and unrecognised text return false (rule 9),
  /// except a limit notice or a repayment limit, which only update the limit.
  Future<bool> ingest(FulizaMessage m, DateTime at) async {
    switch (m) {
      case FulizaDraw():
        return _repo.addEvent(
          FulizaEvent(
            kind: FulizaEventKind.draw,
            code: m.code,
            at: at,
            amountCents: m.drawCents,
            feeCents: m.feeCents,
            printedTotalCents: m.printedTotalCents,
          ),
        );
      case FulizaRepayment():
        final lim = m.availableLimitCents;
        if (lim != null) await _repo.setLimitCents(lim);
        return _repo.addEvent(
          FulizaEvent(
            kind: m.isFull ? FulizaEventKind.repayFull : FulizaEventKind.repayPartial,
            code: m.code,
            at: at,
            amountCents: m.amountCents,
          ),
        );
      case FulizaLimitNotice():
        await _repo.setLimitCents(m.limitCents);
        return false;
      case FulizaFailedNotice():
      case FulizaUnrecognised():
        return false;
    }
  }

  Future<FulizaState> state() async =>
      FulizaCalculator.compute(await _repo.events(), await _repo.paymentCodes(), limitCents: await _repo.limitCents());
}
