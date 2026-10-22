/// A thin view model over the news the Notifications page shows: notices,
/// updates and What's new. Shared by both flavors (no auto-read import).
library;

/// What a news row is.
enum NewsKind { notice, update, whatsNew }

/// One news row. [payload] is opaque here: the adapter that builds the item
/// puts the original data in it (for a notice, the `Notice` of
/// `lib/data/updates/updates_inbox.dart`; for What's new, its release data),
/// and the screen casts it back when the row is opened.
class NewsItem {
  const NewsItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.readAt,
    this.payload,
    this.body,
    this.permanent = false,
  });

  final String id;
  final NewsKind kind;
  final String title;
  final DateTime createdAt;

  /// When the user read it; null while unread.
  final DateTime? readAt;
  final Object? payload;

  /// An optional line of text under the title (the other-version notice).
  final String? body;

  /// True for an item that stays for good: it cannot be dismissed or removed,
  /// is not dropped after the read-retention days, and sorts last once read.
  final bool permanent;

  bool get isUnread => readAt == null;

  NewsItem copyWith({DateTime? readAt, bool clearReadAt = false}) => NewsItem(
        id: id,
        kind: kind,
        title: title,
        createdAt: createdAt,
        readAt: clearReadAt ? null : (readAt ?? this.readAt),
        payload: payload,
        body: body,
        permanent: permanent,
      );
}
