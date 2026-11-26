/// §AUTOREAD.LEVELS.HARD_RULE_COPY: every new string of the 0.2.2 Auto-record hard rule screens (level
/// sheet, confirm dialog, offer card, the one pill, pause and reset controls, Remembered page, Set up,
/// person sheet, category picker, restore review). The ONLY home of these strings: the screen slices
/// import this file and add none of their own.
///
/// Three kinds of line, each marked on its own line:
/// - `// SIGNED 25-11 (...)`: the PM's signed words (ITEM2-REVIEW-SIGNOFF-2026-11-25, sections "Signed
///   wording" and "Signed at sign-off"), verbatim. Pinned by test/autoread/ui/levels/hard_rule_copy_signed_test.dart.
/// - `// SIGN WORDING-DRAFT (...)`: a draft line copied from a mock (mock-hard-rule, or mock-remembered-v2
///   with its scene id). The PM signs these in slice W2.
/// - `kTodo...`: PLACEHOLDERS for lines no mock has; the PM writes them (W2).
///
/// Item 2 redesign (C1, 25-11): "limit" replaces "ceiling" in every user-facing value (key names may keep
/// "Ceiling"). Every counted line goes through [peopleCount] ("1 person" / "{n} people"). Keys whose
/// arguments changed got NEW functions next to the old ones; slice I2 (26-11) deleted the old keys nothing used
/// any more, with their pins. Keys marked `// 0.2.3` are signed but not shown in 0.2.2 ("Categories I choose"
/// moved to 0.2.3, plan section 11): never delete them.
/// NOT here on purpose (still open PM items): the confirm buttons "Turn on" / "Cancel" ([kHardConfirmTurnOn]
/// is unchanged) and the Settings row "0 names" subtitle.
library;

import '../../../domain/format/money.dart' show kshTrim;
import '../../../domain/format/source_types.dart' show sourceTypeName;
import '../../rules/rule_model.dart';

// ---------------------------------------------------------------- counts
/// "person" for 1, "people" otherwise (the noun alone, for lines with a word between count and noun).
String _peopleNoun(int n) => n == 1 ? 'person' : 'people';

/// "1 person" / "{n} people". SIGNED 25-11 ("Singular: "1 person" everywhere"). Every counted line uses it.
String peopleCount(int n) => '$n ${_peopleNoun(n)}';

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
// SIGN WORDING-DRAFT (mock n_sug)
String hardSheetNoteSuggested(String name) => "mmogo offers $name's most-used categories on the alert. Nothing records without a tap.";

// ---------------------------------------------------------------- limit field (key names keep "Ceiling")
// SIGN WORDING-DRAFT (mock ceil_l; PM-signed label, "(optional)" dropped 25-11)
const String kHardCeilingLabel = 'Ask first above Ksh';
// SIGN WORDING-DRAFT (the "Ksh" prefix drawn in the mock field)
const String kHardCeilingPrefix = 'Ksh';
// SIGN WORDING-DRAFT (mock ceil_e)
const String kHardCeilingError = 'Enter an amount above 0, or leave it empty.';
// SIGN PLACEHOLDER: the mock has no line for a limit above Ksh 1,000,000 (plan section 5). PM to write.
const String kTodoHardCeilingTooHigh = '[PM to write: limit above Ksh 1,000,000]';

// ---------------------------------------------------------------- greyed Auto-record reasons
// SIGNED 25-11 ("Paybill line")
const String kHardPaybillAlwaysAsks = 'Paybill payments always ask first.';
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
// SIGN WORDING-DRAFT (mock conf_ok). Still an open PM item after sign-off ("Turn on" / "Cancel"): unchanged.
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

// ---------------------------------------------------------------- the one pill (never a number)
// SIGNED 25-11 ("Pill", Suggested)
String hardPillSuggested(String name) => '$name set to Suggested';
// SIGNED 25-11 ("Pill", Ask first)
String hardPillAskFirst(String name, String category) => '$name set to Ask first · $category';
// SIGNED 25-11 ("Pill", Auto-record stage 1)
String hardPillAuto(String name, String category) => '$name set to Auto-record as $category';
// SIGNED 25-11 ("Pill", Auto-record stage 2, no limit)
const String kHardPillAnyAmount = 'Records any amount.';
// SIGNED 25-11 ("Pill", the button next to kHardPillAnyAmount)
const String kHardPillSetLimit = 'Set a limit';
// SIGNED 25-11 ("Pill", Auto-record stage 2 with a limit): "Records up to Ksh {limit}."
String hardPillUpTo(int limitCents) => 'Records up to ${kshTrim(limitCents)}.';
// SIGNED 25-11 ("Pill", the button next to hardPillUpTo)
const String kHardPillChange = 'Change';

