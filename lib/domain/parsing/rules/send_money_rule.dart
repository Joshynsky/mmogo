import '../parsed_sms_fields.dart';
import 'parse_helpers.dart';

/// §DOMAIN.PARSING.SEND_MONEY — Send Money (`sent to <NAME> <phone>`).
///
/// 0.1.2 S8a (PK3): the phone accepts `0`, `+254`, `254`, `00254` followed by
/// 1 or 7 and 8 digits, stored as printed (the key rule lives in
/// `phone_key.dart`); the name is any case with letters, spaces, apostrophes,
/// dots and hyphens, no digits, whitespace collapsed.
class SendMoneyRule {
  SendMoneyRule._();

  static final RegExp _re = RegExp(
    r"^([A-Z0-9]{10})\s+Confirmed\.\s+Ksh([\d,]+\.\d{2})\s+sent to\s+([A-Za-z][A-Za-z\s'’.\-]*?)\s+"
    r'((?:\+254|254|00254|0)[17]\d{8})\s+on\s+'
    '$kDatePattern\\s+at\\s+$kTimePattern\\b'
    '[\\s\\S]*?$kFeePattern',
  );

  static ParsedSmsFields? tryParse(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    return ParsedSmsFields(
      code: m.group(1)!,
      sourceType: SmsSourceType.sendMoney,
      amountCents: parseAmountCents(m.group(2)!),
      counterpartyLabel: normalizeLabel(m.group(3)!),
      counterpartyPhone: m.group(4)!.trim(),
      paybillAccountNumber: null,
      transactionOccurredAt: parseOccurredAt(m.group(5)!, m.group(6)!),
      transactionCostCents: parseMoneyCents(m.group(7)!),
    );
  }
}
