import 'parse_result.dart';
import 'parsed_sms_fields.dart';

/// T5 — SMS parsing engine.
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
class SmsParser {
  SmsParser._();

  // Buy Goods ("paid to <merchant>."): no account number, no phone — just
  // a merchant name terminated by ". on <date>". Checked FIRST.
  static final RegExp _buyGoodsRe = RegExp(
    r'^([A-Z0-9]{10})\s+Confirmed\.\s+Ksh([\d,]+\.\d{2})\s+paid to\s+(.+?)\.\s*on\s+'
    r'(\d{1,2}/\d{1,2}/\d{2,4})\s+at\s+([\d:]+\s*[APMapm]{2})\b'
    r'[\s\S]*?Transaction cost,\s*Ksh([\d,]+\.\d{2})',
  );

  // Paybill ("sent to <business> for account <number>"). Checked SECOND —
  // must come before Send Money since both share the "sent to" prefix.
  static final RegExp _paybillRe = RegExp(
    r'^([A-Z0-9]{10})\s+Confirmed\.\s+Ksh([\d,]+\.\d{2})\s+sent to\s+(.+?)\s+for account\s+(.+?)\s+on\s+'
    r'(\d{1,2}/\d{1,2}/\d{2,4})\s+at\s+([\d:]+\s*[APMapm]{2})\b'
    r'[\s\S]*?Transaction cost,\s*Ksh([\d,]+\.\d{2})',
  );

  // Send Money ("sent to <NAME> <phone>"), the catch-all fallback shape —
  // checked LAST, only once the other two more-specific keyword markers
  // ("paid to" / "for account") have both failed to match.
  static final RegExp _sendMoneyRe = RegExp(
    r'^([A-Z0-9]{10})\s+Confirmed\.\s+Ksh([\d,]+\.\d{2})\s+sent to\s+([A-Z\s]+?)\s+(0[17]\d{8})\s+on\s+'
    r'(\d{1,2}/\d{1,2}/\d{2,4})\s+at\s+([\d:]+\s*[APMapm]{2})\b'
    r'[\s\S]*?Transaction cost,\s*Ksh([\d,]+\.\d{2})',
  );

  // Inner time-format check, used once a candidate time string has
  // already been captured by one of the three regexes above.
  static final RegExp _timeRe =
      RegExp(r'^(\d{1,2}):(\d{2})\s*([APap][Mm])$');

  /// Parses a raw pasted M-Pesa SMS body. Returns
  /// [ParseResult.success]/[ParseResult.error] — never throws for a
  /// malformed/unmatched message; an unmatched paste is a first-class,
  /// explicit, transient result (an explicit error, not a silent fallback).
  static ParseResult parse(String rawMessage) {
    try {
      return _parse(rawMessage);
    } on FormatException {
      // A matched shape with an impossible value (a zero amount, a date or
      // time that does not exist) is "not recognised", never a success.
      return const ParseResult.error(_noMatchReason);
    }
  }

  static ParseResult _parse(String rawMessage) {
    final text = rawMessage.trim();
    if (text.isEmpty) {
      return const ParseResult.error(_noMatchReason);
    }

    final buyGoods = _buyGoodsRe.firstMatch(text);
    if (buyGoods != null) {
      return ParseResult.success(ParsedSmsFields(
        code: buyGoods.group(1)!,
        sourceType: SmsSourceType.buyGoods,
        amountCents: _parseAmountCents(buyGoods.group(2)!),
        counterpartyLabel: _normalizeLabel(buyGoods.group(3)!),
        counterpartyPhone: null,
        paybillAccountNumber: null,
        transactionOccurredAt:
            _parseOccurredAt(buyGoods.group(4)!, buyGoods.group(5)!),
        transactionCostCents: _parseMoneyCents(buyGoods.group(6)!),
      ));
    }

    final paybill = _paybillRe.firstMatch(text);
    if (paybill != null) {
      return ParseResult.success(ParsedSmsFields(
        code: paybill.group(1)!,
        sourceType: SmsSourceType.payBill,
        amountCents: _parseAmountCents(paybill.group(2)!),
        counterpartyLabel: _normalizeLabel(paybill.group(3)!),
        counterpartyPhone: null,
        paybillAccountNumber: paybill.group(4)!.trim(),
        transactionOccurredAt:
            _parseOccurredAt(paybill.group(5)!, paybill.group(6)!),
        transactionCostCents: _parseMoneyCents(paybill.group(7)!),
      ));
    }

    final sendMoney = _sendMoneyRe.firstMatch(text);
    if (sendMoney != null) {
      return ParseResult.success(ParsedSmsFields(
        code: sendMoney.group(1)!,
        sourceType: SmsSourceType.sendMoney,
        amountCents: _parseAmountCents(sendMoney.group(2)!),
        counterpartyLabel: _normalizeLabel(sendMoney.group(3)!),
        counterpartyPhone: sendMoney.group(4)!.trim(),
        paybillAccountNumber: null,
        transactionOccurredAt:
            _parseOccurredAt(sendMoney.group(5)!, sendMoney.group(6)!),
        transactionCostCents: _parseMoneyCents(sendMoney.group(7)!),
      ));
    }

    return const ParseResult.error(_noMatchReason);
  }

  static const String _noMatchReason =
      "Couldn't recognize this message. It doesn't match a Send Money, "
      'Buy Goods, or Paybill confirmation. Check the pasted text, or '
      'switch to the Cash tab to enter it manually.';

  static int _parseMoneyCents(String amount) {
    final cleaned = amount.replaceAll(',', '');
    final value = double.parse(cleaned);
    return (value * 100).round();
  }

  /// The transaction amount: must be above zero (the fee may be 0.00).
  static int _parseAmountCents(String amount) {
    final cents = _parseMoneyCents(amount);
    if (cents <= 0) throw FormatException('Amount must be above zero: $amount');
    return cents;
  }

  static String _normalizeLabel(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// `dateStr` like "22/8/26" (d/m/yy or d/m/yyyy); `timeStr` like
  /// "10:52 AM" — matches all three real screenshot samples' format.
  /// Returns epoch millis in the device's local time zone, consistent
  /// with `schema.dart`'s other INTEGER epoch-millis columns (no UTC
  /// conversion assumed anywhere else in this schema either).
  static int _parseOccurredAt(String dateStr, String timeStr) {
    final dateParts = dateStr.split('/').map(int.parse).toList();
    final day = dateParts[0];
    final month = dateParts[1];
    var year = dateParts[2];
    if (year < 100) year += 2000;

    final timeMatch = _timeRe.firstMatch(timeStr.trim());
    if (timeMatch == null) {
      throw FormatException('Unrecognized time format: $timeStr');
    }
    var hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final meridiem = timeMatch.group(3)!.toUpperCase();
    if (meridiem == 'AM') {
      if (hour == 12) hour = 0;
    } else {
      if (hour != 12) hour += 12;
    }
    final at = DateTime(year, month, day, hour, minute);
    // DateTime rolls impossible values over (31/2/26 -> 3 March); a date or
    // time that does not round-trip is not a real one.
    if (at.year != year || at.month != month || at.day != day || at.hour != hour || at.minute != minute) {
      throw FormatException('Not a real date/time: $dateStr $timeStr');
    }
    return at.millisecondsSinceEpoch;
  }
}
