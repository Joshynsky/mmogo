import 'package:flutter/material.dart';

import '../../../data/backup/restore_types.dart';
import '../../copy/backup_copy.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/error_notes.dart';
import '../../widgets/tap_target.dart';
import 'backup_sheet_shell.dart';
import 'skipped_rows_list.dart';

/// §SCREEN.BACKUP.REPLACE_SHEETS — 0.1.2 S10b (A2c, RS1, CB8, A9). The two
/// sheets that stand between "Replace" and the write:
///
///  1. the WARNING, only when `ReplacePreview.skippedCount > 0`: entries that
///     cannot go into the safety copy are lost for good and Undo cannot bring
///     them back. The user must tick "I understand they cannot be recovered"
///     before Continue works;
///  2. the CONFIRM: what is removed, "included + lost = live" for the
///     transactions, the remembered-recipients sentence, "Undo is not exact".
///
/// On both, Cancel is the large filled default and holds the initial focus;
/// a tap outside, Back and a swipe down are Cancel. The buttons are pinned
/// below the scroll area. Words say "lost" / "not kept in the safety copy",
/// never "skipped". Nothing here shows a name, an amount or a number from a
/// row: counts, dates and types only.

/// The warning. `true` only on Continue (after the tick).
Future<bool> showReplaceWarningSheet(BuildContext context, ReplacePreview rp, {bool changed = false}) async {
  final palette = AppPalette.of(context);
  final ok = await showBackupSheet<bool>(context, (_) => ReplaceWarningSheet(palette: palette, preview: rp, changed: changed));
  return ok ?? false;
}

class ReplaceWarningSheet extends StatefulWidget {
  const ReplaceWarningSheet({super.key, required this.palette, required this.preview, this.changed = false});

  final AppPalette palette;
  final ReplacePreview preview;

  /// The count changed while the user was looking (A9c): say so.
  final bool changed;

  @override
  State<ReplaceWarningSheet> createState() => _ReplaceWarningSheetState();
}

class _ReplaceWarningSheetState extends State<ReplaceWarningSheet> {
  bool _ticked = false;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final rp = widget.preview;
    final n = rp.skippedCount;
    final entries = allEntries(rp.skipped.shown);
    return BackupSheetShell(
      key: const Key('replaceWarningSheet'),
      palette: p,
      title: kLostWarningTitle,
      body: [
        if (widget.changed)
          Semantics(
            liveRegion: true,
            child: Text(
              kChangedWhileChecking,
              key: const Key('replaceChangedNote'),
              style: TextStyle(fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w800, color: p.ink),
            ),
          ),
        Text(
          lostWarningBody(n, allEntries: entries),
          key: const Key('replaceWarningBody'),
          style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShowWhichButton(palette: p, open: _open, onTap: () => setState(() => _open = !_open)),
            if (_open)
              SkippedRowsList(
                palette: p,
                rows: rp.skipped.shown,
                total: n,
                title: lostWarningListTitle(n),
                footer: kOnlyDateAndType,
                showReasons: false,
              ),
          ],
        ),
        _TickRow(
          key: const Key('replaceTick'),
          palette: p,
          label: kLostTickLabel,
          checked: _ticked,
          onTap: () => setState(() => _ticked = !_ticked),
        ),
      ],
      actions: SheetActions(
        secondary: FilledButton(
          key: const Key('replaceWarnCancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          style: FilledButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
          ),
          child: const Text(kCancel),
        ),
        primary: OutlinedButton(
          key: const Key('replaceWarnContinue'),
          onPressed: _ticked ? () => Navigator.of(context).pop(true) : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            foregroundColor: p.ink,
            side: BorderSide(color: _ticked ? p.ink : p.line, width: 1.5),
          ),
          child: Semantics(
            hint: _ticked ? null : kLostTickLabel,
            child: const Text(kContinue),
          ),
        ),
      ),
    );
  }
}

class _TickRow extends StatelessWidget {
  const _TickRow({super.key, required this.palette, required this.label, required this.checked, required this.onTap});

