/// §AUTOREAD.WAITING_ROW — one row of the To parse / To categorize lists.
///
/// Lives under `lib/autoread/` (the standard build drops it) and is reached
/// from shared code only inside `if (kAutoReadCompiled)`. Built on the shared
/// `NotifRowShell`. It shows nothing of the raw message: a ready row says only
/// "M-Pesa message ready" until a description arrives; a waiting row shows the
/// parsed amount and name.
/// Waiting and ready rows have no dismiss or remove of any kind; unreadable
/// and gone rows have Remove (with the page's confirmation, not built here).
library;

import 'package:flutter/material.dart';

import '../../domain/format/money.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/screens/notifications/news_row.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/notif_colors.dart';
import '../../ui/widgets/notif_shape_icon.dart';
import '../logic/message_details.dart' show kDetailsLink, unreadableSubline;
import '../logic/waiting_logic.dart';
import '../model/held_description.dart';
import '../model/waiting_item.dart';
import 'notifications_autoread_copy.dart';
import 'unreadable_copy.dart';

// NOT IN THE COPY FILE (taken from the signed mock's row keywords and the
// brief's title pattern; the orchestrator may move them into the copy file).
const String kSpokenReadyToParse = 'Ready to parse';
const String kSpokenReadyCouldNotRead = 'Ready to parse, could not be read';
const String kSpokenWaitingCategory = 'Waiting for a category';
const String kSpokenMessageGone = 'Message gone';
const String kTitleSent = 'Sent';
const String kTitlePaid = 'Paid';
const String kTitleWithdrew = 'Withdrew';
const String kTitleAirtime = 'Bought airtime';

/// "Sent Ksh 640 to Jane Wanjiku" from the parsed fields (no raw text). The
/// name part is left out when the message carried none.
String waitingTitle(ParsedSmsFields f) {
  final amount = kshTrim(f.amountCents);
  final who = (f.counterpartyLabel ?? '').trim();
  final to = who.isEmpty ? '' : ' to $who';
  switch (f.sourceType) {
    case SmsSourceType.sendMoney:
    case SmsSourceType.pochi:
      return '$kTitleSent $amount$to';
    case SmsSourceType.payBill:
    case SmsSourceType.buyGoods:
      return '$kTitlePaid $amount$to';
    case SmsSourceType.agentWithdrawal:
      return '$kTitleWithdrew $amount${who.isEmpty ? '' : ' from $who'}';
    case SmsSourceType.airtime:
      return '$kTitleAirtime $amount';
  }
}

String _two(int n) => n < 10 ? '0$n' : '$n';

/// "18-10-2026, 09:12" (dd-mm-yyyy) from epoch millis.
String _whenText(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${_two(d.day)}-${_two(d.month)}-${d.year}, ${_two(d.hour)}:${_two(d.minute)}';
}

/// One waiting auto-read item. Every kind is handled; the kind used is
/// `effectiveKind(item, now)`, so a held message past the window shows as gone.
class WaitingRow extends StatelessWidget {
  const WaitingRow(
    this.item,
    this.now, {
    super.key,
    this.onParse,
    this.onCategorize,
    this.onPaste,
    this.onRemove,
    this.onDetails,
    this.description,
  });

  final WaitingItem item;
  final DateTime now;
  final VoidCallback? onParse;
  final VoidCallback? onCategorize;
  final VoidCallback? onPaste;
  final VoidCallback? onRemove;

  /// Opens the Details sheet. Null: no Details link (rows without a wired page).
  final VoidCallback? onDetails;

  /// What a held message is, in words (memory only, may be null: the row then
  /// keeps its plain title). Used for ready and unreadable rows only.
  final HeldDescription? description;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final kind = effectiveKind(item, now);
    final age = rowAgeText(item.heldAt, now);

    final String title;
    final String keyword;
    String? subtitle;
    String foot;
    NotifRowAction? action;
    NotifRowAction? link;
    Widget? extra;
    Widget icon;

