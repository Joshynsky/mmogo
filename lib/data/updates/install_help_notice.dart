import '../prefs/update_prefs.dart';
import 'updates_inbox.dart';

/// The one-time "Install help" notice (auto-read build only; the caller guards
/// the build, this file knows nothing about flavors). It lights the bell once,
/// then stays in Notifications for good as a read item that cannot be
/// dismissed. No network.
///
/// Added at most once per install: [UpdatePrefs.keyInstallHelpNoticeAdded] is
/// set when it is added (or found already stored). The wording is not stored:
/// the row shows `install_help_copy.dart`.
class InstallHelpNotice {
  InstallHelpNotice._();

  /// Call after [UpdatesInbox.load]. Returns true when the notice was added.
  /// Never throws.
  static Future<bool> addIfNeeded(UpdatesInbox inbox, {DateTime? now}) async {
    try {
      if (await UpdatePrefs.readInstallHelpNoticeAdded()) return false;
      if (inbox.contains(Notice.installHelpTag)) {
        await UpdatePrefs.writeInstallHelpNoticeAdded();
        return false;
      }
      final added = await inbox.add(Notice(
        tag: Notice.installHelpTag,
        notes: '',
        receivedAt: now ?? DateTime.now(),
        installHelp: true,
      ));
      if (added) await UpdatePrefs.writeInstallHelpNoticeAdded();
      return added;
    } catch (_) {
      return false;
    }
  }
}
