/// §DATA.MAINTENANCE.TYPES — the result types of Delete data (0.1.2 S9b-1).
/// COUNTS ONLY: nothing here ever carries a name, phone number, code or amount.
library;

enum DeleteDataOutcome {
  /// Everything asked for is done and checked.
  done,

  /// Level 1 only: the check after the delete found rows left, so the whole
  /// delete was rolled back. UI: "Nothing was deleted".
  nothingWasDeleted,

  /// A step failed. For Level 1 the database part is already committed (it is
  /// NOT rolled back); [DeleteDataResult.failedStep] says where it stopped and
  /// "Try again" re-runs the same method. UI: "Delete data did not finish ...".
  notFinished,

  /// Another restore / undo / delete / reset holds the `DataOpGate`, or an
  /// automatic backup would not stand still. Nothing was touched.
  busy,
}

enum DeleteDataStep {
  database,
  vacuum,
  safetyCopy,
  recipientMemory,
  queue,
  sinceCount,
  prefs,
  files,
  resetFlag,
}

class DeleteDataResult {
  const DeleteDataResult({
    required this.outcome,
    this.transactionsDeleted = 0,
    this.softDeletedIncluded = 0,
    this.learnedReceiversDeleted = 0,
    this.safetyCopyCleared = false,
    this.vacuumRan = false,
    this.failedStep,
  });

  final DeleteDataOutcome outcome;

  /// Live transactions that were deleted (soft-deleted ones are counted in
  /// [softDeletedIncluded], not here).
  final int transactionsDeleted;
  final int softDeletedIncluded;
  final int learnedReceiversDeleted;
  final bool safetyCopyCleared;
  final bool vacuumRan;

  /// Set for [DeleteDataOutcome.notFinished] only.
  final DeleteDataStep? failedStep;

  @override
  String toString() =>
      'DeleteDataResult(${outcome.name}, tx: $transactionsDeleted, soft: $softDeletedIncluded, '
      'receivers: $learnedReceiversDeleted, safety: $safetyCopyCleared, vacuum: $vacuumRan, step: ${failedStep?.name})';
}

/// What there is to delete right now (counts and presence flags).
class DeleteDataPeek {
  const DeleteDataPeek({
    required this.liveTransactions,
    required this.softDeletedTransactions,
    required this.learnedReceivers,
    required this.safetyCopyPresent,
    required this.rememberedRecipientsPresent,
    required this.queuePresent,
    this.rememberedRecipientsCount = 0,
    this.nothingLeftAtLevel2 = false,
    this.incomplete = false,
  });

  final int liveTransactions;
  final int softDeletedTransactions;
  final int learnedReceivers;
  final bool safetyCopyPresent;
  final bool rememberedRecipientsPresent;
  final bool queuePresent;

  /// How many remembered recipients (a count, never a name).
  final int rememberedRecipientsCount;

  /// Level 2 has nothing to do: no transactions (live or deleted), no learned
  /// receivers, no user categories, no safety copy, and the only stored pref
  /// keys are (a subset of) `whatsnew_seen_version`.
  final bool nothingLeftAtLevel2;

  /// Part of the picture could not be read. Then neither "nothing left" flag
  /// is true (the sheet must not claim there is nothing to delete).
  final bool incomplete;

  bool get nothingLeftToDeleteAtLevel1 =>
      !incomplete &&
      liveTransactions == 0 &&
      softDeletedTransactions == 0 &&
      learnedReceivers == 0 &&
      !safetyCopyPresent &&
      !rememberedRecipientsPresent &&
      !queuePresent;
}

/// The public face of Delete data. Methods never throw.
abstract class DeleteDataService {
  Future<DeleteDataPeek> peek();

  /// Level 1: deletes the transactions (live and recently deleted), the
  /// learned receivers, the safety copy, the remembered recipients and the
  /// queue; keeps categories and every setting.
  Future<DeleteDataResult> deleteMyTransactions();

  /// Level 2: resets the app to a fresh install (database file, safety copy,
  /// every preference). The caller then runs the soft restart.
  Future<DeleteDataResult> resetApp();
}
