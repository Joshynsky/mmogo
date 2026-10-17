/// §COPY.DELETE_DATA — words for Delete data and the stale-Undo case (0.1.2
/// S9b-1). S9b-2 (the sheet) adds the rest of its words to THIS file.
///
/// CB6 bans these words anywhere in the Delete data screens: "Erases",
/// "left on this phone", "authentication", and a "Hi," greeting. The mock
/// `settings.html` lines 320-335 still use some of them and must NOT be
/// copied. Nothing here ever carries a name, phone number, code or amount.
library;

/// Result of Delete data that did not finish (Try again re-runs it).
const kDeleteDataNotFinished = 'Delete data did not finish. Try again.';

/// The delete changed nothing (the check after it found rows left, so it was
/// rolled back).
const kDeleteDataNothingDeleted = 'Nothing was deleted';

/// Another restore / undo / delete / reset is running.
const kDataOpBusy = 'Another change is in progress, try again';

/// A stale Undo or Restore: the entry is gone (purged, or Delete data).
const kEntryNoLongerThere = 'That entry is no longer there';

// ---------------------------------------------------------------------------
// 0.1.2 S9b-2: the Delete data row, sheets and results (CB6, binding).
// Every string a Delete data screen shows lives below. The wording says
// "deleted from this phone" and never uses the banned words above; a pattern
// test (`delete_data_copy_test.dart`) scans these constants. Counts only, no
// name, amount or code, anywhere.
// ---------------------------------------------------------------------------

/// The Settings row.
const kDeleteDataTitle = 'Delete data';
const kDeletePermanentTag = 'Permanent';
const kDeleteRowSubtitle = 'Delete your transactions, or reset the app';
const kDeleteRowSubtitleLevel1Done = 'Transactions deleted. You can still reset the app.';
const kDeleteRowSubtitleNothing = 'Nothing to delete';

/// The main sheet (F3: the mock delete-data-help.html). One always-visible
/// line, one short sentence per option; the rest is behind the "?" in the
/// header ([kDeleteExtras]). Every sentence is pinned to what the service
/// really clears by test/data/maintenance/delete_sentences_f3_test.dart.
const kDeleteIntro = 'This cannot be undone.';
const kDeleteHelpLabel = 'About deleting data';
const kDeleteBackUpNow = 'Back up now';
const kDeleteChooseSemantics = 'What to delete';
const kDeleteLevel1Title = 'Delete my transactions';
const kDeleteLevel1Nothing = 'Nothing left to delete here.';
const kDeleteLevel2Title = 'Reset app';
const kDeleteWordLabel = 'Type DELETE to confirm';
const kDeleteWordWord = 'DELETE';
const kDeleteWordHint = 'The red button stays off until the word matches.';
const kDeleteButtonLevel1 = 'Delete transactions';
const kDeleteButtonLevel2 = 'Reset app…';
const kDeleteCancel = 'Cancel';
const kDeleteDone = 'Done';
const kDeleteTryAgain = 'Try again';

/// Spoken hint of the red button while it is off.
const kDeleteButtonSemanticsHint = 'turns on when the word matches';

/// What stays, said the same way on the sheet and on the result.
const kDeleteStayBackups = 'Backup files you saved earlier stay where they are.';
const kDeleteStayAutoList = 'The list of automatic backup files mmogo has written is kept.';
const kDeleteStaySms = 'Your original SMS messages stay on your phone.';
const kDeleteLevel1SafetyGone =
    'The safety copy is deleted too, so Undo of your last Replace is gone.';
const kDeleteLevel1CategoriesStay =
    'Your own categories, and built-in categories you renamed or hid, stay. So do your preferences.';

/// One sentence per option (F3). Delete my transactions: the transactions, the
/// receivers mmogo has learned and the names it remembers go; the settings and
/// ALL categories stay. Reset app: everything mmogo keeps goes; saved backup
/// files stay (the mock said "everything", which they are not part of).
const kDeleteLevel1Short =
    'Deletes your transactions, the receivers mmogo has learned and the names it remembers. Keeps your settings and categories.';
const kDeleteLevel2Short =
    'Deletes everything mmogo keeps on this phone and returns it to first launch. Backup files you saved earlier stay where they are.';

/// Behind the "?" (F3): what each option ALSO deletes, and what is never touched.
const kDeleteExtraLevel1 =
    'Delete my transactions also clears Recently deleted and the safety copy of your last Replace, so Undo of that Replace is gone.';
