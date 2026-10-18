import 'dart:async';

import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/domain/notifications/news_logic.dart';
import 'package:mmogo/domain/notifications/notifications_repository.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';

/// The mock's "now": 18-10-2026 10:00.
final DateTime kFakeNow = DateTime(2026, 10, 18, 10, 0);

NewsItem _news(String id, NewsKind kind, String title, int ageMinutes, {int? readAgeDays}) =>
    NewsItem(
      id: id,
      kind: kind,
      title: title,
      createdAt: kFakeNow.subtract(Duration(minutes: ageMinutes)),
      readAt: readAgeDays == null ? null : kFakeNow.subtract(Duration(days: readAgeDays)),
    );

NewsItem _update() => _news('upd1', NewsKind.update, kUpdateRowTitle, 1440);
NewsItem _whatsNew() => _news('wn1', NewsKind.whatsNew, kWhatsNewRowTitle, 12960);

/// The NEWS rows of the five signed data sets (invented, from the mock).
List<NewsItem> typicalNews() => [
      _news('n1', NewsKind.notice, 'Back up your data', 2880),
      _news('n2', NewsKind.notice, 'Tip: remembered recipients', 5760),
      _update(),
      _whatsNew(),
      _news('n3', NewsKind.notice, 'Tip: the weekly view', 20000, readAgeDays: 5),
    ];

List<NewsItem> manyNews() => [
      _news('n1', NewsKind.notice, 'Back up your data', 2880),
      _news('n2', NewsKind.notice, 'Tip: remembered recipients', 5760),
      _news('n3', NewsKind.notice, 'Tip: the weekly view', 7000),
      _update(),
      _whatsNew(),
    ];

List<NewsItem> emptyNews() => [];

/// Reading off changes nothing for news: same rows as Typical.
List<NewsItem> readingOffNews() => typicalNews();

List<NewsItem> longNews() => [
      for (var i = 1; i <= 4; i++) _news('n$i', NewsKind.notice, 'Notice number $i', 1000 * i),
      _update(),
      _whatsNew(),
    ];

/// In-memory [NotificationsRepository].
class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository(Iterable<NewsItem> initial, {DateTime Function()? clock})
      : _items = List.of(initial),
        _clock = clock ?? (() => kFakeNow);

  List<NewsItem> _items;
  final DateTime Function() _clock;
  final _controller = StreamController<List<NewsItem>>.broadcast();

  List<NewsItem> get items => List.unmodifiable(_items);

  void _emit() => _controller.add(List.unmodifiable(_items));

  @override
  Stream<List<NewsItem>> watchNews() async* {
    yield List.unmodifiable(_items);
    yield* _controller.stream;
  }

  @override
  Future<void> markRead(String id, DateTime at) async {
    _items = [for (final i in _items) i.id == id && i.isUnread ? i.copyWith(readAt: at) : i];
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    _items = _items.where((i) => i.id != id).toList();
    _emit();
  }

  @override
  Future<void> completeUpdate(String updateId) async {
    final wn = NewsItem(
      id: 'wn-$updateId',
      kind: NewsKind.whatsNew,
      title: kWhatsNewRowTitle,
      createdAt: _clock(),
    );
    _items = swapUpdateForWhatsNew(_items, updateId, wn);
    _emit();
  }
}
