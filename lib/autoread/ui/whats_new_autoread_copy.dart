/// The auto-read build's words on the What's-new page (0.1.2 A5a): its banner,
/// its intro, its first item, its Notifications item and its Privacy item.
/// The page reaches this file only inside `if (kAutoReadCompiled)`.
///
/// Wording follows the signed mock `_pipeline/ui-rework/whats-new-page.html`
/// (its COPY object) and the partner's file of 20-10-2026. The held time comes
/// from `held_window.dart`; no hour count is typed here.
library;

import '../held_window.dart';

const kWhatsNewAutoBannerHead = 'This is the auto-read version of mmogo';
const kWhatsNewAutoBannerBody =
    'It reads your M\u2011Pesa messages and puts them on a waiting list for you to categorize and review. '
    'If you do not want SMS permission, the standard version works without it.';

const kWhatsNewAutoIntro = 'Seven things changed. Tap one to read it. Tap Got it when you are done.';

// The first item.
const kWhatsNewReadingTitle = 'Auto-read';
const kWhatsNewReadingSummary = 'mmogo reads your M\u2011Pesa messages as they arrive and puts them on a waiting list.';
const kWhatsNewReadingBody =
    'mmogo reads messages from M\u2011Pesa as they arrive and holds them on this phone. '
    'A notification tells you one is ready; it shows no amount and no name. '
    'In Notifications, you Parse a message, then Categorize it. '
    'Nothing counts in your totals until you categorize it. You can still paste messages as before.';

/// The hour count follows [kHeldWindow].
final String kWhatsNewReadingBody2 =
    'Reading is controlled in Settings, Reading messages, with the switch "Read M\u2011Pesa messages". '
    'It asks your consent first and only keeps messages from M\u2011Pesa. '
    // NEW, needs PM signature (one sentence: Parse from the notification starts on after Allow; off in Settings).
    'Parse from the notification starts on after you allow it, and you can turn it off in Settings. '
    'Turn it off at any time: new messages stop arriving. '
    'Messages already held stay until you delete them or they expire (kept up to ${kHeldWindow.inHours} hours).';

// The Notifications item: the waiting list lives on the bell page; nothing about another version.
const kWhatsNewAutoNotificationsSummary = 'The bell now opens Notifications, where your messages wait.';
const kWhatsNewAutoNotificationsBody =
    'The bell opens Notifications. Updates and notices appear there, and so do your M\u2011Pesa messages: '
    'To parse, then To categorize. Updates is in Settings, under About.';

/// PROVISIONAL, awaiting the PM's signature. The signed sentence "No permissions
/// except internet" is true only in the standard build (this build asks for SMS
/// and notification permissions), so it must not be shown here. These two are
/// the page's stand-in until the PM signs a Privacy line for this build.
const kWhatsNewPrivacyAutoReadSummaryProvisional =
    'This version asks for SMS and notification permissions. Your messages stay on this phone.';
const kWhatsNewPrivacyAutoReadBodyProvisional =
    'This version asks for SMS and notification permissions so it can read your M\u2011Pesa messages. '
    'The internet is used only to check for updates (switchable off). Your messages stay on this phone.';
