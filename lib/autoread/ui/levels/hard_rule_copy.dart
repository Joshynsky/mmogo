/// §AUTOREAD.LEVELS.HARD_RULE_COPY: every new string of the 0.2.2 Auto-record hard rule screens (level
/// sheet, confirm dialog, offer card, the one pill, pause and reset controls, Remembered layout A, restore
/// review). The ONLY home of these strings: the screen slices import this file and add none of their own.
///
/// Text is the draft from the signed mock `_pipeline/v0.2.2/mock-hard-rule/index.html` (key in brackets),
/// with the PM's 25-11 changes applied: the ceiling label has no "(optional)", the Paybill line has no "yet".
/// Every string is WORDING-DRAFT and marked `// SIGN`: the PM signs them before release (plan section 5).
/// `kTodo...` constants are PLACEHOLDERS for lines the mock does not have; the PM writes them (slice W).
library;

import '../../../domain/format/money.dart' show kshTrim;
import '../../rules/rule_model.dart';

// ---------------------------------------------------------------- levels
// SIGN WORDING-DRAFT (mock lvl_sug)
const String kHardLevelSuggested = 'Suggested';
// SIGN WORDING-DRAFT (mock lvl_ask)
const String kHardLevelAskFirst = 'Ask first';
// SIGN WORDING-DRAFT (mock lvl_auto)
const String kHardLevelAutoRecord = 'Auto-record';

/// The name of a level, all three levels.
String hardRuleLevelName(RuleLevel l) => switch (l) {
      RuleLevel.suggested => kHardLevelSuggested,
      RuleLevel.askFirst => kHardLevelAskFirst,
      RuleLevel.autoRecord => kHardLevelAutoRecord,
    };

// ---------------------------------------------------------------- level sheet
// SIGN WORDING-DRAFT (mock sheet_t)
String hardSheetTitle(String name) => 'What should mmogo do for $name?';
// SIGN WORDING-DRAFT (mock n_sug)
String hardSheetNoteSuggested(String name) => "mmogo offers $name's most-used categories on the alert. Nothing records without a tap.";
// SIGN WORDING-DRAFT (mock n_ask)
String hardSheetNoteAskFirst(String category) => 'mmogo asks "Record as $category?" with one tap each time.';
// SIGN WORDING-DRAFT (mock n_auto)
const String kHardSheetNoteAutoRecord = 'Recorded with no tap. You get a notice every time, and you can Undo it.';

// ---------------------------------------------------------------- ceiling field
// SIGN WORDING-DRAFT (mock ceil_l; PM-signed label, "(optional)" dropped 25-11)
const String kHardCeilingLabel = 'Ask first above Ksh';
// SIGN WORDING-DRAFT (the "Ksh" prefix drawn in the mock field)
const String kHardCeilingPrefix = 'Ksh';
// SIGN WORDING-DRAFT (mock ceil_ph)
const String kHardCeilingPlaceholder = 'No ceiling';
// SIGN WORDING-DRAFT (mock ceil_h)
const String kHardCeilingHint = 'Leave empty for no ceiling. A payment above this amount is asked first.';
// SIGN WORDING-DRAFT (mock ceil_e)
const String kHardCeilingError = 'Enter an amount above 0, or leave it empty.';
// SIGN PLACEHOLDER: the mock has no line for a ceiling above Ksh 1,000,000 (plan section 5). PM to write.
const String kTodoHardCeilingTooHigh = '[PM to write: ceiling above Ksh 1,000,000]';

// ---------------------------------------------------------------- greyed Auto-record reasons
// SIGN WORDING-DRAFT (mock why_bill with "yet" removed per PM 25-11; the PM's own example was
// "Paybill payments always ask first": confirm the exact words)
const String kHardWhyNotPaybill = 'Not for Paybill. Ask first is the highest level.';
// SIGN WORDING-DRAFT (mock why_agent)
const String kHardWhyNotWithdrawal = 'Not for withdrawals. Ask first is the highest level.';

// ---------------------------------------------------------------- confirm dialog (Cancel = kLevelSheetCancel)
// SIGN WORDING-DRAFT (mock conf_t)
String hardConfirmTitle(String name) => 'Auto-record $name?';
// SIGN WORDING-DRAFT (mock conf_b0)
String hardConfirmBodyNoCeiling(String name, String category) =>
    "From now on mmogo records $name's payments as $category without asking. You can Undo any of them.";
