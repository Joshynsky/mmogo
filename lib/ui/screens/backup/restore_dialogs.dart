import 'package:flutter/material.dart';

import '../../../data/backup/restore_types.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import 'restore_messages.dart';
import '../../widgets/palette_alert_dialog.dart';

/// A modal, non-dismissible progress dialog ("Checking file...",
/// "Restoring..."). Returns a function that closes it.
VoidCallback showRestoreProgress(BuildContext context, String label) {
  final navigator = Navigator.of(context);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: PaletteAlertDialog(
        key: const Key('restoreProgress'),
        content: Row(
          children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 18),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  ).whenComplete(() => open = false);
  return () {
    if (open) {
      open = false;
      navigator.pop();
    }
  };
}

/// The rejection dialog: one plain reason, then "Nothing was changed.".
Future<void> showRestoreRejectDialog(BuildContext context, String reason) => showDialog<void>(
  context: context,
  builder: (ctx) => PaletteAlertDialog(
    key: const Key('restoreRejectDialog'),
    title: const Text(kRestoreRejectTitle),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(reason, style: const TextStyle(fontWeight: FontWeight.w700), key: const Key('restoreRejectReason')),
        const SizedBox(height: 10),
        const Text(kRestoreNothingChanged),
      ],
    ),
    actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
  ),
);

/// "Could not restore. Nothing was changed." (or the Replace-refused line).
Future<void> showRestoreFailedDialog(BuildContext context, {String message = kRestoreFailedMessage}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => PaletteAlertDialog(
        key: const Key('restoreFailedDialog'),
        title: const Text(kRestoreFailedTitle),
        content: Text(message, key: const Key('restoreFailedMessage')),
        actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// The merge-or-replace dialog. Returns the chosen mode, or null on Cancel.
Future<RestoreMode?> showMergeOrReplaceDialog(BuildContext context, RestorePreview p) =>
    showDialog<RestoreMode>(
      context: context,
      builder: (ctx) => _MergeDialog(preview: p, palette: AppPalette.of(ctx)),
    );

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({required this.preview, required this.palette});

  final RestorePreview preview;
  final AppPalette palette;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  RestoreMode _mode = RestoreMode.merge;

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final fileTotal = p.fileClassifications + p.fileTransactions + p.fileCounterpartyMap;
    return PaletteAlertDialog(
      key: const Key('restoreMergeDialog'),
      title: const Text(kMergeDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _KeyValue('Backup made', restoreFileDate(p.fileCreatedAt), key: const Key('restoreFileDate')),
            _KeyValue(
              'In the file',
              fileTotal == 0
                  ? kBackupHasNoEntries
                  : restoreCountsLine(p.fileTransactions, p.fileClassifications, p.fileCounterpartyMap),
              key: const Key('restoreInFile'),
            ),
            _KeyValue(
              'New to this phone',
              '${p.newTransactions} ${p.newTransactions == 1 ? 'transaction' : 'transactions'}',
              key: const Key('restoreNewHere'),
            ),
            _KeyValue(
              'Already here',
              '${p.duplicateTransactions} ${p.duplicateTransactions == 1 ? 'transaction' : 'transactions'}',
              key: const Key('restoreAlreadyHere'),
            ),
            const SizedBox(height: 6),
            _Option(
              key: const Key('restoreOptionMerge'),
              title: kMergeOptionTitle,
              help: kMergeOptionHelp,
              selected: _mode == RestoreMode.merge,
              palette: widget.palette,
              onTap: () => setState(() => _mode = RestoreMode.merge),
            ),
            _Option(
              key: const Key('restoreOptionReplace'),
              title: kReplaceOptionTitle,
              help: kReplaceOptionHelp,
              selected: _mode == RestoreMode.replace,
              palette: widget.palette,
              onTap: () => setState(() => _mode = RestoreMode.replace),
            ),
            const SizedBox(height: 8),
            Text.rich(
              const TextSpan(
                children: [
                  TextSpan(text: 'Why mmogo asks. ', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: kWhyRestoreAsks),
                ],
              ),
              key: const Key('restoreWhyAsks'),
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('restoreContinue'),
          onPressed: () => Navigator.of(context).pop(_mode),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.title,
    required this.help,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String title;
  final String help;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$title. $help',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? palette.primary : palette.mutedInk.withValues(alpha: 0.4), width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: palette.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(help, style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Replace confirmation. `true` only on "Replace everything".
Future<bool> showReplaceConfirmDialog(BuildContext context, RestorePreview p) async {
  final fileTotal = p.fileClassifications + p.fileTransactions + p.fileCounterpartyMap;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => PaletteAlertDialog(
      key: const Key('restoreReplaceDialog'),
      title: const Text(kReplaceConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              replaceRemovesLine(
                p.phoneTransactions + p.phoneRecentlyDeleted,
                p.phoneUserClassifications,
                p.phoneCounterpartyMap,
              ),
              key: const Key('restoreReplaceRemoves'),
            ),
            const SizedBox(height: 10),
            _KeyValue(
              'This phone now',
              restoreCountsLine(p.phoneTransactions, p.phoneUserClassifications, p.phoneCounterpartyMap),
              key: const Key('restoreReplacePhone'),
            ),
            _KeyValue(
              'The file',
              restoreCountsLine(p.fileTransactions, p.fileClassifications, p.fileCounterpartyMap),
              key: const Key('restoreReplaceFile'),
            ),
            if (p.phoneRecentlyDeleted > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${p.phoneRecentlyDeleted} recently deleted '
                  '${p.phoneRecentlyDeleted == 1 ? 'transaction is' : 'transactions are'} included in the '
                  'transaction count above.',
                  style: const TextStyle(fontSize: 12.5),
                  key: const Key('restoreReplaceDeletedNote'),
                ),
              ),
            if (fileTotal == 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  kReplaceEmptyFileNote,
                  style: TextStyle(fontWeight: FontWeight.w800),
                  key: Key('restoreReplaceEmptyNote'),
                ),
              ),
            const Text(kUndoNotExactNotice, key: Key('restoreUndoNotExact')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('restoreReplaceGo'),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text(kReplaceConfirmButton),
        ),
      ],
    ),
  );
  return ok ?? false;
}
