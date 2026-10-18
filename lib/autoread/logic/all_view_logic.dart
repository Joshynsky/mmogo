/// §AUTOREAD.ALLVIEW — the "All" chip: ONE ordered list of waiting and news
/// rows, per the signed mock (notifications-notes.md, "Sort rule").
library;

import '../../domain/notifications/news_item.dart';
import '../../domain/notifications/news_logic.dart' show capCount;
import '../model/waiting_item.dart';
import 'waiting_logic.dart';

/// One row of the All list: a waiting item or a news item.
sealed class NotifRow {
  const NotifRow();
}

class WaitingRow extends NotifRow {
  final WaitingItem item;
  const WaitingRow(this.item);
}

class NewsRow extends NotifRow {
  final NewsItem item;
  const NewsRow(this.item);
}

/// To parse first (ready, expiring soonest; unreadable and gone last), then
/// to categorize (newest transaction first), then UNREAD news only, newest
/// first. Read news are reached only through News > Read.
List<NotifRow> allViewOrder(
  Iterable<WaitingItem> waiting,
  Iterable<NewsItem> news,
  DateTime now,
) {
  final unread = news.where((n) => n.isUnread).toList()
    ..sort((a, b) {
      final t = b.createdAt.compareTo(a.createdAt);
      return t != 0 ? t : a.id.compareTo(b.id);
    });
  return [
    for (final w in sortReadyToParse(waiting, now)) WaitingRow(w),
    for (final w in sortWaitingCategory(waiting, now)) WaitingRow(w),
    for (final n in unread) NewsRow(n),
  ];
}

/// The All chip number: Parse + Categorize + unread news.
int allCount(Iterable<WaitingItem> waiting, Iterable<NewsItem> news, DateTime now) =>
    parseCount(waiting, now) +
    categorizeCount(waiting, now) +
    news.where((n) => n.isUnread).length;

/// [allCount] with the 99+ cap.
String allCountLabel(Iterable<WaitingItem> waiting, Iterable<NewsItem> news, DateTime now) =>
    capCount(allCount(waiting, news, now));