    switch (kind) {
      case WaitingKind.readyToParse:
        final what = description?.what;
        title = what ?? kReadyRowTitle;
        subtitle = what == null ? null : kReadyRowFine;
        keyword = kSpokenReadyToParse;
        foot = '$age · ${expiresInLine(expiresLeft(item, now))}';
        action = NotifRowAction(
          label: kActionParse,
          semantics: '$kActionParse the M-Pesa message received ${spokenTime(age)}',
          onTap: onParse,
          fill: true,
        );
        icon = _diamond(p, false);
      case WaitingKind.waitingCategory:
        final f = item.parsed;
        title = f == null ? kSpokenWaitingCategory : waitingTitle(f);
        keyword = kSpokenWaitingCategory;
        subtitle = f == null ? null : _whenText(f.transactionOccurredAt);
        foot = age;
        action = NotifRowAction(
          label: kActionCategorize,
          semantics: '$kActionCategorize: $title',
          onTap: onCategorize,
          fill: true,
        );
        icon = _pill(p);
        if (item.sameCodeDifferentDetails) extra = _FlagLine(palette: p);
      case WaitingKind.unreadable:
        final notice = description?.notice ?? false;
        title = notice ? kNoticeTitle : kUnreadableTitle;
        subtitle = notice ? kNoticeSub : unreadableSubline(description, item.heldAt);
        keyword = notice ? kNoticeTitle : kSpokenReadyCouldNotRead;
        foot = 'Received $age';
        action = null; // tap the row or Details to see how to paste it
        link = _remove();
        icon = _diamond(p, true);
      case WaitingKind.gone:
        title = kGoneLine;
        keyword = kSpokenMessageGone;
        subtitle = kGoneRecovery;
        foot = kGoneFooter;
        action = _paste();
        link = _remove();
        icon = _diamond(p, true);
    }
    if (kind == WaitingKind.readyToParse) foot = 'Received $foot';

    final spoken = [
      keyword,
      title,
      ?subtitle,
      if (item.sameCodeDifferentDetails) kFlaggedLine,
      spokenTime(foot),
    ].map((s) => s.endsWith('.') ? s : '$s.').join(' ');

    return NotifRowShell(
      icon: icon,
      title: title,
      subtitle: subtitle,
      footText: foot,
      action: action,
      link: link,
      leadLink: onDetails == null ? null : _details(title),
      onOpen: kind == WaitingKind.unreadable ? onDetails : null,
      extra: extra,
      spokenLabel: spoken,
    );
  }

  // SIGNED (PM 13-11-2026): the label "Details".
  NotifRowAction _details(String title) => NotifRowAction(
        label: kDetailsLink,
        semantics: '$kDetailsLink of this message: $title',
        onTap: onDetails,
      );

  NotifRowAction _paste() => NotifRowAction(
        label: kActionPaste,
        semantics: 'Paste the message instead',
        onTap: onPaste,
        fill: true,
      );

  NotifRowAction _remove() => NotifRowAction(
        label: kActionRemove,
        semantics: '$kActionRemove this message',
        onTap: onRemove,
      );

  Widget _diamond(AppPalette p, bool dim) {
    final icon = NotifShapeIcon(
      shape: NotifShape.diamondDot,
      color: notifShapeColor(p, NotifShape.diamondDot),
      ink: notifShapeInk(p, NotifShape.diamondDot),
      size: 26,
    );
    return dim ? Opacity(key: const Key('waitingRowDimIcon'), opacity: 0.45, child: icon) : icon;
  }

  Widget _pill(AppPalette p) {
    // The mock's waiting icon: a wide pill with a tag glyph (no number).
    return Container(
      key: const Key('waitingRowPillIcon'),
      width: 32,
      height: 22,
      decoration: BoxDecoration(
        color: notifShapeColor(p, NotifShape.pill),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.sell, size: 14, color: notifShapeInk(p, NotifShape.pill)),
    );
  }
}

/// The flagged line: same code, different details. Icon plus words, not
/// colour alone.
class _FlagLine extends StatelessWidget {
  const _FlagLine({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final accent = notifShapeColor(palette, NotifShape.pill);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          key: const Key('waitingRowFlag'),
          color: palette.textCard,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.warning_amber_rounded, size: 16, color: accent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            kFlaggedLine,
                            style: TextStyle(color: palette.ink, fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
