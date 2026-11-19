/// §AUTOREAD.UNREADABLE_COPY - words for a held message the app could not read.
/// Every string is SIGNED (PM 13-11-2026); a changed value needs a new signature.
library;

// SIGNED (PM 13-11-2026)
const String kUnreadableTitle = 'This message could not be read';

// SIGNED (PM 19-11-2026): the row title for an M-Pesa system notice that is not a transaction.
const String kNoticeTitle = 'M-Pesa notice (not a transaction)';

// WORDING-DRAFT (PM to sign): the line under it, and the note in Details.
const String kNoticeSub = 'Nothing to paste or record. You can remove it.';
const String kNoticeNote = 'This is a message from M-Pesa, not a payment. There is nothing to paste or record.';

// SIGNED (PM 13-11-2026)
const String kUnreadableTapHint = 'Tap to see how to paste it.';

// SIGNED (PM 13-11-2026)
const String kUnreadableCodeLabel = 'M-Pesa code';

// SIGNED (PM 13-11-2026)
const String kUnreadableTimeLabel = 'Time';

// SIGNED (PM 13-11-2026)
const String kNotFound = 'Not found';

// SIGNED (PM 13-11-2026): shown when the code was found.
const String kUnreadablePasteWithCode =
    'To paste it: open Messages, find the message with this code, copy it, then paste it into mmogo.';

// SIGNED (PM 13-11-2026): shown when there is no code; the time (or the time it arrived) follows.
const String kUnreadablePasteNoCodePrefix = 'Open Messages and look for an M-Pesa message sent at';

// SIGNED (PM 13-11-2026): true when the message is removed earlier, too.
const String kUnreadableFine = 'Not read yet. Kept on this phone only, up to 24 hours.';

// SIGNED (PM 13-11-2026): the quiet line under a ready row that is described.
const String kReadyRowFine = 'Read on this phone. Nothing is saved until you tap Parse.';
