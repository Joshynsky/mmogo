/// B32/B33: wording for the Privacy and your data page, its two link rows, and
/// the Send feedback row. The fixed sentences (W1, W2, W3, W7, XFER, W6) come
/// from `data_copy.dart`; nothing here re-types them.
///
/// Never write "nothing is sent anywhere" or "no permissions" (the update check
/// uses the internet).
library;

import 'data_copy.dart';

const kPrivacyTitle = 'Privacy and your data';

/// Settings "Privacy and security" group.
const kSettingsPrivacyGroup = 'Privacy and security';
const kSettingsPrivacySubtitle = 'What is stored here and what leaves your phone';

/// Link row on the Backup page.
const kBackupPrivacyRowSubtitle = 'What is stored here and what leaves your phone';

/// Link row on the Privacy page.
const kPrivacyBackupRowTitle = 'Backup and restore';
const kPrivacyBackupRowSubtitle = 'Back up now, restore, and auto-backup';

const kPrivacyStoredTitle = 'What is stored on this phone';
const kPrivacyStoredBody =
    'Your transactions, your classifications, the receivers mmogo has learned, and your settings. '
    "All of it stays on this phone. Android's own backup is switched off for mmogo, "
    'so Android does not copy your data to Google.';

const kPrivacyLeavesTitle = 'What leaves the phone';
const kPrivacyLeavesBody =
    'That is the only thing mmogo sends. Nothing about your money or messages leaves your phone. '
    'You can turn the update check off on the Updates page, and then mmogo makes no request at all.';

const kPrivacyBackupFilesTitle = 'Backup files';
const kPrivacyBackupFilesBody =
    'A backup is a file saved on your phone. You choose where it goes; mmogo does not upload it anywhere.';

const kPrivacyCloudTitle = 'Folders that sync to the cloud';

/// Settings "Updates and feedback": Send feedback row (B33).
const kSendFeedbackLabel = 'Send feedback';
const kSendFeedbackSubtitle = 'Opens the mmogo issues page on GitHub in your browser. $kFeedbackHint';
const kSendFeedbackCouldNotOpen = 'Could not open the browser.';
