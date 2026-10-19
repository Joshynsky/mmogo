import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../platform/storage_bridge.dart';
import '../backup/safety_copy_store.dart';
import '../db/app_database.dart';
import '../prefs/backup_prefs.dart';
import 'data_file_system.dart';
import 'data_prefs_access.dart';
import 'delete_data_types.dart';
import 'device_keys.dart';

/// §DATA.MAINTENANCE.RESET — everything "Reset app" touches, injectable. The
/// default constructor is the REAL app; a test passes temp paths and fakes
/// (never the defaults).
class ResetEnv {
  ResetEnv({
    AppDatabase? db,
    DatabaseFactory Function()? dbFactory,
    SafetyCopyStore? safety,
    DataPrefsAccess? prefs,
    StorageBridge Function()? bridge,
    DataFileSystem? fs,
    int Function()? nowMs,
    Future<bool> Function()? deviceWipe,
    this.grantTimeout = const Duration(seconds: 5),
    this.flagReadTimeout = const Duration(seconds: 2),
  })  : db = db ?? AppDatabase.instance,
        dbFactory = dbFactory ?? (() => databaseFactory),
        safety = safety ?? SafetyCopyStore(),
        prefs = prefs ?? SharedDataPrefsAccess(),
        bridge = bridge ?? (() => StorageBridge.instance),
        fs = fs ?? const IoDataFileSystem(),
        nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        deviceWipe = deviceWipe ?? defaultDeviceWipe;

  final AppDatabase db;
  final DatabaseFactory Function() dbFactory;
  final SafetyCopyStore safety;
  final DataPrefsAccess prefs;
  final StorageBridge Function() bridge;
  final DataFileSystem fs;
  final int Function() nowMs;

  /// Device state that lives outside the database and the preferences (the
  /// platform side of a feature). True only when it is gone AND read back; false
  /// or a throw = the delete did not finish (fail closed). Null = nothing to do.
  final Future<bool> Function()? deviceWipe;

  /// What a default [ResetEnv] uses. Feature code sets it once at start (before
  /// the start-up resume); null in the standard build.
  static Future<bool> Function()? defaultDeviceWipe;

  /// Runs [deviceWipe]; true when there is none or it proved the wipe.
  Future<bool> runDeviceWipe() async {
    final w = deviceWipe;
    if (w == null) return true;
    try {
      return await w();
    } catch (_) {
      return false;
    }
  }

  final Duration grantTimeout;
  final Duration flagReadTimeout;
}

/// Steps 4 to 7 of Reset app. The same code runs after a normal reset has
/// closed the database and at the next start-up when the flag is still there
/// (the resume), so a crash anywhere ends the same way. Every step is
/// idempotent. Returns null when the reset is complete (the flag is gone),
/// else the step that failed first.
class ResetSteps {
  ResetSteps(this.env);
  final ResetEnv env;

  static const _sidecars = ['', '-journal', '-wal', '-shm'];

  Future<DeleteDataStep?> finish() async {
    if (!await _deleteFiles()) return DeleteDataStep.files;
    try {
      await env.safety.clearVerified();
    } catch (_) {
      return DeleteDataStep.safetyCopy;
    }
    if (!await env.runDeviceWipe()) return DeleteDataStep.queue;
    await _releaseGrant(); // best effort, never a failure
    if (!await _wipePrefs()) return DeleteDataStep.prefs;
    if (!await _removeFlag()) return DeleteDataStep.resetFlag;
    return null;
  }

  /// Step 4: the database file and its journal / wal / shm; none may remain.
  Future<bool> _deleteFiles() async {
    try {
      final path = await env.db.databasePath();
      try {
        await env.dbFactory().deleteDatabase(path);
      } catch (_) {
        // The plain delete below decides.
      }
      for (final s in _sidecars) {
        try {
          await env.fs.delete('$path$s');
        } catch (_) {
          // Checked below.
        }
      }
      for (final s in _sidecars) {
        if (await env.fs.exists('$path$s')) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Step 6a: give the old backup folder's permission back, BEFORE the prefs
  /// that hold its address are wiped. The files in the folder stay.
  Future<void> _releaseGrant() async {
    try {
      final uri = await env.prefs.readString(BackupPrefs.keyAutoBackupFolderUri);
      if (uri == null || uri.isEmpty) return;
      await env.bridge().releaseGrant(uri).timeout(env.grantTimeout);
    } catch (_) {
      // A permission that stays is harmless.
    }
  }

  /// Step 6b: remove EVERY key except the flag (not `prefs.clear()`), then
  /// read back: only the flag remains.
  Future<bool> _wipePrefs() async {
    try {
      for (final k in await env.prefs.keys()) {
        if (k == kResetPendingKey) continue;
        if (!await env.prefs.remove(k)) return false;
      }
      final left = await env.prefs.keys();
      return left.every((k) => k == kResetPendingKey);
    } catch (_) {
      return false;
    }
  }

  /// Step 7: the flag goes LAST; only now is the reset complete.
  Future<bool> _removeFlag() async {
    try {
      if (!await env.prefs.remove(kResetPendingKey)) return false;
      return !await env.prefs.has(kResetPendingKey);
    } catch (_) {
      return false;
    }
  }
}

/// How the last [ResetResume.runIfPending] ended.
enum ResetResumeOutcome {
  /// No reset was pending.
  nothingPending,

  /// A pending reset was finished; the app starts as a first launch.
  completed,

  /// A pending reset could not be finished (the flag stays; the next launch
  /// tries again). The app starts normally; show "Delete data did not finish".
  notFinished,

  /// The flag could not be read in time; the app starts normally and tries
  /// again next launch.
  flagUnreadable,
}

/// Start-up half of Reset app. `main()` awaits [runIfPending] right after
/// `WidgetsFlutterBinding.ensureInitialized()` and BEFORE anything opens the
/// database, loads the palette or runs the open-failure gate.
class ResetResume {
  ResetResume._();

  /// How the latest call ended (for the start-up banner and tests).
  static ResetResumeOutcome lastOutcome = ResetResumeOutcome.nothingPending;

  /// The step the latest unfinished resume stopped at.
  static DeleteDataStep? lastFailedStep;

  /// True when a pending reset was found AND finished. Never throws, and a
  /// failure never blocks start-up (no crash loop: the next launch retries).
  /// Tests pass [env] with temp paths and fakes.
  static Future<bool> runIfPending({ResetEnv? env}) async {
    lastOutcome = ResetResumeOutcome.nothingPending;
    lastFailedStep = null;
    try {
      final e = env ?? ResetEnv();
      final bool pending;
      try {
        pending = await e.prefs.has(kResetPendingKey).timeout(e.flagReadTimeout);
      } catch (_) {
        lastOutcome = ResetResumeOutcome.flagUnreadable;
        return false;
      }
      if (!pending) return false;
      AppDatabase.resetInProgress = true;
      try {
        final failed = await ResetSteps(e).finish();
        if (failed != null) {
          lastOutcome = ResetResumeOutcome.notFinished;
          lastFailedStep = failed;
          return false;
        }
        lastOutcome = ResetResumeOutcome.completed;
        return true;
      } finally {
        AppDatabase.resetInProgress = false;
      }
    } catch (_) {
      lastOutcome = ResetResumeOutcome.notFinished;
      lastFailedStep = DeleteDataStep.resetFlag;
      AppDatabase.resetInProgress = false;
      return false;
    }
  }
}
