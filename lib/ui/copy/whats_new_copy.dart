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
const kWhatsNewInternetLead = 'A first for mmogo: it uses the internet.';
const kWhatsNewInternetBody =
    ' $kNetworkSentence $kUpdateCheckCadence '
    'You can turn it off on the Updates page (Profile, Settings, Updates). '
    'There are no Android notifications: when there is news, the bell on Home shows a dot.';

const kWhatsNewOpenBackup = 'Open Backup and restore';
const kWhatsNewGotIt = 'Got it';
