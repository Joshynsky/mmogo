/// Shared parser for typed Ksh amounts, pure Dart. Integer-cents only: no
/// `double` anywhere, so `1e5`, `Infinity`, `NaN`, negatives and sub-cent
/// values like `0.004` can never reach a stored amount. Used by the Add
/// screen (amount and fee) and the Analytics edit sheet (amount and cost).
library;

/// The largest amount accepted: Ksh 10,000,000.00, in cents.
const maxKshCents = 1000000000;

/// Wording shown inline when an amount is not acceptable.
const kshAmountHelp = 'Enter an amount from 0.01 to 10,000,000.00';

/// The shape the amount fields may hold while typing: up to 8 digits, then
/// an optional `.` with at most two decimals. The empty string is allowed
/// (it is "nothing typed yet"); [parseKshCents] is the real gate.
final kshTypingShape = RegExp(r'^\d{0,8}(\.\d{0,2})?$');

/// Parses [text] (trimmed) as Ksh into integer cents, or `null` if it is not
/// digits with an optional single `.` and at most two decimals, or is above
/// [maxKshCents]. `0` / `0.00` parse to 0 only when [allowZero] is set (a
/// fee), otherwise they are `null` (an amount must be above zero).
int? parseKshCents(String text, {bool allowZero = false}) {
  final m = RegExp(r'^(\d*)(?:\.(\d{0,2}))?$').firstMatch(text.trim());
  if (m == null) return null;
  final whole = m.group(1)!;
  final frac = m.group(2) ?? '';
  if (whole.isEmpty && frac.isEmpty) return null;
  if (whole.length > 9) return null; // also keeps int.parse far from overflow
  final cents = (whole.isEmpty ? 0 : int.parse(whole)) * 100 + (frac.isEmpty ? 0 : int.parse(frac.padRight(2, '0')));
  if (cents > maxKshCents) return null;
  if (cents == 0 && !allowZero) return null;
  return cents;
}
