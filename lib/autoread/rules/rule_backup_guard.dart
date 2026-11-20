/// AUTOREAD RULES guard: rules never travel in a backup and never survive a
/// Replace restore, Delete data or "Record receiver details" OFF.
///
/// [wipe] removes every rule key, the undone-codes list and the history
/// summary (`autoread_hist_v1`, written by slice S2b), then reads back; false
/// means something is still there (fail closed for Delete data).
library;

import '../logic/reading_controller.dart' show ReadingPrefs, SharedReadingPrefs;
import 'prefs_undone_codes.dart' show kUndoneCodesKey;
import 'rule_codec.dart' show kRuleKeyPrefix;

/// The history summary preference (owned by S2b; wiped here).
const String kHistorySummaryKey = 'autoread_hist_v1';

/// Everything this feature keeps that must never enter a backup. A test pins
/// that none of these is in `backup_setting_keys.dart`.
const List<String> kRuleKeyPrefixes = [kRuleKeyPrefix, kUndoneCodesKey, kHistorySummaryKey];

bool _isRuleData(String k) => kRuleKeyPrefixes.any(k.startsWith);

class RuleBackupGuard {
  RuleBackupGuard({ReadingPrefs? prefs}) : _prefs = prefs ?? SharedReadingPrefs();

  final ReadingPrefs _prefs;

  /// True when no rule, undone-code or history key is left afterwards.
  Future<bool> wipe() async {
    try {
      for (final k in (await _prefs.keys()).where(_isRuleData).toList()) {
        await _prefs.remove(k);
      }
      return !(await _prefs.keys()).any(_isRuleData);
    } catch (_) {
      return false;
    }
  }

  /// Called after a committed Replace restore: every person goes back to
  /// Suggested. A Merge restore never calls this.
  Future<bool> afterReplaceRestore() => wipe();
}
