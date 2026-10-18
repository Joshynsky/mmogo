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
  });

  final String id;
  final NewsKind kind;
  final String title;
  final DateTime createdAt;

  /// When the user read it; null while unread.
  final DateTime? readAt;
  final Object? payload;

  bool get isUnread => readAt == null;

  NewsItem copyWith({DateTime? readAt, bool clearReadAt = false}) => NewsItem(
        id: id,
        kind: kind,
        title: title,
        createdAt: createdAt,
        readAt: clearReadAt ? null : (readAt ?? this.readAt),
        payload: payload,
      );
}
