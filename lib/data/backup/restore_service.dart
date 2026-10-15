import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../maintenance/data_op_gate.dart';
import 'backup_service.dart';
import 'backup_settings.dart';
import 'backup_validator.dart';
import 'restore_plan.dart';
import 'restore_steps.dart';
import 'restore_types.dart';
import 'restore_writer.dart';
import 'safety_copy_store.dart';
import 'skipped_row_describer.dart';

export 'backup_validator.dart' show RestoreRejected, RestoreRejectReason;
export 'restore_steps.dart' show RestoreTimerFactory;
export 'restore_types.dart';
export 'skipped_row_describer.dart';

/// Restore orchestration (architecture D5). The order is fixed here, not by
/// the UI:
///
///  1. Stage 1: the WHOLE file is validated (pure, in an isolate). Any
///     problem throws [RestoreRejected]; nothing has been written.
///  2. Replace only: the live rows are read back through the export (rows that
///     cannot be exported are counted, described and need the user's consent),
///     then a private safety copy of this phone's data is written and proven
///     readable ([SafetyCopyStore.write]); any problem throws [RestoreFailed]
///     and nothing has been written.
///  3. Stage 2: ONE `db.transaction` does every write ([RestoreWriter]). Any
///     error rolls it back whole and throws [RestoreFailed]
///     ([RestoreFailed.userMessage]: "Could not restore. Nothing was
///     changed.").
///  4. Only after the commit: allowlisted settings from the file
///     ([BackupSettings.applyAfterCommit]; merge fills only unset ones (A5),
///     replace overwrites). A failed settings write never undoes the data.
///
/// Device-only preferences (remembered recipients, appearance) are never read
/// or written here (F3): a restore, Replace and Undo included, leaves them be.
///
/// The caller refreshes the screens afterwards (`PrimaryShell.dataChanged`).
class RestoreService {
  RestoreService({
    required Future<Database> Function() db,
    required BackupService backup,
    SafetyCopyStore? safety,
    BackupSettings? settings,
    RestoreWriter writer = const RestoreWriter(),
    bool validateInIsolate = true,
    DataOpGate? gate,
    Duration slowAfter = const Duration(seconds: 10),
    RestoreTimerFactory? timer,
  })  : _timer = timer,
        _slowAfter = slowAfter,
        _gate = gate ?? DataOpGate.instance,
        _db = db,
        _backup = backup,
        _safety = safety ?? SafetyCopyStore(),
        _settings = settings ?? BackupSettings(),
        _writer = writer,
        _isolate = validateInIsolate;

  final Future<Database> Function() _db;
  final BackupService _backup;
  final SafetyCopyStore _safety;
  final BackupSettings _settings;
  final RestoreWriter _writer;
  final bool _isolate;
  final DataOpGate _gate;
  final RestoreTimerFactory? _timer;

  /// A step still running after this long emits a `slow` event (BP2: 10 s).
  final Duration _slowAfter;

  RestoreStepReporter _steps(void Function(RestoreStepEvent)? onStep) =>
      RestoreStepReporter(onStep, slowAfter: _slowAfter, timer: _timer);

  /// Full validation and a read-only preview of what a merge would add.
  /// Writes nothing. Throws [RestoreRejected] for a bad file.
  Future<RestorePreview> inspect(Uint8List bytes) async {
    final db = await _db();
    await _guardSchema(db);
    final groups = await _enabledGroups(db);
    final file = await _validate(bytes, groups);
    return db.transaction((txn) async {
      final plan = RestorePlan.build(file, await RestoreLookups.load(txn));
      Future<int> count(String sql) async =>
          (await txn.rawQuery(sql)).first['n'] as int? ?? 0;
      return RestorePreview(
        fileSchemaVersion: file.schemaVersion,
        fileCreatedAt: file.createdAt,
        fileClassifications: file.classifications.length,
        fileTransactions: file.transactions.length,
        fileCounterpartyMap: file.counterpartyMap.length,
        newClassifications: plan.newClassifications.length,
        newTransactions: plan.newTransactions.length,
        duplicateTransactions: plan.txSkipped,
        newCounterpartyMap: plan.newMapRows.length,
        phoneTransactions: await count(
            'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL'),
        phoneUserClassifications: await count(
            'SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NULL'),
        phoneCounterpartyMap: await count(
            'SELECT COUNT(*) AS n FROM counterparty_classification_map'),
        phoneRecentlyDeleted: await count(
            'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NOT NULL'),
      );
    });
  }

