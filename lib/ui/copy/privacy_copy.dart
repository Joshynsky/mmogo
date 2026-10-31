/// B32/B33: wording for the Privacy and your data page, its two link rows, and
/// the Send feedback row. The fixed sentences (W1, W2, W3, W7, XFER, W6) come
/// from `data_copy.dart`; nothing here re-types them.
///
/// Never write "nothing is sent anywhere" or "no permissions" alone (the update
/// check uses the internet). The one allowed form is [kPrivacySentenceStandard].
library;

import 'data_copy.dart';
import 'settings_copy.dart' show kCaptureReceiverLabel;

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
    'Your transactions, your categories, the receivers mmogo has learned, and your settings. '
    "All of it stays on this phone. Android's own backup is switched off for mmogo, "
    'so Android does not copy your data to Google.';

/// C-B12 / SEC-02 (PM yes 29-10-2026): receiver details are stored only with the
/// "Record receiver details" switch on; in the auto-read build a waiting message holds them too.
/// The switch name comes from [kCaptureReceiverLabel], so this page cannot drift from Settings.
const kPrivacyStoredReceiverDetails =
    'Receiver names and phone numbers are kept on saved entries only when "$kCaptureReceiverLabel" is on. '
    "In the auto-read version, a message waiting to be categorized also holds the receiver's name and number until you categorize or remove it.";

/// The standard build has no waiting list, so its Privacy page says nothing about the auto-read
/// version (PM 31-10-2026: the standard app must not name a feature it does not have).
const kPrivacyStoredReceiverDetailsStandard =
    'Receiver names and phone numbers are kept on saved entries only when "$kCaptureReceiverLabel" is on.';

/// C-B12, COPY AHEAD OF FEATURE: the agent number exists from slice S3 (AG1).
const kPrivacyStoredAgentNumber = "An agent number is kept beside the receiver's phone number.";

/// C-B12: remembered answers ship with 0.1.2 S8c-2 (no longer copy ahead of the feature).
const kPrivacyStoredRememberedAnswers =
    'The Send Money or Pochi answer mmogo remembers is kept only when the tick is on. '
    'It is not in backups and not shared.';

/// The sentences that are true only once a later slice ships (see
/// `_pipeline/v0.1.2/baseline/s1-deviations.md`); a test lists them.
const kPrivacyCopyAheadOfFeature = [kPrivacyStoredAgentNumber];

/// Canonical privacy line (Judge P5-8, E8 STANDARD build): exact, one constant.
const kPrivacySentenceStandard = 'No permissions except internet, used only to check for updates (switchable off).';

/// 0.1.3 F1: the Privacy page of the AUTO-READ build. That build also asks for
/// SMS and notification permission, so it must not show
/// [kPrivacySentenceStandard] (true only for the standard build).
const kPrivacySentenceAutoRead =
    'This version asks for internet, used only to check for updates (switchable off), '
    'and for SMS and notification permission, only if you switch reading on.';

/// 0.1.3 F1: the pair the README and the website say about both versions
/// (commit 34e792a, 27-10-2026). A test checks both files carry them word for word.
const kPrivacyPublicStandard = 'The standard version asks only for internet, used only to check for updates (switchable off).';
const kPrivacyPublicAutoRead = 'The auto-read version also asks for SMS and notification permission, only if you switch reading on.';

/// Independence line: the full sentence on the Privacy page (C-B10e), the short
/// form wherever the app prose describes the products.
const kIndependenceFull =
    'mmogo is an independent app. It is not made, approved or checked by Safaricom. '
    'Product names such as M\u2011Pesa, Paybill, Buy Goods and Pochi are used only to describe the messages it reads.';
const kIndependenceShort = 'mmogo is independent. Not made or approved by Safaricom.';

const kPrivacyLeavesTitle = 'What leaves the phone';
const kPrivacyLeavesBody =
    'That is the only thing mmogo sends. Nothing about your money or messages leaves your phone. '
    'You can turn the update check off on the Updates page, and then mmogo makes no automatic request.';

/// Visible outside any expander (Judge C-B10a/d).
const kPrivacyCheckNowOnce = 'Even with automatic checks off, Check for updates now goes online once when you tap it.';

const kPrivacyBackupFilesTitle = 'Backup files';
const kPrivacyBackupFilesBody =
    'A backup is a file saved on your phone. You choose where it goes; mmogo does not upload it anywhere.';

const kPrivacyCloudTitle = 'Folders that sync to the cloud';

/// Settings "Updates and feedback": Send feedback row (B33).
const kSendFeedbackLabel = 'Send feedback';
const kSendFeedbackSubtitle = 'Opens the mmogo issues page on GitHub in your browser. $kFeedbackHint';
const kSendFeedbackCouldNotOpen = 'Could not open the browser.';

/// 0.1.2 S11a (A6): the label of the collapsed detail that holds
/// `kNetworkDisclosure` and `kPrivacyLeavesBody`.
const kPrivacyLeavesToggle = 'What exactly leaves the phone';
