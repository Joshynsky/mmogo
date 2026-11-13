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

// SIGNED (PM 13-11-2026)
const String kChooseLaterChip = 'Later';

// SIGNED (PM 13-11-2026)
/// What a screen reader says for the row.
String chooseCategorySpoken(String description) => 'Choose a category for $description';
