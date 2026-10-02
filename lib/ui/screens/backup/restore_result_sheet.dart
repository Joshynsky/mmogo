import 'package:flutter/material.dart';

import '../../../data/backup/restore_types.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import 'backup_widgets.dart';

/// What the user did on the result sheet.
enum RestoreSheetAction { done, undo }

/// Which sheet to show.
enum RestoreSheetKind { merged, replaced, undone }

/// The result sheet: added / skipped / rejected per table, the settings note
/// when some settings could not be applied, and "Undo" after a Replace while
/// the safety copy exists. Dismissing it counts as Done.
Future<RestoreSheetAction> showRestoreResultSheet(
  BuildContext context,
  RestoreResult result, {
  required RestoreSheetKind kind,
}) async {
  final palette = AppPalette.of(context);
  final action = await showModalBottomSheet<RestoreSheetAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ResultSheet(result: result, kind: kind, palette: palette),
  );
  return action ?? RestoreSheetAction.done;
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.result, required this.kind, required this.palette});

  final RestoreResult result;
  final RestoreSheetKind kind;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final title = switch (kind) {
      RestoreSheetKind.merged => kResultMergedTitle,
      RestoreSheetKind.replaced => kResultReplacedTitle,
      RestoreSheetKind.undone => kResultUndoneTitle,
    };
    final note = switch (kind) {
      RestoreSheetKind.merged => kResultMergeNote,
      RestoreSheetKind.replaced => kResultReplaceNote,
      RestoreSheetKind.undone => kResultUndoneNote,
    };
    final canUndo = kind == RestoreSheetKind.replaced && result.safetyCopyKept;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('restoreResultSheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800), key: const Key('restoreResultTitle')),
            const SizedBox(height: 12),
            Table(
              key: const Key('restoreResultTable'),
              columnWidths: const {0: FlexColumnWidth(2.2)},
              children: [
                _row(const ['Table', 'Added', 'Skipped', 'Rejected'], header: true),
                _row(['Transactions', ..._cells(result.transactions)]),
                _row(['Classifications', ..._cells(result.classifications)]),
                _row(['Saved receivers', ..._cells(result.counterpartyMap)]),
              ],
            ),
            const SizedBox(height: 12),
            Text(note, style: const TextStyle(height: 1.45)),
            if (!result.settingsApplied) ...[
              const SizedBox(height: 10),
              BackupWarning(palette: palette, text: kSettingsNotApplied, bottomGap: 0),
            ],
            if (canUndo) ...[
              const SizedBox(height: 10),
              const Text(kResultSafetyCopyNote, key: Key('restoreResultSafetyNote')),
              const SizedBox(height: 6),
              const Text(kUndoNotExactNotice, style: TextStyle(fontSize: 12.5)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canUndo)
                  OutlinedButton(
                    key: const Key('restoreUndoButton'),
                    onPressed: () => Navigator.of(context).pop(RestoreSheetAction.undo),
                    child: const Text('Undo'),
                  ),
                const SizedBox(width: 10),
                FilledButton(
                  key: const Key('restoreDoneButton'),
                  onPressed: () => Navigator.of(context).pop(RestoreSheetAction.done),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static List<String> _cells(TableCounts c) => ['${c.added}', '${c.skipped}', '${c.rejected}'];

  static TableRow _row(List<String> cells, {bool header = false}) => TableRow(
    children: [
      for (var i = 0; i < cells.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            cells[i],
            textAlign: i == 0 ? TextAlign.start : TextAlign.end,
            style: TextStyle(fontWeight: header ? FontWeight.w800 : FontWeight.w400, fontSize: 13.5),
          ),
        ),
    ],
  );
}
