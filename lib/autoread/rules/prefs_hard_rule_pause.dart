/// §AUTOREAD.HARD_RULE_PAUSE - the one "pause all Auto-record" switch (0.2.2 item 2, S-2).
///
/// Stored in preferences so it survives an app restart. Delete data clears it
/// (AutoReadWipe). It is NOT a rule key and NOT a backup setting: a restore
/// never pauses or unpauses by itself. While paused every Auto-record rule
/// behaves as Ask first; rules, levels and ceilings stay saved.
/// Reads fail closed (a failure or a 2 s timeout reads as paused).
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

const String kHardPausedPrefsKey = 'autoread_hard_paused';
const Duration kHardPauseBound = Duration(seconds: 2);

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
