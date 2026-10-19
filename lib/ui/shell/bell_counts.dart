/// §SHELL.BELL_COUNTS — what the bell shows, worked out from the news list and
/// (in the auto-read build) two waiting counts. Shared by both flavors; it
/// knows nothing about auto-read except two plain numbers.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/notifications/news_item.dart';

/// The bell's four kinds. [waiting] is the number in the top-right pill
/// (waiting for a category), [readyToParse] the number beside the diamond.
@immutable
class BellCounts {
  const BellCounts({this.update = false, this.newNotice = false, this.waiting = 0, this.readyToParse = 0});

  /// An unread update row exists (the arrow).
  final bool update;

  /// An unread notice or What's new row exists (the star).
  final bool newNotice;
  final int waiting;
  final int readyToParse;

  static const none = BellCounts();

  @override
  bool operator ==(Object other) =>
      other is BellCounts &&
      other.update == update &&
      other.newNotice == newNotice &&
      other.waiting == waiting &&
      other.readyToParse == readyToParse;

  @override
  int get hashCode => Object.hash(update, newNotice, waiting, readyToParse);
}

/// Two numbers from the waiting side (supplied by auto-read code only).
@immutable
class WaitingBellNumbers {
  const WaitingBellNumbers(this.waiting, this.readyToParse);
  final int waiting;
  final int readyToParse;
}

/// The arrow and star flags from the news list: unread only.
({bool update, bool newNotice}) newsBellFlags(Iterable<NewsItem> items) => (
      update: items.any((i) => i.isUnread && i.kind == NewsKind.update),
      newNotice: items.any((i) => i.isUnread && i.kind != NewsKind.update),
    );

/// Combines the two streams into one [BellCounts] value the bell listens to.
class BellCountsTracker {
  BellCountsTracker({required Stream<List<NewsItem>> news, Stream<WaitingBellNumbers>? waiting}) {
    _newsSub = news.listen((v) {
      final f = newsBellFlags(v);
      _update = f.update;
      _notice = f.newNotice;
      _publish();
    }, onError: (Object _) {});
    _waitingSub = waiting?.listen((v) {
      _waiting = v;
      _publish();
    }, onError: (Object _) {});
  }

  final ValueNotifier<BellCounts> value = ValueNotifier<BellCounts>(BellCounts.none);
  StreamSubscription<List<NewsItem>>? _newsSub;
  StreamSubscription<WaitingBellNumbers>? _waitingSub;
  bool _update = false;
  bool _notice = false;
  WaitingBellNumbers _waiting = const WaitingBellNumbers(0, 0);

  void _publish() => value.value = BellCounts(
        update: _update,
        newNotice: _notice,
        waiting: _waiting.waiting,
        readyToParse: _waiting.readyToParse,
      );

  void dispose() {
    _newsSub?.cancel();
    _waitingSub?.cancel();
    value.dispose();
  }
}
