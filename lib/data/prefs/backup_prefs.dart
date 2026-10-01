import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// Bounded wait for the prefs plugin (same reason as `AppPrefs`: a stuck
/// platform channel must degrade to "unset", never hang the caller).
const _prefsTimeout = Duration(seconds: 2);

/// Device-local backup state in `shared_preferences` (0.1.1, Lead ruling F3:
/// `auto_backup_*` snake_case names). Same defensive shape as `AppPrefs`:
/// every read falls back to its documented default, every write swallows a
/// failure and reports it as `false`.
///
/// Which of these keys may be restored from a backup file is decided in ONE
/// place, `backup_setting_keys.dart`; only [keyAutoBackupEveryN] and
/// [keyAutoBackupKeepK] are in it. The folder, enabled, paused, count and
/// last-at keys are never read from a file.
class BackupPrefs {
  BackupPrefs._();

  static const keyAutoBackupEnabled = 'auto_backup_enabled';
  static const keyAutoBackupEveryN = 'auto_backup_every_n';
  static const keyAutoBackupKeepK = 'auto_backup_keep_k';
  static const keyAutoBackupFolderUri = 'auto_backup_folder_uri';

  /// Display-only name of the chosen folder (not one of the seven pinned F3
  /// names; used by the setup sheet and the Backup page row).
  static const keyAutoBackupFolderName = 'auto_backup_folder_name';
  static const keyAutoBackupSinceCount = 'auto_backup_since_count';
  static const keyAutoBackupPaused = 'auto_backup_paused';
  static const keyAutoBackupLastAt = 'auto_backup_last_at';
  static const keyBackupLastManualAt = 'backup_last_manual_at';

  static const defaultEveryN = 10;
  static const minEveryN = 1;
  static const maxEveryN = 100;

  static const defaultKeepK = 5;
  static const minKeepK = 2;
  static const maxKeepK = 20;

  /// Live "paused" state for the Backup page row and the Settings subtitle.
  /// Updated by [writePaused] and [clearAutoBackup]; the pref stays the
  /// source of truth (this carries a copy for listeners).
  static final ValueNotifier<bool> pausedNotifier = ValueNotifier<bool>(false);

  static Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance().timeout(_prefsTimeout);

  static Future<T> _read<T>(
    T fallback,
    T Function(SharedPreferences p) read,
  ) async {
    try {
      return read(await _prefs());
    } catch (_) {
      return fallback;
    }
  }

  /// `true` only when the write definitely happened.
  static Future<bool> _write(
    Future<bool> Function(SharedPreferences p) write,
  ) async {
    try {
      return await write(await _prefs()).timeout(_prefsTimeout);
    } catch (_) {
      return false;
    }
  }

  // --- enabled -----------------------------------------------------------

  static Future<bool> readEnabled() =>
      _read(false, (p) => p.getBool(keyAutoBackupEnabled) ?? false);

  static Future<bool> writeEnabled(bool value) =>
      _write((p) => p.setBool(keyAutoBackupEnabled, value));

  // --- every N / keep K (clamped on read AND write) -------------------------

  static Future<int> readEveryN() => _read(
        defaultEveryN,
        (p) => (p.getInt(keyAutoBackupEveryN) ?? defaultEveryN)
            .clamp(minEveryN, maxEveryN),
      );

  static Future<bool> writeEveryN(int value) => _write(
        (p) => p.setInt(keyAutoBackupEveryN, value.clamp(minEveryN, maxEveryN)),
      );

  static Future<int> readKeepK() => _read(
        defaultKeepK,
        (p) => (p.getInt(keyAutoBackupKeepK) ?? defaultKeepK)
            .clamp(minKeepK, maxKeepK),
      );

  static Future<bool> writeKeepK(int value) => _write(
        (p) => p.setInt(keyAutoBackupKeepK, value.clamp(minKeepK, maxKeepK)),
      );

  // --- folder ----------------------------------------------------------------

  static Future<String?> readFolderUri() => _read<String?>(null, (p) {
        final v = p.getString(keyAutoBackupFolderUri);
        return (v == null || v.isEmpty) ? null : v;
      });

  /// `null` or empty removes the key.
  static Future<bool> writeFolderUri(String? uri) => _write(
        (p) => (uri == null || uri.isEmpty)
            ? p.remove(keyAutoBackupFolderUri)
            : p.setString(keyAutoBackupFolderUri, uri),
      );

  static Future<String?> readFolderName() => _read<String?>(null, (p) {
        final v = p.getString(keyAutoBackupFolderName);
        return (v == null || v.isEmpty) ? null : v;
      });

  static Future<bool> writeFolderName(String? name) => _write(
        (p) => (name == null || name.isEmpty)
            ? p.remove(keyAutoBackupFolderName)
            : p.setString(keyAutoBackupFolderName, name),
      );

  // --- counter -----------------------------------------------------------------

  static Future<int> readSinceCount() => _read(0, (p) {
        final v = p.getInt(keyAutoBackupSinceCount) ?? 0;
        return v < 0 ? 0 : v;
      });

  static Future<bool> writeSinceCount(int value) => _write(
        (p) => p.setInt(keyAutoBackupSinceCount, value < 0 ? 0 : value),
      );

  // --- paused -------------------------------------------------------------------

  static Future<bool> readPaused() async {
    final v = await _read(false, (p) => p.getBool(keyAutoBackupPaused) ?? false);
    pausedNotifier.value = v;
    return v;
  }

  static Future<bool> writePaused(bool value) async {
    final ok = await _write((p) => p.setBool(keyAutoBackupPaused, value));
    if (ok) pausedNotifier.value = value;
    return ok;
  }

  // --- last-backup times ------------------------------------------------------------

  /// ISO-8601 string, as pinned by F3.
  static Future<DateTime?> readLastAt() => _read<DateTime?>(null, (p) {
        final v = p.getString(keyAutoBackupLastAt);
        return v == null ? null : DateTime.tryParse(v);
      });

  static Future<bool> writeLastAt(DateTime when) =>
      _write((p) => p.setString(keyAutoBackupLastAt, when.toIso8601String()));

  /// Epoch ms, as pinned by F3.
  static Future<DateTime?> readLastManualAt() => _read<DateTime?>(null, (p) {
        final v = p.getInt(keyBackupLastManualAt);
        return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
      });

  static Future<bool> writeLastManualAt(DateTime when) => _write(
        (p) => p.setInt(keyBackupLastManualAt, when.millisecondsSinceEpoch),
      );

  // --- turning auto-backup off ---------------------------------------------------------

  /// Clears the folder keys when auto-backup is turned off: folder uri and
  /// name, enabled, paused and the counter. (The caller releases the SAF
  /// grant.) Leaves every-N, keep-K and the last-backup time alone.
  static Future<bool> clearAutoBackup() async {
    final ok = await _write((p) async {
      for (final k in const [
        keyAutoBackupFolderUri,
        keyAutoBackupFolderName,
        keyAutoBackupEnabled,
        keyAutoBackupPaused,
        keyAutoBackupSinceCount,
      ]) {
        await p.remove(k);
      }
      return true;
    });
    if (ok) pausedNotifier.value = false;
    return ok;
  }
}
