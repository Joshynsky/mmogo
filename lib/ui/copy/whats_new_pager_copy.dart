/// 0.1.2 A5a (WN1, PK2, CW2): the What's-new page's words (the page replaced the
/// six-card sheet). The item texts follow the signed mock
/// `_pipeline/ui-rework/whats-new-page.html` (its COPY object), the partner's
/// wording file of 20-10-2026 and the signed sentences of `pages/wording.html`;
/// the fixed sentences come from their one source constant and are never
/// retyped here. This file holds the standard build's words only; the other
/// build's own words are in `lib/autoread/ui/whats_new_autoread_copy.dart`. PM
/// placeholders are listed in `s11a-deviations.md`.
library;

import 'data_copy.dart';
import 'privacy_copy.dart';

/// The version the page is about. A FIXED constant (not `AppInfo`): the page's
/// title and the Updates entry say 0.1.3 (PM 31-10-2026: they must match the
/// build). The six items below describe the 0.1.3 changes (wording signed by the
/// PM 01-11-2026, `_pipeline/v0.1.3/wording-drafts.md` WN-0.1.3).
const kWhatsNewPagerVersion = '0.1.3';

const kWhatsNewPagerTitle = "What's new in mmogo $kWhatsNewPagerVersion";

/// The Updates entry (a synthetic card, not a stored notice).
const kWhatsNewEntryBody =
    'The bottom bar, airtime on Paid to, receiver details, Recently deleted, exports and privacy.';

/// PLACEHOLDER (not the mock's "See what's new": that label opens the browser
/// for release notices, see the Updates footnote).
const kWhatsNewEntryButton = "Read what's new";

/// The line under the title (standard build: six items).
const kWhatsNewIntro = 'Six small things changed. Tap one to read it. Tap Got it when you are done.';

/// The banner at the very top of the standard build's page. It never uses the
/// words of the other version's name: it only says what the second version
/// does.
const kWhatsNewBannerHead = 'This is the standard version of mmogo';
const kWhatsNewBannerBody =
    'There is a second version that can read and parse your M\u2011Pesa messages for you. '
    'It puts them on a waiting list for you to categorize and review. '
    'It asks for SMS permission, so it is separate and optional.';
const kWhatsNewBannerLink = 'Open the mmogo page';

// Item 1 (NAV)
const kWhatsNewNavTitle = 'Navigation bar';
const kWhatsNewNavSummary = "The bottom bar no longer hides behind your phone's buttons.";
const kWhatsNewNavBody =
    'On phones with the three buttons at the bottom, the Home, Analytics, Paid to and Profile tabs were covered. '
    'They now sit above the buttons.';

// Item 2 (F3)
const kWhatsNewAirtimeTitle = 'Airtime on Paid to';
const kWhatsNewAirtimeSummary = 'Paid to now counts airtime.';
const kWhatsNewAirtimeBody =
    'Paid out on Paid to now matches This month on Home. '
    'Airtime shows as one line at the end of the overview: how many purchases and how much. '
    'It is hidden while you search or filter by category.';

// Item 3 (F6): has the Change in Settings button.
const kWhatsNewReceiverTitle = 'Receiver details';
const kWhatsNewReceiverSummary = 'You choose whether receiver names and numbers are kept.';
const kWhatsNewReceiverBody =
    'In Settings, Record receiver details is on or off. '
    "When it is off, new entries are saved without the receiver's name or number. "
    'Entries you already saved are not changed.';
const kWhatsNewChangeInSettings = 'Change in Settings';

// Item 4 (F2)
const kWhatsNewDeletedTitle = 'Recently deleted';
const kWhatsNewDeletedSummary = 'Recently deleted says how long you can restore.';
const kWhatsNewDeletedBody =
    "You can restore a deleted entry for 1 hour. The 'coming soon' web page row is gone.";

// Item 5 (SEC-03)
const kWhatsNewExportsTitle = 'Exports';
const kWhatsNewExportsSummary = 'Exports no longer leave copies behind.';
const kWhatsNewExportsBody =
    'After you share a CSV, the temporary copies mmogo made are removed. '
    'Delete data also removes any left over from an earlier version.';

// Item 6 (the closing item; PM-signed sentences, never retyped)
const kWhatsNewCard5Title = 'Privacy';
/// The closed line: the signed sentence without its parenthetical, derived (not retyped).
final kWhatsNewCard5Summary = kPrivacySentenceStandard.replaceFirst(' (switchable off)', '');

/// The signed canonical sentence (standard build), shown first and in bold.
const kWhatsNewCard5Body = kPrivacySentenceStandard;

/// R14 (F4): the canonical sentence already says the internet is used only to
/// check for updates, so only the second half of W7 follows it.
const kWhatsNewCard5Network = kNetworkSeenSentence;

/// The last paragraph of the Privacy item (WN-0.1.3 item 6).
const kWhatsNewCard5Receiver =
    'The Privacy page now says exactly what is kept for your version, including the receiver details above.';