const kDeleteExtraLevel2 =
    'Reset app also deletes your preferences, your own categories, changes you made to built-in categories and your display name. It forgets the auto-backup folder.';
const kDeleteExtraBackups = 'Backup files you saved earlier are not touched.';
const kDeleteExtras = [kDeleteExtraLevel1, kDeleteExtraLevel2, kDeleteExtraBackups];
const kDeleteLevel2BackupsForget =
    'Backup files you saved earlier stay where they are, but mmogo forgets which folder they are in.';

const kDeleteCountsPrefix = 'Right now: ';

/// Shown when the counts could not be read (never "nothing left" then).
const kDeleteCountsUnknown = 'Counts are not available right now.';

/// The Reset app confirm sheet.
const kDeleteConfirmTitle = 'Reset app?';
const kDeleteConfirmBody = 'This resets mmogo to a fresh install. Continue?';
const kDeleteConfirmButton = 'Reset app';

/// Busy states.
const kDeleteBusyLevel1 = 'Deleting your transactions from this phone…';
const kDeleteBusyLevel2 = 'Resetting mmogo…';

/// Results.
const kDeleteDoneTitle = 'Your transactions are deleted from this phone';
const kDeleteNothingDeletedTitle = 'Nothing was deleted';
const kDeleteNothingDeletedBody = 'Nothing was changed. You can try again.';

/// A Level 2 failure also says what happens next (the kept flag finishes the
/// reset at the next start; anything added meanwhile is deleted).
const kDeleteLevel2NotFinishedExtra =
    'If you close mmogo now, the reset finishes the next time you open it. Anything you add before then will be deleted.';

/// restart() found no RestartScope: the reset is done, the app must be reopened.
const kDeleteResetDoneReopen = 'Reset is done. Close mmogo and open it again.';

/// The one-time start-up notice after a resume that did not finish.
const kDeleteStartupNotice = kDeleteDataNotFinished;

String _plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

/// The Level 1 counts, from the peek: zeros left out, singular and plural.
/// Counts only. Empty string when every count is zero.
String deleteCountsText({
  required int live,
  required int recentlyDeleted,
  required int learnedReceivers,
  required int rememberedRecipients,
}) {
  final parts = <String>[
    if (live > 0) _plural(live, 'transaction', 'transactions'),
    if (recentlyDeleted > 0) _plural(recentlyDeleted, 'recently deleted', 'recently deleted'),
    if (learnedReceivers > 0) _plural(learnedReceivers, 'learned receiver', 'learned receivers'),
    if (rememberedRecipients > 0) _plural(rememberedRecipients, 'remembered recipient', 'remembered recipients'),
  ];
  return parts.join(', ');
}

/// Every string that a Delete data screen can show or speak, for the pattern
/// test (CB6). Add a new constant here when you add one above.
const kDeleteDataAllStrings = <String>[
  kDeleteDataNotFinished,
  kDeleteDataNothingDeleted,
  kDataOpBusy,
  kDeleteDataTitle,
  kDeletePermanentTag,
  kDeleteRowSubtitle,
  kDeleteRowSubtitleLevel1Done,
  kDeleteRowSubtitleNothing,
  kDeleteIntro,
  kDeleteHelpLabel,
  kDeleteBackUpNow,
  kDeleteChooseSemantics,
  kDeleteLevel1Title,
  kDeleteLevel1Nothing,
  kDeleteLevel2Title,
  kDeleteWordLabel,
  kDeleteWordHint,
  kDeleteButtonLevel1,
  kDeleteButtonLevel2,
  kDeleteCancel,
  kDeleteDone,
  kDeleteTryAgain,
  kDeleteButtonSemanticsHint,
  kDeleteStayBackups,
  kDeleteStayAutoList,
  kDeleteStaySms,
  kDeleteLevel1SafetyGone,
  kDeleteLevel1CategoriesStay,
  kDeleteLevel1Short,
  kDeleteLevel2Short,
  kDeleteExtraLevel1,
  kDeleteExtraLevel2,
  kDeleteExtraBackups,
  kDeleteLevel2BackupsForget,
  kDeleteCountsPrefix,
  kDeleteCountsUnknown,
  kDeleteConfirmTitle,
  kDeleteConfirmBody,
  kDeleteConfirmButton,
  kDeleteBusyLevel1,
  kDeleteBusyLevel2,
  kDeleteDoneTitle,
  kDeleteNothingDeletedTitle,
  kDeleteNothingDeletedBody,
  kDeleteLevel2NotFinishedExtra,
  kDeleteResetDoneReopen,
  kDeleteStartupNotice,
];
