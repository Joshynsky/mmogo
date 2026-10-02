import 'package:flutter/material.dart';

import '../../../data/updates/untrusted_text.dart';
import '../../../data/updates/updates_inbox.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import '../backup/backup_format.dart';
import 'notes_text.dart';

/// One notice on the Updates page: version tag, received date, a "New" pill
/// while unread, a heading, the notes as PLAIN text (never selectable, no
/// link spans), "Show all notes" when they are longer than the collapsed
/// view, and "See what's new" (which opens the mmogo page, a constant) on a
/// release notice. The welcome notice has no "See what's new".
class NoticeCard extends StatefulWidget {
  const NoticeCard({super.key, required this.notice, required this.onSeeWhatsNew, this.onOpenBackup});

  final Notice notice;
  final VoidCallback onSeeWhatsNew;

  /// Opens Backup and restore (the backup-paused notice's button).
  final VoidCallback? onOpenBackup;

  /// Lines shown before "Show all notes".
  static const collapsedLines = 6;

  @override
  State<NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<NoticeCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final n = widget.notice;
    final title = n.welcome
        ? kWelcomeNoticeTitle
        : n.backupPaused
            ? kBackupPausedNoticeTitle
            : updateNoticeTitle(n.tag);
    // The welcome and backup-paused wording lives in data_copy.dart, not in storage.
    final notes = n.welcome
        ? kWelcomeNoticeNotes
        : n.backupPaused
            ? kBackupPausedNoticeNotes
            : plainReleaseNotes(n.notes);
    final notesStyle = TextStyle(fontSize: 13, height: 1.5, color: palette.softInk);

    return Container(
      key: Key('notice-${n.tag}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: n.read ? null : Border(left: BorderSide(color: palette.primary, width: 4)),
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: palette.tint, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  n.backupPaused ? 'Backup' : n.tag,
                  style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: palette.tintInk),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Received ${formatBackupDay(n.receivedAt)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.mutedInk),
                ),
              ),
              if (!n.read)
                Container(
                  key: const Key('noticeNewPill'),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: palette.primary, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    kUpdatesNewPill.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: palette.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.3, color: palette.ink)),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) {
                final painter = TextPainter(
                  text: TextSpan(text: notes, style: notesStyle),
                  maxLines: NoticeCard.collapsedLines,
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout(maxWidth: box.maxWidth);
                final longer = painter.didExceedMaxLines;
                painter.dispose();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Plain Text on purpose: not SelectableText, no spans.
                    Text(
                      notes,
                      key: const Key('noticeNotes'),
                      maxLines: _open ? UntrustedText.maxLines : NoticeCard.collapsedLines,
                      overflow: TextOverflow.ellipsis,
                      style: notesStyle,
                    ),
                    if (longer || _open)
                      TextButton(
                        key: const Key('noticeShowAll'),
                        onPressed: () => setState(() => _open = !_open),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: palette.primary,
                        ),
                        child: Text(
                          _open ? kUpdatesShowFewerNotes : kUpdatesShowAllNotes,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          if (n.backupPaused) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: FilledButton(
                key: const Key('noticeOpenBackup'),
                onPressed: widget.onOpenBackup,
                style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.onPrimary),
                child: const Text(kBackupPausedNoticeButton),
              ),
            ),
          ] else if (!n.welcome) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: FilledButton(
                key: const Key('noticeSeeWhatsNew'),
                onPressed: widget.onSeeWhatsNew,
                style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.onPrimary),
                child: const Text(kUpdatesSeeWhatsNew),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
