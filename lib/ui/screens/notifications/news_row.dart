/// §NOTIF.NEWS_ROW — the row widgets of the Notifications list.
///
/// [NotifRowShell] is the shared layout (icon, title, optional subtitle, age
/// line, one action pill on the right, one quiet link); [NewsRow] is the news
/// flavor (notice, update, What's new). Rows take data and callbacks, never a
/// repository. Shared by both flavors. Other row kinds build on the shell.
library;

import 'package:flutter/material.dart';

import '../../../domain/notifications/news_item.dart';
import '../../copy/notifications_copy.dart';
import '../../copy/other_version_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/notif_colors.dart';
import '../../widgets/notif_shape_icon.dart';
import '../../widgets/tap_target.dart';
import 'news_row_style.dart';

/// The age line of a row: "just now", "5 min ago", "3 h ago", "2 days ago"
/// (the mock's `ago`). A time in the future counts as "just now".
String rowAgeText(DateTime from, DateTime now) {
  final m = now.difference(from).inMinutes;
  if (m < 2) return 'just now';
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h < 48) return '$h h ago';
  return '${h ~/ 24} days ago';
}

/// The spoken form of a short time text ("1 h" is "1 hour", "4 h" is "4 hours").
String spokenTime(String s) => s
    .replaceAllMapped(RegExp(r'\b1 h\b'), (_) => '1 hour')
    .replaceAllMapped(RegExp(r' h\b'), (_) => ' hours')
    .replaceAllMapped(RegExp(r' min\b'), (_) => ' minutes');

/// The icon of a read row is drawn at this opacity. The mock fades the whole
/// row to 0.8, but that takes muted text under 4.5:1 in the light palettes, so
/// only the icon fades; the title goes to the muted ink and normal weight.
const double kReadIconOpacity = 0.75;

/// A secondary text or action on a row: [label] is what is shown, [semantics]
/// what a screen reader says (starts with [label]).
class NotifRowAction {
  const NotifRowAction({required this.label, required this.semantics, required this.onTap, this.fill = false});

  final String label;
  final String semantics;
  final VoidCallback? onTap;

  /// True for the filled (primary) pill, false for the outlined pill.
  final bool fill;
}

/// The shared row layout of the Notifications page, on the palette's `surface`
/// (as the signed mock does).
class NotifRowShell extends StatelessWidget {
  const NotifRowShell({
    super.key,
    required this.icon,
    required this.title,
    required this.spokenLabel,
    this.boldTitle = true,
    this.showUnreadDot = false,
    this.subtitle,
    this.footText,
    this.action,
    this.link,
    this.extra,
    this.dimmed = false,
    this.onOpen,
  });

  /// The kind icon (about 34 px box). Faded when [dimmed].
  final Widget icon;
  final String title;
  final String? subtitle;

  /// The age line (and, for held messages, the quiet expiry).
  final String? footText;
  final bool boldTitle;
  final bool showUnreadDot;

  /// The ONE action pill on the right.
  final NotifRowAction? action;

  /// The quiet link at the end of the age line (Dismiss, Remove).
  final NotifRowAction? link;

  /// Extra content under the row (the flagged line).
  final Widget? extra;
  final bool dimmed;

  /// A tap on the text part of the row (not a separate screen-reader button).
  final VoidCallback? onOpen;

