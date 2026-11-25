import 'package:flutter/material.dart';

import '../../../data/backup/restore_types.dart';
import '../../copy/backup_copy.dart';
import '../../copy/data_copy.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/highlight_pulse.dart';
import '../../widgets/tap_target.dart';
import '../settings/settings_targets.dart';
import 'backup_sheet_shell.dart';
import 'backup_widgets.dart';
import 'restore_rules_note.dart';
import 'skipped_rows_list.dart';

/// What the user did on the result sheet.
enum RestoreSheetAction { done, undo }

/// Which sheet to show.
enum RestoreSheetKind { merged, replaced, undone }

/// The result sheet (S10b A9d, A2, A14). Merge: added / skipped / rejected per
/// table (the file-side "skipped" column), the settings that were restored.
/// Replace: "N entries restored. N lost." with a "Show which" list of what was
/// lost (first 20 and the exact N, no "Show all": the Replace result only holds
/// 20 rows), the Undo line, "Undo". Undo: never says "the data is back" when
/// the Replace lost rows (it says "Everything except those N entries is back"),
/// and says so when the safety copy could not be removed. Done is the default;
/// a tap outside, Back and a swipe down are Done.
///
/// [lostCount] is the number the Replace reported, kept by the flow so the Undo
/// result (which carries none) can name it.
Future<RestoreSheetAction> showRestoreResultSheet(
  BuildContext context,
  RestoreResult result, {
  required RestoreSheetKind kind,
  int lostCount = 0,
}) async {
  final palette = AppPalette.of(context);
  final action = await showBackupSheet<RestoreSheetAction>(
    context,
    (_) => _ResultSheet(result: result, kind: kind, palette: palette, lostCount: lostCount),
  );
  return action ?? RestoreSheetAction.done;
}

/// The fixed labels of the settings this restore applied, in the order of
/// [kRestoredSettingLabels]; keys it does not know are left out. Never a value.
List<String> restoredSettingLabels(Iterable<String> appliedKeys) {
  final applied = appliedKeys.toSet();
  return [
    for (final e in kRestoredSettingLabels.entries)
      if (applied.contains(e.key)) e.value,
  ];
}

class _ResultSheet extends StatefulWidget {
  const _ResultSheet({required this.result, required this.kind, required this.palette, required this.lostCount});

