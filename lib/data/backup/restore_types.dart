import 'backup_settings.dart';

/// How a valid backup file is applied (architecture D5).
enum RestoreMode {
  /// Default. Adds only what this phone does not have; never edits or deletes
  /// an existing row. Settings are applied only where still unset (A5).
  merge,

  /// Deletes this phone's entries, learned receivers and user-made
  /// classifications, then writes the file's. Built-ins are kept and take the
  /// file's names. A private safety copy is written first (A8). Settings from
  /// the file overwrite.
  replace,
}

/// Rows per table: `added` were inserted; `skipped` were already on this
/// phone (or, for a built-in classification, matched by its `seed_key`) and
/// were not inserted. `rejected` is always 0 today: the validator refuses the
/// WHOLE file on any bad row, so a restore that runs never rejects single
/// rows. Kept so the result sheet's shape does not change if that rule ever
/// does.
class TableCounts {
  const TableCounts({this.added = 0, this.skipped = 0, this.rejected = 0});

  final int added;
  final int skipped;
  final int rejected;

  int get total => added + skipped + rejected;

  @override
  bool operator ==(Object other) =>
      other is TableCounts &&
      other.added == added &&
      other.skipped == skipped &&
      other.rejected == rejected;

  @override
  int get hashCode => Object.hash(added, skipped, rejected);

  @override
  String toString() => 'TableCounts(added: $added, skipped: $skipped, rejected: $rejected)';
}

/// What the database part of a restore did (before settings).
class RestoreTally {
  const RestoreTally({
    required this.classifications,
    required this.transactions,
    required this.counterpartyMap,
    this.builtInsUpdated = 0,
  });

  final TableCounts classifications;
  final TableCounts transactions;
  final TableCounts counterpartyMap;

  /// Replace mode only: built-in classifications that took the file's name,
  /// active flag and date (they are never deleted or inserted).
  final int builtInsUpdated;
}

/// Read-only summary of a valid file, for the merge-or-replace dialog.
/// Computed WITHOUT writing anything.
class RestorePreview {
  const RestorePreview({
    required this.fileSchemaVersion,
    required this.fileCreatedAt,
    required this.fileClassifications,
    required this.fileTransactions,
    required this.fileCounterpartyMap,
    required this.newClassifications,
    required this.newTransactions,
    required this.duplicateTransactions,
    required this.newCounterpartyMap,
    required this.phoneTransactions,
    required this.phoneUserClassifications,
    required this.phoneCounterpartyMap,
    required this.phoneRecentlyDeleted,
  });

  final int fileSchemaVersion;

  /// Epoch ms the backup was made (from the file).
  final int fileCreatedAt;

  final int fileClassifications;
  final int fileTransactions;
  final int fileCounterpartyMap;

  /// What a MERGE would add (and skip) against this phone right now.
  final int newClassifications;
  final int newTransactions;
  final int duplicateTransactions;
  final int newCounterpartyMap;

  /// This phone now (for the replace confirmation: "This phone now: ...").
  final int phoneTransactions;
  final int phoneUserClassifications;
  final int phoneCounterpartyMap;

  /// Recently deleted entries a REPLACE would also remove for good.
  final int phoneRecentlyDeleted;
}

/// Outcome of a restore that committed.
class RestoreResult {
  const RestoreResult({
    required this.mode,
    required this.tally,
    required this.settings,
    this.safetyCopyKept = false,
  });

  final RestoreMode mode;
  final RestoreTally tally;

  /// Settings are applied AFTER the commit. When `settings.ok` is false the
  /// data restore still stands and the UI says "Settings could not be
  /// applied".
  final SettingsApplyResult settings;

  /// Replace: a private safety copy of the old data exists (Undo is offered).
  final bool safetyCopyKept;

  TableCounts get classifications => tally.classifications;
  TableCounts get transactions => tally.transactions;
  TableCounts get counterpartyMap => tally.counterpartyMap;
  bool get settingsApplied => settings.ok;

  /// Architecture D5 contract: totals over the three tables.
  int get inserted =>
      classifications.added + transactions.added + counterpartyMap.added;
  int get skipped =>
      classifications.skipped + transactions.skipped + counterpartyMap.skipped;
}

/// Why a restore of a VALID file did not happen. In every case the database
/// is exactly as it was (one transaction, rolled back, or never opened).
enum RestoreFailReason {
  /// The database is older than version 2 (no `seed_key`); never expected.
  schemaTooOld,

  /// Replace: the safety copy could not be written, read back or checked.
  safetyCopyFailed,

  /// Replace: the safety copy would leave rows out (the exporter had to skip
  /// rows it could not make valid), so it could not bring everything back.
  safetyCopyIncomplete,

  /// Replace: the data changed between the safety copy and the transaction.
  dataChangedMeanwhile,

  /// Undo: there is no safety copy.
  noSafetyCopy,

  /// Any database error inside the transaction (constraint, trigger, I/O).
  databaseError,
}

/// Thrown by `RestoreService` when a restore could not be done. Carries no
/// row content. [cause] is for logs and tests only, never shown.
class RestoreFailed implements Exception {
  const RestoreFailed(this.reason, [this.cause]);

  /// The one message the user sees (PM wording).
  static const String userMessage = 'Could not restore. Nothing was changed.';

  final RestoreFailReason reason;
  final Object? cause;

  @override
  String toString() => 'RestoreFailed(${reason.name})';
}
