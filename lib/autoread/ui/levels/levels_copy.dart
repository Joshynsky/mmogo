/// §AUTOREAD.LEVELS.COPY: every new word of the Remembered page's second tab,
/// the level sheet and the Suggest settings rows (mock
/// `_pipeline/v0.2.1/mock-auto-record`). Every string here is WORDING-DRAFT:
/// the PM signs after the slices land. 0.2.1 has two levels only; the
/// Auto-record words are NOT here (0.2.2 adds them with the third level).
library;

// WORDING-DRAFT (mock rem_tab_auto)
const String kLevelsTabLabel = 'Suggest and auto-record';
// WORDING-DRAFT (mock: tab 1 renamed from Recipients)
const String kLevelsRecipientsTab = 'Remembered';
// WORDING-DRAFT (mock)
const String kLevelsForgetAllLabel = 'Forget all recipients';
// WORDING-DRAFT (replaces the old airtime-only note; true for 0.2.1: Forget all clears names only)
const String kLevelsForgetAllNote = 'Your airtime switches and levels are not affected.';

// WORDING-DRAFT (mock rem_helper, cut to the two 0.2.1 levels)
const String kLevelsHelper = 'Suggested is the default and changes nothing yet. Ask first asks for one tap.';
// WORDING-DRAFT (mock rem_empty)
const String kLevelsEmpty = 'Nobody yet. They appear here after you record a message to them.';
// WORDING-DRAFT (mock rem_fnone)
const String kLevelsFilterEmpty = 'Nobody at this level yet.';
// WORDING-DRAFT (mock rem_nohist)
const String kLevelsNoHistory = 'No history yet';
// WORDING-DRAFT
const String kLevelsLoadFailed = 'Could not load this list.';

// WORDING-DRAFT (mock level tags)
const String kLevelSuggested = 'Suggested';
// WORDING-DRAFT
const String kLevelAskFirst = 'Ask first';
// WORDING-DRAFT (mock filter "All")
const String kLevelFilterAll = 'All';
// WORDING-DRAFT (spoken name of the filter group)
const String kLevelFilterGroup = 'Level filter';
// WORDING-DRAFT (spoken name of the type chip group)
const String kTypeChipsGroup = 'Types';

// WORDING-DRAFT: the short code (the tag on each row) and the spoken/readable name per type (the chip text; the Airtime chip takes the type name from source_types.dart).
const String kChipSendMoney = 'SM';
const String kChipPayBill = 'PB';
const String kChipBuyGoods = 'BG';
const String kChipWithdrawal = 'W';
const String kChipPochi = 'P';
const String kSpokenSendMoney = 'Send Money';
const String kSpokenPayBill = 'Paybill';
const String kSpokenBuyGoods = 'Buy Goods';
const String kSpokenWithdrawal = 'Withdrawals';
const String kSpokenPochi = 'Pochi';

/// WORDING-DRAFT: spoken name of a muted chip.
String chipComingLaterSpoken(String name) => '$name, coming later';

/// WORDING-DRAFT: spoken name of a person's level button.
String levelButtonSpoken(String name, String level) => '$name: $level. Change';

// ---- Level sheet (mock rule_t, rule_cat, notes) ----
/// WORDING-DRAFT
String levelSheetTitle(String name) => 'What should mmogo do for $name?';
// WORDING-DRAFT (the row that opens the category sheet)
const String kLevelSheetCategory = 'Choose a category';
// WORDING-DRAFT (title of the small category sheet)
const String kCategoryPickTitle = 'Choose a category';
// WORDING-DRAFT (the row's value while none is chosen)
const String kLevelSheetNoneChosen = 'None chosen';
// WORDING-DRAFT (mock rule_suggest_note, "Suggest" renamed Suggested, no stored rule)
String levelSheetSuggestedNote(String name) =>
    'Suggested: the default. Nothing records without a tap and no rule is stored.';
// WORDING-DRAFT (mock rule_soft_note)
const String kLevelSheetAskFirstNote = 'Ask first: mmogo asks with one tap each time.';
// WORDING-DRAFT
const String kLevelSheetPickCategory = 'Choose a category for Ask first.';
// WORDING-DRAFT
const String kLevelSheetNoCategories = 'No categories to choose from.';
// WORDING-DRAFT
const String kLevelSheetCapReached = 'Too many people have a level. Forget one to add another.';
// WORDING-DRAFT
const String kLevelSheetSaveFailed = 'Could not save. Try again.';
// WORDING-DRAFT (mock save/cancel)
const String kLevelSheetSave = 'Save';
const String kLevelSheetCancel = 'Cancel';

// ---- Help sheet: the page's ONE "?" while this tab shows. Levels first, then the rules per type. ----
// WORDING-DRAFT (title for the second tab's "?")
const String kLevelsHelpTitle = 'About Suggest and auto-record';
// WORDING-DRAFT
const String kLevelsHelpLevels =
    'For each person or account, choose what mmogo does. Suggested (the default) changes nothing; nothing records without a tap. Ask first asks "Record as [Category]?" with one tap. The type buttons show one type at a time.';
// WORDING-DRAFT (heading line per type)
const String kLevelsHelpHeadSend = 'Send Money';
const String kLevelsHelpHeadPaybill = 'Paybill';
const String kLevelsHelpHeadBuyGoods = 'Buy Goods';
const String kLevelsHelpHeadPochi = 'Pochi';
const String kLevelsHelpHeadWithdrawals = 'Withdrawals';
// WORDING-DRAFT (rule text for the four receiver types)
const String kLevelsHelpReceiverRule = 'Each person or account can be Suggested or Ask first. Ask first uses one category, from the categories of this type.';
// WORDING-DRAFT (Pochi lists remembered names only)
const String kLevelsHelpPochiRule = 'Only Pochi names you asked mmogo to remember are listed. Each can be Suggested or Ask first, with a Pochi category.';
// WORDING-DRAFT
const String kLevelsHelpWithdrawalsRule = 'Coming in a later version.';
// WORDING-DRAFT (airtime has two switches instead of levels)
const String kLevelsHelpAirtimeIntro = 'Airtime has two switches instead of levels: For myself and For another number.';
// WORDING-DRAFT (moved from under the switches; was autoRecordExplainTap, now says both labels)
const String kLevelsHelpAirtimeTap = 'You tap Parse on each message, then mmogo files it under the category of the switch: For myself or For another number.';
// WORDING-DRAFT
const String kLevelsHelpPrivacy = 'Everything here stays on this phone. It is in your backups, so keep your backup files private. mmogo never sends it anywhere.';
// WORDING-DRAFT (spoken name of the "?" is the page's: About this page)

// ---- Settings rows (mock set_sugg, set_after) ----
// WORDING-DRAFT (section label)
const String kSuggestSectionLabel = 'Suggestions';
// WORDING-DRAFT (0.2.1 offers "Ask first", not Auto-record)
const String kSuggestSwitchLabel = 'Offer Ask first';
// WORDING-DRAFT
const String kSuggestSwitchSub = 'After you record the same person and category several times in a row, mmogo offers to ask first next time.';
// WORDING-DRAFT (mock set_after)
const String kSuggestAfterLabel = 'Offer after N in a row';
// WORDING-DRAFT (mock set_after_sub)
const String kSuggestAfterSub = 'Successful records in a row, 2 to 10.';
/// WORDING-DRAFT (mock set_after_opt)
String suggestAfterOption(int n) => '$n in a row';
// WORDING-DRAFT
const String kSuggestSaveFailed = 'Could not save that setting.';
