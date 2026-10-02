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
