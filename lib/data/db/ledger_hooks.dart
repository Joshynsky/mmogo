/// §DATA.DB.LEDGER_HOOKS - one small place where the app learns that a ledger row was added, edited,
/// deleted (moved to Recently deleted) or restored, without the data layer knowing who listens.
///
/// Nothing is set in the standard build, so every call here does nothing. The auto-read build sets the
/// four callbacks once at start (the rules and the history summary follow the ledger). A callback
/// runs on its own, after the database call returned; it can never fail or slow the save, and a
/// failure inside it is dropped. It receives only the row number.
library;

import 'dart:async';

class LedgerHooks {
  LedgerHooks._();

  /// A row was added (Add, a saved waiting item).
  static void Function(int id)? onInserted;

  /// A row's fields were edited (the category may have changed).
  static void Function(int id)? onEdited;

  /// A row was moved to Recently deleted (an Undo or a delete).
  static void Function(int id)? onRemoved;

  /// A row came back from Recently deleted.
  static void Function(int id)? onRestored;

  /// Many rows may have changed at once (a restore from a backup).
  static void Function()? onBulk;

  static void inserted(int id) => _fire(onInserted, id);
  static void edited(int id) => _fire(onEdited, id);
  static void removed(int id) => _fire(onRemoved, id);
  static void restored(int id) => _fire(onRestored, id);

  static void bulkChanged() {
    final f = onBulk;
    if (f == null) return;
    unawaited(Future<void>(() => f()).catchError((Object _) {}));
  }

  static void _fire(void Function(int id)? f, int id) {
    if (f == null) return;
    unawaited(Future<void>(() => f(id)).catchError((Object _) {}));
  }
}
