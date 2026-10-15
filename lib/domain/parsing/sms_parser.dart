import 'parse_result.dart';
import 'rules/airtime_rule.dart';
import 'rules/buy_goods_rule.dart';
import 'rules/name_only_rule.dart';
import 'rules/paybill_rule.dart';
import 'rules/send_money_rule.dart';
import 'rules/withdrawal_rule.dart';

/// T5 — SMS parsing engine (§DOMAIN.PARSING).
///
/// 0.1.2 S8a: the regexes now live in `rules/` (one file per shape). The
/// dispatch order below is fixed: Buy Goods, Paybill, Send Money (the three
/// 0.1.1 shapes, unchanged order), then Withdrawal and Airtime (their opening
/// words cannot match the first three), then Name-only LAST (it is the loosest
/// "sent to" shape and must never shadow Send Money or Paybill).

///
/// Plain Dart regex, no parsing library — this is the exact mechanism
/// demonstrated against the three real M-Pesa
/// screenshot samples in `image refrences/` (`mpesa message example.png`
/// = Send Money, `Paybill example.png`, `Buy goods example.png`):
/// classify-then-extract in a FIXED check order — test "paid to" (Buy
/// Goods) first, then "for account" (Paybill), else Send Money — because
/// the three signatures are lexically disjoint at the keyword level and
/// checking in any other order risks a Paybill/Buy Goods message being
/// misread as Send Money (a plain "sent to" prefix appears in both Send
/// Money and Paybill messages; only checking Paybill's more specific
/// "for account" marker first, before falling through to the bare "sent
/// to ... phone-number" Send Money shape, keeps them from colliding).
///
/// Field extraction and the check order itself are carried forward from
/// the earlier prototype's independently-unit-tested standalone JS
/// `parseSms()` implementation as a validated reference for the three signatures/fields/order — this
/// is a fresh, idiomatic Dart implementation, not a port, and every regex
/// below was re-verified directly against this project's actual
/// screenshot transcriptions (see the test suite), not assumed to carry
/// over unchanged.
/// Hard length cap (0.1.2 S8a, WD1): a longer input is refused before any
/// regex runs, so no pattern ever sees an adversarial megabyte.
const int kSmsMaxChars = 2000;

class SmsParser {
  SmsParser._();

  /// Parses a raw pasted M-Pesa SMS body. Never throws; an unmatched paste is
  /// a first-class, explicit, transient result and is never stored. Results:
  /// [ParseSuccess], [ParseNeedsType] (name only), [ParseTooLong] or
  /// [ParseError] (not recognised).
  static ParseResult parse(String rawMessage) {
    // WD1: FIRST statement, before trim and before any regex.
    if (rawMessage.length > kSmsMaxChars) return const ParseTooLong();
    try {
      return _parse(rawMessage);
    } on FormatException {
      // A matched shape with an impossible value (a zero amount, a date or
      // time that does not exist) is "not recognised", never a success.
      return const ParseResult.error(kSmsNoMatchReason);
    }
  }

  static ParseResult _parse(String rawMessage) {
    final text = rawMessage.trim();
    if (text.isEmpty) {
      return const ParseResult.error(kSmsNoMatchReason);
    }

    final fields = BuyGoodsRule.tryParse(text) ??
        PaybillRule.tryParse(text) ??
        SendMoneyRule.tryParse(text) ??
        WithdrawalRule.tryParse(text) ??
        AirtimeRule.tryParse(text);
    if (fields != null) return ParseResult.success(fields);

    final nameOnly = NameOnlyRule.tryParse(text);
    if (nameOnly != null) return ParseResult.needsType(nameOnly);

    return const ParseResult.error(kSmsNoMatchReason);
  }

  /// The signed WD9 wording (mock `NOMATCH`, copied character for character,
  /// including the curly apostrophes).
  static const String kSmsNoMatchReason =
      'Couldn’t recognize this message. It doesn’t match a Send Money, Paybill, '
      'Buy Goods, Pochi, Withdrawal or Airtime confirmation. Check the pasted '
      'text, or choose the type and enter it yourself.';
}
