/// Pure news logic for the Notifications page. No clock reads: callers pass
/// `now`. Shared by both flavors.
library;

import 'news_item.dart';

/// A read news item leaves the Read view this long after it was read.
const Duration kNewsReadRetention = Duration(days: 30);

/// Unread first, then read; each group newest first, except that a read
/// permanent item is last of all. Returns a new list.
List<NewsItem> sortNews(Iterable<NewsItem> items) {
  final list = items.toList();
  list.sort((a, b) {
    if (a.isUnread != b.isUnread) return a.isUnread ? -1 : 1;
    if (!a.isUnread && a.permanent != b.permanent) return a.permanent ? 1 : -1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return list;
}

/// Unread view: unread items only. Read view: read items only, without those
/// read [kNewsReadRetention] ago or more (a permanent item is never left out). Sorted as [sortNews].
List<NewsItem> visibleNews(
  Iterable<NewsItem> items,
  DateTime now, {
  required bool readView,
}) {
  return sortNews(items.where((i) {
    if (!readView) return i.isUnread;
    final at = i.readAt;
    if (at == null) return false;
    if (i.permanent) return true;
    return now.difference(at) < kNewsReadRetention;
  }));
}

/// The number the News chip, heading and bell show: unread items only.
int unreadNewsCount(Iterable<NewsItem> items) =>
    items.where((i) => i.isUnread).length;

/// "99+" above 99. Shared with the waiting counts.
String capCount(int n) => n > 99 ? '99+' : '$n';

/// Replaces the update [updateId] by [whatsNewItem], which is made unread. The
/// caller gives it a `createdAt` of now, so it is the newest. No stale update
/// row is left. If [updateId] is not in [items], the list is returned unchanged.
List<NewsItem> swapUpdateForWhatsNew(
  List<NewsItem> items,
  String updateId,
  NewsItem whatsNewItem,
) {
  if (!items.any((i) => i.id == updateId)) return List.of(items);
  final fresh = whatsNewItem.copyWith(clearReadAt: true);
  return [for (final i in items) i.id == updateId ? fresh : i];
}