  /// §DATA.RESTORE.REPLACE_S10A — read-only (no gate, no write): what a Replace would do to this phone
  /// right now. The live rows are read back through the same export the
  /// safety copy uses; rows that cannot be exported are counted as lost and
  /// described (date and type only) BEFORE anything could delete them. With
  /// [bytes] the file is validated too (throws [RestoreRejected]). Throws
  /// [RestoreFailed] (`safetyCopyFailed`) when the live rows cannot be read.
  Future<ReplacePreview> previewReplace([Uint8List? bytes]) async {
    final db = await _db();
    await _guardSchema(db);
    ValidatedBackup? file;
    if (bytes != null) file = await _validate(bytes, await _enabledGroups(db));
    final export = await _exportLive();
    final userClasses = (await db.rawQuery(
                'SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NULL'))
            .first['n'] as int? ??
        0;
    final id = export.identity;
    return ReplacePreview(
      identity: id,
      skipped: export.notIncluded,
      phoneTransactions: id.transactions.live,
      phoneUserClassifications: userClasses,
      phoneCounterpartyMap: id.counterpartyMap.live,
      phoneRecentlyDeleted: export.deletedLeftOut,
      fileTransactions: file?.transactions.length,
      fileClassifications: file?.classifications.length,
      fileCounterpartyMap: file?.counterpartyMap.length,
    );
  }

  /// Validates [bytes] in full, then restores them in [mode]. See the class
  /// comment for the order. Throws [RestoreRejected] (bad file) or
  /// [RestoreFailed] (nothing was changed).
  ///
  /// Replace and rows that cannot go into the safety copy (A2a): [acceptedSkipped]
  /// is the number the user agreed to lose (from [previewReplace]). When the
  /// real count is above it (or it is null while the real count is above 0)
  /// the restore refuses BEFORE any write with
  /// [RestoreFailReason.skippedChanged]. [onStep] receives the real progress
  /// events (validating, safetyCopy, writing); it never breaks the restore.
  Future<RestoreResult> restore(
    Uint8List bytes,
    RestoreMode mode, {
    int? acceptedSkipped,
    void Function(RestoreStepEvent event)? onStep,
  }) async {
    // S9b-1 (A7): one data operation at a time. Busy touches nothing.
    if (!_gate.tryAcquire()) throw const RestoreFailed(RestoreFailReason.busy);
    try {
      return await _restore(bytes, mode, acceptedSkipped, _steps(onStep));
    } finally {
      _gate.release();
    }
  }

  Future<RestoreResult> _restore(
    Uint8List bytes,
    RestoreMode mode,
    int? acceptedSkipped,
    RestoreStepReporter steps,
  ) async {
    late final Database db;
    late final Set<String> groups;
    final file = await steps.run(RestoreStep.validating, () async {
      db = await _db();
      await _guardSchema(db);
      groups = await _enabledGroups(db);
      return _validate(bytes, groups);
    });

    _SafetyCopy? copy;
    if (mode == RestoreMode.replace) {
      copy = await steps.run(
          RestoreStep.safetyCopy, () => _makeSafetyCopy(groups, acceptedSkipped));
    }

    final tally = await steps.run(
        RestoreStep.writing, () => _write(db, file, mode, copy?.live));
    final settings = await _applySettings(file.prefs, onlyIfUnset: mode == RestoreMode.merge);
    return RestoreResult(
      mode: mode,
      tally: tally,
      settings: settings,
      safetyCopyKept: mode == RestoreMode.replace,
      lost: copy?.lost ?? SkippedSummary.empty,
      identity: copy?.identity,
    );
  }

  /// True while a safety copy exists (the Backup page offers "Undo").
  Future<bool> canUndo() async {
    try {
      return await _safety.exists();
    } catch (_) {
      return false;
    }
  }

  /// Undo the last replace: a REPLACE from the safety copy, in one
  /// transaction, without making a new safety copy. On success the safety
  /// copy is removed and PROVEN removed ([SafetyCopyStore.clearVerified]), so
  /// Undo is no longer offered; when it cannot be removed the result carries
  /// `safetyCopyStillThere`. Entries added after the replace are lost; the UI
  /// must say so.
  Future<RestoreResult> undoLastReplace({void Function(RestoreStepEvent event)? onStep}) async {
    if (!_gate.tryAcquire()) throw const RestoreFailed(RestoreFailReason.busy);
    try {
      return await _undoLastReplace(_steps(onStep));
    } finally {
      _gate.release();
    }
  }