// SIGN WORDING-DRAFT (mock conf_b1)
String hardConfirmBodyCeiling(String name, String category, int ceilingCents) =>
    "From now on mmogo records $name's payments up to ${kshTrim(ceilingCents)} as $category without asking. "
    'Above that it asks first. You can Undo any of them.';
// SIGN WORDING-DRAFT (mock conf_ok)
const String kHardConfirmTurnOn = 'Turn on';

// ---------------------------------------------------------------- offer card
// SIGN WORDING-DRAFT (mock offer_t)
String hardOfferTitle(String name) => 'Auto-record $name?';
// SIGN WORDING-DRAFT (mock offer_b; the mock's 3 is the "Suggest after" number)
String hardOfferBody(String name, String category, int times) =>
    "You've recorded $name as $category $times times in a row. Should mmogo ask first next time, or record it for you?";
// SIGN WORDING-DRAFT (mock offer_not)
const String kHardOfferNotNow = 'Not now';
// SIGN WORDING-DRAFT (mock offer_ask)
const String kHardOfferAskFirst = 'Ask me first';
// SIGN WORDING-DRAFT (mock offer_auto)
const String kHardOfferAutoRecord = 'Auto-record';

// ---------------------------------------------------------------- the one pill
// SIGN WORDING-DRAFT (mock pill_sug / pill_ask / pill_auto)
String hardPillStage1(String name, RuleLevel level) => switch (level) {
      RuleLevel.suggested => '$name set to Suggested',
      RuleLevel.askFirst => '$name set to Ask first',
      RuleLevel.autoRecord => '$name set to Auto-record',
    };
// SIGN WORDING-DRAFT (mock pill2_t with pill_noceil / pill_ceil)
String hardPillStage2(String name, int? ceilingCents) =>
    '$name is on Auto-record with ${ceilingCents == null ? 'no ceiling' : 'a ceiling of ${kshTrim(ceilingCents)}'}.';
// SIGN WORDING-DRAFT (mock pill2_s)
const String kHardPillStage2Sub = 'You can change this.';
// SIGN WORDING-DRAFT (mock pill_chg)
const String kHardPillChangeCeiling = 'Change ceiling';

// ---------------------------------------------------------------- pause (amber, reversible)
// SIGN WORDING-DRAFT (mock pause_t; also the switch's spoken name)
const String kHardPauseTitle = 'Pause all Auto-record';
// SIGN WORDING-DRAFT (mock pause_s)
const String kHardPauseSub = 'Everyone on Auto-record is asked first. Rules stay saved.';
// SIGN WORDING-DRAFT (mock pause_ban)
String hardPausedBanner(int n) => 'Auto-record is paused. $n people are asked first until you resume.';
// SIGN WORDING-DRAFT (mock resume)
const String kHardResume = 'Resume';
// SIGN WORDING-DRAFT (mock pause_toast)
const String kHardPausedToast = 'Auto-record paused. Rules are saved.';
// SIGN WORDING-DRAFT (mock resume_toast)
String hardResumedToast(int n) => 'Auto-record is back on for $n people.';
// SIGN WORDING-DRAFT (mock tag_paused: the amber tag on a To confirm item)
const String kHardPausedTag = 'Auto-record paused: asking first';
// SIGN WORDING-DRAFT (mock set_pause_row)
const String kHardPauseSettingsTitle = 'Pause all Auto-record';
// SIGN WORDING-DRAFT (mock set_pause_sub)
const String kHardPauseSettingsSub = 'Turns every Auto-record person into Ask first until you switch it back.';

// ---------------------------------------------------------------- red buttons (counts only, never names)
// SIGN WORDING-DRAFT (mock reset_btn)
const String kHardResetButton = 'Reset everyone to Suggested';
// SIGN WORDING-DRAFT (mock reset_t)
String hardResetTitle(int n) => 'Reset $n people to Suggested?';
// SIGN WORDING-DRAFT (mock reset_b)
const String kHardResetBody =
    'Their Ask first and Auto-record levels and ceilings are removed. Recipients stay remembered. Nothing already recorded changes.';
