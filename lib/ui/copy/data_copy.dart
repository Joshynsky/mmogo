/// B13 — the single source for the 0.1.1 data-safety wording (backup warning,
/// cloud-sync notice, network disclosure, feedback hint, why Restore asks,
/// phone-to-phone note). Widgets use these constants; none of them re-types the
/// sentences. The text is the PM-approved wording from the signed-off prototype
/// (`ui-surfaces.md` 0.1.1 inventory, W1, W2, W4, W6, W7, XFER).
///
/// Never write "nothing is sent anywhere" or "no permissions" anywhere in the
/// app: the update check uses the internet (criteria 31 to 35).
library;

/// W1: shown before the share sheet, in the auto-backup setup, and on the
/// Privacy page.
const kBackupFileWarning =
    'This backup is not encrypted. It contains your transactions, including names and phone numbers. '
    'Anyone who gets the file can read it. Keep it somewhere private.';

/// W2: shown once each time a backup folder is picked, before it is saved, and
/// on the Privacy page.
const kCloudSyncNotice =
    'If this folder is synced to a cloud service such as Google Drive, OneDrive or Dropbox, your backup files, '
    'with their names and phone numbers, will be copied there too. '
    'Choose a folder that is not synced if you do not want that.';

/// How often the update check runs (Lead ruling: measured from the last
/// successful check; a failed or offline attempt does not use up the week).
const kUpdateCheckCadence = 'mmogo checks when you open the app, and at most once a week after a successful check.';

/// W7 plus the cadence: what leaves the phone (Privacy page, What's new,
/// Settings).
const kNetworkDisclosure =
    'The internet is used only to check for updates. GitHub sees your IP address and that the request comes '
    'from the mmogo app. No entries, names or messages are sent. $kUpdateCheckCadence';

/// W6: under the Send feedback row.
const kFeedbackHint = 'Do not paste M-Pesa messages, names or phone numbers into a public issue.';

/// W4 (a and b): the merge-or-replace dialog's explanation of why Restore asks.
const kWhyRestoreAsks =
    'Merge adds what is missing and skips entries already on this phone (matched by M-Pesa code). '
    "Replace erases everything on this phone first and puts the file's data in. "
    'Use Merge unless you want this phone to match the file exactly. '
    'On a new phone both give the same result. '
    'On a phone that already has entries, only you know which you want.';

/// XFER (amendment 8): the backup file is the only route to a new phone.
const kPhoneTransferNotice =
    "Android's phone-to-phone transfer will not carry mmogo data. "
    'A backup file is the only way to move to a new phone.';

/// W3: why a backup matters (Backup page header, What's-new, Privacy page).
const kUninstallErasesNotice =
    'Uninstalling mmogo erases your data from this phone. Only a backup you saved can bring it back.';

// --- B17: the Restore flow (prototype wording, `ui-surfaces.md` W4, W5) -------

/// The button on the Backup page.
const kRestoreButtonLabel = 'Restore from a file';

/// One-line explanation under the Restore button.
const kRestoreIntro = 'Pick a mmogo backup file. Nothing changes until you choose how to restore it.';

/// Modal progress labels.
const kRestoreCheckingFile = 'Checking file...';
const kRestoreRestoring = 'Restoring...';
const kRestoreReplacing = 'Saving a safety copy, then replacing...';
const kRestoreUndoing = 'Undoing...';

/// Rejection dialog (plain reason, then "Nothing was changed.").
const kRestoreRejectTitle = "This file can't be restored";
const kRestoreNothingChanged = 'Nothing was changed.';
const kRejectNotMmogo = 'This is not a mmogo backup.';
const kRejectNewer = 'This backup was made by a newer version of mmogo. Update the app first.';
const kRejectDamaged = 'This file is damaged or incomplete.';
const kRejectTooLarge = 'This file is too large to be a backup.';
const kRejectInvalidEntry = 'This backup has an invalid entry';

/// Every restore failure shows this one message (PM wording; B15/B16 ruling f).
const kRestoreFailedTitle = 'Could not restore';
const kRestoreFailedMessage = 'Could not restore. Nothing was changed.';

