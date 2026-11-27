/// §AUTOREAD.LEVELS.RESTORE_RULE_MESSAGES: fills the Backup screens' rules-note holder
/// ([RestoreRulesNotes], lib/ui) with the 0.2.2 restore wording from hard_rule_copy.dart (slice U6).
/// The Backup screens cannot import the auto-read side, so the wiring calls
/// [installRestoreRuleMessages] once at start (slice I1). Counts only: never a person's name.
/// The details-off note shows whenever rules were dropped (backups carry rules whatever the flag);
/// the Auto-record review line is dormant while [autoRecordUi] is false.
library;

import '../../../data/backup/restore_rules.dart' show RulesRestoreOutcome;
import '../../../ui/copy/backup_copy.dart' show restoreRulesKeptNames, restoreRulesLine, restoreRulesNeedKeep;
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
    ..._rulesLine(o),
    if (o.keptLocalNames.isNotEmpty) RestoreRulesNote(body: restoreRulesKeptNames(o.keptLocalNames)),
    if (autoRecordUi && o.autoRecordAsAskFirst > 0) RestoreRulesNote(body: restoreRulesNeedKeep(o.autoRecordAsAskFirst)),
  ];
}

/// The Rules line (added / replaced / kept from this phone), only while the Auto-record UI is on.
List<RestoreRulesNote> _rulesLine(RulesRestoreOutcome o) {
  if (!autoRecordUi) return const <RestoreRulesNote>[];
  final line = restoreRulesLine(added: o.added, replaced: o.replaced, keptPhone: o.keptPhone);
  return line == null ? const <RestoreRulesNote>[] : [RestoreRulesNote(body: line)];
}

/// Installs [restoreRuleNotes] in the holder (the wiring, I1).
void installRestoreRuleMessages() => RestoreRulesNotes.builder = restoreRuleNotes;

/// Removes it again (tests; the standard build never installs it).
void uninstallRestoreRuleMessages() => RestoreRulesNotes.builder = null;
