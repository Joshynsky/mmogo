/// AUTOREAD RULES guard: rules do not survive Delete data, and the undone-codes list and history summary
/// never travel in a backup.
///
/// CHANGED ON PURPOSE (0.2.2 item 2, S-4a): rules DO travel now, but only in the backup file's own
/// `receiver_rules` section (schema 9). They are still never a backup SETTING: no rule key may
/// appear in `kBackupSettingSpecs` / the file's `prefs`. A Replace restore still wipes them here
/// ([afterReplaceRestore], queued first); the file's rules are then imported by `RuleRestoreApplier`
/// (S-4b, `RulesWiring.restoreSink`, same serial queue), so Replace = wipe, then import. A Merge
/// restore never calls the wipe. Neither touches the pause switch (`autoread_hard_paused`).
///
/// CHANGED ON PURPOSE (0.2.2 item 2, B-HIDE; PM 25-11): "Record receiver details" OFF no longer erases the
/// rules; the store hides them (all() empty, get() null) until it is ON again. At OFF only
/// [clearDetailsOffData] runs (the undone codes and the history summary). [wipe] stays exactly as it was,
/// for Delete data (`AutoReadWipe`) and a Replace restore.
///
/// DECISIONS (B-HIDE, backups while details are OFF):
///  - Export: carries no rules. The export reads the store, which answers empty while OFF (hidden = not used).
///  - Replace restore while OFF: [afterReplaceRestore] erases the HIDDEN rules too, so turning ON later does
///    not bring back the settings from before the restore (the restored phone should match the file). The
///    file's rules are then left out by the import (it refuses while OFF).
///  - Merge restore while OFF: never calls this guard, so the hidden rules stay and come back at ON.
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

/// What details OFF clears (B-HIDE): the undone codes and the history summary, never a rule key.
const List<String> kDetailsOffClearedPrefixes = [kUndoneCodesKey, kHistorySummaryKey];

bool _isRuleData(String k) => kRuleKeyPrefixes.any(k.startsWith);

bool _isDetailsOffData(String k) => kDetailsOffClearedPrefixes.any(k.startsWith);

class RuleBackupGuard {
  RuleBackupGuard({ReadingPrefs? prefs}) : _prefs = prefs ?? SharedReadingPrefs();

  final ReadingPrefs _prefs;

  /// True when no rule, undone-code or history key is left afterwards. Delete data (autoread_wipe.dart) and
  /// a Replace restore; unchanged by B-HIDE.
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

  /// "Record receiver details" went OFF (B-HIDE): only the undone codes and the history summary go; every
  /// rule key stays (hidden by the store). True when none of those two is left afterwards.
  Future<bool> clearDetailsOffData() async {
    try {
      for (final k in (await _prefs.keys()).where(_isDetailsOffData).toList()) {
        await _prefs.remove(k);
      }
      return !(await _prefs.keys()).any(_isDetailsOffData);
    } catch (_) {
      return false;
    }
  }

  /// Called after a committed Replace restore: every rule goes, hidden ones included while details are OFF
  /// (see DECISIONS above); the file's, if any, are imported right after by the restore sink. A Merge restore
  /// never calls this.
  Future<bool> afterReplaceRestore() => wipe();
}