/// Replace is refused when the safety copy could not hold every entry.
const kReplaceNeedsCompleteCopy =
    'Replace needs a complete safety copy and some entries cannot be saved in it. Use Merge instead.';

/// Merge-or-replace dialog.
const kMergeDialogTitle = 'Restore from this backup?';
const kMergeOptionTitle = 'Merge';
const kMergeOptionHelp = 'Keep what is here and add what is missing.';
const kReplaceOptionTitle = 'Replace';
const kReplaceOptionHelp = "Wipe this phone first, then put the file's data in.";
const kBackupHasNoEntries = 'This backup has no entries.';

/// Replace confirmation.
const kReplaceConfirmTitle = 'Replace everything on this phone?';
const kReplaceConfirmButton = 'Replace everything';
const kReplaceEmptyFileNote =
    'This backup has no entries. Replacing with it will leave this phone with no transactions at all.';

/// Replace confirmation: why Undo is not exact (B15/B16 ruling b).
const kUndoNotExactNotice =
    'Undo is not exact. Recently deleted entries are gone for good. '
    'Entries you add after Replacing are lost if you Undo. '
    'A setting that was not set before keeps the value Replace gave it.';

/// W5.
String replaceRemovesLine(int transactions, int classifications, int receivers) =>
    'Replace will remove ${_n(transactions, 'transaction', 'transactions')}, '
    '${_n(classifications, 'classification', 'classifications')} and '
    '${_n(receivers, 'saved receiver', 'saved receivers')} from this phone, '
    "including recently deleted ones, and put the file's data in. "
    'A safety copy of the current data is saved first so you can undo.';

String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Result sheet.
const kResultMergedTitle = 'Merged from the backup';
const kResultReplacedTitle = 'Replaced from the backup';
const kResultUndoneTitle = 'Previous data restored';
const kResultMergeNote =
    'Skipped entries were already on this phone (matched by M-Pesa code). Nothing here was changed or deleted.';
const kResultReplaceNote = 'Everything on this phone now matches the file.';
const kResultSafetyCopyNote = 'A safety copy of what was on this phone is kept in the app, so you can undo.';
const kResultUndoneNote = 'The data from before the replace is back. Entries added after the replace were not kept.';
const kSettingsNotApplied = 'Restored, but some settings could not be applied.';

/// Auto-backup card (B21), wording from the signed-off prototype.
const kAutoBackupPausedSubtitle = 'Auto-backup is paused. Choose a folder again to resume.';
const kAutoBackupOffSubtitle =
    'Off. mmogo can save a backup file to a folder you choose, after every N saved entries.';
const kAutoBackupOnNoFolderSubtitle = 'On. Choose a folder to start.';
const kAutoBackupPausedBannerTitle = 'Auto-backup is paused.';
const kAutoBackupPausedBannerBody =
    ' mmogo can no longer use the folder you picked. Choose a folder again to resume.';
const kAutoBackupNoFolderBanner = 'No folder yet. Choose where the backup files go and auto-backup starts.';
const kAutoBackupFailedBanner = 'Last auto-backup failed. It will try again after your next saved entry.';
const kAutoBackupPausedStatus = 'No automatic retry while paused.';
const kAutoBackupFolderHint =
    'On Android 11 and later, top-level folders such as Downloads are refused. '
    'Pick or create a subfolder, for example Documents / mmogo-backups.';
const kAutoBackupSetupTitle = 'Set up auto-backup';
const kCloudSyncTitle = 'Is this folder synced?';

String autoBackupOnSubtitle(int n) => 'On. A new file after every $n saved ${n == 1 ? 'entry' : 'entries'}.';
String autoBackupSetupIntro(int n, int k) =>
    'mmogo will save a backup file to a folder you choose, after every $n saved '
    '${n == 1 ? 'entry' : 'entries'}, and keep the newest $k.';
String autoBackupIsOnToast(int n) =>
    'Auto-backup is on. The first backup is made after $n saved ${n == 1 ? 'entry' : 'entries'}.';
