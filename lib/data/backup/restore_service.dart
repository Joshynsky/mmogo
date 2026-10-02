import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_service.dart';
import 'backup_settings.dart';
import 'backup_validator.dart';
import 'restore_plan.dart';
import 'restore_types.dart';
import 'restore_writer.dart';
import 'safety_copy_store.dart';

export 'backup_validator.dart' show RestoreRejected, RestoreRejectReason;
export 'restore_types.dart';

/// Restore orchestration (architecture D5). The order is fixed here, not by
/// the UI:
///
///  1. Stage 1: the WHOLE file is validated (pure, in an isolate). Any
///     problem throws [RestoreRejected]; nothing has been written.
///  2. Replace only: a private safety copy of this phone's data is written
///     and proven readable ([SafetyCopyStore.write]); any problem throws
///     [RestoreFailed] and nothing has been written.
///  3. Stage 2: ONE `db.transaction` does every write ([RestoreWriter]). Any
///     error rolls it back whole and throws [RestoreFailed]
///     ([RestoreFailed.userMessage]: "Could not restore. Nothing was
///     changed.").
///  4. Only after the commit: allowlisted settings from the file
///     ([BackupSettings.applyAfterCommit]; merge fills only unset ones (A5),
///     replace overwrites). A failed settings write never undoes the data.
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
  })  : _db = db,
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

  /// Validates [bytes] in full, then restores them in [mode]. See the class
  /// comment for the order. Throws [RestoreRejected] (bad file) or
  /// [RestoreFailed] (nothing was changed).
  Future<RestoreResult> restore(Uint8List bytes, RestoreMode mode) async {
    final db = await _db();
    await _guardSchema(db);
    final groups = await _enabledGroups(db);
    final file = await _validate(bytes, groups);

    ExpectedRows? expect;
    if (mode == RestoreMode.replace) expect = await _makeSafetyCopy(groups);

    final tally = await _write(db, file, mode, expect);
    final settings = await _applySettings(file.prefs, onlyIfUnset: mode == RestoreMode.merge);
    return RestoreResult(
      mode: mode,
      tally: tally,
      settings: settings,
      safetyCopyKept: mode == RestoreMode.replace,
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
  /// copy is removed (so Undo is no longer offered). Entries added after the
  /// replace are lost; the UI must say so.
  Future<RestoreResult> undoLastReplace() async {
    Uint8List? bytes;
    try {
      bytes = await _safety.readLatest();
    } catch (e) {
      throw RestoreFailed(RestoreFailReason.noSafetyCopy, e);
    }
    if (bytes == null) throw const RestoreFailed(RestoreFailReason.noSafetyCopy);

    final db = await _db();
    await _guardSchema(db);
    final groups = await _enabledGroups(db);
    final file = await _validate(bytes, groups);
    final tally = await _write(db, file, RestoreMode.replace, null);
    final settings = await _applySettings(file.prefs, onlyIfUnset: false);
    try {
      await _safety.clear();
    } catch (_) {}
    return RestoreResult(mode: RestoreMode.replace, tally: tally, settings: settings);
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

  Future<ExpectedRows> _makeSafetyCopy(Set<String> groups) async {
    final BackupExport export;
    try {
      export = await _backup.export();
    } catch (e) {
      throw RestoreFailed(RestoreFailReason.safetyCopyFailed, e);
    }
    if (export.skippedCount > 0) {
      // The copy would not hold every row, so Undo could not bring them all
      // back: refuse rather than lose data (data-model.md D, replace step 0).
      throw const RestoreFailed(RestoreFailReason.safetyCopyIncomplete);
    }
    final expect = ExpectedRows(
      transactions: export.transactions,
      classifications: export.classifications,
      counterpartyMap: export.counterpartyMap,
    );
    try {
      await _safety.write(export.bytes, expect: expect, enabledGroupCodes: groups);
    } catch (e) {
      throw RestoreFailed(RestoreFailReason.safetyCopyFailed, e);
    }
    return expect;
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
