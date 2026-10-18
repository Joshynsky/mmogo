import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/domain/notifications/news_logic.dart';
import 'package:mmogo/domain/notifications/notifications_repository.dart';

import '../../support/news_fakes.dart';

NewsItem item(String id, int ageMin, {DateTime? readAt, NewsKind kind = NewsKind.notice}) =>
    NewsItem(
      id: id,
      kind: kind,
      title: id,
      createdAt: kFakeNow.subtract(Duration(minutes: ageMin)),
      readAt: readAt,
    );

List<String> ids(Iterable<NewsItem> l) => l.map((i) => i.id).toList();

void main() {
  test('sortNews: unread first, then read, each newest first', () {
    final l = [
      item('readNew', 10, readAt: kFakeNow),
      item('unreadOld', 500),
      item('readOld', 900, readAt: kFakeNow),
      item('unreadNew', 20),
    ];
    expect(ids(sortNews(l)), ['unreadNew', 'unreadOld', 'readNew', 'readOld']);
  });

  test('unread view shows unread only; counts are unread only', () {
    final l = typicalNews();
    expect(ids(visibleNews(l, kFakeNow, readView: false)), ['upd1', 'n1', 'n2', 'wn1']);
    expect(unreadNewsCount(l), 4);
    expect(unreadNewsCount([]), 0);
  });

  test('read view shows read only', () {
    expect(ids(visibleNews(typicalNews(), kFakeNow, readView: true)), ['n3']);
  });

  test('30-day boundary: 29 d 23 h kept, exactly 30 d dropped', () {
    final kept = item('kept', 1, readAt: kFakeNow.subtract(const Duration(days: 29, hours: 23)));
    final edge = item('edge', 2, readAt: kFakeNow.subtract(kNewsReadRetention));
    final old = item('old', 3, readAt: kFakeNow.subtract(const Duration(days: 31)));
    expect(kNewsReadRetention, const Duration(days: 30));
    expect(ids(visibleNews([kept, edge, old], kFakeNow, readView: true)), ['kept']);
  });

  test('capCount caps above 99', () {
    expect(capCount(0), '0');
    expect(capCount(99), '99');
    expect(capCount(100), '99+');
    expect(capCount(1000), '99+');
  });

  test('swapUpdateForWhatsNew replaces the update, unread, no stale row', () {
    final items = typicalNews();
    final wn = NewsItem(
      id: 'wn2',
      kind: NewsKind.whatsNew,
      title: 'x',
      createdAt: kFakeNow,
      readAt: kFakeNow, // forced unread
    );
    final out = swapUpdateForWhatsNew(items, 'upd1', wn);
    expect(out.any((i) => i.id == 'upd1'), isFalse);
    expect(out.where((i) => i.kind == NewsKind.update), isEmpty);
    final swapped = out.firstWhere((i) => i.id == 'wn2');
    expect(swapped.isUnread, isTrue);
    expect(ids(sortNews(out)).first, 'wn2'); // newest
    expect(out.length, items.length);
  });

  test('swapUpdateForWhatsNew with unknown id changes nothing', () {
    final items = typicalNews();
    final wn = item('wn2', 0, kind: NewsKind.whatsNew);
    expect(ids(swapUpdateForWhatsNew(items, 'nope', wn)), ids(items));
  });

  test('five data sets: counts', () {
    expect(unreadNewsCount(typicalNews()), 4);
    expect(unreadNewsCount(manyNews()), 5);
    expect(unreadNewsCount(emptyNews()), 0);
    expect(unreadNewsCount(readingOffNews()), 4);
    expect(unreadNewsCount(longNews()), 6);
  });

  group('FakeNotificationsRepository', () {
    test('markRead moves an item to Read and the count falls', () async {
      final r = FakeNotificationsRepository(typicalNews());
      final NotificationsRepository repo = r;
      await repo.markRead('n1', kFakeNow);
      expect(unreadNewsCount(r.items), 3);
      expect(ids(visibleNews(r.items, kFakeNow, readView: true)), contains('n1'));
    });

    test('remove works for read and unread', () async {
      final r = FakeNotificationsRepository(typicalNews());
      await r.remove('n1');
      await r.remove('n3');
      expect(r.items.any((i) => i.id == 'n1' || i.id == 'n3'), isFalse);
    });

    test('completeUpdate swaps in a newest unread whats-new row', () async {
      final r = FakeNotificationsRepository(typicalNews());
      await r.completeUpdate('upd1');
      expect(r.items.any((i) => i.kind == NewsKind.update), isFalse);
      final first = sortNews(r.items).first;
      expect(first.id, 'wn-upd1');
      expect(first.kind, NewsKind.whatsNew);
    });

    test('watchNews emits current list then changes', () async {
      final r = FakeNotificationsRepository(typicalNews());
      final got = <int>[];
      final sub = r.watchNews().listen((l) => got.add(l.length));
      await Future<void>.delayed(Duration.zero);
      await r.remove('n1');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(got, [5, 4]);
    });
  });
}
