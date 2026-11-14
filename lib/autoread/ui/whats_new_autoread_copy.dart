/// The auto-read build's words on the What's-new page (0.1.2 A5a): its banner,
/// its intro and its Privacy item (0.1.3: the six items are the standard
/// build's, so the Auto-read and Notifications items are gone).
/// The page reaches this file only inside `if (kAutoReadCompiled)`.
///
/// Wording follows the signed mock `_pipeline/ui-rework/whats-new-page.html`
/// (its COPY object) and the partner's file of 20-10-2026.
library;

import '../../ui/copy/privacy_copy.dart' show kPrivacySentenceAutoRead;
import 'privacy_autoread_copy.dart' show kPrivacyAutoRecordedTrail, kPrivacyKeptNotShown;

const kWhatsNewAutoBannerHead = 'This is the auto-read version of mmogo';
const kWhatsNewAutoBannerBody =
    'It reads your M\u2011Pesa messages and puts them on a waiting list for you to categorize and review. '
    'If you do not want SMS permission, the standard version works without it.';

/// The intro: the same as the standard build's (kWhatsNewIntro), so there is no second copy here.

// New in 0.2.0, this build only (SIGNED PM 14-11-2026). The sentences taken from the
// 13-11 signed list are marked.
const kWhatsNewTodoTitle = 'To do page';
const kWhatsNewTodoSummary = 'Notifications now has one To do page.';
const kWhatsNewTodoBody =
    'Notifications now has one To do page with five lists: To parse, Could not read, To categorize, '
    'Recorded by you and Recorded automatically.';
const kWhatsNewTodoDescribes = 'Messages waiting for you now say what they are, for example Sent Ksh 200 to Wanjiru.';

const kWhatsNewUnreadTitle = 'Messages mmogo cannot read';
const kWhatsNewUnreadSummary = 'You now see its code, amount and time.';
const kWhatsNewUnreadBody =
    'If mmogo cannot read a message, it shows its code, amount and time in the app so you can paste it yourself.';

const kWhatsNewTrailTitle = 'Recorded automatically';
const kWhatsNewTrailSummary = 'The list now stays for 24 hours.';
const kWhatsNewTrailBody = 'The Recorded automatically list now stays for 24 hours, so you can see what mmogo recorded for you and undo it.';

const kWhatsNewAutoSettingsTitle = 'Auto-record in Settings';
const kWhatsNewAutoSettingsSummary = 'The airtime switches moved to Settings, under Remembered.';
const kWhatsNewAutoSettingsBody =
    'The Auto-record airtime switches are now in Settings, under Remembered. '
    'Each automatic record can be undone. You do not need to tap Categorize.';
const kWhatsNewAutoDefaults =
    'Your existing choices for showing details and Parse from the notification are not changed.';

/// The Privacy item of this build: every sentence is SIGNED (13-11-2026) and comes from its one
/// place; the first line is the permissions line.
const kWhatsNewPrivacyAutoReadSummary =
    'This version asks for SMS and notification permission. Your messages stay on this phone.';
const kWhatsNewPrivacyAutoReadBody = kPrivacySentenceAutoRead;

/// Last paragraphs of the Privacy item in this build, signed sentences only.
const kWhatsNewPrivacyAutoReadTrail = kPrivacyAutoRecordedTrail;
const kWhatsNewPrivacyAutoReadKept = kPrivacyKeptNotShown;

/// The last paragraph of the Privacy item in this build (WN-0.1.3 item 6).
const kWhatsNewPrivacyAutoReadReceiverNote =
    'The Privacy page now says exactly what is kept for your version, including the receiver details above. '
    "A message waiting to be categorized also holds the receiver's name and number until you categorize or remove it.";
