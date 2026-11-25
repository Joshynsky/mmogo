/// §AUTOREAD.CATEGORIZE_COPY — the Categorize sheet's fixed words (split from categorize_sheet.dart, 0.2.2).
/// Re-exported by categorize_sheet.dart, so existing imports keep working.
library;

// Strings. From the Add screen: hint, "Add", "+ New", duplicate text. From the
// signed mock: heading (kActionCategorize), "Category", "Choose a category to
// save", "Save in X", "Close", the 100-character text, the detail labels.
// NOT IN MOCK or Add (plainest words): the empty-name text, the two failure texts.
const String kCategorizeCategoryLabel = 'Category';
// WORDING-DRAFT (item 0 Part 1, 24-11): shown only when the person has suggested chips.
const String kCategorizeSuggestedLabel = 'Suggested';
const String kCategorizeAllLabel = 'All categories';
const String kCategorizeNewPill = '+ New';
const String kCategorizeNewHint = 'New category name';
const String kCategorizeNewAdd = 'Add';
const String kCategorizeClose = 'Close';
const String kCategorizeChoosePrompt = 'Choose a category to save';
String categorizeSaveIn(String name) => 'Save in $name';
const String kCategorizeTooLong =
    'A category name can be up to 100 characters.';
String categorizeDuplicate(String name) =>
    'A category named "$name" already exists.';
const String kCategorizeEmptyName =
    'Type a name for the category.'; // NOT IN MOCK
const String kCategorizeLoadFailed =
    'Could not load the categories.'; // NOT IN MOCK
const String kCategorizeNewFailed =
    'Could not create the category. Try again.'; // NOT IN MOCK
const String kCategorizeSaveFailed =
    'Could not save. Try again.'; // NOT IN MOCK
const String kCategorizeCheckThis = 'Check this one.'; // mock flag box
/// SIGNED (PM 13-11-2026): under the one fixed category of an airtime item.
const String kCategorizeAirtimeFixed = 'Set when the airtime was read. It cannot be changed.';
// SIGNED (PM 13-11-2026): the labels of the details block.
const String kCategorizeLabelType = 'Type';
const String kCategorizeLabelAmount = 'Amount';
const String kCategorizeLabelPaidTo = 'Paid to';
const String kCategorizeLabelDate = 'Date';
const String kCategorizeLabelCost = 'Transaction cost';
