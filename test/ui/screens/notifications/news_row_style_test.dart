import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';
import 'package:mmogo/ui/screens/notifications/news_row_style.dart';

NewsItem _item(NewsKind k, {bool read = false}) => NewsItem(
      id: 'a',
      kind: k,
      title: 'T',
      createdAt: DateTime(2026, 10, 1),
      readAt: read ? DateTime(2026, 10, 2) : null,
    );

void main() {
  test('unread: dot, bold, not dimmed, prefixes', () {
    final want = {
      NewsKind.notice: kSpokenNewNotice,
      NewsKind.update: kSpokenUpdateAvailable,
      NewsKind.whatsNew: kSpokenNewWhatsNew,
    };
    for (final k in NewsKind.values) {
      final s = styleFor(_item(k));
      expect(s.showUnreadDot, isTrue);
      expect(s.boldTitle, isTrue);
      expect(s.dimmed, isFalse);
      expect(s.spokenPrefix, want[k]);
    }
  });

  test('read: no dot, not bold, dimmed, prefixes', () {
    final want = {
      NewsKind.notice: kSpokenReadNotice,
      NewsKind.update: kSpokenReadUpdate,
      NewsKind.whatsNew: kSpokenReadWhatsNew,
    };
    for (final k in NewsKind.values) {
      final s = styleFor(_item(k, read: true));
      expect(s.showUnreadDot, isFalse);
      expect(s.boldTitle, isFalse);
      expect(s.dimmed, isTrue);
      expect(s.spokenPrefix, want[k]);
    }
  });
}
