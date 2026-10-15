import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../backup/auto_backup_service.dart';
import '../db/app_database.dart';
import '../db/db_open.dart' show firstIntOf;
import '../prefs/backup_prefs.dart';
import '../prefs/recipient_memory.dart';
import 'data_op_gate.dart';
import 'delete_data_types.dart';
import 'device_keys.dart';
import 'reset_resume.dart';

export 'delete_data_types.dart';

/// §DATA.MAINTENANCE.SERVICE — Delete data (DD1 / CA7, 0.1.2 S9b-1). Follows
/// `_pipeline/v0.1.2/baseline/dbe-note-delete-data.md` step by step.
///
/// THIS CODE IS DESTRUCTIVE. Tests must inject a temp database path, a temp
/// safety folder, mock prefs and fakes ([ResetEnv]); see
/// `test/support/data_op_env.dart`.
///
/// The public methods never throw: a step that fails becomes
/// [DeleteDataOutcome.notFinished] with [DeleteDataResult.failedStep]. The
/// [DataOpGate] is always released in a `finally`. Results are counts only.
class DeleteDataServiceImpl implements DeleteDataService {
  DeleteDataServiceImpl({
    ResetEnv? env,
    RecipientMemory? memory,
    AutoBackupService Function()? autoBackup,
    DataOpGate? gate,
    this.onDataChanged,
    this.vacuumTimeout = const Duration(seconds: 20),
    this.quiesceBound = AutoBackupService.quiesceBound,
    Future<void> Function(Database db)? vacuum,
    Future<int> Function(DatabaseExecutor db, String table)? countRows,
    Future<bool> Function(int value)? writeSinceCount,
    Future<int> Function()? readSinceCount,
  })  : env = env ?? ResetEnv(),
        _memory = memory ?? RecipientMemory(),
        _auto = autoBackup ?? (() => AutoBackupService.instance),
        _gate = gate ?? DataOpGate.instance,
        _vacuum = vacuum ?? _defaultVacuum,
        _countRows = countRows ?? _defaultCount,
        _writeSince = writeSinceCount ?? BackupPrefs.writeSinceCount,
        _readSince = readSinceCount ?? BackupPrefs.readSinceCount;

  final ResetEnv env;
  final RecipientMemory _memory;
  final AutoBackupService Function() _auto;
  final DataOpGate _gate;
  final Future<void> Function(Database db) _vacuum;
  final Future<int> Function(DatabaseExecutor db, String table) _countRows;
  final Future<bool> Function(int value) _writeSince;
  final Future<int> Function() _readSince;

  /// Step f of Level 1: the screens refresh (the UI passes
  /// `() => PrimaryShell.active?.dataChanged()` and re-reads the Backup page).
  /// Null = nothing to refresh (tests).
  final void Function()? onDataChanged;

  final Duration vacuumTimeout;
  final Duration quiesceBound;

