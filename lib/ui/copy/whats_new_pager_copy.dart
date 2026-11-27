/// 0.1.2 A5a (WN1, PK2, CW2): the What's-new page's words (the page replaced the
/// six-card sheet). 0.2.2: every item text is the PM-signed draft
/// `_pipeline/v0.2.2/WHATS-NEW-0.2.2-WORDING-DRAFT-2026-11-26.md` (signed 26-11-2026, with the PM's
/// answers: the standard build's Backups item keeps only the restore-direction lines). The fixed
/// sentences come from their one source constant and are never retyped here. This file holds the
/// standard build's words and the words shared by both builds; the other build's own words are in
/// `lib/autoread/ui/whats_new_autoread_copy.dart`. The 0.2.2 page lists only 0.2.2 items.
library;

import 'data_copy.dart';
import 'privacy_copy.dart';

/// The version the page is about. A FIXED constant (not `AppInfo`): the page's
/// title and the Updates entry say 0.2.2 (PM 31-10-2026: they must match the build).
// WORDING-SIGNED (0.2.2, PM 26-11-2026)
const kWhatsNewPagerVersion = '0.2.2';

/// The tag on each item.
// WORDING-SIGNED (0.2.2, PM 26-11-2026)
const kWhatsNewTagNew = 'New in 0.2.2';

const kWhatsNewPagerTitle = "What's new in mmogo $kWhatsNewPagerVersion";

/// The Updates entry (a synthetic card, not a stored notice). The other build adds
/// `kWhatsNewAutoEntryExtra` (see `whatsNewEntryBody()`).
// WORDING-SIGNED (0.2.2, PM 26-11-2026)
const kWhatsNewEntryBody = "Black, search in Settings, a regrouped Settings, and backups that keep people's settings.";

/// PLACEHOLDER (not the mock's "See what's new": that label opens the browser
/// for release notices, see the Updates footnote).
const kWhatsNewEntryButton = "Read what's new";

/// The line under the title.
// WORDING-SIGNED (0.2.2, PM 26-11-2026)
const kWhatsNewIntro = 'Tap one to read it.';

// The fold and the line above Privacy.
// WORDING-SIGNED (0.2.2, PM 26-11-2026)
const kWhatsNewStill = 'Everything from 0.2.1 is still here.';
const kWhatsNewMoreLabel = 'More changes';
const kWhatsNewMoreShow = 'Show more changes';
const kWhatsNewMoreHide = 'Hide more changes';
const kWhatsNewOpenInSettings = 'Open in Settings';

/// The banner at the very top of the standard build's page; its link opens the install guide.
// WORDING-SIGNED (0.2.2, PM 26-11-2026)
const kWhatsNewBannerHead = 'This is the standard version of mmogo';
const kWhatsNewBannerBody =
    'There is a second version that reads your M\u2011Pesa messages for you. '
    'It asks for SMS permission, so Google Play Protect may block it when you install it. '
    'The guide shows how to get past that. It is separate and optional.';
const kWhatsNewBannerLink = 'Read the install guide';

// Items shown in both builds. The words only the other build shows are in
// `lib/autoread/ui/whats_new_autoread_copy.dart`.
// WORDING-SIGNED (0.2.2, PM 26-11-2026)

// 1. Black
const kWhatsNewBlackTitle = 'New black theme';
const kWhatsNewBlackSummary = 'Appearance now has a Black choice.';
const kWhatsNewBlackBody =
    'Appearance now has four choices: System, Light, Dark and Black. '
    'Black is Dark on a true black page. System follows your phone and never gives Black.';

// 2. Search in Settings
const kWhatsNewSearchTitle = 'Search in Settings';
const kWhatsNewSearchSummary = 'Find a setting by typing.';
const kWhatsNewSearchBody =
    'Tap the magnifier at the top right of Settings. Type, or tap a suggestion. '
    'Tap a result and Settings scrolls to that row and highlights it.';

// 3. Settings is regrouped. The draft's body names Reading messages and Auto-record, which only the other
// build has; the standard build never names that version here, so its line lists only its own groups.
const kWhatsNewRegroupTitle = 'Settings is regrouped';
const kWhatsNewRegroupSummary = 'Settings is sorted into clearer groups.';
const kWhatsNewRegroupBody = 'The order is now Look, Adding entries, Your data and About.';

// 4. Backups. The direction lines are constants in data_copy.dart; the PM dropped the
// people's-settings sentence for the standard build (it has no people's settings).
const kWhatsNewBackupsTitle = 'Backups';
const kWhatsNewBackupsSummary = kBackupNotRestorableByOlderV6;
const kWhatsNewBackupsBody = '$kBackupOlderStillRestoreV6 $kBackupNotRestorableByOlderV6';

// 5. Ocean
const kWhatsNewOceanTitle = 'Ocean looks clearer';
const kWhatsNewOceanSummary = 'The Ocean look is refreshed.';
const kWhatsNewOceanBody =
    'In Ocean, the Add button is sun yellow, Send Money is blue so it no longer looks like a button, '
    'empty bars and switches are easier to see, and the dark teal is calmer. Leaf and Indigo are unchanged.';

// More changes (fold, both builds). The titles are short labels for the closed rows.
const kWhatsNewHomeTitle = 'Home';
const kWhatsNewHomeSummary =
    '"Cash withdrawn, not counted" shows only the part you have not yet linked to a Cash entry, and hides when nothing is left.';
const kWhatsNewHomeBody =
    '"Cash withdrawn, not counted" shows only the part you have not yet linked to a Cash entry, '
    'and hides when nothing is left. Entries made in the same minute stay in the order they happened.';

const kWhatsNewSameNameTitle = 'Same name, two people';
const kWhatsNewSameNameBody = 'Two people with the same name are told apart by their phone number, shown like 0722***555.';

const kWhatsNewNotNowTitle = 'Not now and Back';
const kWhatsNewNotNowBody = '"Not now" replaces "Categorize later" and "Later". Android Back closes the keyboard first.';

const kWhatsNewReceiverTitle = 'Record receiver details';
const kWhatsNewReceiverBody =
    'Record receiver details: switching it off now hides the people mmogo remembers instead of erasing them. '
    'Forget all and Delete data still erase them.';

// The closing item: the signed sentence is never retyped; the second paragraph is the signed rules line.
const kWhatsNewCard5Title = 'Privacy';

/// The closed line and the first, bold paragraph: the signed sentence.
const kWhatsNewCard5Summary = kPrivacySentenceStandard;
const kWhatsNewCard5Body = kPrivacySentenceStandard;

/// The second paragraph of the Privacy item, in both builds (unchanged from 0.2.1).
const kWhatsNewPrivacyRules = 'The rules you set for each person stay on this phone. They are in your backups, so keep your backup files private. mmogo never sends them anywhere.';
