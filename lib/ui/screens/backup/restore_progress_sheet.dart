import 'package:flutter/material.dart';

import '../../../data/backup/restore_types.dart';
import '../../copy/backup_copy.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import 'backup_sheet_shell.dart';

/// §SCREEN.BACKUP.PROGRESS — 0.1.2 S10b (BP2, A7, A10). The busy sheet of a
/// Merge, a Replace or an Undo. Replace shows a step list fed by the service's
/// real step events (Checking the file / Saving a safety copy / Replacing your
/// data); Merge and Undo show their one label. The slow line appears when a
/// `slow` event arrives (no timer here). The list is a live region. While it
/// runs the sheet cannot be dismissed: no outside tap, no swipe, Back does
/// nothing. A failed step is not drawn here: the flow closes the sheet and
/// shows the failure.

enum RestoreProgressKind { merge, replace, undo }

/// The state the sheet draws, fed by `onStep`.
class RestoreProgressController extends ChangeNotifier {
  final Map<RestoreStep, RestoreStepPhase> _phase = {};
  bool _slow = false;

  bool get slow => _slow;

  /// The last phase seen for [step], or null when nothing arrived yet.
  RestoreStepPhase? phaseOf(RestoreStep step) => _phase[step];

  void onStep(RestoreStepEvent e) {
    if (e.phase == RestoreStepPhase.slow) {
      _slow = true;
    } else {
      _phase[e.step] = e.phase;
    }
    notifyListeners();
  }
}

/// A shown progress sheet: feed it step events, then [close] it.
class RestoreProgress {
  RestoreProgress._(this.controller, this._close);

  final RestoreProgressController controller;
  final VoidCallback _close;

  void onStep(RestoreStepEvent e) => controller.onStep(e);
  void close() => _close();
}

RestoreProgress showRestoreProgressSheet(BuildContext context, RestoreProgressKind kind) {
  final navigator = Navigator.of(context);
  final palette = AppPalette.of(context);
  final controller = RestoreProgressController();
  var open = true;
  showBackupSheet<void>(
    context,
    (_) => PopScope(
      canPop: false,
      child: _ProgressSheet(palette: palette, kind: kind, controller: controller),
    ),
    dismissible: false,
  ).whenComplete(() => open = false);
  return RestoreProgress._(controller, () {
    if (open) {
      open = false;
      navigator.pop();
    }
  });
}

class _ProgressSheet extends StatelessWidget {
  const _ProgressSheet({required this.palette, required this.kind, required this.controller});

  final AppPalette palette;
  final RestoreProgressKind kind;
  final RestoreProgressController controller;

  @override
  Widget build(BuildContext context) {
    final title = switch (kind) {
      RestoreProgressKind.merge => kRestoreRestoring,
      RestoreProgressKind.replace => kReplaceProgressTitle,
      RestoreProgressKind.undo => kRestoreUndoing,
    };
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => BackupSheetShell(
        key: const Key('restoreProgressSheet'),
        palette: palette,
        title: title,
        body: [
          if (kind == RestoreProgressKind.replace)
            Semantics(
              liveRegion: true,
              container: true,
              child: Column(
                key: const Key('restoreStepList'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in const [RestoreStep.validating, RestoreStep.safetyCopy, RestoreStep.writing])
                    _StepRow(palette: palette, step: s, phase: controller.phaseOf(s)),
                ],
              ),
            )
          else
            const Center(
              child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
            ),
          if (controller.slow)
            Semantics(
              liveRegion: true,
              child: Text(
                kRestoreSlow,
                key: const Key('restoreSlowLine'),
                style: TextStyle(fontSize: 13.5, height: 1.45, color: palette.ink),
              ),
            ),
        ],
      ),
    );
  }
}

String restoreStepLabel(RestoreStep s) => switch (s) {
  RestoreStep.validating => kStepValidating,
  RestoreStep.safetyCopy => kStepSafetyCopy,
  RestoreStep.writing => kStepWriting,
};

class _StepRow extends StatelessWidget {
  const _StepRow({required this.palette, required this.step, required this.phase});

  final AppPalette palette;
  final RestoreStep step;
  final RestoreStepPhase? phase;

  @override
  Widget build(BuildContext context) {
    final done = phase == RestoreStepPhase.done;
    final active = phase == RestoreStepPhase.started;
    final stepText = restoreStepLabel(step);
    final state = done ? 'done' : (active ? 'in progress' : 'waiting');
    return Semantics(
      label: '$stepText, $state',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: done
                    ? Icon(Icons.check_rounded, size: 20, color: palette.primary)
                    : active
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.circle_outlined, size: 14, color: palette.mutedInk),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stepText,
                key: Key('restoreStep-${step.name}'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: (done || active) ? palette.ink : palette.mutedInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