// ---------------------------------------------------------------- undo of a no-tap entry
// SIGNED 25-11 ("No-tap message"): "{Name}, Ksh {amount} recorded as {Category}" (+ Undo, existing key).
String hardAutoArrived(String name, int amountCents, String category) =>
    '$name, ${kshTrim(amountCents)} recorded as $category';
// SIGNED 25-11 ("Undo pill")
String hardUndoStays(String name) => 'Undone. $name stays on Auto-record.';

// ---------------------------------------------------------------- pause (amber, reversible)
// SIGN WORDING-DRAFT (mock pause_t; also the switch's spoken name)
const String kHardPauseTitle = 'Pause all Auto-record';
// SIGNED 25-11 ("Pause row"; the page switch row uses the same line, mock-remembered-v2 pause_sub)
const String kHardPauseSub = 'Every Auto-record person is asked first until you resume.';
// SIGN WORDING-DRAFT (mock pause_ban; the count via peopleCount, verb agrees with it)
String hardPausedBanner(int n) =>
    'Auto-record is paused. ${peopleCount(n)} ${n == 1 ? 'is' : 'are'} asked first until you resume.';
// SIGN WORDING-DRAFT (mock resume; also the pinned notice's action, signed 25-11 "Pause")
const String kHardResume = 'Resume';
// SIGNED 25-11 ("Pause pill")
const String kHardPausedToast = 'Auto-record paused. Your settings are kept.';
// SIGN WORDING-DRAFT (mock resume_toast; the count via peopleCount)
String hardResumedToast(int n) => 'Auto-record is back on for ${peopleCount(n)}.';
// SIGN WORDING-DRAFT (mock tag_paused: the amber tag on a To confirm item)
const String kHardPausedTag = 'Auto-record paused: asking first';
// SIGN WORDING-DRAFT (mock set_pause_row)
const String kHardPauseSettingsTitle = 'Pause all Auto-record';
// SIGNED 25-11 ("Pause row")
const String kHardPauseSettingsSub = 'Every Auto-record person is asked first until you resume.';
// SIGNED 25-11 ("Pause": the pinned phone notice title; mock-remembered-v2 al-paused)
const String kHardPausedNoticeTitle = 'Auto-record is paused';

// ---------------------------------------------------------------- red buttons (counts only, never names)
// SIGN WORDING-DRAFT (mock reset_btn)
const String kHardResetButton = 'Reset everyone to Suggested';
// SIGNED 25-11 ("Reset"): "Reset {n} people to Suggested?"
String hardResetTitle(int n) => 'Reset ${peopleCount(n)} to Suggested?';
// SIGNED 25-11 ("Reset")
const String kHardResetBody =
    'They go back to Suggested and their limits are removed. mmogo still remembers them. Nothing already recorded changes.';
// SIGNED 25-11 ("Reset": Cancel · Reset)
const String kHardResetOk = 'Reset';
// SIGN WORDING-DRAFT (mock reset_toast; the count via peopleCount)
String hardResetToast(int n) => '${peopleCount(n)} reset to Suggested.';
// SIGNED 25-11 ("Signed at sign-off": page button)
const String kHardForgetButton = 'Forget all people';
// SIGNED 25-11 ("Forget all"): "Forget all {n} people?"
String hardForgetTitle(int n) => 'Forget all ${peopleCount(n)}?';
// SIGNED 25-11 ("Forget all")
const String kHardForgetBody =
    "mmogo forgets their names, numbers and Auto-record settings. Nothing already recorded changes. This can't be undone.";
// SIGNED 25-11 ("Forget all": Cancel · Forget all)
const String kHardForgetOk = 'Forget all';
// SIGNED 25-11 ("Forget all"): "Forgot {n} people."
String hardForgetToast(int n) => 'Forgot ${peopleCount(n)}.';

