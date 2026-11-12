/// §AUTOREAD.MESSAGE_DETAILS — what the "Details" sheet of a waiting item shows
/// (pure Dart, no widgets, no clock: every function takes `now`).
///
/// Mock: `_pipeline/global-mock/screens/notifications.js`, sheet `msg` (item 7
/// of CHANGES-2026-11-03). The raw message text is never kept: a readable
/// message is shown through the fields the parser found; an unreadable one only
/// through its first words, with anything that looks like a code, a number or a
/// name in capitals left out.
library;

import '../../domain/format/money.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../model/waiting_item.dart';

/// The only sender the receiver accepts (`SmsReceiverLogic.ALLOWED_SENDERS`).
const String kDetailsSender = 'MPESA';

/// Time left in words: 24 h or more "N h" (rounded up), under a day "3 h 20 min"
/// (a whole hour is "3 h"), under an hour "45 min", under a minute (or zero or
/// negative) "less than 1 min". Never negative.
String timeLeftWords(Duration left) {
  final m = left.inMinutes;
  if (left >= const Duration(hours: 24)) return '${(m + 59) ~/ 60} h';
  if (m < 1) return 'less than 1 min';
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '$r min';
  return r == 0 ? '$h h' : '$h h $r min';
}

/// Exact time left for the Details sheet ([timeLeftWords]). Zero or negative:
/// "none left".
String exactTimeLeft(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  if (left <= Duration.zero) return 'none left';
  return timeLeftWords(left);
}

String _two(int n) => n < 10 ? '0$n' : '$n';

