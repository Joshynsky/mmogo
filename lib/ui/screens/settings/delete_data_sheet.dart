import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/maintenance/delete_data_types.dart';
import '../../copy/delete_data_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';
import '../../widgets/help_sheet.dart';
import '../../widgets/palette_alert_dialog.dart';
import '../../widgets/tap_target.dart';
import '../backup/backup_export_flow.dart';
import '../backup/backup_format.dart' show kBackupFailedMessage;
import '../backup/backup_widgets.dart' show BackupWarning;

/// §SETTINGS.DELETE_SHEET — the Delete data sheet (0.1.2 S9b-2, DD2 + CB6) and
/// its Reset app confirm sheet. This file only CHOOSES: it never calls the
/// delete service's delete methods. It returns the level the user confirmed;
/// the run, the busy state and the results live in `delete_data_run_sheet.dart`.

/// What the user can ask for.
enum DeleteLevel { transactions, reset }

/// How long the red button of the Reset app confirm ignores taps (A6).
const kDeleteConfirmArmDelay = Duration(milliseconds: 600);

/// Shows the Delete data sheet. Returns the confirmed level, or null for
/// Cancel, a tap outside, a swipe down and Back (nothing is deleted).
Future<DeleteLevel?> showDeleteDataSheet(
  BuildContext context, {
  required Future<DeleteDataPeek> Function() peek,
  DeleteDataPeek? initialPeek,
  BackupExportFlow? flow,
}) {
  return showModalBottomSheet<DeleteLevel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => DeleteDataSheet(peek: peek, initialPeek: initialPeek, flow: flow),
  );
}

class DeleteDataSheet extends StatefulWidget {
  const DeleteDataSheet({super.key, required this.peek, this.initialPeek, this.flow});

  final Future<DeleteDataPeek> Function() peek;
  final DeleteDataPeek? initialPeek;

  /// The Back up now flow (A2); null = the real one.
  final BackupExportFlow? flow;

  @override
  State<DeleteDataSheet> createState() => _DeleteDataSheetState();
}

class _DeleteDataSheetState extends State<DeleteDataSheet> {
  late final BackupExportFlow _flow = widget.flow ?? BackupExportFlow();
  final _word = TextEditingController();
  DeleteDataPeek? _peek;
  late DeleteLevel _level;
  bool _backingUp = false;

  /// The "?" in the header shows the extras (what each option also deletes).
  bool _extras = false;

  bool get _level1Disabled => _peek?.nothingLeftToDeleteAtLevel1 ?? false;
  bool get _matches => _word.text.trim().toUpperCase() == kDeleteWordWord;

