/// §AUTOREAD.HARD_RULE_ARRIVAL_TOAST - 0.2.2 item 2 (B2d; redesign U-UNDO): the in-app message for a row
/// Auto-record wrote when mmogo opened (no tap): "{Name}, Ksh {amount} recorded as {Category}" with Undo
/// (signed, hard_rule_copy.dart `hardAutoArrived`). Undo moves the row to Recently deleted and the person STAYS
/// on Auto-record (D-U, reverses S-3; the engine side is slice B-DU), so the top pill then says "Undone. {Name}
/// stays on Auto-record." (`hardUndoStays`). Both are the top pill ([PillToast]), never a bottom snackbar; a
/// missing overlay shows nothing, the row is recorded either way. The name is the plain name: no phone number,
/// masked or not, and no digits ([autoArrivalPlainName]).
library;

import '../../ui/widgets/pill_toast.dart';
import '../ui/levels/hard_rule_copy.dart' show hardAutoArrived, hardUndoStays;
import 'queued_yes.dart';
import 'queued_yes_toast.dart' show kQueuedYesUndo;

// WORDING-MISSING -> W2 (shown only when the caller cannot name the person; today's caller passes no names, I2)
const String _kTodoArrivalName = '[PM to write: name when the person is not known]';
// WORDING-MISSING -> W2 (shown only when the caller cannot name the category; today's caller passes none, I2)
const String _kTodoArrivalCategory = '[PM to write: category when its name is not known]';

/// Looks up a label (the person's name, the category's name) for one recorded entry; null or blank = unknown.
typedef AutoArrivalLabel = String? Function(QueuedYesRecorded e);

final RegExp _numberish = RegExp(r'[0-9*]');
final RegExp _spaces = RegExp(r'\s+');

/// The plain name for the message and the undo pill: every word that holds a digit or a mask star is dropped, so
/// a name built as "Name 0722***456" (levelWho) or a bare number never shows a number. Blank = unknown (null).
String? autoArrivalPlainName(String? raw) {
  if (raw == null) return null;
  final name = raw.trim().split(_spaces).where((w) => w.isNotEmpty && !_numberish.hasMatch(w)).join(' ');
  return name.isEmpty ? null : name;
}

/// One message per recorded entry; a newer pill replaces the older one. [undo] moves that entry's row to Recently
/// deleted; the rule is left as it is (D-U). [nameOf] and [categoryOf] give the person's name and the category
/// name; until a caller passes them the W2 placeholders show (Auto-record is dormant, so nobody sees them yet).
void showAutoArrivalToasts(
  List<QueuedYesRecorded> recorded,
  Future<void> Function(QueuedYesRecorded e) undo, {
  AutoArrivalLabel? nameOf,
  AutoArrivalLabel? categoryOf,
}) {
  for (final e in recorded) {
    final name = autoArrivalPlainName(nameOf?.call(e)) ?? _kTodoArrivalName;
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
