/// §AUTOREAD.CHOOSE_CATEGORY_COPY - words of the choose-a-category row.
/// Every string is SIGNED (PM 13-11-2026). "+ New" and the
/// load-failed line are the Categorize sheet's own constants, not repeated here.
library;

// SIGNED (PM 13-11-2026)
const String kChooseCategoryTitle = 'Choose a category';

// SIGNED (PM 13-11-2026)
/// Second line of a freshly read row.
String chooseCategoryFresh(String description) => '$description. Read. Not recorded yet.';

// SIGNED (PM 13-11-2026)
/// Second line of a row that was moved to To categorize (no second sentence).
String chooseCategoryLater(String description) => '$description.';

// WORDING-DRAFT (F8, PM 24-11: replaces the signed 'Later'; one word everywhere: 'Not now')
const String kChooseLaterChip = 'Not now';

// WORDING-DRAFT (item 0 Part 1, 24-11): the Undo pill after a suggested chip recorded at once, e.g. 'Recorded Ksh 300 as Debts.'
String chipRecordedToast(String amount, String category) => 'Recorded $amount as $category.';

// WORDING-DRAFT: after Undo of a chip-recorded entry.
const String kChipUndoneToast = 'Undone. Moved to Recently deleted.';

// WORDING-DRAFT: what a screen reader says for a suggested chip on the card.
String chipSpoken(String category) => 'Record as $category';

// SIGNED (PM 13-11-2026)
/// What a screen reader says for the row.
String chooseCategorySpoken(String description) => 'Choose a category for $description';
