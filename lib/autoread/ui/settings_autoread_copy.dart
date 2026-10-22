/// §AUTOREAD.SETTINGS_COPY — every string of the Settings rows, the consent
/// sheet, the delete-held confirmation and the restricted-settings help.
///
/// PM read pending (19-10-2026): ALL of this wording is PROVISIONAL until the
/// product manager has read it. It follows the Judge's copy rules
/// (04-judge-verdict.md, condition 10): no absolutes, none of the banned
/// phrases, no compliance claim, the held window comes from the constant in
/// `held_window.dart` (no hour count is typed here), and the responsible
/// person is ONE constant below (no email).
///
/// Autoread flavor only; reached from the Settings screen inside
/// `if (kAutoReadCompiled)`.
library;

import '../held_window.dart';

/// Who is responsible for this feature (PM 18-10-2026): a name, no email. ONE
/// constant so a contact can be added later.
const String kResponsiblePerson = 'Joshua Waga';

/// The sentences the Judge explicitly allows even though they hold "never"
/// (condition 10). The banned-phrase scan removes exactly these before it looks
/// for "never".
const String kOtherMessagesLine = 'Other messages are never stored, parsed or logged.';
const String kDeveloperLine =
    'mmogo’s developer never receives your data: the app does not send it anywhere.';

// ---------------------------------------------------------------- Settings

const String kReadingSectionLabel = 'Reading messages';
const String kReadLabel = 'Read M-Pesa messages';
const String kReadStatusOff = 'Off. Turn on to be told when an M-Pesa message arrives.';
const String kReadStatusOn = 'On. M-Pesa messages are held on this phone until you parse them.';
const String kReadStatusWorking = 'Working…';
const String kReadStatusUnavailable = 'Not available on this phone.';

const String kReadDeniedSms = 'SMS was not allowed, so Read is still off.';
const String kReadDeniedNotifications = 'Notifications were not allowed, so Read is still off.';
const String kReadDeniedBlocked =
    'Android did not allow it, so Read is still off. Tap Trouble turning it on? for help.';
const String kReadFailed = 'Could not change this. Try again.';
const String kReadStillOn = 'Could not turn Read off. Try again.';

// The visible "capture is on but not working" row (Judge condition 7).
const String kFixLabel = 'Capture is on but not working: fix';
const String kFixSms = 'SMS is not allowed. Tap to allow it.';
const String kFixNotifications = 'Notifications are not allowed. Tap to allow them.';
const String kFixBoth = 'SMS and notifications are not allowed. Tap to allow them.';
const String kFixStillBlocked = 'Android is still blocking it. Here is what to try.';

// Delete held messages.
const String kDeleteHeldLabel = 'Delete held messages';
const String kDeleteHeldNone = 'No messages are held.';
String deleteHeldSubtitle(int n) =>
    '$n ${n == 1 ? 'message is' : 'messages are'} held on this phone. The originals stay in your Messages.';
const String kDeleteHeldTitle = 'Delete held messages?';
const String kDeleteHeldBody =
    'Messages mmogo is holding for you to parse will be removed. They stay in your phone’s Messages, so you can paste them instead.';
const String kDeleteHeldCancel = 'Cancel';
const String kDeleteHeldConfirm = 'Delete';
const String kDeleteHeldDone = 'Held messages deleted.';
const String kDeleteHeldFailed = 'Could not delete them all. Try again.';

// Restricted-settings help (row, sheet).
const String kHelpRowLabel = 'Trouble turning it on?';
const String kHelpRowSubtitle = 'Steps for when Android blocks SMS for mmogo.';
const String kHelpTitle = 'Trouble turning it on?';
const String kHelpIntro =
    'Some phones block SMS for an app that was not installed from a store, until you allow restricted settings.';
const List<String> kHelpSteps = [
  'Tap Open app settings below.',
  'If you see a three-dot menu at the top, open it and choose Allow restricted settings.',
  'Open Permissions and allow SMS and Notifications.',
  'Come back to mmogo. The Read M-Pesa messages row shows where things stand.',
];
const String kHelpNote =
    'Android only lets mmogo open its own page in Android settings, not the exact permission screen.';
const String kHelpOpen = 'Open app settings';
const String kHelpClose = 'Close';

// ---------------------------------------------------------------- Consent

const String kConsentTitle = 'Read M-Pesa messages?';

/// Switch 1 on the consent screen: the existing lead sentences (Judge condition
/// 10), word for word from the PM-approved mock consent-reading.html. The old
/// last clause "and you can turn this off at any time" now lives in
/// [kConsentFooter].
const String kConsentReadDesc =
    'mmogo keeps only messages from M-Pesa and drops the rest. It does not send any of it off your phone. Pasting still works.';

