import 'package:flutter/material.dart';

import '../../../data/backup/backup_service.dart';
import '../../copy/backup_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';
import 'backup_sheet_shell.dart';
import 'skipped_rows_list.dart';

/// §SCREEN.BACKUP.SHARED — 0.1.2 S10b (BP2, A3). After "Back up now" handed
/// the file to the share sheet: what went out (counts), what was tidied, what
/// was left out (with "Show which"), and the one honest sentence about where
/// it went. It claims nothing else about the file being saved. Done is the
/// default; Back, a tap outside and a swipe down all just close it.

/// "N entries could not be made valid ..." (or "items") with "Show which"
/// and the inline list. Used on the Back up now card (until the next Back up
/// now) and in the Backup shared sheet.
class BackupLeftOutNote extends StatefulWidget {
  const BackupLeftOutNote({super.key, required this.palette, required this.export});

  final AppPalette palette;
  final BackupExport export;

  @override
  State<BackupLeftOutNote> createState() => _BackupLeftOutNoteState();
}

class _BackupLeftOutNoteState extends State<BackupLeftOutNote> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.export;
    final p = widget.palette;
    final n = e.skippedCount;
    final entries = e.skipped.every((s) => s.table == 'transactions');
    return Container(
      key: const Key('backupLeftOutNote'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              backupLeftOutLine(n, allEntries: entries),
              key: const Key('backupLeftOutLine'),
              style: TextStyle(fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600, color: p.tintInk),
            ),
          ),
          ShowWhichButton(palette: p, open: _open, onTap: () => setState(() => _open = !_open)),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SkippedRowsList(
                palette: p,
                rows: e.skippedRows,
                total: n,
                title: notIncludedTitle(n),
                footer: kStillInApp,
                allowShowAll: true,
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showBackupSharedSheet(BuildContext context, BackupExport export) {
  final palette = AppPalette.of(context);
  return showBackupSheet<void>(context, (_) => _BackupSharedSheet(palette: palette, export: export));
}

class _BackupSharedSheet extends StatelessWidget {
  const _BackupSharedSheet({required this.palette, required this.export});

  final AppPalette palette;
  final BackupExport export;

  @override
  Widget build(BuildContext context) {
    final c = export.sharedCounts;
    TextStyle ink({bool bold = false}) => TextStyle(
      fontSize: 13.5,
      height: 1.45,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: palette.ink,
    );
    return BackupSheetShell(
      palette: palette,
      title: kBackupSharedTitle,
      body: [
        Text(
          backupSharedCountsLine(c.transactions, c.categories, export.counterpartyMap, userCategories: c.userCategories),
          key: const Key('backupSharedCounts'),
          style: ink(),
        ),
        if (export.repairedCount > 0)
          Text(backupTidiedLine(export.repairedCount), key: const Key('backupSharedTidied'), style: ink()),
        if (export.skippedCount > 0) BackupLeftOutNote(palette: palette, export: export),
        Text(kBackupFilesApp, key: const Key('backupSharedFilesApp'), style: ink(bold: true)),
      ],
      actions: FilledButton(
        key: const Key('backupSharedDone'),
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(),
        style: FilledButton.styleFrom(
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
        ),
        child: const Text(kDone),
      ),
    );
  }
}
