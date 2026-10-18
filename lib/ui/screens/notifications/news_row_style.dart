/// Plain-data styling of a news row (unread or read). The row widgets read
/// these flags; no widget here. Shared by both flavors.
library;

import '../../../domain/notifications/news_item.dart';
import '../../copy/notifications_copy.dart';

class NewsRowStyle {
  const NewsRowStyle({
    required this.showUnreadDot,
    required this.boldTitle,
    required this.dimmed,
    required this.spokenPrefix,
  });

  final bool showUnreadDot;
  final bool boldTitle;
  final bool dimmed;
  final String spokenPrefix;
}

NewsRowStyle styleFor(NewsItem item) {
  final unread = item.isUnread;
  final String prefix;
  switch (item.kind) {
    case NewsKind.notice:
      prefix = unread ? kSpokenNewNotice : kSpokenReadNotice;
    case NewsKind.update:
      prefix = unread ? kSpokenUpdateAvailable : kSpokenReadUpdate;
    case NewsKind.whatsNew:
      prefix = unread ? kSpokenNewWhatsNew : kSpokenReadWhatsNew;
  }
  return NewsRowStyle(
    showUnreadDot: unread,
    boldTitle: unread,
    dimmed: !unread,
    spokenPrefix: prefix,
  );
}