  static Future<void> _defaultVacuum(Database db) async {
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Optional.
    }
    await db.execute('VACUUM');
  }

  static Future<int> _defaultCount(DatabaseExecutor db, String table) async =>
      firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;

  static const _nothingDeleted = 'Nothing was deleted';

  // ---------------------------------------------------------------- peek

  @override
  Future<DeleteDataPeek> peek() async {
    var incomplete = false;
    var live = 0, soft = 0, learned = 0, userClasses = 0;
    try {
      final db = await env.db.database;
      live = await _scalar(db, 'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL');
      soft = await _scalar(db, 'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NOT NULL');
      learned = await _scalar(db, 'SELECT COUNT(*) FROM counterparty_classification_map');
      userClasses = await _scalar(db, 'SELECT COUNT(*) FROM classifications WHERE seed_key IS NULL');
    } catch (_) {
      incomplete = true;
    }
    var safety = false;
    try {
      safety = await env.safety.exists();
    } catch (_) {
      incomplete = true;
    }
    var remembered = 0;
    try {
      remembered = (await _memory.list()).length;
    } catch (_) {
      incomplete = true;
    }
    var queue = false;
    var extraKeys = false;
    try {
      final keys = await env.prefs.keys();
      queue = queueKeys.any(keys.contains);
      extraKeys = keys.any((k) => k != kBaselinePrefKey);
    } catch (_) {
      incomplete = true;
    }
    return DeleteDataPeek(
      liveTransactions: live,
      softDeletedTransactions: soft,
      learnedReceivers: learned,
      safetyCopyPresent: safety,
      rememberedRecipientsPresent: remembered > 0,
      rememberedRecipientsCount: remembered,
      queuePresent: queue,
      nothingLeftAtLevel2: !incomplete &&
          live == 0 &&
          soft == 0 &&
          learned == 0 &&
          userClasses == 0 &&
          !safety &&
          !extraKeys,
      incomplete: incomplete,
    );
  }

  Future<int> _scalar(DatabaseExecutor db, String sql) async => firstIntOf(await db.rawQuery(sql)) ?? 0;

  // ------------------------------------------------------------- level 1

  @override
  Future<DeleteDataResult> deleteMyTransactions() async {
    if (!_gate.tryAcquire()) return const DeleteDataResult(outcome: DeleteDataOutcome.busy);
    var step = DeleteDataStep.database;
    var live = 0, soft = 0, learned = 0;
    var committed = false;
    var vacuumRan = false;
    var safetyCleared = false;
    DeleteDataResult partial(DeleteDataOutcome o, [DeleteDataStep? failed]) => DeleteDataResult(
          outcome: o,
          transactionsDeleted: committed ? live : 0,
          softDeletedIncluded: committed ? soft : 0,
          learnedReceiversDeleted: committed ? learned : 0,
          safetyCopyCleared: safetyCleared,
          vacuumRan: vacuumRan,
          failedStep: failed,
        );
    try {
      // Auto-backup must stand still; one that will not is "busy".
      if (!await _quiesce()) return const DeleteDataResult(outcome: DeleteDataOutcome.busy);

      // The database part: ONE transaction (note: capture, delete, verify).
      final db = await env.db.database;
      try {
        await db.transaction((txn) async {
          live = await _scalar(txn, 'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL');
          soft = await _scalar(txn, 'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NOT NULL');
          learned = await _scalar(txn, 'SELECT COUNT(*) FROM counterparty_classification_map');
          await txn.delete('counterparty_classification_map');
          await txn.delete('transactions');
          // Count again with no deleted_at filter: soft-deleted rows too.
          final left = await _countRows(txn, 'counterparty_classification_map') + await _countRows(txn, 'transactions');
          if (left != 0) throw StateError(_nothingDeleted);
        });
        committed = true;
      } on StateError catch (e) {
        if (e.message == _nothingDeleted) return partial(DeleteDataOutcome.nothingWasDeleted);
        return partial(DeleteDataOutcome.notFinished, DeleteDataStep.database);
      } catch (_) {
        return partial(DeleteDataOutcome.notFinished, DeleteDataStep.database);
      }

      // a. best-effort VACUUM: never a failure.
      step = DeleteDataStep.vacuum;
      try {
        await _vacuum(db).timeout(vacuumTimeout);
        vacuumRan = true;
      } catch (_) {
        vacuumRan = false;
      }

      // b. safety copy: removed AND proven gone (Undo of Replace is gone).
      step = DeleteDataStep.safetyCopy;
      try {
        await env.safety.clearVerified();
        if (await env.safety.exists()) throw StateError('safety copy left');
        safetyCleared = true;
      } catch (_) {
        return partial(DeleteDataOutcome.notFinished, step);
      }

      // c. remembered recipients: forgetAll() true AND absent on a fresh read.
      step = DeleteDataStep.recipientMemory;
      try {
        if (!await _memory.forgetAll()) throw StateError('not forgotten');
        if (await env.prefs.has(RecipientMemory.prefsKey)) throw StateError('still stored');
      } catch (_) {
        return partial(DeleteDataOutcome.notFinished, step);
      }

      // d. the queue (and the phone-merge report): removed, read back absent.
      step = DeleteDataStep.queue;
      try {
        for (final k in [...queueKeys, kPhoneMergeReportKey]) {
          if (await env.prefs.has(k) && !await env.prefs.remove(k)) throw StateError('not removed');
          if (await env.prefs.has(k)) throw StateError('still stored');
        }
      } catch (_) {
        return partial(DeleteDataOutcome.notFinished, step);
      }

      // e. the auto-backup counter goes to 0 (the folder, the written list and
      // every file in it are left alone).
      step = DeleteDataStep.sinceCount;
      try {
        if (!await _writeSince(0)) throw StateError('not written');
        if (await _readSince() != 0) throw StateError('not zero');
      } catch (_) {
        return partial(DeleteDataOutcome.notFinished, step);
      }

      // f. the screens refresh (they show the empty state, Undo is gone).
      try {
        onDataChanged?.call();
      } catch (_) {}
      return partial(DeleteDataOutcome.done);
    } catch (_) {
      return partial(DeleteDataOutcome.notFinished, step);
    } finally {
      try {
        _auto().resume();
      } catch (_) {}
      _gate.release();
    }
  }

  Future<bool> _quiesce() async {
    try {
      return await _auto().quiesce(bound: quiesceBound);
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------- level 2

  @override
  Future<DeleteDataResult> resetApp() async {
    if (!_gate.tryAcquire()) return const DeleteDataResult(outcome: DeleteDataOutcome.busy);
    var step = DeleteDataStep.database;
    var live = 0, soft = 0, learned = 0;
    DeleteDataResult result(DeleteDataOutcome o, [DeleteDataStep? failed]) => DeleteDataResult(
          outcome: o,
          transactionsDeleted: o == DeleteDataOutcome.done ? live : 0,
          softDeletedIncluded: o == DeleteDataOutcome.done ? soft : 0,
          learnedReceiversDeleted: o == DeleteDataOutcome.done ? learned : 0,
          safetyCopyCleared: o == DeleteDataOutcome.done,
          failedStep: failed,
        );
    var guardSet = false;
    try {
      // 1. nothing else may run; an auto-backup that will not stop is
      // "not finished at step database" and touches nothing.
      if (!await _quiesce()) return result(DeleteDataOutcome.notFinished, DeleteDataStep.database);

      // Counts for the result, only when the database is already open (never
      // opens or creates the file just to count).
      if (env.db.isOpen) {
        try {
          final db = await env.db.database;
          live = await _scalar(db, 'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL');
          soft = await _scalar(db, 'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NOT NULL');
          learned = await _scalar(db, 'SELECT COUNT(*) FROM counterparty_classification_map');
        } catch (_) {}
      }

      // 2. the flag, written and read back, before anything is touched.
      step = DeleteDataStep.resetFlag;
      try {
        final at = env.nowMs();
        if (!await env.prefs.setInt(kResetPendingKey, at)) throw StateError('flag not written');
        if (await env.prefs.readInt(kResetPendingKey) != at) throw StateError('flag not read back');
      } catch (_) {
        return result(DeleteDataOutcome.notFinished, step);
      }

      // 3. close the handle (the guard first: nothing may reopen the file).
      step = DeleteDataStep.database;
      AppDatabase.resetInProgress = true;
      guardSet = true;
      try {
        await env.db.close();
      } catch (_) {
        return result(DeleteDataOutcome.notFinished, step);
      }

      // 4-7 (shared with the start-up resume).
      final failed = await ResetSteps(env).finish();
      if (failed != null) return result(DeleteDataOutcome.notFinished, failed);
      return result(DeleteDataOutcome.done);
    } catch (_) {
      return result(DeleteDataOutcome.notFinished, step);
    } finally {
      // Cleared only when the flag is gone or the reset stopped with a failure.
      if (guardSet) AppDatabase.resetInProgress = false;
      try {
        _auto().resume();
      } catch (_) {}
      _gate.release();
    }
  }
}
