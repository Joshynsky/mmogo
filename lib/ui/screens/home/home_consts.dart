import '../../../domain/format/source_types.dart';
import '../../../domain/money/spent_amount.dart';

/// §HOME.CONST — Home's shared constants: the fixed type order and the tiny-screen
/// fallback row count.
/// The transaction types that get a bar on Home, in the fixed bar order (T20:
/// the same order every period, so a colour never moves) with their display
/// names. A withdrawal adds nothing to spent, so it has no bar; its fee is
/// still in Home's cost figure (that sums every type, not this list).
final homeTypeOrder = [
  for (final t in sourceTypeOrder)
    if (!isWithdrawal(t.$1)) t,
];

/// When not even one whole recent row fits (a tiny screen or very large
/// text), Home becomes an ordinary scrolling page showing this many rows.
const homeRecentFallbackRows = 5;

/// F1 (0.2.2): the Home line for cash taken out and not yet counted. The label
/// is the PM's locked wording (21-11); the amount beside it is the leftover only.
/// WORDING-DRAFT: wording to be signed before release.
const kHomeCashLeftoverLabel = 'Cash withdrawn, not counted';
