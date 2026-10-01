import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../prefs/app_prefs.dart';
import 'backup_setting_keys.dart';

export 'backup_setting_keys.dart';

/// Outcome of [BackupSettings.applyAfterCommit]. Never an exception: a
/// failed settings write must not undo a data restore (the UI then says
/// "Settings could not be applied").
class SettingsApplyResult {
  const SettingsApplyResult({
    required this.ok,
    this.applied = const [],
    this.skipped = const [],
    this.problemKey,
  });

  /// False when the block was rejected whole (unknown key, wrong type or
  /// range) or a write failed.
  final bool ok;

  /// File keys written.
  final List<String> applied;

  /// File keys left alone because the phone already has a value (merge).
  final List<String> skipped;

  /// The first offending file key when [ok] is false (never its value).
  final String? problemKey;
}

/// The backup file's settings block: what goes into a backup
/// ([snapshot]) and what is applied after a restore commits
/// ([applyAfterCommit]). The allowlist is [kBackupSettingSpecs].
///
/// Injectable: the restore service takes a `BackupSettings` so a test can
/// substitute a fake that records call order (B16).
class BackupSettings {
  BackupSettings({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? _defaultPrefs;

  final Future<SharedPreferences> Function() _prefs;

  static Future<SharedPreferences> _defaultPrefs() =>
      SharedPreferences.getInstance().timeout(const Duration(seconds: 2));

  /// The allowlisted settings that are SET on this phone, keyed by file key.
  /// A value that would fail its own check is left out, so the exporter can
  /// never emit a settings block the validator would reject. Returns an
  /// empty map when preferences cannot be read.
  Future<Map<String, Object?>> snapshot() async {
    try {
      final p = await _prefs();
      final out = <String, Object?>{};
      for (final spec in kBackupSettingSpecs) {
        if (!p.containsKey(spec.prefsKey)) continue;
        final Object? value = p.get(spec.prefsKey);
        if (spec.accepts(value)) out[spec.fileKey] = value;
      }
      return out;
    } catch (_) {
      return <String, Object?>{};
    }
  }

  /// Checks a whole settings block without writing: returns the first
  /// offending file key, or `null` when every key is allowlisted and its
  /// value passes. An unknown key or a wrong type fails the WHOLE block.
  static String? firstProblem(Map<String, Object?> settings) {
    for (final entry in settings.entries) {
      final spec = backupSettingSpecFor(entry.key);
      if (spec == null || !spec.accepts(entry.value)) return entry.key;
    }
    return null;
  }

  /// Applies [settings] to this phone. Call ONLY after the restore
  /// transaction has committed (criterion 10).
  ///
  /// The block is validated first; if any key is unknown or any value fails,
  /// nothing is written. With [onlyIfUnset] (merge mode, A5) a key the phone
  /// already has a value for is skipped; replace mode overwrites.
  Future<SettingsApplyResult> applyAfterCommit(
    Map<String, Object?> settings, {
    bool onlyIfUnset = false,
  }) async {
    final bad = firstProblem(settings);
    if (bad != null) return SettingsApplyResult(ok: false, problemKey: bad);

    final applied = <String>[];
    final skipped = <String>[];
    try {
      final p = await _prefs();
      for (final entry in settings.entries) {
        final spec = backupSettingSpecFor(entry.key)!;
        if (onlyIfUnset && _isSet(p, spec)) {
          skipped.add(spec.fileKey);
          continue;
        }
        final ok = await _write(p, spec, entry.value);
        if (!ok) {
          return SettingsApplyResult(
            ok: false,
            applied: applied,
            skipped: skipped,
            problemKey: spec.fileKey,
          );
        }
        applied.add(spec.fileKey);
        if (spec.prefsKey == AppPrefs.keyUserDisplayName) {
          // Home listens to this to refresh its greeting.
          AppPrefs.userDisplayNameRevision.value++;
        }
      }
    } catch (_) {
      return SettingsApplyResult(
        ok: false,
        applied: applied,
        skipped: skipped,
      );
    }
    return SettingsApplyResult(ok: true, applied: applied, skipped: skipped);
  }

  static bool _isSet(SharedPreferences p, BackupSettingSpec spec) {
    if (!p.containsKey(spec.prefsKey)) return false;
    if (spec.kind == BackupSettingKind.text) {
      final v = p.get(spec.prefsKey);
      return v is String && v.trim().isNotEmpty;
    }
    return true;
  }

  static Future<bool> _write(
    SharedPreferences p,
    BackupSettingSpec spec,
    Object? value,
  ) {
    switch (spec.kind) {
      case BackupSettingKind.boolean:
        return p.setBool(spec.prefsKey, value! as bool);
      case BackupSettingKind.integer:
        return p.setInt(spec.prefsKey, value! as int);
      case BackupSettingKind.text:
      case BackupSettingKind.choice:
        return p.setString(spec.prefsKey, value! as String);
    }
  }
}