  Future<RestoreResult> _undoLastReplace(RestoreStepReporter steps) async {
    Uint8List? bytes;
    try {
      bytes = await _safety.readLatest();
    } catch (e) {
      throw RestoreFailed(RestoreFailReason.noSafetyCopy, e);
    }
    if (bytes == null) throw const RestoreFailed(RestoreFailReason.noSafetyCopy);
    final copyBytes = bytes;

    late final Database db;
    late final Set<String> groups;
    final file = await steps.run(RestoreStep.validating, () async {
      db = await _db();
      await _guardSchema(db);
      groups = await _enabledGroups(db);
      return _validate(copyBytes, groups);
    });
    final tally = await steps.run(
        RestoreStep.writing, () => _write(db, file, RestoreMode.replace, null));
    final settings = await _applySettings(file.prefs, onlyIfUnset: false);
    var stillThere = false;
    try {
      await _safety.clearVerified();
    } catch (_) {
      stillThere = true;
    }
    return RestoreResult(
      mode: RestoreMode.replace,
      tally: tally,
      settings: settings,
      safetyCopyStillThere: stillThere,
    );
  }

  // ---------------------------------------------------------------------------

  Future<ValidatedBackup> _validate(Uint8List bytes, Set<String> groups) {
    if (!_isolate) {
      return Future.value(BackupValidator.validate(bytes, enabledGroupCodes: groups));
    }
    return _validateInIsolate(bytes, groups);
  }

  /// Static so the isolate closure captures only the bytes and the groups.
  static Future<ValidatedBackup> _validateInIsolate(Uint8List bytes, Set<String> groups) =>
      Isolate.run(() => BackupValidator.validate(bytes, enabledGroupCodes: groups));

  /// Reads the live rows back through the export. Any failure here is a
  /// refusal BEFORE a live write.
  Future<BackupExport> _exportLive() async {
    try {
      return await _backup.export();
    } catch (e) {
      throw RestoreFailed(RestoreFailReason.safetyCopyFailed, e);
    }
  }

  /// Replace step 0 (A2a). Order: read the live rows back (export), check the
  /// user's consent for rows that cannot be exported, write the safety copy
  /// and prove it. Nothing here touches the live tables.
  ///
  /// Two row-count sets (addendum B): the safety copy must hold the INCLUDED
  /// counts; the transaction compares the LIVE counts (included + skipped).
  Future<_SafetyCopy> _makeSafetyCopy(Set<String> groups, int? acceptedSkipped) async {
    final export = await _exportLive();
    final id = export.identity;
    final skipped = export.skippedCount;
    if (skipped > 0 && (acceptedSkipped == null || acceptedSkipped < skipped)) {
      throw const RestoreFailed(RestoreFailReason.skippedChanged);
    }
    final included = ExpectedRows(
      transactions: id.transactions.included,
      classifications: id.classifications.included,
      counterpartyMap: id.counterpartyMap.included,
    );
    try {
      await _safety.write(export.bytes, expect: included, enabledGroupCodes: groups);
    } catch (e) {
      throw RestoreFailed(RestoreFailReason.safetyCopyFailed, e);
    }
    return _SafetyCopy(
      live: ExpectedRows(
        transactions: id.transactions.included + id.transactions.skipped,
        classifications: id.classifications.included + id.classifications.skipped,
        counterpartyMap: id.counterpartyMap.included + id.counterpartyMap.skipped,
      ),
      lost: export.notIncluded,
      identity: id,
    );
  }

  Future<RestoreTally> _write(
    Database db,
    ValidatedBackup file,
    RestoreMode mode,
    ExpectedRows? expect,
  ) async {
    try {
      return await db.transaction((txn) => mode == RestoreMode.merge
          ? _writer.merge(txn, file)
          : _writer.replace(txn, file, expect: expect));
    } on RestoreDataChanged catch (e) {
      throw RestoreFailed(RestoreFailReason.dataChangedMeanwhile, e);
    } catch (e) {
      throw RestoreFailed(RestoreFailReason.databaseError, e);
    }
  }

  Future<SettingsApplyResult> _applySettings(
    Map<String, Object?> prefs, {
    required bool onlyIfUnset,
  }) async {
    if (prefs.isEmpty) return const SettingsApplyResult(ok: true);
    try {
      return await _settings.applyAfterCommit(prefs, onlyIfUnset: onlyIfUnset);
    } catch (_) {
      return const SettingsApplyResult(ok: false);
    }
  }

  static Future<void> _guardSchema(Database db) async {
    final v = (await db.rawQuery('PRAGMA user_version')).first.values.first;
    if (v is! int || v < 2) throw const RestoreFailed(RestoreFailReason.schemaTooOld);
  }

  static Future<Set<String>> _enabledGroups(Database db) async => {
        for (final r in await db.rawQuery(
            'SELECT code FROM classification_groups WHERE enabled = 1'))
          r['code']! as String,
      };
}

/// What Replace step 0 hands on: the LIVE counts the transaction must find,
/// the rows that will be lost (described before the write) and the identity.
class _SafetyCopy {
  const _SafetyCopy({required this.live, required this.lost, required this.identity});
  final ExpectedRows live;
  final SkippedSummary lost;
  final ReplaceIdentity identity;
}
