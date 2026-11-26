/// §AUTOREAD.HARD_RULE_ARRIVAL_TOAST - 0.2.2 item 2 (B2d; redesign U-UNDO): the in-app message for a row
/// Auto-record wrote when mmogo opened (no tap): "{Name}, Ksh {amount} recorded as {Category}" with Undo
/// (signed, hard_rule_copy.dart `hardAutoArrived`). Undo moves the row to Recently deleted and the person STAYS
/// on Auto-record (D-U, reverses S-3; the engine side is slice B-DU), so the top pill then says "Undone. {Name}
/// stays on Auto-record." (`hardUndoStays`). Both are the top pill ([PillToast]), never a bottom snackbar; a
/// missing overlay shows nothing, the row is recorded either way. The name is the plain name: no phone number,
/// masked or not, and no digits ([autoArrivalPlainName]).
library;

import '../../ui/widgets/pill_toast.dart';
import '../logic/plain_name.dart' show pillPersonName, plainPersonName;
import '../ui/levels/hard_rule_copy.dart' show hardAutoArrived, hardUndoStays;
import 'queued_yes.dart';
import 'queued_yes_toast.dart' show kQueuedYesUndo;

// The W2 placeholder for an unknown name now lives in ../logic/plain_name.dart (pillPersonName; I2c, unchanged text).
// WORDING-MISSING -> W2 (shown only when the caller cannot name the category: its name could not be read)
const String _kTodoArrivalCategory = '[PM to write: category when its name is not known]';

/// Looks up a label (the person's name, the category's name) for one recorded entry; null or blank = unknown.
typedef AutoArrivalLabel = String? Function(QueuedYesRecorded e);

/// The plain name for the message and the undo pill: every word that holds a digit or a mask star is dropped, so
/// a name built as "Name 0722***456" (levelWho) or a bare number never shows a number. Blank = unknown (null).
/// Same as the shared [plainPersonName] (I2c), kept under this name for its callers.
String? autoArrivalPlainName(String? raw) => plainPersonName(raw);

/// The labels the app's import passes (I2): [payeeByItem] = waiting item id -> the payee name on that item (as
/// the SMS gave it, read BEFORE the import removed the item; [showAutoArrivalToasts] makes it plain), and
/// [categoryById] = category id -> its name. A missing entry = unknown (the W2 placeholder shows).
({AutoArrivalLabel nameOf, AutoArrivalLabel categoryOf}) autoArrivalLabels(
        Map<String, String?> payeeByItem, Map<int, String> categoryById) =>
    (nameOf: (e) => payeeByItem[e.itemId], categoryOf: (e) => categoryById[e.categoryId]);

/// One message per recorded entry; a newer pill replaces the older one. [undo] moves that entry's row to Recently
/// deleted; the rule is left as it is (D-U). [nameOf] and [categoryOf] give the person's name and the category
/// name (the app passes them through [autoArrivalLabels]); an unknown one shows its W2 placeholder.
void showAutoArrivalToasts(
  List<QueuedYesRecorded> recorded,
  Future<void> Function(QueuedYesRecorded e) undo, {
  AutoArrivalLabel? nameOf,
  AutoArrivalLabel? categoryOf,
}) {
  for (final e in recorded) {
    final name = pillPersonName(nameOf?.call(e));
    final category = categoryOf?.call(e)?.trim();
    PillToast.show(
      hardAutoArrived(name, e.amountCents, (category == null || category.isEmpty) ? _kTodoArrivalCategory : category),
      actionLabel: kQueuedYesUndo,
      onAction: () async {
        await undo(e);
        PillToast.show(hardUndoStays(name));
      },
    );
  }
}
