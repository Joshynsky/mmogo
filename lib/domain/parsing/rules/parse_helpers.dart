/// §DOMAIN.PARSING.HELPERS — pieces shared by every parsing rule (0.1.2 S8a).
///
/// Moved here unchanged from `sms_parser.dart` so the six rules use ONE date,
/// time, money and label routine. A value that matches a shape but is
/// impossible (zero amount, 31/2/26, 25:00) throws [FormatException]; the
/// caller ([SmsParser.parse]) turns that into "not recognised".
library;

/// `22/8/26` or `22/8/2026`.
const String kDatePattern = r'(\d{1,2}/\d{1,2}/\d{2,4})';

/// `10:52 AM`, `9:15 AM`.
const String kTimePattern = r'([\d:]+\s*[APMapm]{2})';

/// `Transaction cost, Ksh7.00` — the fee text with its amount captured.
const String kFeePattern = r'Transaction cost,\s*Ksh([\d,]+\.\d{2})';

final RegExp _timeRe = RegExp(r'^(\d{1,2}):(\d{2})\s*([APap][Mm])$');
final RegExp _spaces = RegExp(r'\s+');

int parseMoneyCents(String amount) {
  final cleaned = amount.replaceAll(',', '');
  final value = double.parse(cleaned);
  return (value * 100).round();
}

/// The transaction amount: must be above zero (the fee may be 0.00).
int parseAmountCents(String amount) {
  final cents = parseMoneyCents(amount);
  if (cents <= 0) throw FormatException('Amount must be above zero: $amount');
  return cents;
}

/// Trim and collapse every run of whitespace to one space.
String normalizeLabel(String raw) => raw.trim().replaceAll(_spaces, ' ');

/// `dateStr` like "22/8/26" (d/m/yy or d/m/yyyy); `timeStr` like "10:52 AM".
/// Returns epoch millis in the device's local time zone, consistent with
/// `schema.dart`'s other INTEGER epoch-millis columns.
int parseOccurredAt(String dateStr, String timeStr) {
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
  if (at.year != year ||
      at.month != month ||
      at.day != day ||
      at.hour != hour ||
      at.minute != minute) {
    throw FormatException('Not a real date/time: $dateStr $timeStr');
  }
  return at.millisecondsSinceEpoch;
}
