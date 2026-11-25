/// §AUTOREAD.LEVELS.HARD_RULE_RESET_FOOTER: the red "Reset everyone to Suggested" button at the foot of the
/// Remembered page's second tab (mock ctl-a) and its counts-only confirm (mock ctl-a-reset): no person is
/// named. Reset goes through [RuleBulkOps.resetAllToSuggested]: rules stay (level Suggested, ceiling and the
/// restore mark cleared), nobody is raised, the pause switch is never touched.
/// Draws nothing while [autoRecordUi] is false (dormant).
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/pill_toast.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart';
import 'levels_copy.dart' show kLevelSheetCancel, kLevelSheetSaveFailed;

class HardRuleResetFooter extends StatefulWidget {
  const HardRuleResetFooter({super.key, required this.bulk, this.onDone});

  final RuleBulkOps bulk;

  /// After a reset that changed someone (the page reloads its list). Gets the number changed.
  final ValueChanged<int>? onDone;

  @override
  State<HardRuleResetFooter> createState() => _HardRuleResetFooterState();
}

class _HardRuleResetFooterState extends State<HardRuleResetFooter> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    int n;
    try {
      n = await widget.bulk.resetCount();
    } catch (_) {
      PillToast.show(kLevelSheetSaveFailed);
      return;
    }
    if (!mounted) return;
    if (n == 0) {
      // Nobody above Suggested: nothing to confirm, say so with the same count line.
      PillToast.show(hardResetToast(0));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (_) => HardRuleResetDialog(count: n));
    if (ok != true) return;
    int done;
    try {
      done = await widget.bulk.resetAllToSuggested();
    } catch (_) {
      done = 0;
    }
    PillToast.show(done == 0 ? kLevelSheetSaveFailed : hardResetToast(done));
    if (done > 0) widget.onDone?.call(done);
  }

  @override
  Widget build(BuildContext context) {
    if (!autoRecordUi) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    return OutlinedButton(
      key: const Key('hardResetButton'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: p.error,
        side: BorderSide(color: p.error, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
      ),
      onPressed: _busy ? null : _tap,
      child: const Text(kHardResetButton, textAlign: TextAlign.center),
    );
  }
}

/// "Reset {n} people to Suggested?": counts only. Pops true only on Reset.
class HardRuleResetDialog extends StatelessWidget {
  const HardRuleResetDialog({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    const minSize = Size(64, 44);
    return AlertDialog(
      title: Text(hardResetTitle(count), key: const Key('hardResetTitle')),
      content: const SingleChildScrollView(child: Text(kHardResetBody, key: Key('hardResetBody'))),
      actions: [
        TextButton(
          key: const Key('hardResetCancel'),
          style: TextButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(kLevelSheetCancel),
        ),
        FilledButton(
          key: const Key('hardResetOk'),
          style: FilledButton.styleFrom(minimumSize: minSize, backgroundColor: p.error, foregroundColor: p.onDelete),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(kHardResetOk),
        ),
      ],
    );
  }
}
