import '../prefs/update_prefs.dart';
import 'updates_inbox.dart';

/// The one-time "Another version of mmogo" notice (standard build only; the
/// caller guards the build, this file knows nothing about flavors). It lights
/// the bell once, then stays in Notifications for good as a read item that
/// cannot be dismissed. No network.
///
/// Added at most once per install: [UpdatePrefs.keyOtherVersionNoticeAdded] is
/// set when it is added (or found already stored), so it never comes back as
/// unread. The wording is not stored: the row shows `other_version_copy.dart`.
class OtherVersionNotice {
  OtherVersionNotice._();

  /// Call after [UpdatesInbox.load]. Returns true when the notice was added.
  /// Never throws.
  static Future<bool> addIfNeeded(UpdatesInbox inbox, {DateTime? now}) async {
    try {
      if (await UpdatePrefs.readOtherVersionNoticeAdded()) return false;
      if (inbox.contains(Notice.otherVersionTag)) {
        await UpdatePrefs.writeOtherVersionNoticeAdded();
        return false;
      }
      final added = await inbox.add(Notice(
        tag: Notice.otherVersionTag,
        notes: '',
        receivedAt: now ?? DateTime.now(),
        otherVersion: true,
      ));
      if (added) await UpdatePrefs.writeOtherVersionNoticeAdded();
      return added;
    } catch (_) {
      return false;
    }
  }
}
