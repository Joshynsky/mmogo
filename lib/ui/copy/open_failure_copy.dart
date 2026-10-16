/// §COPY.OPEN_FAILURE — every word of the open-failure screen (0.1.2 S10c,
/// OF1 / CB7). Wording of the OPN-1 variant is a PLACEHOLDER for the PM.
///
/// CB7 bans a list of phrases here; test/ui/startup_gate_test.dart holds the
/// list and scans this file. The reassuring title and the "Nothing was
/// changed" sentence belong to the UPG-3 variant only, which is shown only
/// after a verified rollback with the Android proof on record.
library;

/// OPN-1 (anything else): makes no promise about the data.
const kOpenFailTitleOther = 'mmogo could not open';
const kOpenFailBodyOther = 'mmogo could not open its storage. We cannot tell what state it is in.';

/// UPG-3 (verified rolled-back upgrade) only.
const kOpenFailTitleUpg3 = 'Your data is untouched';
const kOpenFailBodyUpg3 = 'mmogo could not finish updating its storage, so it has not opened. Nothing was changed.';

const kOpenFailLeadIn = 'Try again. If it still will not open, please follow these steps:';

const kOpenFailSteps = <String>[
  'Close mmogo and open it again.',
  'Free some storage space on the phone if it is nearly full.',
  'Do not uninstall mmogo. Uninstalling erases your entries from this phone.',
  'Keep any backup files you have saved.',
];

/// Shown after the first failed Try again.
const kOpenFailStillHead = 'Still not working.';
const kOpenFailStillTail = 'Close mmogo and open it again.';

const kOpenFailTryAgain = 'Try again';
const kOpenFailTrying = 'Trying again...';
const kOpenFailCloseApp = 'Close app';

const kOpenFailCodeOther = 'OPN-1';
const kOpenFailCodeUpg3 = 'UPG-3';

String openFailCodeLine(String code) => 'If it keeps failing, send us this code: $code.';
