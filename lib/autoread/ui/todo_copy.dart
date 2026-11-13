/// §AUTOREAD.TODO_COPY - words of the To do page. Names are frozen; the
/// Values are SIGNED (PM 13-11-2026).
library;

// SIGNED (PM 13-11-2026)
/// Chip label.
const String kTodoChipLabel = 'To do';

// SIGNED (PM 13-11-2026)
/// Empty card title.
const String kTodoEmptyTitle = 'All caught up';

// SIGNED (PM 13-11-2026)
/// Empty card body.
const String kTodoEmptyBody = 'No messages to parse and nothing to categorize. New M-Pesa messages show up here.';

// SIGNED (PM 13-11-2026)
/// Spoken chip name; the page adds the count ("To do, 3").
const String kTodoChipSpoken = 'To do';

// SIGNED (PM 13-11-2026)
/// Quiet note after Later.
const String kNoteMovedToCategorize = 'Moved to To categorize.';

// SIGNED (PM 13-11-2026)
/// Quiet note after a category was chosen in the row ([title] = "Sent Ksh 200 to X").
String noteRecorded(String title) => 'Recorded: $title.';

// SIGNED (PM 13-11-2026)
/// Quiet note after Parse all read [n] messages.
String noteReadMany(int n) => 'Read $n messages. Choose a category for each, or Later.';
