/// The auto-read build's words on the What's-new page (0.1.2 A5a): its banner, the
/// items only it shows, the lines it adds to shared items and its Privacy item.
/// The page reaches this file only inside `if (kAutoReadCompiled)`.
///
/// 0.2.1: every text follows the PM-signed mock
/// `_pipeline/v0.2.1/mock-whats-new-0.2.1/index.html` (ITEMS marked `autoOnly`, `auto`, `autoBody`),
/// signed 20-11-2026. The intro is the same as the standard build's (kWhatsNewIntro).
library;

const kWhatsNewAutoBannerHead = 'This is the auto-read version of mmogo';
const kWhatsNewAutoBannerBody =
    'It reads your M\u2011Pesa messages and puts them on a waiting list for you to categorize and review. '
    'If you do not want SMS permission, the standard version works without it.';

// WORDING-DRAFT (0.2.1, signed mock 20-11-2026)

/// Added after the shared Withdrawals paragraphs in this build.
const kWhatsNewAutoWithdrawalsExtra =
    'In this version, mmogo also asks about your earlier withdrawals. They wait on the Notifications page as one item, '
    'for example "3 withdrawals need a decision". For each one, choose Cash only or Categorize.';

/// Added after the shared Suggested categories paragraphs, before the last one.
const kWhatsNewAutoSuggestBody = [
  'For each person you choose a level: Suggested or Ask first.',
  'A third level, Auto-record, where mmogo records without asking for people you choose, is planned for the next update. '
      'It is not in this one.',
];

// Ask first (this build only)
const kWhatsNewAskTitle = 'Ask first';
const kWhatsNewAskSummary = 'mmogo reads a message from a person you choose and asks before it records.';
const kWhatsNewAskBody = [
  'For a person you set to Ask first, mmogo reads their message by itself when it arrives. '
      'It shows one alert: "Record as Groceries?" with Not now, Change category and Yes.',
  'A tap always decides. Nothing is recorded without a tap.',
  'If you tap Yes while mmogo is closed, the alert says it is queued. '
      'The entry is added when you next open mmogo, even after a phone restart.',
  'Change category opens the Categorize sheet for that entry, even from another app.',
  'People set to Ask first do not need the Tap to parse step.',
];

// Notifications page (this build only). The line is the 20-11-2026 correction (four lists).
const kWhatsNewNotifTitle = 'Notifications page';
const kWhatsNewNotifSummary = 'Messages waiting for you are in lists, with a count on the bell.';
const kWhatsNewNotifBody =
    'The Notifications page groups what needs you into lists: To confirm, To parse, To categorize and Could not read. '
    'The bell shows how many are waiting.';

// Hide details after (this build only)
const kWhatsNewHideTitle = 'Hide details after';
const kWhatsNewHideSummary = 'Choose how long an alert shows the message details.';
const kWhatsNewHideBody = [
  'In Settings, under Reading, "Hide details after" sets how long an alert shows the message details: '
      'Never, 5 minutes, 15 minutes, 30 minutes or 1 hour.',
  'Only the alert goes away. The message stays for 24 hours.',
];

// Recorded automatically filter (this build only)
const kWhatsNewRecordedTitle = 'Recorded automatically filter';
const kWhatsNewRecordedSummary = 'A filter for entries mmogo recorded for you.';
const kWhatsNewRecordedBody = 'A "Recorded automatically" filter now covers entries from 0.2.1 onward.';

/// The Privacy item of this build: the closed line and the bold first paragraph are the
/// signed permissions line (13-11-2026); the second paragraph is the shared kWhatsNewPrivacyRules.
const kWhatsNewPrivacyAutoReadSummary =
    'This version asks for SMS and notification permission. Your messages stay on this phone.';
const kWhatsNewPrivacyAutoReadBody = kWhatsNewPrivacyAutoReadSummary;
