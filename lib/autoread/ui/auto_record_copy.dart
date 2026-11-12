/// §AUTOREAD.AUTO_RECORD_COPY: every word the Remembered page's second tab adds
/// (the Settings row's words live in settings_copy.dart). SIGNED = signed off by the PM; DRAFT = still to be
/// signed. Mock: `global-mock/plugins/mk-air-switch.html` (round 5).
library;

import '../../domain/format/source_types.dart';
import 'airtime_kind_copy.dart' show kAirKindMyselfSub, kAirKindOtherSub;

// The switch labels are kAirKindMyselfLabel / kAirKindOtherLabel (one place).

// DRAFT (mock text; PM answer: page title is "Remembered")
const String kAutoRecordPageTitle = 'Remembered';
// DRAFT (mock text)
const String kAutoRecordRecipientsTab = 'Recipients';
// DRAFT (mock text)
const String kAutoRecordForgetAllLabel = 'Forget all recipients';
// DRAFT (mock text)
const String kAutoRecordForgetAllNote = 'The airtime switches are not affected.';

/// Tab 2 label. DRAFT (mock text). [on] is how many of the two switches are on.
String autoRecordTabLabel(int on) => 'Recorded automatically · $on';

/// Spoken tab 2 label. DRAFT.
String autoRecordTabSpoken(int on) => 'Recorded automatically, $on of 2 on';

// DRAFT (mock text): the type name comes from its one place.
final String kAutoRecordChipAirtime = sourceTypeName('AIRTIME');
// DRAFT (mock text): code and spoken name of the muted chips.
const List<(String, String)> kAutoRecordLaterChips = [
  ('SM', 'Send money'),
  ('PB', 'Paybill'),
  ('BG', 'Buy goods'),
  ('W', 'Withdrawal'),
  ('P', 'Pochi'),
];

/// DRAFT (mock text)
String autoRecordChipLaterSpoken(String typeName) => '$typeName, coming later';

// DRAFT (mock text)
const String kAutoRecordChipsGroup = 'Types recorded automatically';

// DRAFT (mock text; the same subs as the card, kept in one place here)
const String kAutoRecordMyselfSub = kAirKindMyselfSub;
// DRAFT
const String kAutoRecordOtherSub = kAirKindOtherSub;

// [label] is the row label (For myself / For another number).
// DRAFT (PM decision 12-11-2026): line one of the block under an opened row.
String autoRecordExplainTap(String label) => 'You tap Parse on each message, then mmogo files it under $label.';
// DRAFT (PM decision 12-11-2026): line two, muted.
const String kAutoRecordExplainLater = 'Filing without a tap comes in a later version.';

// DRAFT (mock text)
const String kAutoRecordLaterTypes = 'The other types are coming in a later version.';

/// SIGNED (PM 13-11-2026): ON toast; says airtime already parsed and waiting is filed at once (PM answer Q3).
String autoRecordOnToast(String label) =>
    '$label is on. You tap Parse each time. Airtime already parsed and waiting is recorded at once.';

/// DRAFT (mock text)
String autoRecordOffToast(String label) => '$label is off. Nothing is recorded for you.';
