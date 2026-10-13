/// T12 — Suggestion pill / counterparty auto-suggest system.
///
/// Pure, DB-free derivation of `counterparty_classification_map
/// .counterparty_key` — the single most load-bearing requirement of this
/// slice (counterparty_key normalization consistency): the read path (looking up a suggestion,
/// `CounterpartyDao.lookup`) and the write path (upserting on confirm,
/// `CounterpartyDao.upsertOnConfirm`) MUST both call this exact same
/// function on the exact same inputs — never a re-implemented or
/// copy-pasted normalization living separately on either side. This file
/// is the authoritative implementation of that requirement.
///
/// `lib/domain/analytics/party_key.dart`'s own `counterpartyKeyFor` (built
/// at T9/Analytics, before this row existed) was a separately-disclosed
/// placeholder with the same intent but an independent (and
/// confirmed-divergent — no internal-whitespace collapse) implementation.
/// T15 (Parties) retired that file entirely once it had a real caller to
/// reconcile: this function is now the single implementation every caller
/// in this codebase uses, in Dart (`AnalyticsDao` and the Paid to queries) and via
/// this same rule reimplemented nowhere else.
///
/// **Exact normalization rule (decided and documented here, per this
/// dispatch's own instruction — same citable-decision convention
/// `classification_dao.dart`'s `fetchFlatActiveClassifications` doc
/// comment already uses for its own dedup rule):**
///   - **SEND_MONEY** -> `counterparty_phone` through the phone key rule in
///     `phone_key.dart` (0.1.2, C-A4): 07xx / 01xx and their +254 / 254 /
///     00254 forms are one key; anything else is the trimmed raw value (the
///     0.1.1 rule). The stored `counterparty_phone` is never rewritten.
///   - **PAYBILL** -> `<label>#<account>`, where `<label>` is
///     `counterparty_label` trimmed, every run of internal whitespace
///     collapsed to one space, then upper-cased; `<account>` is
///     `paybill_account_number` trimmed with internal whitespace likewise
///     collapsed, but NOT upper-cased (an account number's case, on the
///     rare occasion it contains letters, is treated as significant —
///     unlike a business label, which is a free-text display string).
///   - **BUY_GOODS** -> the same `<label>` normalization as PAYBILL's
///     business half (trim, collapse internal whitespace, upper-case),
///     alone, with no account/`#` suffix (no account number exists for
///     Buy Goods to disambiguate with).
///   - Internal-whitespace collapsing is this function's own explicit
///     addition beyond a literal "trimmed/uppercased" rule
///     for BUY_GOODS — added because two real SMS samples for the
///     same business have been observed to vary in incidental internal
///     spacing, which would otherwise silently derive two different keys
///     for what is really one counterparty. Flagged as a judgment call in
///     this dispatch's FLAGS, not asserted as literal spec text.
///   - A null/missing field normalizes to an empty-string component rather
///     than throwing. The write path only ever calls this once the
///     relevant schema CHECK constraints already guarantee the field is
///     non-null for its own source_type; the read path (looking up a
///     suggestion while the user is still mid-typing an identity field)
///     may legitimately call this with an incomplete value, and must
///     degrade to "matches nothing" rather than crash.
library;

import '../parsing/parsed_sms_fields.dart';
import 'phone_key.dart';

/// Derives the exact `counterparty_classification_map.counterparty_key`
/// string for [sourceType] from whichever identity field(s) that
/// source_type uses. Both [CounterpartyDao.lookup] callers (read path) and
/// [CounterpartyDao.upsertOnConfirm] callers (write path) must call this
/// with the same field values for the same real-world counterparty in
/// order to match — see this file's own header doc comment.
String deriveCounterpartyKey({
  required SmsSourceType sourceType,
  String? counterpartyLabel,
  String? counterpartyPhone,
  String? paybillAccountNumber,
}) {
  switch (sourceType) {
    case SmsSourceType.sendMoney:
      return normalizePhoneKey(counterpartyPhone);
    case SmsSourceType.payBill:
      return '${_normalizeLabel(counterpartyLabel)}#${_normalizeAccount(paybillAccountNumber)}';
    case SmsSourceType.buyGoods:
      return _normalizeLabel(counterpartyLabel);
    case SmsSourceType.pochi:
    case SmsSourceType.agentWithdrawal:
    case SmsSourceType.airtime:
      // These types never learn a receiver (no counterparty map row), so
      // there is no key: the empty string, as Cash has.
      return '';
  }
}

String _normalizeLabel(String? raw) {
  return (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
}

String _normalizeAccount(String? raw) {
  return (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
}
