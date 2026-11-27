/// The auto-read build's words on the What's-new page (0.1.2 A5a): its banner, the
/// items only it shows, the lines it adds to shared items and its Privacy item.
/// The page reaches this file only inside `if (kAutoReadCompiled)`.
///
/// 0.2.2: every text is the PM-signed draft
/// `_pipeline/v0.2.2/WHATS-NEW-0.2.2-WORDING-DRAFT-2026-11-26.md` (signed 26-11-2026). The intro
/// is the same as the standard build's (kWhatsNewIntro).
library;

// WORDING-SIGNED (0.2.2, PM 26-11-2026)
const kWhatsNewAutoBannerHead = 'This is the auto-read version of mmogo';
const kWhatsNewAutoBannerBody =
    'It reads your M\u2011Pesa messages and puts them on a waiting list for you to categorize and review. '
    'If you do not want SMS permission, the standard version works without it. '
    'If your phone blocked the install, the install guide shows how.';
const kWhatsNewAutoBannerLink = 'Open the install guide';

/// Added to the Updates entry text in this build.
const kWhatsNewAutoEntryExtra = 'Auto-record for people you choose.';

/// Item 4 in this build: its own title, closed line and first paragraphs (the people's settings are
/// here), then the shared direction lines, then the Keep it? paragraph.
const kWhatsNewAutoBackupsTitle = "Backups keep people's settings";
const kWhatsNewAutoBackupsSummary = "A new backup holds each person's settings.";
const kWhatsNewAutoBackupsIntro = "A backup now holds each person's level, limit and category suggestions.";
const kWhatsNewAutoBackupsOlder = "Backups from 0.2.1 and earlier still restore, without people's settings.";
const kWhatsNewAutoBackupsKeepIt =
    'After a restore, anyone who was on Auto-record waits under one banner, "Keep it?", '
    'with Keep and Turn off. Until you choose, they ask first.';

/// Item 3 in this build: the draft's full body (the standard build's body lists only its own groups).
const kWhatsNewAutoRegroupBody =
    'The order is now Look, Adding entries, Reading messages, Auto-record, Your data and About. '
    'Reading messages and Auto-record only appear in the auto-read version. '
    'The Settings tour has a step for Auto-record in that version.';

// 7. Auto-record
const kWhatsNewAutoRecordTitle = 'Auto-record';
const kWhatsNewAutoRecordSummary = 'mmogo can record for people you trust, without asking.';
const kWhatsNewAutoRecordBody = [
  'For a person you choose, mmogo can record their payments without asking. '
      'It covers Send Money, Buy Goods, airtime and Pochi. '
      'Each person\'s level is Suggested, Ask first or Auto-record. '
      'For Auto-record you can set a limit: payments up to it are recorded, anything above is asked first. '
      'Paybill always asks first.',
  'You get a pop-up when a message arrives. The entry is added the next time you open mmogo.',
  'Entries recorded this way show under Recently recorded with an Auto-record tag. '
      'Undo takes the entry back and keeps the person on Auto-record. To stop it, change their level or pause.',
];

// 8. Pause all Auto-record
const kWhatsNewPauseTitle = 'Pause all Auto-record';
const kWhatsNewPauseSummary = 'One switch asks first for everyone.';
const kWhatsNewPauseBody =
    'Pause asks first for everyone until you resume. While it is on, a notice stays on your phone with a '
    'Resume button, and the To do page says so. Your settings are kept.';

// 9. Suggested categories (replaces the 0.2.1 line that said it did not suggest yet)
const kWhatsNewSuggestTitle = 'Suggested categories';
const kWhatsNewSuggestSummary = 'mmogo suggests the categories you use for a person.';
const kWhatsNewSuggestBody =
    'For a person at Suggested, the waiting card and the Categorize sheet show up to two categories you used '
    'most for them in their last 10 payments. Tap one to record at once. An Undo message follows. '
    'Paybill, withdrawals and airtime are not suggested.';

// 10. Reset and Forget
const kWhatsNewResetTitle = 'Reset and Forget';
const kWhatsNewResetSummary = 'Start over for everyone, if you want.';
const kWhatsNewResetBody =
    'On the Remembered page you can reset everyone to Suggested, or forget all people. '
    'Both say what they will do first. Nothing already recorded changes.';

// More changes (fold, this build only)
const kWhatsNewTodoTitle = 'To do page';
const kWhatsNewTodoBody = 'Answers you owe come first. Messages mmogo could not read have their own heading.';

const kWhatsNewFixesTitle = 'Fixes';
const kWhatsNewFixesSummary = 'A queued alert disappears once its entry is recorded.';
const kWhatsNewFixesBody =
    'A queued alert disappears once its entry is recorded; a message that arrives while mmogo is open shows up '
    'without reopening; the Ask first card leaves after you tap it. '
    'Large text no longer breaks mid-word at 200%.';

/// The Privacy item of this build: the closed line and the bold first paragraph are the
/// signed permissions line (13-11-2026); the second paragraph is the shared kWhatsNewPrivacyRules.
const kWhatsNewPrivacyAutoReadSummary = 'This version asks for SMS and notification permission. Your messages stay on this phone.';
const kWhatsNewPrivacyAutoReadBody = kWhatsNewPrivacyAutoReadSummary;
