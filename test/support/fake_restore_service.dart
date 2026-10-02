// A RestoreService for widget tests: no database, no files. Records calls,
// can fail or wait on a Completer at each step.
import 'dart:async';
import 'dart:typed_data';

import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_service.dart';

RestorePreview fakePreview({
  int fileTx = 187,
  int fileCls = 2,
  int fileMap = 15,
  int newTx = 142,
  int dupTx = 45,
  int phoneTx = 60,
  int phoneCls = 3,
  int phoneMap = 7,
  int deleted = 4,
}) => RestorePreview(
  fileSchemaVersion: 2,
  fileCreatedAt: DateTime(2026, 9, 20, 10, 15).millisecondsSinceEpoch,
  fileClassifications: fileCls,
  fileTransactions: fileTx,
  fileCounterpartyMap: fileMap,
  newClassifications: 1,
  newTransactions: newTx,
  duplicateTransactions: dupTx,
  newCounterpartyMap: 11,
  phoneTransactions: phoneTx,
  phoneUserClassifications: phoneCls,
  phoneCounterpartyMap: phoneMap,
  phoneRecentlyDeleted: deleted,
);

RestoreResult fakeResult(RestoreMode mode, {bool settingsOk = true, bool keepCopy = true}) => RestoreResult(
  mode: mode,
  tally: mode == RestoreMode.merge
      ? const RestoreTally(
          classifications: TableCounts(added: 1, skipped: 1),
          transactions: TableCounts(added: 142, skipped: 45),
          counterpartyMap: TableCounts(added: 11, skipped: 4),
        )
      : const RestoreTally(
          classifications: TableCounts(added: 2),
          transactions: TableCounts(added: 187),
          counterpartyMap: TableCounts(added: 15),
        ),
  settings: SettingsApplyResult(ok: settingsOk),
  safetyCopyKept: mode == RestoreMode.replace && keepCopy,
);

class FakeRestoreService implements RestoreService {
  FakeRestoreService({RestorePreview? preview}) : preview = preview ?? fakePreview();

  RestorePreview preview;
  final List<String> calls = [];
  Uint8List? lastBytes;

  Object? inspectError;
  Object? restoreError;
  Object? undoError;
  bool settingsOk = true;

  /// When set, the step waits for it (to look at the progress state).
  Completer<void>? inspectGate;
  Completer<void>? restoreGate;

  @override
  Future<RestorePreview> inspect(Uint8List bytes) async {
    calls.add('inspect');
    lastBytes = bytes;
    await inspectGate?.future;
    if (inspectError != null) throw inspectError!;
    return preview;
  }

  @override
  Future<RestoreResult> restore(Uint8List bytes, RestoreMode mode) async {
    calls.add('restore:${mode.name}');
    await restoreGate?.future;
    if (restoreError != null) throw restoreError!;
    return fakeResult(mode, settingsOk: settingsOk);
  }

  @override
  Future<bool> canUndo() async => true;

  @override
  Future<RestoreResult> undoLastReplace() async {
    calls.add('undo');
    if (undoError != null) throw undoError!;
    return fakeResult(RestoreMode.replace, keepCopy: false);
  }
}
