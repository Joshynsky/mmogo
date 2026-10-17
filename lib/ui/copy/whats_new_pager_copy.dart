/// 0.1.2 S11a (WN1, PK2, CW2): the What's-new pager's words. The card texts
/// follow the signed mock `_pipeline/ui-rework/pages/wording.html` (lines
/// 129-137); the fixed sentences come from their one source constant and are
/// never retyped here. PM placeholders are listed in `s11a-deviations.md`.
library;

import 'data_copy.dart';
import 'privacy_copy.dart';

/// The version the pager is about. A FIXED constant (not `AppInfo`): the app
/// version is bumped at the release step, but the pager's title and the
/// Updates entry say 0.1.2 now.
const kWhatsNewPagerVersion = '0.1.2';

const kWhatsNewPagerTitle = "What's new in mmogo $kWhatsNewPagerVersion";

/// The Updates entry (a synthetic card, not a stored notice).
const kWhatsNewEntryBody =
    'Withdrawals, airtime and Pochi, weeks, same phone number as one person, backups and privacy.';

/// PLACEHOLDER (not the mock's "See what's new": that label opens the browser
/// for release notices, see the Updates footnote).
const kWhatsNewEntryButton = "Read what's new";

const kWhatsNewCardCount = 5;

String whatsNewCardOfText(int number) => 'Card $number of $kWhatsNewCardCount';

// Card 1
const kWhatsNewCard1Title = 'Withdrawals, airtime and Pochi';

/// PLACEHOLDER for the PM: the mock's "Analytics shows how many you made and
/// what they cost" is not true in the app, so the second part says what the
/// app really shows.
const kWhatsNewCard1Body =
    'mmogo now understands these M\u2011Pesa messages. '
    'Home and Paid to show how many you made and what they cost. '
    'A withdrawal adds 0 to what you spent; only its Transaction cost counts toward costs.';

// Card 2
const kWhatsNewCard2Title = 'Weeks';
const kWhatsNewCard2Body =
    'Before, a week meant the last 7 days: today and the 6 days before it. '
    'That did not match the calendar, so we corrected it. '
    'A week now runs from the day you choose in Settings (Monday unless you change it). '
    'Past weekly figures are regrouped to match; nothing saved changes.';
const kWhatsNewChangeInSettings = 'Change in Settings';

// Card 3 (invented example name and numbers, as in the mock)
const kWhatsNewCard3Title = 'Same phone number = one person';
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

// Card 4
const kWhatsNewCard4Title = 'Backups';
const kWhatsNewCard4Body =
    'Backups from 0.1.1 still restore. $kBackupNotRestorableByOlder $kUninstallErasesNotice';

// Card 5
const kWhatsNewCard5Title = 'Privacy';
/// R14 (F4): the canonical sentence already says the internet is used only to
/// check for updates, so only the second half of W7 follows it.
const kWhatsNewCard5Body = '$kPrivacySentenceStandard $kNetworkSeenSentence';