// ---------------------------------------------------------------- Remembered page
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
// SIGN WORDING-DRAFT (mock row_paused)
const String kHardRowPaused = 'Paused: asking first';
// SIGN WORDING-DRAFT (mock row_only_ask)
const String kHardRowAskFirstHighest = 'Ask first is the highest level here';
// SIGNED 25-11 ("Signed at sign-off": the line on Suggested rows with no chosen list)
const String kHardSuggestsFromLast10 = 'Suggests from last 10 payments';
// SIGNED 25-11 ("Details-off card")
const String kHardDetailsOffCard =
    "Record receiver details is off, so mmogo doesn't use your saved people or record them for you. "
    'Your settings come back when you turn it on.';
// SIGNED 25-11 ("Details-off card": its button)
const String kHardTurnOnInSettings = 'Turn it on in Settings';
// SIGN WORDING-DRAFT (mock off_btn / off_ok; signed 25-11 as the restore details-off button)
const String kHardOpenSettings = 'Open Settings';
// SIGNED 25-11 ("Redesign": the bottom bar button)
const String kHardSetUpButton = 'Set up';
// SIGNED 25-11 ("Redesign": the Set up sheet title; also the Set up button's spoken name, mock setup_aria)
const String kHardSetUpTitle = 'Set up a recipient';
// SIGNED 25-11 (F-5: the one list's heading)
const String kHardRecentlyRecorded = 'Recently recorded';
// SIGNED 25-11 (F-5: the tag on no-tap entries; the same words as the level name)
const String kHardAutoRecordTag = kHardLevelAutoRecord;

// ---------------------------------------------------------------- Suggest from (person sheet)
// Section 11 (PM 25-11): "Categories I choose" moved to 0.2.3. The keys marked `// 0.2.3` are not shown in 0.2.2;
// keep them (never delete). kHardSuggestChoose stays in use as the up-to-2 picker's no-name title.
// 0.2.3
// SIGNED 25-11 ("Signed at sign-off": Suggest words)
const String kHardSuggestFrom = 'Suggest from:';
// 0.2.3
// SIGNED 25-11 ("Signed at sign-off": Suggest words)
const String kHardSuggestLast10 = 'Last 10 payments';
// SIGNED 25-11 ("Signed at sign-off": Suggest words)
const String kHardSuggestChoose = 'Categories I choose';
// SIGNED 25-11 ("Signed at sign-off": the heading named in "the two How Suggest works texts")
const String kHardSuggestHowTitle = 'How Suggest works';
// 0.2.3
// SIGNED 25-11 ("Signed at sign-off": How Suggest works, Last 10 payments; mock-remembered-v2 sug_hist_p)
String hardSuggestHowLast10(String name) =>
    "When you pay $name, the alert says Tap Parse. Then mmogo suggests the categories you used most in $name's "
    'last 10 payments. Nothing records without a tap.';
// 0.2.3
// SIGNED 25-11 ("Signed at sign-off": How Suggest works, Categories I choose; mock-remembered-v2 sug_pick_p).
// [max] = the most categories a person can choose (C2's kMaxChosenCategories, 2).
String hardSuggestHowChosen(String name, int max) =>
    'When you pay $name, the alert shows your categories as buttons straight away, with no Parse tap. '
    'Choose up to $max. Nothing records without a tap.';
// 0.2.3
// SIGNED 25-11 ("Signed at sign-off": Suggest words)
const String kHardSuggestAlertPreview = 'Your alert will show:';
// 0.2.3
// SIGNED 25-11 ("Signed at sign-off": Suggest words)
const String kHardSuggestNoneChosen = 'None chosen yet';
// 0.2.3
// SIGNED 25-11 ("Signed at sign-off": the must-choose error)
const String kHardSuggestNeedOne = 'Choose at least one category, or pick Last 10 payments.';

// ---------------------------------------------------------------- person sheet: mock-only drafts (W2 signs)
// SIGN WORDING-DRAFT (mock-remembered-v2 p-ask ask_h)
const String kHardAskHowTitle = 'How Ask first works';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-ask imp_ask)
String hardAskHow(String name, String category) =>
    'When you pay $name, the alert asks "Record as $category?". One tap records it. Nothing records until you tap.';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-auto auto_h)
const String kHardAutoHowTitle = 'How Auto-record works';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-auto imp_auto)
String hardAutoHow(String name, String category) =>
    'Payments to $name are recorded as $category with no tap. You get a notice every time, and you can Undo it.';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-auto imp_ceil_h2)
