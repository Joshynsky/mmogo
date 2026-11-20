/// AUTOREAD QUEUED_YES toast: tells the user that a Yes tapped on a phone alert was recorded when mmogo opened,
/// with Undo (the row moves to Recently deleted, the same soft delete as every other Undo).
/// Shown as a top pill toast on the root overlay, so it appears on whatever page is open. A missing overlay
/// (a test, a closing app) shows nothing; the entry is recorded either way.
library;

import '../../domain/format/money.dart';
import '../../ui/widgets/pill_toast.dart';
import 'queued_yes.dart';

// WORDING-DRAFT (PM signs later)
String queuedYesToast(String amount) => 'Recorded $amount from your Yes on the alert.';
// WORDING-DRAFT
const String kQueuedYesUndo = 'Undo';
// WORDING-DRAFT
const String kQueuedYesUndone = 'Moved to Recently deleted. You can restore it there within 1 hour.';

/// Shows one toast per recorded entry; the pill replaces the one before it, so the last shows. [undo] moves that
/// entry's row to Recently deleted.
void showQueuedYesToasts(List<QueuedYesRecorded> recorded, Future<void> Function(QueuedYesRecorded e) undo) {
  for (final e in recorded) {
    PillToast.show(
      queuedYesToast(kshTrim(e.amountCents)),
      actionLabel: kQueuedYesUndo,
      onAction: () async {
        await undo(e);
        PillToast.show(kQueuedYesUndone);
      },
    );
  }
}