  /// What a screen reader says for the whole row: kind, title, details, age.
  final String spokenLabel;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final text = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                if (showUnreadDot)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        key: const Key('notifRowUnreadDot'),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                TextSpan(text: title),
              ],
            ),
            style: TextStyle(
              color: dimmed ? p.mutedInk : p.ink,
              fontSize: 14,
              height: 1.3,
              fontWeight: boldTitle ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(subtitle!, style: TextStyle(color: p.mutedInk, fontSize: 12.5, height: 1.35)),
            ),
        ],
      ),
    );

    final body = Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: p.brightness == Brightness.dark
            ? null
            : const [BoxShadow(color: Color(0x0F0A2832), blurRadius: 6, offset: Offset(0, 1))],
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 34,
                  child: Center(
                    child: dimmed ? Opacity(key: const Key('notifRowDimIcon'), opacity: kReadIconOpacity, child: icon) : icon,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ExcludeSemantics(
                  child: onOpen == null
                      ? text
                      : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onOpen, child: text),
                ),
              ),
              if (action != null) ...[const SizedBox(width: 10), _ActionPill(action: action!, palette: p)],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (footText != null)
                  Expanded(
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: link == null ? 8 : 0, top: link == null ? 4 : 0),
                        child: Text(
                          footText!,
                          style: TextStyle(color: p.mutedInk, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (link != null) _LinkButton(action: link!, palette: p),
              ],
            ),
          ),
          if (extra != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: extra),
        ],
      ),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: spokenLabel,
      child: body,
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.action, required this.palette});

  final NotifRowAction action;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final bg = action.fill ? palette.primary : Colors.transparent;
    final fg = action.fill ? palette.onPrimary : palette.primary;
    return Semantics(
      button: true,
      label: action.semantics,
      excludeSemantics: true,
      onTap: action.onTap,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: palette.primary, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: action.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  action.label,
                  style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.action, required this.palette});

  final NotifRowAction action;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.semantics,
      excludeSemantics: true,
      onTap: action.onTap,
      child: InkWell(
        onTap: action.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: kMinTapTarget, minHeight: kMinTapTarget),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 6),
            child: Center(
              widthFactor: 1,
              child: Text(
                action.label,
                style: TextStyle(
                  color: palette.mutedInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: palette.mutedInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One news row: a notice, an update or a What's new item.
///
/// Unread: dot and bold title, the main action (Read for a notice or What's
/// new, Update for an update) as a filled pill and a quiet Dismiss link. Read:
/// dimmed, the age line ends with " · Read" (so it is not colour alone), and
/// the one action is Remove. [onOpen] is a tap on the text part of the row.
class NewsRow extends StatelessWidget {
  const NewsRow(
    this.item,
    this.now, {
    super.key,
    this.onOpen,
    this.onUpdate,
    this.onDismiss,
    this.onRemove,
    this.onRead,
    this.onSeeMore,
  });

  final NewsItem item;
  final DateTime now;
  final VoidCallback? onOpen;
  final VoidCallback? onUpdate;
  final VoidCallback? onDismiss;
  final VoidCallback? onRemove;
  final VoidCallback? onRead;

  /// The action of a permanent item (opens the mmogo page).
  final VoidCallback? onSeeMore;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final style = styleFor(item);
    final shape = item.kind == NewsKind.notice ? NotifShape.star : NotifShape.arrow;
    final age = rowAgeText(item.createdAt, now) + (item.isUnread ? '' : kNewsAgeReadSuffix);

    final NotifRowAction? action;
    NotifRowAction? link;
    if (item.permanent) {
      // Never dismissed or removed: no pill, only the link under the text (the
      // long body needs the full width).
      action = null;
      link = NotifRowAction(
        label: kOtherVersionNoticeAction,
        semantics: kOtherVersionNoticeActionSpoken,
        onTap: onSeeMore,
      );
    } else if (!item.isUnread) {
      action = NotifRowAction(
        label: kNewsActionRemove,
        semantics: '$kNewsActionRemove: ${item.title}',
        onTap: onRemove,
      );
    } else {
      action = item.kind == NewsKind.update
          ? NotifRowAction(
              label: kNewsActionUpdate,
              semantics: '$kNewsActionUpdate: ${item.title}',
              onTap: onUpdate,
              fill: true,
            )
          : NotifRowAction(
              label: kNewsActionRead,
              semantics: '$kNewsActionRead: ${item.title}',
              onTap: onRead,
              fill: true,
            );
      link = NotifRowAction(
        label: kNewsActionDismiss,
        semantics: '$kNewsActionDismiss: ${item.title}',
        onTap: onDismiss,
      );
    }

    return NotifRowShell(
      icon: NotifShapeIcon(
        shape: shape,
        color: notifShapeColor(p, shape),
        ink: notifShapeInk(p, shape),
        size: shape == NotifShape.star ? 24 : 26,
      ),
      title: item.title,
      subtitle: item.body,
      boldTitle: style.boldTitle,
      showUnreadDot: style.showUnreadDot,
      dimmed: style.dimmed,
      footText: age,
      action: action,
      link: link,
      onOpen: onOpen,
      spokenLabel: '${style.spokenPrefix}. ${item.title}. ${item.body == null ? '' : '${item.body} '}${spokenTime(age)}.',
    );
  }
}
