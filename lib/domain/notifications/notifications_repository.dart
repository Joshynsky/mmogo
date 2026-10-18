/// The news side of the Notifications page's data source. Shared by both
/// flavors; the auto-read side has its own contract.
library;

import 'news_item.dart';

abstract class NotificationsRepository {
  /// All news, read and unread, in any order (use `sortNews` / `visibleNews`).
  /// Emits the current list first, then again after every change.
  Stream<List<NewsItem>> watchNews();

  /// Marks the item [id] read at [at]. Unknown id: nothing happens.
  Future<void> markRead(String id, DateTime at);

  /// Removes the item [id], read or unread (the page calls this Dismiss for
  /// unread rows and Remove for read rows). Unknown id: nothing happens.
  Future<void> remove(String id);

  /// The update [updateId] was installed: its row is replaced by an unread
  /// What's new row (see `swapUpdateForWhatsNew`).
  Future<void> completeUpdate(String updateId);
}