  @override
  void initState() {
    super.initState();
    _peek = widget.initialPeek;
    _level = _level1Disabled ? DeleteLevel.reset : DeleteLevel.transactions;
    _word.addListener(() => setState(() {}));
    _refresh();
  }

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    DeleteDataPeek p;
    try {
      p = await widget.peek();
    } catch (_) {
      return; // keep what is shown
    }
    if (!mounted) return;
    setState(() {
      _peek = p;
      if (_level1Disabled && _level == DeleteLevel.transactions) {
        _level = DeleteLevel.reset;
        _word.clear();
      }
    });
  }

  void _select(DeleteLevel l) {
    if (l == _level) return;
    setState(() {
      _level = l;
      _word.clear(); // a typed word never carries over to the other level
    });
  }

  Future<void> _backUp() async {
    if (_backingUp) return;
    _backingUp = true;
    try {
      if (!await BackupExportFlow.confirm(context)) return;
      if (!mounted) return;
      final outcome = await _flow.execute();
      if (!mounted) return;
      // Shared, not shared and cancelled change nothing here: the sheet, the
      // level and the typed word stay, and Delete is neither blocked nor forced.
      if (outcome is BackupFailed) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => PaletteAlertDialog(
            title: const Text('Could not create the backup'),
            content: const Text(kBackupFailedMessage),
            actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      _backingUp = false;
    }
  }

  Future<void> _go() async {
    if (!_matches) return;
    if (_level == DeleteLevel.transactions) {
      Navigator.of(context).pop(DeleteLevel.transactions);
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => const ResetConfirmSheet(),
    );
    if (ok == true && mounted) Navigator.of(context).pop(DeleteLevel.reset);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final peek = _peek;
    final matches = _matches;
    final l1 = _level == DeleteLevel.transactions;
    return HelpSheetFrame(
      title: kDeleteDataTitle,
      bodyKey: const Key('deleteSheetScroll'),
      headerAction: HelpButton(
        key: const Key('deleteHelpButton'),
        label: kDeleteHelpLabel,
        expanded: _extras,
        onPressed: () => setState(() => _extras = !_extras),
      ),
      body: [
        BackupWarning(
          key: const Key('deleteIntro'),
          palette: palette,
          text: kDeleteIntro,
          bottomGap: 0,
          stripe: false,
        ),
        Text(
          kDeleteNotTouched,
          key: const Key('deleteNotTouched'),
          style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.softInk),
        ),
        if (_extras)
          Container(
            key: const Key('deleteExtras'),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: palette.tint, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < kDeleteExtras.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  Text(
                    kDeleteExtras[i],
                    style: TextStyle(fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600, color: palette.tintInk),
                  ),
                ],
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('deleteBackUpNow'),
            autofocus: true,
            onPressed: _backUp,
            icon: const Icon(Icons.backup_outlined, size: 18),
            label: const Text(kDeleteBackUpNow),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              foregroundColor: palette.primary,
              side: BorderSide(color: palette.primary),
            ),
          ),
        ),
        Semantics(
          container: true,
          label: kDeleteChooseSemantics,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LevelCard(
                key: const Key('deleteLevel1'),
                palette: palette,
                title: kDeleteLevel1Title,
                selected: l1,
                enabled: !_level1Disabled,
                lines: _level1Disabled ? const [kDeleteLevel1Nothing] : _level1Lines(peek),
                onTap: () => _select(DeleteLevel.transactions),
              ),
              const SizedBox(height: 8),
              _LevelCard(
                key: const Key('deleteLevel2'),
                palette: palette,
                title: kDeleteLevel2Title,
                selected: !l1,
                enabled: true,
                lines: const [kDeleteLevel2Short],
                onTap: () => _select(DeleteLevel.reset),
              ),
            ],
          ),
        ),
        TextField(
          key: const Key('deleteWordField'),
          controller: _word,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          // The keyboard's Done key only closes the keyboard; it never deletes.
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          style: TextStyle(color: palette.ink),
          decoration: InputDecoration(
            labelText: kDeleteWordLabel,
            helperText: kDeleteWordHint,
            helperMaxLines: 2,
            labelStyle: TextStyle(color: palette.mutedInk),
            helperStyle: TextStyle(color: palette.mutedInk),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: palette.line)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: palette.primary, width: 2)),
          ),
        ),
      ],
      // R30: Cancel and the red button are PINNED under the scrolling body, so
      // they stay on screen above the keyboard and at large text; the field's
      // own caret logic scrolls the field and its hint into the body above them.
      actions: Row(
        children: [
          Expanded(
            child: TextButton(
              key: const Key('deleteCancel'),
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                foregroundColor: palette.ink,
              ),
              child: const Text(kDeleteCancel),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              key: const Key('deleteGo'),
              onPressed: matches ? _go : null,
              style: _redStyle(palette),
              // The hint merges into the button's own node (spoken while it is off).
              child: Semantics(
                hint: matches ? null : kDeleteButtonSemanticsHint,
                child: Text(l1 ? kDeleteButtonLevel1 : kDeleteButtonLevel2, textAlign: TextAlign.center),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The Level 1 card: the live counts (omitted when the read was incomplete),
  /// then what goes and what stays in one sentence (F3).
  List<String> _level1Lines(DeleteDataPeek? p) {
    final counts = (p == null || p.incomplete)
        ? ''
        : deleteCountsText(
            live: p.liveTransactions,
            recentlyDeleted: p.softDeletedTransactions,
            learnedReceivers: p.learnedReceivers,
            rememberedRecipients: p.rememberedRecipientsCount,
          );
    return [
      if (p != null && p.incomplete) kDeleteCountsUnknown else if (counts.isNotEmpty) '$kDeleteCountsPrefix$counts.',
      kDeleteLevel1Short,
    ];
  }
}

/// The red button look: `palette.diffUp` with `palette.onDelete`, 44 high.
ButtonStyle _redStyle(AppPalette palette) => FilledButton.styleFrom(
  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
  backgroundColor: palette.diffUp,
  foregroundColor: palette.onDelete,
  disabledBackgroundColor: palette.track,
  disabledForegroundColor: palette.mutedInk,
);

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    super.key,
    required this.palette,
    required this.title,
    required this.selected,
    required this.enabled,
    required this.lines,
    required this.onTap,
  });

  final AppPalette palette;
  final String title;
  final bool selected;
  final bool enabled;
  final List<String> lines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: enabled,
      button: true,
      excludeSemantics: true,
      label: '$title. ${lines.join(' ')}',
      onTap: enabled ? onTap : null,
      child: Material(
        color: selected ? palette.tint : palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? palette.primary : palette.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 20,
                      color: enabled ? palette.primary : palette.mutedInk,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.ink)),
                        for (final l in lines) ...[
                          const SizedBox(height: 4),
                          Text(l, style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.mutedInk)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The second sheet for Reset app. Pops true only on the red button (which
/// ignores taps for [kDeleteConfirmArmDelay]); Cancel (the focused default),
/// a tap outside, a swipe down and Back pop null.
class ResetConfirmSheet extends StatefulWidget {
  const ResetConfirmSheet({super.key});

  @override
  State<ResetConfirmSheet> createState() => _ResetConfirmSheetState();
}

class _ResetConfirmSheetState extends State<ResetConfirmSheet> {
  bool _armed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kDeleteConfirmArmDelay, () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return BottomSheetShell(
      palette: palette,
      children: [
        Semantics(
          header: true,
          child: Text(kDeleteConfirmTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: palette.ink)),
        ),
        Text(kDeleteConfirmBody, style: TextStyle(fontSize: 14, height: 1.45, color: palette.ink)),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                key: const Key('resetConfirmCancel'),
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                child: const Text(kDeleteCancel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const Key('resetConfirmGo'),
                // Always "on", but a tap in the first moments is ignored (A6).
                onPressed: () {
                  if (_armed) Navigator.of(context).pop(true);
                },
                style: _redStyle(palette),
                child: const Text(kDeleteConfirmButton),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
