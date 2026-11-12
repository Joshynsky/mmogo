/// §AUTOREAD.DETAILS_COPY (0.2.0 row 16, J1): the words for the "Show details"
/// choice: its consent-sheet row and the one-time card for a phone that agreed
/// before the choice existed. Every const is tagged SIGNED: the PM signed the wording (13-11-2026)
/// (a test checks the tag above each const). No dash-style punctuation, no
/// "no internet" or "nothing leaves" claim; the network is not mentioned here.
///
/// Autoread flavor only.
library;

/// How long a details alert stays before Android removes it (J1 B3). The Kotlin
/// side holds the same number (AlertText.DETAILS_TIMEOUT_MS); a test pins both.
// SIGNED (a number, not a string: the minutes behind the words below).
const int kDetailsAlertMinutes = 15;

/// The lock-screen sentence, ONE wording for every place (J1 condition d).
// SIGNED (J1 d, PM 12-11-2026 wording; PM signs).
const String kLockScreenSentence =
    'It is generic when the phone is locked as the message arrives; the lock screen can show details later unless Android is set to hide sensitive content.';

// SIGNED (consent sheet switch 3, label).
const String kConsentDetailsLabel = 'Show details in alerts';

// SIGNED (consent sheet switch 3, line under the label).
const String kConsentDetailsDesc =
    'The alert shows the kind of message, the amount and the other person’s name, and goes away after $kDetailsAlertMinutes minutes. $kLockScreenSentence';

// SIGNED (consent sheet, shown under switch 3 while Read is off).
const String kConsentDetailsGrey = 'Turn on Read M-Pesa messages first.';

// SIGNED (one-time card, title).
const String kUpgradeCardTitle = 'Show details in alerts?';

// SIGNED (one-time card, body; states the lock-screen limit).
const String kUpgradeCardBody =
    'Alerts on this phone only say a message is ready. You can have them show the kind of message, the amount and the other person’s name, and they go away after $kDetailsAlertMinutes minutes. $kLockScreenSentence You can change this any time in Settings.';

// SIGNED (one-time card, button that turns details on).
const String kUpgradeCardYes = 'Show details';

// SIGNED (one-time card, button that keeps alerts generic).
const String kUpgradeCardNo = 'Keep generic';

/// Every string above, for the banned-phrase scan.
// SIGNED (the list carries the same wording as the consts).
List<String> allConsentDetailsCopy() => [
      kLockScreenSentence,
      kConsentDetailsLabel,
      kConsentDetailsDesc,
      kConsentDetailsGrey,
      kUpgradeCardTitle,
      kUpgradeCardBody,
      kUpgradeCardYes,
      kUpgradeCardNo,
    ];
