// A RestoreService for widget tests: no database, no files. Records calls,
// can fail or wait on a Completer at each step, and (S10b) previews a Replace,
// plays scripted step events, and returns results that carry lost rows.
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

const _types = ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI', 'AIRTIME'];

/// [n] invented skipped entries: dates and types only (never a value), with
/// one unreadable entry per 17 rows and a mix of reasons.
List<SkippedRowInfo> fakeSkippedEntries(int n) => [
  for (var i = 0; i < n; i++)
    i % 17 == 16
        ? const SkippedRowInfo(kind: SkipKind.entry, reason: SkipReason.couldNotRead)
        : SkippedRowInfo(
            kind: SkipKind.entry,
            reason: i.isEven ? SkipReason.missingDetail : SkipReason.notAllowed,
            date: DateTime(2026, 9, 1 + i % 28, 10, 30),
            type: _types[i % _types.length],
          ),
];

/// A Replace preview. [rows] are the lost rows (default: [lost] invented
/// entries); the summary caps them at 20 like the real one. Phone counts and
/// the identity follow from the rows.
ReplacePreview fakeReplacePreview({
  int lost = 0,
  List<SkippedRowInfo>? rows,
  int tx = 60,
  int cls = 3,
  int map = 7,
  int deleted = 4,
}) {
  final all = rows ?? fakeSkippedEntries(lost);
  int count(SkipKind k) => all.where((r) => r.kind == k).length;
  final txLost = count(SkipKind.entry);
  final clsLost = count(SkipKind.category);
  final mapLost = count(SkipKind.savedReceiver);
  return ReplacePreview(
    identity: ReplaceIdentity(
      transactions: TableIdentity(included: tx - txLost, skipped: txLost, live: tx),
      classifications: TableIdentity(included: cls - clsLost, skipped: clsLost, live: cls),
      counterpartyMap: TableIdentity(included: map - mapLost, skipped: mapLost, live: map),
    ),
    skipped: SkippedSummary.of(all),
    phoneTransactions: tx,
    phoneUserClassifications: cls,
    phoneCounterpartyMap: map,
    phoneRecentlyDeleted: deleted,
    fileTransactions: 187,
    fileClassifications: 2,
    fileCounterpartyMap: 15,
  );
}

RestoreResult fakeResult(
  RestoreMode mode, {
  bool settingsOk = true,
  bool keepCopy = true,
  SkippedSummary lost = SkippedSummary.empty,
  bool stillThere = false,
  List<String> applied = const [],
}) => RestoreResult(
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
  settings: SettingsApplyResult(ok: settingsOk, applied: applied),
  safetyCopyKept: mode == RestoreMode.replace && keepCopy,
  lost: lost,
  safetyCopyStillThere: stillThere,
);

class FakeRestoreService implements RestoreService {
  FakeRestoreService({RestorePreview? preview}) : preview = preview ?? fakePreview();

  RestorePreview preview;
  final List<String> calls = [];
  Uint8List? lastBytes;
  int? lastAcceptedSkipped;

  Object? inspectError;
  Object? restoreError;
  Object? undoError;
  bool settingsOk = true;

  /// When set, the step waits for it (to look at the progress state).
  Completer<void>? inspectGate;
  Completer<void>? restoreGate;
  Completer<void>? undoGate;
  Completer<void>? previewGate;

  /// S10b: errors for the next restore calls, one per call, before
  /// [restoreError] (a refusal that changes on the second try).
  final List<Object> restoreErrorQueue = [];

  /// S10b: Replace previews for the next previewReplace calls, one per call;
  /// once empty, [replacePreview] (default: nothing would be lost).
  final List<ReplacePreview> previewQueue = [];
  ReplacePreview replacePreview = fakeReplacePreview();
  Object? previewReplaceError;

  /// S10b: what the Replace result and the Undo result carry.
  SkippedSummary resultLost = SkippedSummary.empty;
  bool undoStillThere = false;
  List<String> appliedSettings = const [];

  /// S10b: step events played during restore / undo: [steps] first, then the
  /// gate is awaited, then [stepsAfterGate].
  List<RestoreStepEvent> steps = const [];
  List<RestoreStepEvent> stepsAfterGate = const [];

  /// The sink the last restore / undo was given (a test can push live events).
  void Function(RestoreStepEvent event)? onStepSink;

  @override
  Future<RestorePreview> inspect(Uint8List bytes) async {
    calls.add('inspect');
    lastBytes = bytes;
    await inspectGate?.future;
    if (inspectError != null) throw inspectError!;
    return preview;
  }

  @override
  Future<RestoreResult> restore(
    Uint8List bytes,
    RestoreMode mode, {
    int? acceptedSkipped,
    void Function(RestoreStepEvent event)? onStep,
  }) async {
    calls.add('restore:${mode.name}');
    lastAcceptedSkipped = acceptedSkipped;
    onStepSink = onStep;
    for (final e in steps) {
      onStep?.call(e);
    }
    await restoreGate?.future;
    for (final e in stepsAfterGate) {
      onStep?.call(e);
    }
    if (restoreErrorQueue.isNotEmpty) throw restoreErrorQueue.removeAt(0);
    if (restoreError != null) throw restoreError!;
    return fakeResult(
      mode,
      settingsOk: settingsOk,
      lost: mode == RestoreMode.replace ? resultLost : SkippedSummary.empty,
      applied: appliedSettings,
    );
  }

  @override
  Future<ReplacePreview> previewReplace([Uint8List? bytes]) async {
    calls.add('previewReplace');
    await previewGate?.future;
    if (previewReplaceError != null) throw previewReplaceError!;
    return previewQueue.isNotEmpty ? previewQueue.removeAt(0) : replacePreview;
  }

  @override
  Future<bool> canUndo() async => true;

  @override
  Future<RestoreResult> undoLastReplace({void Function(RestoreStepEvent event)? onStep}) async {
    calls.add('undo');
    onStepSink = onStep;
    for (final e in steps) {
      onStep?.call(e);
    }
    await undoGate?.future;
    if (undoError != null) throw undoError!;
    return fakeResult(RestoreMode.replace, keepCopy: false, stillThere: undoStillThere, applied: appliedSettings);
  }
}