  final RestoreResult result;
  final RestoreSheetKind kind;
  final AppPalette palette;
  final int lostCount;

  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final kind = widget.kind;
    final p = widget.palette;
    final title = switch (kind) {
      RestoreSheetKind.merged => kResultMergedTitle,
      RestoreSheetKind.replaced => kResultReplacedTitle,
      RestoreSheetKind.undone => kResultUndoneTitle,
    };
    // Replace: the result's own number. Undo: the number the Replace reported.
    final lost = kind == RestoreSheetKind.replaced ? result.lostCount : widget.lostCount;
    final note = switch (kind) {
      RestoreSheetKind.merged => kResultMergeNote,
      RestoreSheetKind.replaced => kResultReplaceNote,
      RestoreSheetKind.undone => lost > 0 ? resultUndoneLostNote(lost) : kResultUndoneNote,
    };
    final canUndo = kind == RestoreSheetKind.replaced && result.safetyCopyKept;
    final labels = restoredSettingLabels(result.settings.applied);
    // 0.2.2 (U6): what happened to the rules, worded by the auto-read side; none without its holder.
    final ruleNotes = RestoreRulesNotes.notesFor(result.rules);
    TextStyle body({bool bold = false}) => TextStyle(
      fontSize: 13.5,
      height: 1.45,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      color: p.ink,
    );
    return BackupSheetShell(
      key: const Key('restoreResultSheet'),
      palette: p,
      title: title,
      titleKey: const Key('restoreResultTitle'),
      body: [
        if (kind == RestoreSheetKind.replaced)
          Text(
            replaceRestoredLine(result.transactions.added, lost),
            key: const Key('replaceRestoredLine'),
            style: body(bold: true),
          ),
        if (kind == RestoreSheetKind.replaced && lost > 0)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShowWhichButton(palette: p, open: _open, onTap: () => setState(() => _open = !_open)),
              if (_open)
                SkippedRowsList(
                  palette: p,
                  rows: result.lost.shown,
                  total: lost,
                  title: lostResultListTitle(lost),
                  footer: kOnlyDateAndType,
                  showReasons: false,
                ),
            ],
          ),
        Table(
          key: const Key('restoreResultTable'),
          columnWidths: const {0: FlexColumnWidth(2.2)},
          children: kind == RestoreSheetKind.merged
              ? [
                  _row(p, const ['Table', 'Added', 'Skipped', 'Rejected'], header: true),
                  _row(p, ['Transactions', ..._cells(result.transactions)]),
                  _row(p, ['Categories', ..._cells(result.classifications)]),
                  _row(p, ['Saved receivers', ..._cells(result.counterpartyMap)]),
                ]
              : [
                  _row(p, const ['Table', 'Restored'], header: true),
                  _row(p, ['Transactions', '${result.transactions.added}']),
                  _row(p, ['Categories', '${result.classifications.added}']),
                  _row(p, ['Saved receivers', '${result.counterpartyMap.added}']),
                ],
        ),
        Text(note, key: const Key('restoreResultNote'), style: body()),
        if (labels.isNotEmpty)
          Text(settingsRestoredLine(labels), key: const Key('restoreResultSettings'), style: body()),
        for (var i = 0; i < ruleNotes.length; i++) RulesNoteBlock(key: Key('restoreRulesNote$i'), note: ruleNotes[i], palette: p),
        if (!result.settingsApplied) BackupWarning(palette: p, text: kSettingsNotApplied, bottomGap: 0),
        if (kind == RestoreSheetKind.undone && result.safetyCopyStillThere)
          Semantics(
            liveRegion: true,
            child: Text(
              kResultSafetyCopyStillThere,
              key: const Key('restoreSafetyCopyStillThere'),
              style: body(bold: true),
            ),
          ),
        if (canUndo) ...[
          Text(
            lost > 0 ? replaceUndoLostNote(lost) : kResultSafetyCopyNote,
            key: const Key('restoreResultSafetyNote'),
            style: body(),
          ),
          Text(kUndoNotExactNotice, style: const TextStyle(fontSize: 12.5)),
        ],
      ],
      actions: SheetActions(
        secondary: canUndo
            ? OutlinedButton(
                key: const Key('restoreUndoButton'),
                onPressed: () => Navigator.of(context).pop(RestoreSheetAction.undo),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                  foregroundColor: p.primary,
                  side: BorderSide(color: p.primary, width: 1.5),
                ),
                child: const Text('Undo'),
              )
            : null,
        primary: FilledButton(
          key: const Key('restoreDoneButton'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(RestoreSheetAction.done),
          style: FilledButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
          ),
          child: const Text(kDone),
        ),
      ),
    );
  }

  static List<String> _cells(TableCounts c) => ['${c.added}', '${c.skipped}', '${c.rejected}'];

  static TableRow _row(AppPalette p, List<String> cells, {bool header = false}) => TableRow(
    children: [
      for (var i = 0; i < cells.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            cells[i],
            textAlign: i == 0 ? TextAlign.start : TextAlign.end,
            style: TextStyle(fontWeight: header ? FontWeight.w800 : FontWeight.w400, fontSize: 13.5, color: p.ink),
          ),
        ),
    ],
  );
}

/// One rules note (U6): optional bold title, the counts-only text, and an "Open Settings" button that
/// opens Settings with the "Record receiver details" switch outlined. Announced when the sheet opens.
class RulesNoteBlock extends StatelessWidget {
  const RulesNoteBlock({super.key, required this.note, required this.palette});

  final RestoreRulesNote note;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final button = note.settingsButton;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (note.title != null)
            Semantics(
              header: true,
              child: Text(
                note.title!,
                style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w800, color: p.ink),
              ),
            ),
          Text(note.body, style: TextStyle(fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w700, color: p.ink)),
          if (button != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('restoreRulesOpenSettings'),
                onPressed: () {
                  HighlightRequest.set(kSettingsTargetCaptureReceiver);
                  Navigator.of(context).pushNamed(Routes.settings);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                  foregroundColor: p.primary,
                ),
                child: Text(button),
              ),
            ),
        ],
      ),
    );
  }
}
