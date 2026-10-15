import '../parsed_sms_fields.dart';
import 'parse_helpers.dart';

/// §DOMAIN.PARSING.BUY_GOODS — Buy Goods (`paid to <merchant>.`), moved
/// unchanged from `sms_parser.dart` in 0.1.2 S8a. No account, no phone.
class BuyGoodsRule {
  BuyGoodsRule._();

  static final RegExp _re = RegExp(
    r'^([A-Z0-9]{10})\s+Confirmed\.\s+Ksh([\d,]+\.\d{2})\s+paid to\s+(.+?)\.\s*on\s+'
    '$kDatePattern\\s+at\\s+$kTimePattern\\b'
    '[\\s\\S]*?$kFeePattern',
  );

  /// The fields, or null when [text] (already trimmed) is not this shape.
  static ParsedSmsFields? tryParse(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    return ParsedSmsFields(
      code: m.group(1)!,
      sourceType: SmsSourceType.buyGoods,
      amountCents: parseAmountCents(m.group(2)!),
      counterpartyLabel: normalizeLabel(m.group(3)!),
      counterpartyPhone: null,
      paybillAccountNumber: null,
      transactionOccurredAt: parseOccurredAt(m.group(4)!, m.group(5)!),
      transactionCostCents: parseMoneyCents(m.group(6)!),
    );
  }
}
