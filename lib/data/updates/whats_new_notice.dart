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

  /// The swap on install (0.2.1 #3): when the last load dropped a release notice because the update
  /// is now installed, and the installed version has What's new pages ([hasContentFor]), the
  /// "What's new in mmogo X" item takes the update row's place. Returns true when it was added.
  static Future<bool> swapIfInstalled(
    UpdatesInbox inbox,
    String installed, {
    required bool Function(String versionName) hasContentFor,
    DateTime? now,
  }) async {
    try {
      await inbox.ensureLoaded();
      if (inbox.prunedReleaseTags.isEmpty || !hasContentFor(installed)) return false;
      return await addIfDue(inbox, installed, now: now);
    } catch (_) {
      return false;
    }
  }
}
