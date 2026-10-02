import '../prefs/update_prefs.dart';
import 'updates_inbox.dart';

/// B49: the greeting notice on the first launch of 0.1.1. It tells the user
/// that update checks are on and how to switch them off. No network.
///
/// Added only when ALL hold: the inbox has never been stored, the update
/// check has never run, and the switch is still on. After it is added the
/// inbox exists in storage, so it is never added twice, whether or not the
/// user reads it. The text is not stored: the Updates page shows the wording
/// from `data_copy.dart` for a notice with `welcome: true`.
class WelcomeNotice {
  WelcomeNotice._();

  /// Call after [UpdatesInbox.load] and BEFORE the first update check.
  /// Returns true when the notice was added. Never throws.
  static Future<bool> addIfFirstLaunch(UpdatesInbox inbox, {DateTime? now}) async {
    try {
      if (inbox.hadStoredValue || inbox.notices.isNotEmpty) return false;
      if (await UpdatePrefs.readLastCheckAt() != null) return false;
      if (!await UpdatePrefs.readEnabled()) return false;
      return await inbox.add(Notice(
        tag: Notice.welcomeTag,
        notes: '',
        receivedAt: now ?? DateTime.now(),
        welcome: true,
      ));
    } catch (_) {
      return false;
    }
  }
}