/// "14:05" (24-hour clock).
String clockText(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "Today, 13:52", "Yesterday, 22:10" or "2 days ago, 09:00" for [t] seen from
/// [now] (calendar days, not 24 h blocks).
String receivedText(DateTime t, DateTime now) {
  final a = DateTime(t.year, t.month, t.day);
  final b = DateTime(now.year, now.month, now.day);
  final days = b.difference(a).inDays;
  final day = days <= 0 ? 'Today' : (days == 1 ? 'Yesterday' : '$days days ago');
  return '$day, ${clockText(t)}';
}

/// The type name the Categorize sheet and Add use.
String detailsTypeLabel(SmsSourceType t) => switch (t) {
      SmsSourceType.sendMoney => 'Send Money',
      SmsSourceType.payBill => 'Paybill',
      SmsSourceType.buyGoods => 'Buy Goods',
      SmsSourceType.pochi => 'Pochi la Biashara',
      SmsSourceType.agentWithdrawal => 'Withdrawal',
      SmsSourceType.airtime => 'Airtime',
    };

/// The first [words] words of [body] with every word that holds a digit, or is
/// three or more capital letters, replaced by "…". Never more than the first
/// words, so a name or an amount further in is never reached. Empty body: ''.
String maskedFirstWords(String body, {int words = 3}) {
  final parts = body.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(words);
  final caps = RegExp(r'^[A-Z]{3,}[.,:;]?$');
  return parts
      .map((w) => RegExp(r'\d').hasMatch(w) || caps.hasMatch(w) ? '…' : w)
      .join(' ');
}

/// One row of the sheet: a label and its value.
class DetailLine {
  const DetailLine(this.label, this.value);
  final String label;
  final String value;
}

/// The content of the Details sheet. [lines] are in display order; [note] is
/// the quiet sentence under them.
class MessageDetails {
  const MessageDetails({required this.kind, required this.lines, this.note});
  final WaitingKind kind;
  final List<DetailLine> lines;
  final String? note;

  String? valueOf(String label) {
    for (final l in lines) {
      if (l.label == label) return l.value;
    }
    return null;
  }
}

// WORDING-DRAFT: every label and sentence below is new UI text for the PM to
// review (taken from the mock's Message details sheet).
const String kDetailsTitle = 'Message details';
const String kDetailsSenderLabel = 'Sender';
const String kDetailsReceivedLabel = 'Received';
const String kDetailsAmountLabel = 'Amount';
const String kDetailsUnderstoodLabel = 'What mmogo understood';
const String kDetailsTimeLeftLabel = 'Time left';
const String kDetailsWaitingForLabel = 'Waiting for';
const String kDetailsWhatFailedLabel = 'What failed';
const String kDetailsFirstWordsLabel = 'First words';
const String kDetailsStatusLabel = 'Status';
const String kDetailsFailedValue = 'mmogo could not read this message';
const String kDetailsExpiredValue = 'Expired. No longer on this phone';
const String kDetailsNoteReady = 'Not read yet. Tap Parse to read it. Nothing is saved yet.';
const String kDetailsNoteWaiting =
    'Parsed, not saved yet. It is not counted in your totals until you categorize it.';
const String kDetailsNoteUnreadable =
    'Codes, numbers and amounts are left out on purpose. Open the message in your phone’s Messages, copy it, then paste it in Add.';
const String kDetailsNoteGone = 'Find it in your phone’s Messages, copy it, then paste it in Add.';
const String kDetailsClose = 'Close';
const String kDetailsLink = 'Details';
const String kDetailsMissing = 'This message is no longer in the list.';

/// Builds the sheet content for [item] at [now].
///
/// [fields] are the parser's fields (a parsed item has them; a ready message
/// gets them from a one-time look at the held text); [firstWords] is
/// [maskedFirstWords] of an unreadable message. Neither the body nor a code is
/// passed in or shown.
MessageDetails buildMessageDetails(
  WaitingItem item,
  DateTime now, {
  ParsedSmsFields? fields,
  String? firstWords,
  bool expired = false,
}) {
  final f = fields ?? item.parsed;
  final received = DetailLine(kDetailsReceivedLabel, receivedText(item.heldAt, now));
  const sender = DetailLine(kDetailsSenderLabel, kDetailsSender);
  final left = exactTimeLeft(item.expiresAt, now);
  final sameDay = item.expiresAt.year == now.year && item.expiresAt.month == now.month && item.expiresAt.day == now.day;
  final timeLeft = '$left (expires at ${clockText(item.expiresAt)}${sameDay ? '' : ' tomorrow'})';
  final kind = item.kind == WaitingKind.waitingCategory ? item.kind : (expired ? WaitingKind.gone : item.kind);

  switch (kind) {
    case WaitingKind.gone:
      return MessageDetails(
        kind: kind,
        lines: [sender, received, const DetailLine(kDetailsStatusLabel, kDetailsExpiredValue)],
        note: kDetailsNoteGone,
      );
    case WaitingKind.unreadable:
      return MessageDetails(
        kind: kind,
        lines: [
          sender,
          received,
          const DetailLine(kDetailsWhatFailedLabel, kDetailsFailedValue),
          if (firstWords != null && firstWords.isNotEmpty) DetailLine(kDetailsFirstWordsLabel, '“$firstWords…”'),
          DetailLine(kDetailsTimeLeftLabel, timeLeft),
        ],
        note: kDetailsNoteUnreadable,
      );
    case WaitingKind.readyToParse:
    case WaitingKind.waitingCategory:
      final who = (f?.counterpartyLabel ?? '').trim();
      final understood = f == null ? null : detailsTypeLabel(f.sourceType) + (who.isEmpty ? '' : ', $who');
      final waiting = kind == WaitingKind.waitingCategory;
      return MessageDetails(
        kind: kind,
        lines: [
          sender,
          received,
          if (f != null) DetailLine(kDetailsAmountLabel, kshTrim(f.amountCents)),
          if (understood != null) DetailLine(kDetailsUnderstoodLabel, understood),
          if (waiting)
            const DetailLine(kDetailsWaitingForLabel, 'A category')
          else
            DetailLine(kDetailsTimeLeftLabel, timeLeft),
        ],
        note: waiting ? kDetailsNoteWaiting : kDetailsNoteReady,
      );
  }
}