const String kHardLimitHelpTitle = 'What "Ask first above" means';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-auto imp_ceil_p, mock line 338)
const String kHardLimitHelp =
    'A payment above this amount is asked first. A payment of exactly this amount is recorded. Only the amount counts, not the fee.';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-auto imp_ceil_ph: the empty limit field)
const String kHardLimitNotSet = 'Not set';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-auto imp_ceil_h: the help under the limit field)
const String kHardLimitEmptyHint = 'Leave it empty and mmogo never asks first.';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-sug p_count; singular per the mock's SING table): "{k} payments"
String hardPaymentsCount(int k) => k == 1 ? '1 payment' : '$k payments';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-sug set_to: the level choice's label)
const String kHardSetTo = 'Set to';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-sug lv_sug_btn: the Suggested level's button)
const String kHardLevelSuggestButton = 'Suggest';
// SIGN WORDING-DRAFT (mock-remembered-v2 back: every sheet's back arrow, spoken)
const String kHardBack = 'Back';
// 0.2.3
// SIGN WORDING-DRAFT (mock-remembered-v2 p-sug-chosen sug_cur_l)
const String kHardSuggestCurrentLabel = 'Categories to suggest';
// 0.2.3
// SIGN WORDING-DRAFT (mock-remembered-v2 p-sug-pick0 sug_choose)
const String kHardSuggestChooseButton = 'Choose categories';
// 0.2.3
// SIGN WORDING-DRAFT (mock-remembered-v2 p-sug-chosen sug_change): "Categories ({k} of {m})"
String hardSuggestChangeButton(int k, int m) => 'Categories ($k of $m)';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-keep sug_keep): {level} = the level the person had
String hardSuggestKeeps(String name, String level) => "$name's $level setting stays saved. You can switch back any time.";
// SIGN WORDING-DRAFT (mock-remembered-v2 p-ask cat_l)
const String kHardCategoryLabel = 'Category';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-ask cat_choose)
const String kHardCategoryChoose = 'Choose category';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-ask ask_most: under a pre-filled category)
const String kHardCategoryMostUsed = 'Most used, you can change it.';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-wait ask_wait)
String hardCategoryWaiting(String name) => "$name's only payment is still waiting without a category, so choose one.";
// SIGN WORDING-DRAFT (mock-remembered-v2 p-ask ask_need)
const String kHardCategoryNeed = 'Choose a category so mmogo knows what to ask.';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-ask-err ask_err)
const String kHardCategoryError = 'Choose a category first.';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-half no_cat)
const String kHardNoCategoryYet = 'No category yet';
// SIGN WORDING-DRAFT (mock-remembered-v2 p-sug save)
const String kHardSave = 'Save';

// ---------------------------------------------------------------- category picker: mock-only drafts (W2 signs)
// SIGN WORDING-DRAFT (mock-remembered-v2 pick-multi pk_t_multi)
String hardPickerTitleMulti(String name) => 'Categories for $name';
// SIGN WORDING-DRAFT (mock-remembered-v2 pick-one pk_t_one)
String hardPickerTitleOne(String name) => 'Category for $name';
// SIGN WORDING-DRAFT (mock-remembered-v2 pick-multi pk_s_multi)
String hardPickerUpTo(int m) => 'Choose up to $m.';
// SIGN WORDING-DRAFT (mock-remembered-v2 pick-multi pk_count): "{k} of {m} chosen"
String hardPickerCount(int k, int m) => '$k of $m chosen';
// SIGN WORDING-DRAFT (mock-remembered-v2 pick-multi pk_used: the dot's text label)
const String kHardPickerUsedBefore = 'Used before';
// SIGN WORDING-DRAFT (mock-remembered-v2 pick-multi pk_limit)
String hardPickerLimit(int m) => 'You can choose up to $m. Turn one off first.';
// SIGN WORDING-DRAFT (mock-remembered-v2 pick-multi done)
const String kHardPickerDone = 'Done';

