import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Bounded wait for the prefs plugin (same reason as `AppPrefs`).
const _prefsTimeout = Duration(seconds: 2);

/// Device-local update-check state (0.1.1). Never part of a backup file and
/// never restored from one: a file must not switch network use on or off.
/// Reads fall back to their defaults; writes swallow a failure and report
/// `false`.
class UpdatePrefs {
  UpdatePrefs._();

  static const keyEnabled = 'update_check_enabled';
  static const keyLastCheckAt = 'update_last_check_at';

  /// The check is ON by default (PM decision, A10).
  static const defaultEnabled = true;

  static Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance().timeout(_prefsTimeout);

  static Future<bool> readEnabled() async {
    try {
      return (await _prefs()).getBool(keyEnabled) ?? defaultEnabled;
    } catch (_) {
      return defaultEnabled;
    }
  }

  static Future<bool> writeEnabled(bool value) async {
    try {
      return await (await _prefs()).setBool(keyEnabled, value).timeout(_prefsTimeout);
    } catch (_) {
      return false;
    }
  }

  /// Time of the last SUCCESSFUL check; `null` = never (or unreadable).
  static Future<DateTime?> readLastCheckAt() async {
    try {
      final ms = (await _prefs()).getInt(keyLastCheckAt);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  /// B31: the version whose What's-new modal was last shown (or silently
  /// marked on a fresh install). `null` = never written (0.1.0 never wrote it).
  static const keyWhatsNewSeenVersion = 'whatsnew_seen_version';

  static Future<String?> readWhatsNewSeenVersion() async {
    try {
      return (await _prefs()).getString(keyWhatsNewSeenVersion);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> writeWhatsNewSeenVersion(String versionName) async {
    try {
      return await (await _prefs()).setString(keyWhatsNewSeenVersion, versionName).timeout(_prefsTimeout);
    } catch (_) {
      return false;
    }
  }

  /// Welcome calls this while onboarding is not done (a fresh install): the
  /// installed version counts as seen, so the modal never shows for it. Only
  /// writes when nothing is stored yet.
  static Future<void> markWhatsNewSeenForFreshInstall(String versionName) async {
    if (await readWhatsNewSeenVersion() == null) await writeWhatsNewSeenVersion(versionName);
  }

  static Future<bool> writeLastCheckAt(DateTime at) async {
    try {
      return await (await _prefs())
          .setInt(keyLastCheckAt, at.millisecondsSinceEpoch)
          .timeout(_prefsTimeout);
    } catch (_) {
      return false;
    }
  }
}
