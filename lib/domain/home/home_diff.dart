/// Home's "vs prior period" diff line — reimplements the prototype's
/// `render()` diff calculation as real, unit-tested Dart. Pure/DB-free: takes already-summed totals in, so it's
/// testable without touching sqlite.
enum HomeDiffKind {
  /// Prior period had zero spend and so did this one — nothing meaningful
  /// to compare ("—").
  noPriorNoSpend,

  /// Prior period had zero spend but this one doesn't — a percentage
  /// comparison against zero is meaningless, so a plain message is shown
  /// instead ("No spend in the prior period to compare").
  noPriorHasSpend,

  /// This period's total is >= the prior period's (spending increase or
  /// flat) — red up-arrow.
  up,

  /// This period's total is less than the prior period's (spending
  /// decrease) — green down-arrow.
  down,
}

class HomeDiffResult {
  const HomeDiffResult(this.kind, this.percent);

  final HomeDiffKind kind;

  /// Rounded absolute percentage change. Only meaningful for
  /// [HomeDiffKind.up]/[HomeDiffKind.down]; 0 for the no-prior-data cases.
  final int percent;
}

class HomeDiff {
  HomeDiff._();

  static HomeDiffResult compute({
    required int thisTotalCents,
    required int priorTotalCents,
  }) {
    if (priorTotalCents == 0) {
      return HomeDiffResult(
        thisTotalCents > 0 ? HomeDiffKind.noPriorHasSpend : HomeDiffKind.noPriorNoSpend,
        0,
      );
    }
    final diff = thisTotalCents - priorTotalCents;
    final percent = ((diff.abs() / priorTotalCents) * 100).round();
    return HomeDiffResult(diff >= 0 ? HomeDiffKind.up : HomeDiffKind.down, percent);
  }
}
