import '../parsed_sms_fields.dart';
import 'parse_helpers.dart';

/// §DOMAIN.PARSING.AIRTIME — airtime purchase (0.1.2 S8a, AI1).
///
/// Invented shapes: `PT8N4W7Q2K confirmed.You bought Ksh200.00 of airtime on
/// 31/10/25 at 2:01 PM.New M-PESA balance is Ksh77,777.77. Transaction cost,
/// Ksh0.00.` and the "another number" form `... at 5:57 AM for 254712345678.
/// New M-PESA balance ...`.
///
/// FEE-LINE RULE (pinned by a named test): a message with a
/// `Transaction cost, Ksh<fee>` line uses that fee; a message with NO fee line gets
/// [kAirtimeNoFeeCents] (Safaricom lists airtime as free); a fee line that is
/// present but unreadable is NOT understood (null).
///
/// The label is null: the v3 label CHECK says AIRTIME never carries one, and
/// the screens show the type name. The other number of the "another number"
/// form is deliberately not kept.
const int kAirtimeNoFeeCents = 0;

class AirtimeRule {
  AirtimeRule._();

  static final RegExp _re = RegExp(
    r'^([A-Z0-9]{10})\s+[Cc]onfirmed\.\s*You bought\s+Ksh([\d,]+\.\d{2})\s+of airtime\s+on\s+'
    '$kDatePattern\\s+at\\s+$kTimePattern',
  );
  static final RegExp _feeRe = RegExp(kFeePattern);

  static ParsedSmsFields? tryParse(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    final rest = text.substring(m.end);
    int feeCents;
    if (rest.contains('Transaction cost')) {
      final f = _feeRe.firstMatch(rest);
      if (f == null) return null;
      feeCents = parseMoneyCents(f.group(1)!);
    } else {
      feeCents = kAirtimeNoFeeCents;
    }
    return ParsedSmsFields(
      code: m.group(1)!,
      sourceType: SmsSourceType.airtime,
      amountCents: parseAmountCents(m.group(2)!),
      counterpartyLabel: null,
      counterpartyPhone: null,
      paybillAccountNumber: null,
      transactionOccurredAt: parseOccurredAt(m.group(3)!, m.group(4)!),
      transactionCostCents: feeCents,
    );
  }
}
