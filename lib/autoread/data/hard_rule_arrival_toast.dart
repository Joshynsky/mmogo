/// §AUTOREAD.HARD_RULE_ARRIVAL_TOAST - 0.2.2 item 2 (B2d): the notice for a row Auto-record wrote when mmogo
/// opened (no tap), with Undo (the row moves to Recently deleted; the ledger hook then drops the person to
/// Suggested, S-3). Same pill as the queued-Yes toast; a missing overlay shows nothing, the row is recorded
/// either way. The sentence is a PLACEHOLDER key in hard_rule_copy.dart (the PM writes it, slice W).
library;

import '../../ui/widgets/pill_toast.dart';
import '../ui/levels/hard_rule_copy.dart' show kTodoAutoRecordArrivedToast;
import 'queued_yes.dart';
import 'queued_yes_toast.dart' show kQueuedYesUndo, kQueuedYesUndone;

/// One toast per recorded entry; a newer pill replaces the older one. [undo] moves that entry's row to Recently
/// deleted.
void showAutoArrivalToasts(List<QueuedYesRecorded> recorded, Future<void> Function(QueuedYesRecorded e) undo) {
  for (final e in recorded) {
    PillToast.show(
      kTodoAutoRecordArrivedToast,
      actionLabel: kQueuedYesUndo,
      onAction: () async {
        await undo(e);
        PillToast.show(kQueuedYesUndone);
      },
    );
  }
}
