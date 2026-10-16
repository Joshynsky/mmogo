import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../data/backup/backup_limits.dart';
import '../../../data/backup/backup_service.dart';
import '../../../data/backup/restore_service.dart';
import '../../../data/db/app_database.dart';
import '../../../platform/storage_bridge.dart';
import '../../copy/backup_copy.dart';
import '../../copy/data_copy.dart';
import 'backup_ui_seams.dart';
import 'replace_sheets.dart';
import 'restore_dialogs.dart';
import 'restore_messages.dart';
import 'restore_progress_sheet.dart';
import 'restore_result_sheet.dart';

/// How a run of the Restore flow ended (for the Backup page and tests).
enum RestoreFlowEnd {
  /// The picker was closed without a file.
  pickerCancelled,

  /// The user backed out at the merge-or-replace dialog, the Replace warning
  /// or the Replace confirmation. Nothing was changed.
  cancelled,

  /// A rejection dialog or the failure dialog was shown. Nothing was changed.
  refused,

  /// The data was restored (Merge or Replace). [RestoreFlow.onDataChanged]
  /// has run.
  restored,

  /// The restore was undone.
  undone,
}

/// The Restore flow, step by step: pick a file, check it, ask Merge or
/// Replace. Replace then looks at what would be lost (`previewReplace`, under
/// a non-dismissible "Checking"), shows the loss warning FIRST when rows would
/// be lost (tick before Continue), then the confirm; the restore runs under a
/// step-list sheet and passes `acceptedSkipped`. A refusal because the count
/// changed shows the preview again, never silently. Then the result sheet and
/// Undo after a Replace.
///
/// Every platform and data step is a seam: the file picker is the
/// [StorageBridge] (a fake in tests), the work is a [RestoreService] (a fake in
/// widget tests), and [onDataChanged] is how the app refreshes its screens and
/// palette after the data changed.
class RestoreFlow {
  RestoreFlow({RestoreService Function()? service, StorageBridge? bridge, required this.onDataChanged})
    : _service = service ?? _defaultService,
      _bridge = bridge;

  /// Runs after every committed restore and after a successful Undo. Refresh
  /// the data screens and apply the restored palette and name here.
  final Future<void> Function() onDataChanged;

  final RestoreService Function() _service;
  final StorageBridge? _bridge;

  /// How many rows the last Replace lost (A2): the Undo result carries none,
  /// so the flow remembers it to word the Undo result honestly.
  int _lostCount = 0;

  StorageBridge get _storage => _bridge ?? StorageBridge.instance;

  static RestoreService _defaultService() {
    BackupUiSeams.ensureReal('RestoreService');
    return RestoreService(
      db: () => AppDatabase.instance.database,
      backup: BackupService(db: () => AppDatabase.instance.database),
    );
  }

  /// Runs the whole flow. Never throws: every failure is a dialog or a sheet.
  Future<RestoreFlowEnd> run(BuildContext context) async {
    // 1. Pick.
    final PickedFile? picked;
    try {
      picked = await _storage.pickFile(maxBytes: kBackupMaxBytes);
    } on StorageException catch (e) {
      if (!context.mounted) return RestoreFlowEnd.refused;
      if (e.code == StorageErrorCode.cancelled) return RestoreFlowEnd.pickerCancelled;
      if (e.code == StorageErrorCode.tooLarge) {
        await showRestoreRejectDialog(context, kRejectTooLarge);
      } else {
        await showRestoreFailedDialog(context);
      }
      return RestoreFlowEnd.refused;
    } catch (_) {
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context);
      return RestoreFlowEnd.refused;
    }
    if (picked == null) return RestoreFlowEnd.pickerCancelled;
    if (!context.mounted) return RestoreFlowEnd.cancelled;
    final bytes = picked.bytes;

