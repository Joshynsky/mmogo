/// §AUTOREAD.AIRTIME_KIND_COPY — wording for the two Airtime kinds (WBS row 17,
/// slice B). Every string here is WORDING-DRAFT: the PM picks the final text.
/// Mock: `global-mock/plugins/mk-air-switch.html` (labels locked 11-11).
library;

// WORDING-DRAFT
const String kAirKindMyselfLabel = 'For my number';
// WORDING-DRAFT
const String kAirKindMyselfSub = 'Airtime you buy for yourself.';
// WORDING-DRAFT
const String kAirKindOtherLabel = 'For another number';
// WORDING-DRAFT
const String kAirKindOtherSub = 'Airtime you buy for someone else. The other number is not saved.';
// WORDING-DRAFT: Soft only in this version; Hard is greyed.
const String kAirKindHardLater = 'Hard comes in a later version';

// WORDING-DRAFT
const String kAirKindMyselfOnToast =
    'Auto-record for your number is on. Airtime you buy for yourself is recorded for you; Undo stays on each one.';
// WORDING-DRAFT
const String kAirKindMyselfOffToast =
    'Auto-record for your number is off. That airtime goes through To categorize.';
// WORDING-DRAFT
const String kAirKindOtherOnToast =
    'Auto-record for another number is on. Undo stays on each one. The other number is not saved.';
// WORDING-DRAFT
const String kAirKindOtherOffToast =
    'Auto-record for another number is off. That airtime goes through To categorize.';
