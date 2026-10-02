/// B31: the What's-new modal's wording for 0.1.1 (signed-off prototype
/// `whatsNew()`). The fixed sentences come from `data_copy.dart`.
library;

import 'data_copy.dart';

const kWhatsNewTitle = "What's new in mmogo 0.1.1";

const kWhatsNewBackupLead = 'Back up your data.';
const kWhatsNewBackupBody =
    ' You can now save a backup file and restore it, in Profile, Settings, Backup and restore. '
    'mmogo can also make a backup for you after every few saved entries. '
    'The file is not encrypted: it holds names and phone numbers, so keep it somewhere private.';

/// Bold lead is [kUninstallErasesNotice]; the body is [kPhoneTransferNotice].
const kWhatsNewInternetLead = 'mmogo now uses the internet.';
const kWhatsNewInternetBody =
    ' So you can get updates without leaving the app, mmogo asks GitHub whether a newer version is out. '
    '$kNetworkSentence $kUpdateCheckCadence '
    'You can turn this off any time on the Updates page (Profile, Settings, Updates). '
    'News shows as a dot on the bell on Home. There are no Android notifications.';

const kWhatsNewUnsupportedLead = 'Some messages are not understood yet.';
const kWhatsNewUnsupportedBody =
    ' mmogo does not recognise every M-Pesa message you paste into it. Pochi la Biashara payments, '
    'agent withdrawals and airtime purchases still need to be added by hand for now. '
    'We have only just started, and they are coming in future updates. Thank you for bearing with us. '
    'If you find one we are missing, tell us in Settings, Send feedback.';

/// A personal sign-off, shown last in the What's-new message.
const kWhatsNewSignOff = '— Josh';

const kWhatsNewOpenBackup = 'Open Backup and restore';
const kWhatsNewGotIt = 'Got it';
