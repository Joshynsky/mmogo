import 'package:flutter/material.dart';

import '../../../data/backup/backup_limits.dart';
import '../../../data/backup/backup_service.dart';
import '../../../data/backup/restore_service.dart';
import '../../../data/db/app_database.dart';
import '../../../platform/storage_bridge.dart';
import '../../copy/data_copy.dart';
import 'restore_dialogs.dart';
import 'restore_messages.dart';
import 'restore_result_sheet.dart';

/// How a run of the Restore flow ended (for the Backup page and tests).
enum RestoreFlowEnd {
  /// The picker was closed without a file.
  pickerCancelled,

  /// The user backed out at the merge-or-replace dialog or the Replace
  /// confirmation. Nothing was changed.
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
/// Replace (with a second confirmation for Replace), restore, show the result
/// sheet, and Undo after a Replace.
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

  StorageBridge get _storage => _bridge ?? StorageBridge.instance;

  static RestoreService _defaultService() {
    return RestoreService(
      db: () => AppDatabase.instance.database,
      backup: BackupService(db: () => AppDatabase.instance.database),
    );
  }

  /// Runs the whole flow. Never throws: every failure is a dialog.
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

    // 4. Replace needs a second, explicit confirmation.
    if (mode == RestoreMode.replace) {
      final confirmed = await showReplaceConfirmDialog(context, preview);
      if (!confirmed || !context.mounted) return RestoreFlowEnd.cancelled;
    }

    // 5. Do it.
    final closeRestoring = showRestoreProgress(
      context,
      mode == RestoreMode.replace ? kRestoreReplacing : kRestoreRestoring,
    );
    final RestoreResult result;
    try {
      result = await _service().restore(bytes, mode);
    } on RestoreRejected catch (e) {
      closeRestoring();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreRejectDialog(context, restoreRejectReasonText(e));
      return RestoreFlowEnd.refused;
    } on RestoreFailed catch (e) {
      closeRestoring();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context, message: restoreFailedText(e));
      return RestoreFlowEnd.refused;
    } catch (_) {
      closeRestoring();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context);
      return RestoreFlowEnd.refused;
    }
    closeRestoring();
    await _refresh();
    if (!context.mounted) return RestoreFlowEnd.restored;

    // 6. Result sheet (and Undo after a Replace).
    final kind = mode == RestoreMode.replace ? RestoreSheetKind.replaced : RestoreSheetKind.merged;
    final action = await showRestoreResultSheet(context, result, kind: kind);
    if (action == RestoreSheetAction.undo && context.mounted) {
      return _undo(context);
    }
    return RestoreFlowEnd.restored;
  }

  Future<RestoreFlowEnd> _undo(BuildContext context) async {
    final closeUndoing = showRestoreProgress(context, kRestoreUndoing);
    final RestoreResult result;
    try {
      result = await _service().undoLastReplace();
    } catch (_) {
      closeUndoing();
      if (!context.mounted) return RestoreFlowEnd.refused;
      await showRestoreFailedDialog(context);
      return RestoreFlowEnd.refused;
    }
    closeUndoing();
    await _refresh();
    if (context.mounted) {
      await showRestoreResultSheet(context, result, kind: RestoreSheetKind.undone);
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
