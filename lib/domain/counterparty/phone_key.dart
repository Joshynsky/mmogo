/// §DOMAIN.COUNTERPARTY.PHONE_KEY — the one phone-number key rule (0.1.2, C-A4).
///
/// 07xx and 01xx numbers written with any of the usual prefixes are ONE person:
/// `0712345678`, `+254712345678`, `254712345678` and `00254712345678` all give
/// the key `0712345678`. 07 and 01 never merge with each other. Stored phone
/// values are never rewritten; only the derived key changes.
///
/// Called from exactly one place at runtime: the Send Money branch of
/// `deriveCounterpartyKey` (a static guard test lists the allowed files). The
/// v3 migration keeps its own FROZEN copy (`migration_v3_rekey.dart`) so a later
/// edit here can never change what the one-time re-key did.
library;

final RegExp _separators = RegExp(r'[\s-]');
final RegExp _prefixed = RegExp(r'^(\+254|254|00254)([17][0-9]{8})$');
final RegExp _local = RegExp(r'^0[17][0-9]{8}$');

/// Canonical key of [raw] for SEND_MONEY (DBE T3.1).
///
///  - null gives `''`;
///  - trim, then remove all whitespace and `-`;
///  - `+254` / `254` / `00254` followed by 9 digits starting 1 or 7 gives `0` +
///    those 9 digits;
///  - `0` + 1 or 7 + 8 digits is returned as is;
///  - anything else returns the TRIMMED raw value (the 0.1.1 behaviour): letters,
///    an inner `+`, short or long numbers are left exactly as they were.
///
/// ASCII digits only; idempotent.
String normalizePhoneKey(String? raw) {
  if (raw == null) return '';
  final s = raw.trim();
  final t = s.replaceAll(_separators, '');
  final m = _prefixed.firstMatch(t);
  if (m != null) return '0${m.group(2)}';
  if (_local.hasMatch(t)) return t;
  return s;
}
