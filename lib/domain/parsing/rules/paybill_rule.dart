import '../parsed_sms_fields.dart';
import 'parse_helpers.dart';

/// §DOMAIN.PARSING.PAYBILL — Paybill (`sent to <business> for account <n>`),
/// moved unchanged from `sms_parser.dart` in 0.1.2 S8a. Must be tried before
/// Send Money and Name-only (all share the "sent to" prefix).
class PaybillRule {
  PaybillRule._();

  static final RegExp _re = RegExp(
    r'^([A-Z0-9]{10})\s+Confirmed\.\s+Ksh([\d,]+\.\d{2})\s+sent to\s+(.+?)\s+for account\s+(.+?)\s+on\s+'
    '$kDatePattern\\s+at\\s+$kTimePattern\\b'
    '[\\s\\S]*?$kFeePattern',
  );

  static ParsedSmsFields? tryParse(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    return ParsedSmsFields(
      code: m.group(1)!,
      sourceType: SmsSourceType.payBill,
      amountCents: parseAmountCents(m.group(2)!),
      counterpartyLabel: normalizeLabel(m.group(3)!),
      counterpartyPhone: null,
      paybillAccountNumber: m.group(4)!.trim(),
      transactionOccurredAt: parseOccurredAt(m.group(5)!, m.group(6)!),
      transactionCostCents: parseMoneyCents(m.group(7)!),
    );
  }
}
