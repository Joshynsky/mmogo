/// §AUTOREAD.LEVELS.RESTORE_RULE_MESSAGES: fills the Backup screens' rules-note holder
/// ([RestoreRulesNotes], lib/ui) with the 0.2.2 restore wording from hard_rule_copy.dart (slice U6).
/// The Backup screens cannot import the auto-read side, so the wiring calls
/// [installRestoreRuleMessages] once at start (slice I1). Counts only: never a person's name.
/// The details-off note shows whenever rules were dropped (backups carry rules whatever the flag);
/// the Auto-record review line is dormant while [autoRecordUi] is false.
library;

import '../../../data/backup/restore_rules.dart' show RulesRestoreOutcome;
import '../../../ui/screens/backup/restore_rules_note.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart' show autoRecordUi;

/// The notes for one restore's rules part (empty = the result sheet says nothing about rules).
/// - Rules left out because "Record receiver details" is off: title, count, Open Settings.
/// - People restored from Auto-record who are on Ask first until a review: one count line.
List<RestoreRulesNote> restoreRuleNotes(RulesRestoreOutcome o) {
  return [
    if (o.droppedForPrivacy > 0)
      RestoreRulesNote(
        title: kHardRestoreOffTitle,
        body: hardRestoreOffBody(o.droppedForPrivacy),
        settingsButton: kHardOpenSettings,
      ),
    if (autoRecordUi && o.autoRecordAsAskFirst > 0) RestoreRulesNote(body: hardRestoreToast(o.autoRecordAsAskFirst)),
  ];
}

/// Installs [restoreRuleNotes] in the holder (the wiring, I1).
void installRestoreRuleMessages() => RestoreRulesNotes.builder = restoreRuleNotes;

/// Removes it again (tests; the standard build never installs it).
void uninstallRestoreRuleMessages() => RestoreRulesNotes.builder = null;
