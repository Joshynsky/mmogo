/// AUTOREAD RULES guard: rules survive neither Delete data nor "Record receiver details" OFF,
/// and the undone-codes list and history summary never travel in a backup.
///
/// CHANGED ON PURPOSE (0.2.2 item 2, S-4a): rules DO travel now, but only in the backup file's own
/// `receiver_rules` section (schema 9). They are still never a backup SETTING: no rule key may
/// appear in `kBackupSettingSpecs` / the file's `prefs`. A Replace restore still wipes them here
/// ([afterReplaceRestore], queued first); the file's rules are then imported by `RuleRestoreApplier`
/// (S-4b, `RulesWiring.restoreSink`, same serial queue), so Replace = wipe, then import. A Merge
/// restore never calls the wipe. Neither touches the pause switch (`autoread_hard_paused`).
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

/// Everything this feature keeps outside the database. A test pins that none of these is a backup
/// SETTING (`backup_setting_keys.dart`); rules travel only in the `receiver_rules` section.
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

  /// Called after a committed Replace restore: every rule goes (the file's, if any, are imported
  /// right after by the restore sink). A Merge restore never calls this.
  Future<bool> afterReplaceRestore() => wipe();
}
