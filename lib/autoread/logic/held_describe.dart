/// §AUTOREAD.HELD_DESCRIBE - words for a held message (pure Dart, no widgets).
///
/// A readable message is described from the parser's fields ("Sent Ksh 200 to
/// Wanjiru Kamau"). An unreadable one is described only by what [lightRead]
/// finds: the M-Pesa code, an amount and a time, each null when not found. The
/// light reader returns the matched piece only (never the text around it) and
/// the body is never returned, kept, logged or put in an error.
library;

import '../../domain/airtime/airtime_kind.dart';
import '../../domain/format/money.dart';
import '../../domain/format/source_types.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../model/held_description.dart';

// SIGNED (PM 13-11-2026): the verbs of a held row's description.
const String kHeldSent = 'Sent';
const String kHeldPaid = 'Paid';
const String kHeldWithdrew = 'Withdrew';

/// "Sent Ksh 200 to X", "Paid Ksh 1,200 to X", "Withdrew Ksh 500 from X",
/// "Airtime Ksh 5 for myself" / "Airtime Ksh 5 for another number". The name is
/// always part of it (it stays on screen only).
String describeReadable(ParsedSmsFields f) {
  final amount = kshTrim(f.amountCents);
  final who = (f.counterpartyLabel ?? '').trim();
  switch (f.sourceType) {
    case SmsSourceType.sendMoney:
    case SmsSourceType.pochi:
      return '$kHeldSent $amount${who.isEmpty ? '' : ' to $who'}';
    case SmsSourceType.payBill:
    case SmsSourceType.buyGoods:
      return '$kHeldPaid $amount${who.isEmpty ? '' : ' to $who'}';
    case SmsSourceType.agentWithdrawal:
      return '$kHeldWithdrew $amount${who.isEmpty ? '' : ' from $who'}';
    case SmsSourceType.airtime:
      return '${sourceTypeName(f.sourceType.dbValue)} $amount ${airtimeKindWords(f.airtimeOther)}';
  }
}

/// "for myself" / "for another number" (the signed kind names, lower case).
String airtimeKindWords(bool other) => (other ? kAirtimeNameOther : kAirtimeNameMyself).toLowerCase();

final RegExp _codePattern = RegExp(r'\b(?=[A-Z0-9]*[0-9])(?=[A-Z0-9]*[A-Z])[A-Z0-9]{10}\b');
final RegExp _amountPattern = RegExp(r'Ksh\.?\s?(\d{1,3}(?:,\d{3})*|\d+)(\.\d{1,2})?', caseSensitive: false);
final RegExp _balanceWord = RegExp(r'bal(ance)?\b[^.]*$', caseSensitive: false);
final RegExp _timePattern = RegExp(r'\bat\s+(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);

String _two(int n) => n < 10 ? '0$n' : '$n';

/// Finds the code, the first Ksh amount and the time of day in [body]. Only the
/// matched pieces come back: "UFGH123456", "Ksh 5", "14:08".
HeldDescription lightRead(String body) {
  final code = _codePattern.firstMatch(body)?.group(0);

  // The balance is never picked out (Privacy): an amount that follows the word
  // "balance" is skipped, the next amount is used (found 14-11-2026 on the Oppo).
  String? amount;
  RegExpMatch? a;
  for (final m in _amountPattern.allMatches(body)) {
    final before = body.substring(m.start < 40 ? 0 : m.start - 40, m.start);
    if (_balanceWord.hasMatch(before)) continue;
    if (RegExp(r'^[0.,]*$').hasMatch(m.group(1)! + (m.group(2) ?? ''))) continue; // "Ksh0" is a fee line, not the amount
    a = m;
    break;
  }
  if (a != null) {
    final frac = a.group(2);
    final trimmed = (frac == null || frac == '.0' || frac == '.00') ? '' : frac;
    amount = 'Ksh ${a.group(1)}$trimmed';
  }

  String? time;
  final t = _timePattern.firstMatch(body);
  if (t != null) {
    final h12 = int.parse(t.group(1)!);
    final m = int.parse(t.group(2)!);
    if (h12 >= 1 && h12 <= 12 && m < 60) {
      final pm = t.group(3)!.toUpperCase() == 'PM';
      final h24 = (h12 % 12) + (pm ? 12 : 0);
      time = '${_two(h24)}:${_two(m)}';
    }
  }
  return HeldDescription(code: code, amount: amount, time: time, notice: isSystemNotice(body));
}

final RegExp _noticeShape = RegExp(r'unable\s+to\s+process|similar\s+transaction', caseSensitive: false);
final RegExp _confirmedOpening = RegExp(r'^\s*[A-Z0-9]{10}\s*confirmed\b', caseSensitive: false);

/// True for an M-Pesa system notice that is not a transaction (never a "Confirmed"
/// message). Used only to label the row; the message is kept as before.
bool isSystemNotice(String body) => !_confirmedOpening.hasMatch(body) && _noticeShape.hasMatch(body);
