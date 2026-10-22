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

/// The version the page is about. A FIXED constant (not `AppInfo`): the app
/// version is bumped at the release step, but the page's title and the
/// Updates entry say 0.1.2 now.
const kWhatsNewPagerVersion = '0.1.2';

const kWhatsNewPagerTitle = "What's new in mmogo $kWhatsNewPagerVersion";

/// The Updates entry (a synthetic card, not a stored notice).
const kWhatsNewEntryBody =
    'Withdrawals, airtime and Pochi, weeks, same phone number as one person, backups and privacy.';

/// PLACEHOLDER (not the mock's "See what's new": that label opens the browser
/// for release notices, see the Updates footnote).
const kWhatsNewEntryButton = "Read what's new";

/// The line under the title (standard build: six items).
const kWhatsNewIntro = 'Six things changed. Tap one to read it. Tap Got it when you are done.';

/// The banner at the very top of the standard build's page. It never uses the
/// words of the other version's name: it only says what the second version
/// does.
const kWhatsNewBannerHead = 'This is the standard version of mmogo';
const kWhatsNewBannerBody =
    'There is a second version that can read and parse your M\u2011Pesa messages for you. '
    'It puts them on a waiting list for you to categorize and review. '
    'It asks for SMS permission, so it is separate and optional.';
const kWhatsNewBannerLink = 'Open the mmogo page';

// Item 1
const kWhatsNewCard1Title = 'Withdrawals, airtime and Pochi';
const kWhatsNewCard1Summary =
    'mmogo now understands these M\u2011Pesa messages. Withdrawals are not counted as spending.';

/// PLACEHOLDER for the PM: the mock's "Paid to and Analytics show how many" is
/// not confirmed for Analytics; the partner's wording names only Paid to.
const kWhatsNewCard1Body =
    'mmogo now understands these M\u2011Pesa messages. '
    'Paid to shows how many payments you made and what they cost.';
const kWhatsNewCard1Body2 =
    'A withdrawal is money out, but it is not money you spent, so it adds nothing to what you spent. '
    'Its transaction cost is still tracked. '
    'A withdrawal counts as spending only when you spend that cash and record it as a Cash entry. '
    'mmogo tracks spending.';

// Item 2
const kWhatsNewCard2Title = 'Weeks';
const kWhatsNewCard2Summary = 'A week now runs from the day you choose, Monday unless you change it.';
const kWhatsNewCard2Body =
    'Before, a week meant the last 7 days: today and the 6 days before it. '
    'That did not match the calendar, so we corrected it. '
    'A week now runs from the day you choose in Settings (Monday unless you change it). '
    'Past weekly figures are regrouped to match; nothing saved changes.';
const kWhatsNewChangeInSettings = 'Change in Settings';

// Item 3 (invented example name and numbers, as in the mock)
const kWhatsNewCard3Title = 'Same phone number = one person';
const kWhatsNewCard3Summary = 'The same number written two ways now counts as one person.';
const kWhatsNewCard3Body =
    'Earlier versions counted one number as two people when it was written two ways, for example '
    '0712 345 678 and +254 712 345 678 (07 and 01 numbers alike). '
    'We have corrected that: they now count as one person on Paid to, '
    'and their totals are added together. The numbers saved on your entries do not change.';
// R5 (F2): the signed wording, word for word.
const kWhatsNewCard3Extra =
    'A number written 07... or +254 7... is the same number, so it joins. '
    'The same goes for 01... and +254 1.... '
    'A 07 number and a 01 number are different numbers and stay separate.';
const kWhatsNewPicBefore = 'Before (0.1.1)';
const kWhatsNewPicNow = 'Now (0.1.2)';
const kWhatsNewPicBecomes = 'becomes';
const kWhatsNewPicLabel =
    'Before, version 0.1.1: 0712 345 678, Ksh 1,200, and +254 712 345 678, Ksh 300, as two people. '
    'Now, version 0.1.2: Jane Sample, Ksh 1,500, as one person.';

// Item 4
const kWhatsNewCard4Title = 'Backups';
const kWhatsNewCard4Summary = 'Backups from 0.1.1 still restore.';
const kWhatsNewCard4Body =
    'Backups from 0.1.1 still restore. $kBackupNotRestorableByOlder $kUninstallErasesNotice';

// Item 5 (PM 20-10-2026): the bell. It sits BEFORE Privacy so Privacy stays the closing item.
// Standard build: it says nothing about reading messages here (the banner at the top does).
const kWhatsNewCardNotificationsTitle = 'Notifications';
const kWhatsNewCardNotificationsSummary =
    'The bell now opens Notifications. Updates is now in Settings, under About.';
const kWhatsNewCardNotificationsBody =
    'The bell now opens Notifications. Updates and notices from mmogo appear there, '
    'and anything new shows on the bell. '
    'The Updates page, where you check for updates, is now in Settings, under About.';

// Item 6 (the closing item)
const kWhatsNewCard5Title = 'Privacy';
/// The closed line: the signed sentence without its parenthetical, derived (not retyped).
final kWhatsNewCard5Summary = kPrivacySentenceStandard.replaceFirst(' (switchable off)', '');

/// The signed canonical sentence (standard build), shown first and in bold.
const kWhatsNewCard5Body = kPrivacySentenceStandard;

/// R14 (F4): the canonical sentence already says the internet is used only to
/// check for updates, so only the second half of W7 follows it.
const kWhatsNewCard5Network = kNetworkSeenSentence;
