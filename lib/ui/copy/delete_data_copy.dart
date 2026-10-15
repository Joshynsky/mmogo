/// §COPY.DELETE_DATA — words for Delete data and the stale-Undo case (0.1.2
/// S9b-1). S9b-2 (the sheet) adds the rest of its words to THIS file.
///
/// CB6 bans these words anywhere in the Delete data screens: "Erases",
/// "left on this phone", "authentication", and a "Hi," greeting. The mock
/// `settings.html` lines 320-335 still use some of them and must NOT be
/// copied. Nothing here ever carries a name, phone number, code or amount.
library;

/// Result of Delete data that did not finish (Try again re-runs it).
const kDeleteDataNotFinished = 'Delete data did not finish. Try again.';

/// The delete changed nothing (the check after it found rows left, so it was
/// rolled back).
const kDeleteDataNothingDeleted = 'Nothing was deleted';

/// Another restore / undo / delete / reset is running.
const kDataOpBusy = 'Another change is in progress, try again';

/// A stale Undo or Restore: the entry is gone (purged, or Delete data).
const kEntryNoLongerThere = 'That entry is no longer there';
