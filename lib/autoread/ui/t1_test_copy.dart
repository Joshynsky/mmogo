/// §AUTOREAD.T1 copy — every string of the temporary T1 test screen.
/// Test scaffolding only; removed when the real Notifications page lands.
library;

const String kT1CornerLabel = 'T1';
const String kT1CornerSemantics = 'Auto-read test screen';
const String kT1Title = 'Auto-read test build';
const String kT1Intro =
    'Temporary screen for testing on this phone. It is removed before release.';

const String kT1ReadOn = 'Read is on';
const String kT1ReadOff = 'Read is off';
const String kT1SmsAllowed = 'SMS permission: allowed';
const String kT1SmsNotAllowed = 'SMS permission: not allowed';
const String kT1NotifAllowed = 'Notifications: allowed';
const String kT1NotifNotAllowed = 'Notifications: not allowed';
String t1Waiting(int n) => '$n waiting';

const String kT1AllowPermissions = 'Allow permissions';
const String kT1SwitchLabel = 'Read M-Pesa messages';
const String kT1OpenSettings = 'Open app settings';
const String kT1DeleteHeld = 'Delete held messages';
const String kT1Refresh = 'Refresh';

const String kT1SmsStillOff =
    'SMS permission is not allowed, so Read stays off.';

const String kT1TapHeading = 'Last notification tap';
const String kT1NoTap = 'No tap yet';
String t1TapLine(String tail, bool stillHeld) =>
    'Opened from a notification, id ends …$tail. '
    'Message still held: ${stillHeld ? 'yes' : 'no'}';

String t1Error(String code) => 'That did not work ($code)';
