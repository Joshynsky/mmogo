import 'updates_inbox.dart';

/// The in-app "What's new in mmogo X" item in the bell (0.1.2). Added once per
/// version, at the moment the What's new page is due (the same gate as the
/// first-open page), so it is there even when the page is closed with Back. It
/// stays in Notifications until the user removes it. The wording is not
/// stored: the row shows the page title. No network.
class WhatsNewNotice {
  WhatsNewNotice._();

  /// Returns true when the notice was added. Never throws.
  static Future<bool> addIfDue(UpdatesInbox inbox, String version, {DateTime? now}) async {
    try {
      await inbox.ensureLoaded();
      final tag = Notice.whatsNewTagFor(version);
      if (inbox.contains(tag)) return false;
      return await inbox.add(Notice(
        tag: tag,
        notes: '',
        receivedAt: now ?? DateTime.now(),
        whatsNew: true,
      ));
    } catch (_) {
      return false;
    }
  }
}