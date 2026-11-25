/// §SCREEN.BACKUP.RULES_NOTE: the plain holder for what the restore result sheet says about the
/// rules (0.2.2 item 2, slice U6). The Backup screens cannot import the auto-read side (layout rule
/// E13), so the auto-read side fills [RestoreRulesNotes.builder] with a function from the rule counts
/// to plain text, and the result sheet only draws what it gets. Null builder (standard build, tests,
/// before the wiring installs it) = the sheet is exactly today's.
library;

import 'package:flutter/foundation.dart';

import '../../../data/backup/restore_rules.dart' show RulesRestoreOutcome;

/// One note the result sheet draws under the counts. Text only, already worded by the filler.
@immutable
class RestoreRulesNote {
  const RestoreRulesNote({this.title, required this.body, this.settingsButton});

  /// A bold heading line, or null for a one-line note.
  final String? title;

  /// The note's text (counts only, never a name).
  final String body;

  /// Label of a button that opens Settings at the "Record receiver details" switch; null = no button.
  final String? settingsButton;
}

/// Turns the rules part of a restore into the notes to draw (empty = nothing).
typedef RestoreRulesNoteBuilder = List<RestoreRulesNote> Function(RulesRestoreOutcome outcome);

/// The one holder. Set once by the app's wiring; never by a Backup screen.
class RestoreRulesNotes {
  const RestoreRulesNotes._();

  /// Null = the result sheet draws no rules note at all.
  static RestoreRulesNoteBuilder? builder;

  /// The notes for [outcome]; empty when there is no builder, no rules part, or the builder fails
  /// (a note must never break the result sheet of a committed restore).
  static List<RestoreRulesNote> notesFor(RulesRestoreOutcome? outcome) {
    final b = builder;
    if (b == null || outcome == null) return const [];
    try {
      return b(outcome);
    } catch (_) {
      return const [];
    }
  }
}
