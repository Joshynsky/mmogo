/// §AUTOREAD.NON_TRANSACTION — messages that are known NOT to be an M-Pesa
/// transaction and are ignored quietly (PM decision 01-11-2026: a
/// non-transaction message must not be shown as "Could not read"). Pure Dart.
///
/// Today one shape: the Safaricom airtime recharge notice, "Recharge of 5.00
/// KSH ...". Mirrored in Kotlin by `SmsReceiverLogic.isNonTransactionNotice`
/// (the two must agree). Add a shape here AND there; nothing else is ignored,
/// so a real transaction that fails to parse is still shown.
library;

/// The recharge notice: starts with "Recharge of AMOUNT KSH or KES" and is not a
/// transaction confirmation (no "CODE Confirmed" opening, no "Failed").
final RegExp _recharge = RegExp(
  r'^\s*recharge\s+of\s+[\d.,]+\s*(ksh|kes)\b',
  caseSensitive: false,
);

final RegExp _confirmation = RegExp(r'^\s*[A-Z0-9]{10}\s*confirmed\b', caseSensitive: false);

/// True when [body] is a known non-transaction notice. Never throws.
bool isNonTransactionNotice(String body) {
  if (_confirmation.hasMatch(body)) return false;
  if (RegExp(r'\bfailed\b', caseSensitive: false).hasMatch(body)) return false;
  return _recharge.hasMatch(body);
}