  final AppPalette palette;
  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Row(
            children: [
              Icon(
                checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 24,
                color: checked ? palette.primary : palette.mutedInk,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Replace confirm. `true` only on "Replace everything". [error] is a
/// failure of the last try, shown in a red box with the buttons back (mock M3).
Future<bool> showReplaceConfirmSheet(
  BuildContext context,
  RestorePreview file,
  ReplacePreview rp, {
  String? error,
}) async {
  final palette = AppPalette.of(context);
  final ok = await showBackupSheet<bool>(
    context,
    (_) => ReplaceConfirmSheet(palette: palette, file: file, preview: rp, error: error),
  );
  return ok ?? false;
}

class ReplaceConfirmSheet extends StatelessWidget {
  const ReplaceConfirmSheet({super.key, required this.palette, required this.file, required this.preview, this.error});

  final AppPalette palette;
  final RestorePreview file;
  final ReplacePreview preview;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final rp = preview;
    final id = rp.identity;
    final lost = rp.skippedCount;
    final fileTotal = file.fileClassifications + file.fileTransactions + file.fileCounterpartyMap;
    final lostCats = id.classifications.skipped;
    final lostMap = id.counterpartyMap.skipped;
    TextStyle small({bool bold = false}) =>
        TextStyle(fontSize: 12.5, height: 1.45, fontWeight: bold ? FontWeight.w800 : FontWeight.w400, color: p.ink);
    return BackupSheetShell(
      key: const Key('restoreReplaceDialog'),
      palette: p,
      title: kReplaceConfirmTitle,
      body: [
        Text(
          replaceRemovesLine(
            rp.phoneTransactions + rp.phoneRecentlyDeleted,
            rp.phoneUserClassifications,
            rp.phoneCounterpartyMap,
          ),
          key: const Key('restoreReplaceRemoves'),
          style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
        ),
        _KeyValue(
          palette: p,
          label: 'This phone now',
          value: replaceCountsLine(rp.phoneTransactions, rp.phoneUserClassifications, rp.phoneCounterpartyMap),
          valueKey: const Key('restoreReplacePhone'),
        ),
        _KeyValue(
          palette: p,
          label: 'The file',
          value: replaceCountsLine(file.fileTransactions, file.fileClassifications, file.fileCounterpartyMap),
          valueKey: const Key('restoreReplaceFile'),
        ),
        if (rp.phoneRecentlyDeleted > 0)
          Text(
            '${rp.phoneRecentlyDeleted} recently deleted '
            '${rp.phoneRecentlyDeleted == 1 ? 'transaction is' : 'transactions are'} included in the '
            'transaction count above.',
            style: small(),
            key: const Key('restoreReplaceDeletedNote'),
          ),
        if (fileTotal == 0)
          Text(kReplaceEmptyFileNote, style: small(bold: true), key: const Key('restoreReplaceEmptyNote')),
        if (lost > 0) ...[
          Text(
            keptAndLostSentence(
              live: id.transactions.live,
              included: id.transactions.included,
              lost: id.transactions.skipped,
            ),
            key: const Key('replaceIdentity'),
            style: small(bold: true),
          ),
          if (lostCats > 0)
            Text(lostForGoodLine(lostCats, lostCats == 1 ? 'category' : 'categories'),
                key: const Key('replaceLostCategories'), style: small(bold: true)),
          if (lostMap > 0)
            Text(lostForGoodLine(lostMap, lostMap == 1 ? 'saved receiver' : 'saved receivers'),
                key: const Key('replaceLostReceivers'), style: small(bold: true)),
          Text(kUndoRestoresRest, style: small()),
        ],
        Text(kRememberedRecipientsNotInBackup, key: const Key('replaceRememberedNote'), style: small()),
        Text(kUndoNotExactNotice, key: const Key('restoreUndoNotExact'), style: small()),
        if (error != null) ErrorBox(error!, key: const Key('replaceConfirmError')),
      ],
      actions: SheetActions(
        secondary: FilledButton(
          key: const Key('restoreReplaceCancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          style: FilledButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
          ),
          child: const Text(kCancel),
        ),
        primary: FilledButton(
          key: const Key('restoreReplaceGo'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            backgroundColor: p.diffUp,
            foregroundColor: p.onDelete,
          ),
          child: const Text(kReplaceConfirmButton, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.palette, required this.label, required this.value, required this.valueKey});

  final AppPalette palette;
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: palette.ink)),
        ),
        Expanded(child: Text(value, key: valueKey, style: TextStyle(fontSize: 13, color: palette.ink))),
      ],
    );
  }
}
