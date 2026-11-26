/// §AUTOREAD.HARD_RULE_PAUSE - the one "pause all Auto-record" switch (0.2.2 item 2, S-2).
///
/// Stored in preferences so it survives an app restart. Delete data clears it
/// (AutoReadWipe). It is NOT a rule key and NOT a backup setting: a restore
/// never pauses or unpauses by itself. While paused every Auto-record rule
/// behaves as Ask first; rules, levels and ceilings stay saved.
/// Reads fail closed (a failure or a 2 s timeout reads as paused).
/// B-PAUSE: the pinned phone notice's Resume button (Kotlin, mmogo may be closed) writes this key = `false`,
/// which reads as not paused; [pauseResumeStep] is the Dart mirror of what that button decides.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

const String kHardPausedPrefsKey = 'autoread_hard_paused';
const Duration kHardPauseBound = Duration(seconds: 2);

/// What the pinned paused notice's Resume button does with the stored value it read (0.2.2 item 2,
/// B-PAUSE). Kotlin mirror: PauseNotice.resumeStep / ResumeStep (PauseActionReceiver.kt runs it with mmogo
/// closed; a Dart test pins both).
enum PauseResumeStep {
  /// Stored value is exactly `true`: write `false` (read as not paused), then remove the notice.
  resume,

  /// Absent or exactly `false`: nothing to resume; the notice is stale and goes.
  already,

  /// Anything else, or the value could not be read: do nothing; the pause and the notice stay (fail closed).
  keep,
}

/// Dart mirror of the Kotlin Resume decision. [unreadable] = the preference file could not be read.
PauseResumeStep pauseResumeStep(Object? raw, {bool unreadable = false}) {
  if (unreadable) return PauseResumeStep.keep;
  if (raw == true) return PauseResumeStep.resume;
  if (raw == null || raw == false) return PauseResumeStep.already;
  return PauseResumeStep.keep;
}

class PrefsHardRulePause {
  PrefsHardRulePause({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  Future<SharedPreferences> _fresh() async {
    final p = await _prefs();
    await p.reload();
    return p;
  }

  /// True when paused. Unset = not paused. Any failure = paused (safe side).
  Future<bool> isPaused() async {
    try {
      final p = await _fresh().timeout(kHardPauseBound);
      final v = p.get(kHardPausedPrefsKey);
      if (v == null) return false;
      return v is bool ? v : true; // a wrong-typed value is doubt: paused
    } catch (_) {
      return true;
    }
  }

  /// Returns true when the new state was stored and read back.
  Future<bool> setPaused(bool paused) async {
    try {
      final p = await _fresh().timeout(kHardPauseBound);
      if (paused) {
        await p.setBool(kHardPausedPrefsKey, true).timeout(kHardPauseBound);
      } else {
        await p.remove(kHardPausedPrefsKey).timeout(kHardPauseBound);
      }
      return (await _fresh().timeout(kHardPauseBound)).getBool(kHardPausedPrefsKey) == (paused ? true : null);
    } catch (_) {
      return false;
    }
  }
}
