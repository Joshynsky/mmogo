import '../name_only_fields.dart';
import 'parse_helpers.dart';

/// §DOMAIN.PARSING.NAME_ONLY — `sent to <NAME>` with no phone, no account
/// (0.1.2 S8a, NO1). Tried LAST. The result is "needs type" (a Pochi la
/// Biashara send looks exactly like this), never a saved row.
///
/// Anchored, whitespace tolerant, name at most [kNameOnlyMaxChars] characters,
/// NO digits in the name; the fee line is mandatory. A name that contains
/// "for account" is a Paybill, never this.
const int kNameOnlyMaxChars = 100;

class NameOnlyRule {
  NameOnlyRule._();

  static final RegExp _re = RegExp(
    r'^([A-Z0-9]{10})\s+Confirmed\.\s+Ksh([\d,]+\.\d{2})\s+sent to\s+'
    '([A-Za-z](?:(?!\\s+for\\s+account\\s)[^\\d\\r\\n]){0,${kNameOnlyMaxChars - 1}}?)\\s+on\\s+'
    '$kDatePattern\\s+at\\s+$kTimePattern\\b'
    '[\\s\\S]*?$kFeePattern',
  );

  static NameOnlyFields? tryParse(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    return NameOnlyFields(
      code: m.group(1)!,
      amountCents: parseAmountCents(m.group(2)!),
      name: normalizeLabel(m.group(3)!),
      transactionOccurredAt: parseOccurredAt(m.group(4)!, m.group(5)!),
      transactionCostCents: parseMoneyCents(m.group(6)!),
    );
  }
}
