/// §AUTOREAD.WAITING.REPO — the auto-read half of the Notifications data
/// contract (waiting items only; news has its own repository in
/// `lib/domain/notifications/`).
library;

import '../logic/waiting_logic.dart';
import 'waiting_item.dart';

/// What happened when a ready message was parsed.
enum ParseOutcome {
  /// Read fine: the item is now a [WaitingKind.waitingCategory] row. Nothing
  /// is saved to the ledger yet.
  parsed,

  /// The held text could not be read. The item becomes
  /// [WaitingKind.unreadable]; the user can paste it instead.
  couldNotRead,

  /// The same payment is already saved. The held message is not offered again.
  duplicate,

  /// The held message has run out or its file is missing. The item is (or
  /// becomes) [WaitingKind.gone]; the user can paste it instead.
  gone,
}

abstract class AutoReadWaitingRepository {
  /// All waiting items: the current list first, then again after every change.
  Stream<List<WaitingItem>> watch();

  /// Parse the held message [id]. See [ParseOutcome].
  Future<ParseOutcome> parse(String id);

  /// Save the waiting item [id] under [categoryId]: it becomes a ledger entry
  /// and leaves the list.
  Future<void> saveCategory(String id, String categoryId);

  /// Remove an [WaitingKind.unreadable] or [WaitingKind.gone] row (the message
  /// stays in the phone's Messages). Throws [StateError] for a readable ready
  /// item and for a waiting-category item: records are never discarded in
  /// 0.1.2. Implementations call [checkRemovable].
  Future<void> remove(String id);
}

/// The no-discard rule in one place. Throws [StateError] unless [item] is
/// unreadable or gone at [now] (an expired ready item counts as gone).
void checkRemovable(WaitingItem item, DateTime now) {
  final k = effectiveKind(item, now);
  if (k != WaitingKind.unreadable && k != WaitingKind.gone) {
    throw StateError('Only unreadable or gone items can be removed, not $k.');
  }
}
