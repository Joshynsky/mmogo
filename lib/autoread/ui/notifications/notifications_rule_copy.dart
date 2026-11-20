/// §AUTOREAD.NOTIFICATIONS_RULE_COPY - words of the rule parts of the Notifications page
/// (Suggestions, Ask first rows, Nothing waiting). 0.2.1: levels Suggested and Ask first only.
/// Every string here is WORDING-DRAFT until the PM signs it.
library;

// WORDING-DRAFT
/// Heading of the suggestions section (last section of To do).
const String kHeadingSuggestions = 'Suggestions';

// WORDING-DRAFT
/// Title of the offer card.
const String kSuggestionTitle = 'Ask first next time?';

// WORDING-DRAFT
/// Body of the offer card ([n] records in a row as [cat]).
String suggestionBody(String name, String cat, int n) =>
    'You’ve recorded $name as $cat $n times in a row. Should mmogo ask you first next time?';

// WORDING-DRAFT
/// Body when the category name is not known.
String suggestionBodyNoCat(String name, int n) =>
    'You’ve recorded $name in the same category $n times in a row. Should mmogo ask you first next time?';

// WORDING-DRAFT
const String kSuggestionNotNow = 'Not now';

// WORDING-DRAFT
/// The confirm button: sets the person to Ask first.
const String kSuggestionConfirm = 'Ask first';

// WORDING-DRAFT
/// Quiet note when the rule could not be saved (the list of remembered people is full).
const String kSuggestionNotSaved = 'Could not save this. Try again.';

// WORDING-DRAFT
/// Heading of the Ask first rows.
const String kHeadingToConfirm = 'To confirm';

// WORDING-DRAFT
/// Title of an Ask first row.
String askFirstTitle(String cat) => 'Record as $cat?';

// WORDING-DRAFT
const String kAskFirstChange = 'Change category';

// WORDING-DRAFT
const String kAskFirstLater = 'Categorize later';

// WORDING-DRAFT
const String kAskFirstYes = 'Yes';

// WORDING-DRAFT
/// The quiet line (top) and the bold line (bottom card) when nothing waits.
const String kNothingWaiting = 'Nothing waiting';

// WORDING-DRAFT
/// Spoken words for an Ask first row, before its title.
const String kSpokenAskFirst = 'Waiting for your answer';
