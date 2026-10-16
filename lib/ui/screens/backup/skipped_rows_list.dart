import 'package:flutter/material.dart';

import '../../../data/backup/skipped_row_describer.dart';
import '../../copy/backup_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';

/// §SCREEN.BACKUP.SKIPPED — 0.1.2 S10b (A2c, A3, BP1). ONE list for "Not
/// included in this backup (N)", "Entries that will be lost (N)" and "Entries
/// that were lost (N)". It shows described rows only: a date (dd-mm-yyyy) and
/// the type for an entry that could be read, otherwise "An entry that could
/// not be read" / "A category" / "A saved receiver", then (optionally) a
/// reason. Never an amount, a name, a phone number or a code.
///
/// The list holds [rows] (maybe fewer than [total]); the title always shows
/// the exact [total]. The first 20 rows show; with [allowShowAll] and more
/// rows in [rows] a "Show all" button reveals them (the Backup page and the
/// Backup shared sheet, which hold the full list). "and M more not shown"
/// counts what is still hidden. The box has a height cap and its own scroll,
/// so the buttons around it stay on screen.

/// The text of one row.
String skippedRowText(SkippedRowInfo r, {required bool showReason}) {
  final head = switch (r.kind) {
    SkipKind.category => kRowCategory,
    SkipKind.savedReceiver => kRowSavedReceiver,
    SkipKind.entry =>
      r.unreadable ? kRowUnreadableEntry : '${backupDmy(r.date!)}, ${r.typeName ?? ''}',
  };
  if (!showReason) return head;
  // "An entry that could not be read: it could not be read" says it twice.
  if (r.unreadable && r.reason == SkipReason.couldNotRead) return head;
  return '$head: ${skipReasonText(r.reason)}';
}

String skipReasonText(SkipReason r) => switch (r) {
  SkipReason.missingDetail => kReasonMissingDetail,
  SkipReason.notAllowed => kReasonNotAllowed,
  SkipReason.couldNotRead => kReasonCouldNotRead,
  SkipReason.cascaded => kReasonCascaded,
};

/// True when every described row is an entry (the "entries" / "items" word).
bool allEntries(Iterable<SkippedRowInfo> rows) => rows.every((r) => r.kind == SkipKind.entry);

class SkippedRowsList extends StatefulWidget {
  const SkippedRowsList({
    super.key,
    required this.palette,
    required this.rows,
    required this.total,
    required this.title,
    required this.footer,
    this.showReasons = true,
    this.allowShowAll = false,
    this.maxHeight = 240,
  });

  final AppPalette palette;
  final List<SkippedRowInfo> rows;

  /// N, exactly.
  final int total;
  final String title;
  final String footer;
  final bool showReasons;

  /// A "Show all" button when [rows] holds more than the first 20.
  final bool allowShowAll;
  final double maxHeight;

  @override
  State<SkippedRowsList> createState() => _SkippedRowsListState();
}

class _SkippedRowsListState extends State<SkippedRowsList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final rows = widget.rows;
    final canShowAll = widget.allowShowAll && rows.length > SkippedSummary.cap;
    final cut = canShowAll && !_all;
    final shown = cut ? rows.sublist(0, SkippedSummary.cap) : rows;
    final hidden = widget.total - shown.length;
    return Column(
      key: const Key('skippedRowsList'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.title,
            key: const Key('skippedRowsTitle'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.ink),
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: Scrollbar(
            child: SingleChildScrollView(
              key: const Key('skippedRowsScroll'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Container(
                      key: Key('skippedRow-$i'),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                      child: Text(
                        skippedRowText(shown[i], showReason: widget.showReasons),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink),
                      ),
                    ),
                  if (cut)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(kShowingFirst20, style: TextStyle(fontSize: 12.5, color: p.mutedInk)),
                    ),
                  if (hidden > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Text(
                        moreNotShown(hidden),
                        key: const Key('skippedRowsMore'),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (cut)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('skippedShowAll'),
              onPressed: () => setState(() => _all = true),
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                foregroundColor: p.primary,
              ),
              child: const Text(kShowAll, style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        const SizedBox(height: 4),
        Text(widget.footer, key: const Key('skippedRowsFooter'), style: TextStyle(fontSize: 12.5, color: p.mutedInk)),
      ],
    );
  }
}

/// The "Show which" toggle that opens/closes an inline [SkippedRowsList].
class ShowWhichButton extends StatelessWidget {
  const ShowWhichButton({super.key, required this.palette, required this.open, required this.onTap});

  final AppPalette palette;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        expanded: open,
        child: TextButton(
          key: const Key('showWhichButton'),
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            foregroundColor: palette.primary,
          ),
          child: Text(
            open ? kHideList : kShowWhich,
            style: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
          ),
        ),
      ),
    );
  }
}