/// Switch 2, "Parse from the notification" (label shared with Settings). Per
/// the mock: the first sentence is NEW, the second is reused from the lead.
// NEW, needs PM signature: 'A Parse button on the phone notification parses a waiting message without opening mmogo.'
const String kConsentParseDesc =
    'A Parse button on the phone notification parses a waiting message without opening mmogo. It does not send any of it off your phone.';

/// Shown under switch 2 while switch 1 is off (greyed-row line of the bell mock).
const String kParseGreyLine = 'Turn on Read M-Pesa messages first.';

/// The plain line that everything can be changed later.
// NEW, needs PM signature (based on kConsentOff, now covering each switch).
const String kConsentFooter = 'You can change or turn off each of these at any time in Settings.';

/// Settings row and consent switch 2 (wording of the bell mock).
const String kParseLabel = 'Parse from the notification';

// ------------------------------------------------------- Autostart (Xiaomi)

/// Xiaomi, Redmi and Poco phones only (PM 21-10-2026, Redmi spike: a swiped-away
/// app is not started from a notification unless Autostart is on). Not a
/// switch: an app cannot toggle another OS setting. The button is only ever
/// tapped by the user; the app never opens the screen by itself.
// NEW, needs PM signature (title).
const String kAutostartLabel = 'Autostart for mmogo';
// NEW, needs PM signature (body).
const String kAutostartBody =
    'Parse from the notification works only if Autostart is on for mmogo on this phone. If it is off, the message stays held and you can parse it by opening mmogo.';
// NEW, needs PM signature (button).
const String kAutostartButton = 'Open Autostart settings';
const String kConsentMore = 'More details';
const String kConsentLess = 'Hide details';

const String kConsentWhatIsRead =
    'What is read: messages whose sender is M-Pesa. mmogo works out the details on this phone and shows them to you to check.';
// moved to first screen, PM 22-10-2026 (shown before Allow / Not now, not behind More details)
const String kConsentAndroidPrompt =
    'Android will ask to “send and view SMS”. That prompt is broader than what mmogo uses: the filter for M-Pesa is in mmogo’s own code.';
const String kConsentOthers = kOtherMessagesLine;
const String kConsentNotification =
    'The notification on your phone only says a message is ready. It shows no amount and no name.';
const String kConsentWhereItStays =
    'Where it stays: on this phone. mmogo does not send messages anywhere.';
const String kConsentDeveloper = kDeveloperLine;
const String kConsentForged =
    'A forged message can look genuine. mmogo reads the message text only and cannot check it with M-Pesa.';
String get kConsentHeld => 'Held messages: $kHeldWindowCopy';
const String kConsentOff =
    'You can turn this off at any time in Settings. Turning it off stops new messages from being read. Messages already held stay until you delete them or they expire. The originals stay in your phone’s Messages.';
String get kConsentResponsible => 'Responsible for this feature: $kResponsiblePerson.';

// NEW, needs PM signature (the app says Agree today; the mock says Allow).
const String kConsentAllow = 'Allow';
const String kConsentNotNow = 'Not now';

/// Shown behind "More details", in order. [kConsentAndroidPrompt] is not here:
/// it moved to the first screen (PM 22-10-2026).
List<String> get kConsentDetailLines => [
      kConsentWhatIsRead,
      kConsentNotification,
      kConsentWhereItStays,
      kConsentOthers,
      kConsentHeld,
      kConsentForged,
      kConsentDeveloper,
      kConsentOff,
      kConsentResponsible,
    ];

/// Every user-visible string of this slice, for the banned-phrase scan.
List<String> allSettingsAutoReadCopy() => [
      kReadingSectionLabel,
      kReadLabel,
      kReadStatusOff,
      kReadStatusOn,
      kReadStatusWorking,
      kReadStatusUnavailable,
      kReadDeniedSms,
      kReadDeniedNotifications,
      kReadDeniedBlocked,
      kReadFailed,
      kReadStillOn,
      kFixLabel,
      kFixSms,
      kFixNotifications,
      kFixBoth,
      kFixStillBlocked,
      kDeleteHeldLabel,
      kDeleteHeldNone,
      deleteHeldSubtitle(1),
      deleteHeldSubtitle(3),
      kDeleteHeldTitle,
      kDeleteHeldBody,
      kDeleteHeldCancel,
      kDeleteHeldConfirm,
      kDeleteHeldDone,
      kDeleteHeldFailed,
      kHelpRowLabel,
      kHelpRowSubtitle,
      kHelpTitle,
      kHelpIntro,
      ...kHelpSteps,
      kHelpNote,
      kHelpOpen,
      kHelpClose,
      kConsentTitle,
      kConsentReadDesc,
      kConsentParseDesc,
      kParseGreyLine,
      kConsentFooter,
      kParseLabel,
      kAutostartLabel,
      kAutostartBody,
      kAutostartButton,
      kConsentMore,
      kConsentLess,
      ...kConsentDetailLines,
      kConsentAllow,
      kConsentNotNow,
    ];