    // 2. Check (read-only preview).
    final closeChecking = showRestoreProgress(context, kRestoreCheckingFile);
    final RestorePreview preview;
    try {
      preview = await _service().inspect(bytes);
    } on RestoreRejected catch (e) {
      closeChecking();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreRejectDialog(context, restoreRejectReasonText(e));
      return RestoreFlowEnd.refused;
    } catch (_) {
      closeChecking();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context);
      return RestoreFlowEnd.refused;
    }
    closeChecking();
    if (!context.mounted) return RestoreFlowEnd.cancelled;

    // 3. Merge or Replace.
    final mode = await showMergeOrReplaceDialog(context, preview);
    if (mode == null || !context.mounted) return RestoreFlowEnd.cancelled;

    // 4. Do it: Merge at once, Replace through the loss warning and confirm.
    return mode == RestoreMode.replace ? _replace(context, bytes, preview) : _merge(context, bytes);
  }

  Future<RestoreFlowEnd> _merge(BuildContext context, Uint8List bytes) async {
    final progress = showRestoreProgressSheet(context, RestoreProgressKind.merge);
    final RestoreResult result;
    try {
      result = await _service().restore(bytes, RestoreMode.merge, onStep: progress.onStep);
    } on RestoreRejected catch (e) {
      progress.close();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreRejectDialog(context, restoreRejectReasonText(e));
      return RestoreFlowEnd.refused;
    } on RestoreFailed catch (e) {
      progress.close();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context, message: restoreFailedText(e));
      return RestoreFlowEnd.refused;
    } catch (_) {
      progress.close();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context);
      return RestoreFlowEnd.refused;
    }
    progress.close();
    if (!context.mounted) {
      await _refresh();
      return RestoreFlowEnd.restored;
    }
    return _finish(context, result, RestoreSheetKind.merged);
  }

  Future<RestoreFlowEnd> _replace(BuildContext context, Uint8List bytes, RestorePreview file) async {
    var changed = false;
    while (true) {
      // 4a. What would be lost, read BEFORE anything can delete it. It runs a
      // full export, so it is a non-dismissible "Checking". Never continue
      // without a preview.
      if (!context.mounted) return RestoreFlowEnd.cancelled;
      final closeChecking = showRestoreProgress(context, kReplaceChecking);
      final ReplacePreview rp;
      try {
        rp = await _service().previewReplace(bytes);
      } on RestoreRejected catch (e) {
        closeChecking();
        if (!context.mounted) return RestoreFlowEnd.refused;
        await showRestoreRejectDialog(context, restoreRejectReasonText(e));
        return RestoreFlowEnd.refused;
      } on RestoreFailed catch (e) {
        closeChecking();
        if (!context.mounted) return RestoreFlowEnd.refused;
        await showRestoreFailedDialog(context, message: restoreFailedText(e));
        return RestoreFlowEnd.refused;
      } catch (_) {
        closeChecking();
        if (!context.mounted) return RestoreFlowEnd.refused;
        await showRestoreFailedDialog(context);
        return RestoreFlowEnd.refused;
      }
      closeChecking();
      if (!context.mounted) return RestoreFlowEnd.cancelled;

      // 4b. The warning, FIRST, only when rows would be lost.
      if (rp.skippedCount > 0) {
        final go = await showReplaceWarningSheet(context, rp, changed: changed);
        if (!go || !context.mounted) return RestoreFlowEnd.cancelled;
      }
      changed = false;

      // 4c. The confirm (and again after a failure, with the reason in a red
      // box and the buttons back).
      String? error;
      var lookAgain = false;
      while (!lookAgain) {
        if (!context.mounted) return RestoreFlowEnd.cancelled;
        final go = await showReplaceConfirmSheet(context, file, rp, error: error);
        if (!go || !context.mounted) return RestoreFlowEnd.cancelled;

        // 5. Do it, under the step list.
        final progress = showRestoreProgressSheet(context, RestoreProgressKind.replace);
        try {
          final result = await _service().restore(
            bytes,
            RestoreMode.replace,
            acceptedSkipped: rp.skippedCount,
            onStep: progress.onStep,
          );
          progress.close();
          _lostCount = result.lostCount;
          if (!context.mounted) {
            await _refresh();
            return RestoreFlowEnd.restored;
          }
          return _finish(context, result, RestoreSheetKind.replaced);
        } on RestoreRejected catch (e) {
          progress.close();
          if (!context.mounted) return RestoreFlowEnd.refused;
          await showRestoreRejectDialog(context, restoreRejectReasonText(e));
          return RestoreFlowEnd.refused;
        } on RestoreFailed catch (e) {
          progress.close();
          if (!context.mounted) return RestoreFlowEnd.refused;
          if (e.reason == RestoreFailReason.skippedChanged) {
            changed = true; // look again: re-run the preview, never silent
            lookAgain = true;
          } else {
            error = replaceFailedText(e);
          }
        } catch (e) {
          progress.close();
          if (!context.mounted) return RestoreFlowEnd.refused;
          error = replaceFailedText(e);
        }
      }
    }
  }

  /// After a committed Merge or Replace: refresh the app, then the result sheet
  /// (and Undo after a Replace).
  Future<RestoreFlowEnd> _finish(BuildContext context, RestoreResult result, RestoreSheetKind kind) async {
    await _refresh();
    if (!context.mounted) return RestoreFlowEnd.restored;
    final action = await showRestoreResultSheet(context, result, kind: kind);
    if (action == RestoreSheetAction.undo && context.mounted) {
      return _undo(context);
    }
    return RestoreFlowEnd.restored;
  }

  Future<RestoreFlowEnd> _undo(BuildContext context) async {
    final progress = showRestoreProgressSheet(context, RestoreProgressKind.undo);
    final RestoreResult result;
    try {
      result = await _service().undoLastReplace(onStep: progress.onStep);
    } on RestoreFailed catch (e) {
      progress.close();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context, message: restoreFailedText(e));
      return RestoreFlowEnd.refused;
    } catch (_) {
      progress.close();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context);
      return RestoreFlowEnd.refused;
    }
    progress.close();
    await _refresh();
    if (context.mounted) {
      await showRestoreResultSheet(context, result, kind: RestoreSheetKind.undone, lostCount: _lostCount);
    }
    return RestoreFlowEnd.undone;
  }

  /// A failed refresh must never turn a committed restore into an error.
  Future<void> _refresh() async {
    try {
      await onDataChanged();
    } catch (_) {}
  }
}
