/// The auto-read build's words on the What's-new page (0.1.2 A5a): its banner,
/// its intro and its Privacy item (0.1.3: the six items are the standard
/// build's, so the Auto-read and Notifications items are gone).
/// The page reaches this file only inside `if (kAutoReadCompiled)`.
///
/// Wording follows the signed mock `_pipeline/ui-rework/whats-new-page.html`
/// (its COPY object) and the partner's file of 20-10-2026.
library;

const kWhatsNewAutoBannerHead = 'This is the auto-read version of mmogo';
const kWhatsNewAutoBannerBody =
    'It reads your M\u2011Pesa messages and puts them on a waiting list for you to categorize and review. '
    'If you do not want SMS permission, the standard version works without it.';

/// Six items, the same as the standard build (WN-0.1.3); only the Privacy item
/// and the banner say this build's own words.
const kWhatsNewAutoIntro = 'Six small things changed. Tap one to read it. Tap Got it when you are done.';

/// PROVISIONAL, awaiting the PM's signature. The signed sentence "No permissions
/// except internet" is true only in the standard build (this build asks for SMS
/// and notification permissions), so it must not be shown here. These two are
/// the page's stand-in until the PM signs a Privacy line for this build.
const kWhatsNewPrivacyAutoReadSummaryProvisional =
    'This version asks for SMS and notification permissions. Your messages stay on this phone.';
const kWhatsNewPrivacyAutoReadBodyProvisional =
    'This version asks for SMS and notification permissions so it can read your M\u2011Pesa messages. '
    'The internet is used only to check for updates (switchable off). Your messages stay on this phone.';

/// The last paragraph of the Privacy item in this build (WN-0.1.3 item 6).
const kWhatsNewPrivacyAutoReadReceiverNote =
    'The Privacy page now says exactly what is kept for your version, including the receiver details above. '
    "A message waiting to be categorized also holds the receiver's name and number until you categorize or remove it.";