// ---------------------------------------------------------------- Set up sheet and page: mock-only drafts (W2 signs)
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-half types_aria: the type chips' group name)
const String kHardTypeChipsGroup = 'Payment type';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-half all_n: the first type chip)
const String kHardTypeChipAll = 'All';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-half TYPES: the type chips, (short code, name)). The names
// come from their one place, sourceTypeName (they are the mock's names word for word); only the short
// codes are new here.
final List<(String, String)> kHardTypeChips = [
  ('SM', sourceTypeName('SEND_MONEY')),
  ('PB', sourceTypeName('PAYBILL')),
  ('BG', sourceTypeName('BUY_GOODS')),
  ('P', sourceTypeName('POCHI_LA_BIASHARA')),
  ('A', sourceTypeName('AIRTIME')),
];
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-search imp_q; also the field's spoken name)
const String kHardSetUpSearch = 'Search name or category';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-half imp_hint)
const String kHardSetUpHint = 'Everyone you have paid, most payments first.';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-half grab_up)
const String kHardSheetTaller = 'Make the list taller';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-full grab_down)
const String kHardSheetShorter = 'Make the list shorter';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-pb acct): "account {a}", {a} already masked by the caller
String hardSetUpAccount(String maskedAccount) => 'account $maskedAccount';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-at air_me)
const String kHardAirtimeMyself = 'Myself';
// SIGN WORDING-DRAFT (mock-remembered-v2 setup-at air_other)
const String kHardAirtimeOther = 'Other number';
// 0.2.3 (the row line for a chosen list; 0.2.2 rows always say kHardSuggestsFromLast10)
// SIGN WORDING-DRAFT (mock-remembered-v2 page-sug row_sug): {categories} = the chosen names joined by ", "
String hardRowSuggests(String categories) => 'Suggests $categories';
// SIGN WORDING-DRAFT (mock-remembered-v2 page-open row_ask)
String hardRowAsks(String category) => 'Asks: Record as $category?';
// SIGN WORDING-DRAFT (mock-remembered-v2 page-auto row_auto_c)
String hardRowRecordsUpTo(String category, int limitCents) => 'Records as $category, up to ${kshTrim(limitCents)}';
// SIGN WORDING-DRAFT (mock-remembered-v2 page-auto row_auto_n)
String hardRowRecordsNoLimit(String category) => 'Records as $category, never asks first';
// SIGN WORDING-DRAFT (mock-remembered-v2 page-all grp_none: an open group with nobody in it)
const String kHardGroupNone = 'Nobody here yet.';
// SIGN WORDING-DRAFT (mock-remembered-v2 page-empty imp_first)
const String kHardPageFirstTime = 'Nobody set up yet. mmogo still suggests categories from history.';

// ---------------------------------------------------------------- restore review (signed 25-11 "Restore")
// SIGNED 25-11 ("Restore"): "{n} people were on Auto-record in your backup. They ask first until you check them."
// The verb agrees with the count ("1 person was").
String hardReviewLine(int n) =>
    '${peopleCount(n)} ${n == 1 ? 'was' : 'were'} on Auto-record in your backup. They ask first until you check them.';
// SIGNED 25-11 ("Restore": + Review)
const String kHardReviewButton = 'Review';
// SIGNED 25-11 ("Restore")
const String kHardReviewTitle = 'Auto-record from your backup';
// SIGNED 25-11 ("Restore")
const String kHardReviewSub = 'Tick who goes back on Auto-record. The rest ask first.';
// SIGNED 25-11 ("Restore": Save · Keep all on Ask first)
const String kHardReviewConfirm = 'Save';
// SIGNED 25-11 ("Restore": Save · Keep all on Ask first)
const String kHardReviewKeepAll = 'Keep all on Ask first';
// SIGNED 25-11 ("Restore"): "{n} people back on Auto-record."
String hardReviewToast(int n) => '${peopleCount(n)} back on Auto-record.';
// SIGNED 25-11 ("Restore")
const String kHardReviewKeptToast = 'Everyone stays on Ask first.';
// SIGNED 25-11 ("Restore"): "Backup restored. Check {n} Auto-record people."
String hardRestoreToast(int n) => 'Backup restored. Check $n Auto-record ${_peopleNoun(n)}.';
// SIGNED 25-11 ("Restore", details-off)
const String kHardRestoreOffTitle = 'Backup restored';
// SIGNED 25-11 ("Restore", details-off)
String hardRestoreOffBody(int n) =>
    'Settings for ${peopleCount(n)} were left out because Record receiver details is off. '
    'Turn it on, then restore again to bring them back.';
