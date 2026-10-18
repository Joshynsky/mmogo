@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/all_view_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
// C0a's real NewsItem. Until C0a is merged, a temporary copy of
// The real NewsItem (lib/domain/notifications/news_item.dart, slice C0a) is used.
import 'package:mmogo/domain/notifications/news_item.dart';

import '../support/waiting_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 10, 0);

  NewsItem news(String id, NewsKind k, Duration age, {bool read = false}) => NewsItem(
        id: id,
        kind: k,
        title: id,
        createdAt: now.subtract(age),
        readAt: read ? now : null,
      );

  final waiting = waitingSet(WaitingDataSet.typical, now).items;
  final newsItems = [
    news('notice-old', NewsKind.notice, const Duration(days: 4)),
    news('update', NewsKind.update, const Duration(hours: 24)),
    news('whats-new', NewsKind.whatsNew, const Duration(days: 9)),
    news('notice-new', NewsKind.notice, const Duration(hours: 48)),
    news('read-one', NewsKind.notice, const Duration(days: 14), read: true),
  ];

  test('order: to parse, then to categorize, then unread news only', () {
    final rows = allViewOrder(waiting, newsItems, now);
    final kinds = rows
        .map((r) => switch (r) {
              WaitingRow(:final item) => item.kind.name,
              NewsRow() => 'news',
            })
        .toList();
    expect(kinds, [
      'readyToParse', 'readyToParse', 'readyToParse', 'gone', // to parse group, gone last
      'waitingCategory', 'waitingCategory', 'waitingCategory',
      'news', 'news', 'news', 'news',
    ]);
  });

  test('parse group is soonest-expiring first', () {
    final rows = allViewOrder(waiting, const [], now).whereType<WaitingRow>().toList();
    final ready = rows.take(3).map((r) => r.item.heldAt).toList();
    expect(ready, [...ready]..sort((a, b) => a.compareTo(b)));
  });

  test('categorize group is newest transaction first', () {
    final rows = allViewOrder(waiting, const [], now).whereType<WaitingRow>().skip(4).toList();
    final times = rows.map((r) => r.item.parsed!.transactionOccurredAt).toList();
    expect(times, [...times]..sort((a, b) => b.compareTo(a)));
  });

  test('news: unread only, newest first; read news never appear', () {
    final rows = allViewOrder(const <WaitingItem>[], newsItems, now).whereType<NewsRow>().toList();
    expect(rows.map((r) => r.item.id), ['update', 'notice-new', 'notice-old', 'whats-new']);
  });

  test('the All count is Parse + Categorize + unread news', () {
    expect(allCount(waiting, newsItems, now), 3 + 3 + 4);
    expect(allCountLabel(waiting, newsItems, now), '10');
  });

  test('the All count carries the 99+ cap', () {
    final many = waitingSet(WaitingDataSet.many, now).items;
    expect(allCountLabel(many, newsItems, now), '99+');
  });

  test('empty in, empty out', () {
    expect(allViewOrder(const <WaitingItem>[], const <NewsItem>[], now), isEmpty);
  });
}
