/// 0.1.2 A5a (WN1, PK2, CW2): the What's-new page's words (the page replaced the
/// six-card sheet). 0.2.1: every item text follows the PM-signed mock
/// `_pipeline/v0.2.1/mock-whats-new-0.2.1/index.html` (its COPY and ITEMS objects, signed
/// 20-11-2026); the fixed sentences come from their one source constant and are never
/// retyped here. This file holds the standard build's words and the words shared by both builds;
/// the other build's own words are in `lib/autoread/ui/whats_new_autoread_copy.dart`.
library;

import 'data_copy.dart';
import 'privacy_copy.dart';

/// The version the page is about. A FIXED constant (not `AppInfo`): the page's
/// title and the Updates entry say 0.2.1 (PM 31-10-2026: they must match the
/// build). The 0.2.1 page (PM-signed mock 20-11-2026) lists the items new in 0.2.1, a fold of
/// "more changes", and one line saying everything from 0.2.0 is still here; the 0.2.0 and 0.1.3
/// items are not listed again.
// WORDING-DRAFT (0.2.1, signed mock 20-11-2026)
const kWhatsNewPagerVersion = '0.2.1';

/// The tag on each item (signed mock 20-11-2026).
// WORDING-DRAFT (0.2.1, signed mock 20-11-2026)
const kWhatsNewTagNew = 'New in 0.2.1';

const kWhatsNewPagerTitle = "What's new in mmogo $kWhatsNewPagerVersion";

/// The Updates entry (a synthetic card, not a stored notice).
// WORDING-DRAFT (0.2.1, PM agreed 20-11-2026: only what 0.2.1 built)
const kWhatsNewEntryBody =
    'Withdrawals that log cash, a choice of account in Paid to, an Update button, and clearer messages.';

/// PLACEHOLDER (not the mock's "See what's new": that label opens the browser
/// for release notices, see the Updates footnote).
const kWhatsNewEntryButton = "Read what's new";

/// The line under the title (mock COPY.intro).
// WORDING-DRAFT (0.2.1, signed mock 20-11-2026)
// WORDING-DRAFT (0.2.1, PM 20-11-2026: true for both entry points, Back or Got it)
const kWhatsNewIntro = 'Tap one to read it.';

// The fold and the line above Privacy (mock COPY).
// WORDING-DRAFT (0.2.1, signed mock 20-11-2026)
const kWhatsNewStill = 'Everything from 0.2.0 is still here.';
const kWhatsNewMoreLabel = 'More changes';
const kWhatsNewMoreShow = 'Show more changes';
const kWhatsNewMoreHide = 'Hide more changes';
const kWhatsNewOpenInSettings = 'Open in Settings';

/// The banner at the very top of the standard build's page. It never uses the
/// words of the other version's name: it only says what the second version
/// does.
const kWhatsNewBannerHead = 'This is the standard version of mmogo';
const kWhatsNewBannerBody =
    'There is a second version that can read and parse your M\u2011Pesa messages for you. '
    'It puts them on a waiting list for you to categorize and review. '
    'It asks for SMS permission, so it is separate and optional.';
const kWhatsNewBannerLink = 'Open the mmogo page';

// Items shown in both builds (mock ITEMS). The words only the other build shows are in
// `lib/autoread/ui/whats_new_autoread_copy.dart`.
// WORDING-DRAFT (0.2.1, signed mock 20-11-2026)

// Withdrawals
const kWhatsNewWithdrawalsTitle = 'Withdrawals';
const kWhatsNewWithdrawalsSummary = 'A withdrawal is not counted as spending. You say what the cash was for.';
const kWhatsNewWithdrawalsBody = [
  'A cash withdrawal stays a withdrawal. It is not counted as spending.',
  'On a withdrawal, "What was this money for?" lets you pick a category. mmogo then adds a linked Cash entry under that category, '
      'with the same date as the withdrawal, and that entry counts as spent. "Cash only" is the default: nothing is added.',
  'You can split it: some spent, the rest stays cash. You can add several entries.',
  'If you delete the withdrawal, its Cash entries go with it. Recently deleted brings them all back within 1 hour.',
  'Home shows "Cash withdrawn (not counted)", and withdrawal fees are inside the transaction cost line.',
  'Withdrawals you saved before this update are not changed. Open one to say what the cash was for.',
];

// Suggested categories (has the Open in Settings button)
const kWhatsNewSuggestTitle = 'Suggested categories';
const kWhatsNewSuggestSummary = 'mmogo suggests the categories you use most for each person.';
const kWhatsNewSuggestBody = [
  'mmogo suggests the categories you used most in your last 5 records for that person.',
  'See and change them in Settings, under "Remembered recipients". '
      'Pick one type at a time: Send Money, Paybill, Buy Goods, Pochi, Withdrawals (muted) or Airtime.',
];
const kWhatsNewSuggestLast =
    'These rules stay on this phone and are not in backups. If you restore a backup with Replace, everyone goes back to Suggested.';

// Paid to: choose an account
const kWhatsNewPaidToTitle = 'Paid to: choose an account';
const kWhatsNewPaidToSummary = 'When one person has several accounts, you choose which one to look at.';
const kWhatsNewPaidToBody =
    'When one recipient has several accounts, you now choose which account to look at. '
    'This works when you pay directly, in loop views, and in Year and All time.';

// Backups (the first sentence is the one constant in data_copy.dart)
const kWhatsNewBackupsTitle = 'Backups';
const kWhatsNewBackupsSummary = kBackupNotRestorableByOlderV5;
const kWhatsNewBackupsBody = '$kBackupNotRestorableByOlderV5 Older backups still restore.';

// Pochi
const kWhatsNewPochiTitle = 'Pochi';
const kWhatsNewPochiSummary = 'When a Pochi message is read, you choose Pochi or Send Money.';
const kWhatsNewPochiBody = 'When mmogo reads a Pochi message, you choose whether it is Pochi or Send Money.';

// Updates
const kWhatsNewUpdatesTitle = 'Updates';
const kWhatsNewUpdatesSummary = 'Check for updates from Settings, under About.';
const kWhatsNewUpdatesBody =
    'In Settings, under About, Updates now has "Check for updates now". '
    'When a newer version exists, a filled Update button appears. '
    'The News row stays until you install it, then moves to Updates.';

// What's new links
const kWhatsNewLinksTitle = 'What’s new links to Settings';
const kWhatsNewLinksSummary = 'Items now open the Settings area they describe.';
const kWhatsNewLinksBody =
    'Items on this page now link to the Settings area they describe. Back returns you to the item you were reading.';

// Pop-up messages
const kWhatsNewPillTitle = 'Pop-up messages';
const kWhatsNewPillSummary = 'Messages like Undo now show at the top and follow your theme.';
const kWhatsNewPillBody =
    'Messages like Undo now show as a pill at the top of the screen. It follows your light or dark theme.';

// The closing item: the signed sentence is never retyped; the second paragraph is new in the mock.
const kWhatsNewCard5Title = 'Privacy';

/// The closed line and the first, bold paragraph: the signed sentence (mock: privacyStd).
const kWhatsNewCard5Summary = kPrivacySentenceStandard;
const kWhatsNewCard5Body = kPrivacySentenceStandard;

/// The second paragraph of the Privacy item, in both builds (mock: privacyRules).
const kWhatsNewPrivacyRules = 'The rules you set for each person stay on this phone. They are not in backups.';