// SIGN WORDING-DRAFT (mock reset_ok)
const String kHardResetOk = 'Reset';
// SIGN WORDING-DRAFT (mock reset_toast)
String hardResetToast(int n) => '$n people reset to Suggested.';
// SIGN WORDING-DRAFT (mock forget_btn)
const String kHardForgetButton = 'Forget all recipients';
// SIGN WORDING-DRAFT (mock forget_t)
String hardForgetTitle(int n) => 'Forget all $n recipients?';
// SIGN WORDING-DRAFT (mock forget_b)
const String kHardForgetBody = 'Their levels, ceilings and history are forgotten too. We will ask again next time.';
// SIGN WORDING-DRAFT (mock forget_ok)
const String kHardForgetOk = 'Forget all';
// SIGN WORDING-DRAFT (mock forget_toast)
String hardForgetToast(int n) => 'Forgot $n recipients.';

// ---------------------------------------------------------------- Remembered page, layout A
// SIGN WORDING-DRAFT (mock page helper under the tabs; not in the mock's key table)
const String kHardPageHelper = 'Suggested offers categories. Ask first asks for one tap. Auto-record files it for you.';
// SIGN WORDING-DRAFT (mock grp_auto / grp_ask / grp_sug: the section names are the level names)
String hardGroupName(RuleLevel l) => hardRuleLevelName(l);
// SIGN WORDING-DRAFT (mock show)
String hardGroupShow(int n) => 'Show $n';
// SIGN WORDING-DRAFT (mock hide)
const String kHardGroupHide = 'Hide';
// SIGN WORDING-DRAFT (mock search_ph; also the field's spoken name)
const String kHardSearchPlaceholder = 'Search people';
// SIGN WORDING-DRAFT (mock empty_f)
const String kHardSearchEmpty = 'Nobody matches.';
// SIGN WORDING-DRAFT (mock row_auto0)
const String kHardRowAutoNoCeiling = 'Auto-record, no ceiling';
// SIGN WORDING-DRAFT (mock row_autoc)
String hardRowAutoCeiling(int ceilingCents) => 'Auto-record up to ${kshTrim(ceilingCents)}';
// SIGN WORDING-DRAFT (mock row_paused)
const String kHardRowPaused = 'Paused: asking first';
// SIGN WORDING-DRAFT (mock row_only_ask)
const String kHardRowAskFirstHighest = 'Ask first is the highest level here';
// SIGN WORDING-DRAFT (mock off_line)
const String kHardDetailsOffLine = 'Record receiver details is off. No names are kept, so there are no rules.';
// SIGN WORDING-DRAFT (mock off_btn / off_ok)
const String kHardOpenSettings = 'Open Settings';
// SIGN WORDING-DRAFT (mock rst-off-page empty line, not in the key table)
const String kHardDetailsOffEmpty = 'Nobody is remembered while Record receiver details is off.';

// ---------------------------------------------------------------- restore review
// SIGN WORDING-DRAFT (mock rev_line)
String hardReviewLine(int n) => '$n people were on Auto-record. They are on Ask first until you confirm.';
// SIGN WORDING-DRAFT (mock rev_btn)
const String kHardReviewButton = 'Review';
// SIGN WORDING-DRAFT (mock rev_t)
const String kHardReviewTitle = 'Auto-record from your backup';
// SIGN WORDING-DRAFT (mock rev_s)
const String kHardReviewSub = 'Choose who goes back to Auto-record.';
// SIGN WORDING-DRAFT (mock rev_ok)
const String kHardReviewConfirm = 'Confirm';
// SIGN WORDING-DRAFT (mock rev_keep)
const String kHardReviewKeepAll = 'Keep all on Ask first';
// SIGN WORDING-DRAFT (mock rev_toast)
String hardReviewToast(int n) => '$n people are on Auto-record again.';
// SIGN WORDING-DRAFT (mock revkeep toast)
const String kHardReviewKeptToast = 'All on Ask first.';
// SIGN WORDING-DRAFT (mock rst_toast)
String hardRestoreToast(int n) => 'Backup restored. $n people need a review.';
// SIGN WORDING-DRAFT (mock off_t)
const String kHardRestoreOffTitle = 'Backup restored';
// SIGN WORDING-DRAFT (mock off_b)
String hardRestoreOffBody(int n) => '$n saved rules were left out. Rules need Record receiver details, and it is off.';

// ---------------------------------------------------------------- arrival (slice B2)
// SIGN PLACEHOLDER: toast for a row Auto-record recorded, shown when mmogo opens (today's Yes toast says
// "from your Yes on the alert"; plan section 5). PM to write.
const String kTodoAutoRecordArrivedToast = '[PM to write: recorded by Auto-record toast]';
