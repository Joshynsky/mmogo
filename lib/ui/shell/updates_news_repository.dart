/// §SHELL.NEWS_ADAPTER — the smallest honest [NotificationsRepository] over
/// the existing [UpdatesInbox], used until the integration slice wires the
/// real news store. Shared by both flavors (no auto-read word here).
///
/// What it covers: the inbox notices as news rows (a release notice is an
/// update row; the welcome and backup-paused notices are notice rows), the
/// real unread state, and removing a notice.
///
/// What it does NOT cover (integration must replace it):
/// - What's new rows come only from the "What's new in mmogo X" inbox notice
///   (opening it shows the pages, read-only). The swap on install is wired: when the
///   inbox load drops the update row because it is installed, the What's new item is
///   added in its place ([WhatsNewNotice.swapIfInstalled]); [completeUpdate] only removes.
/// - Marking ONE row read is kept in memory only (the inbox can only mark all
///   read); it is saved when every row is read, and lost on a restart otherwise.
/// - No 30-day read retention is stored (read rows stay until removed).
library;

import 'dart:async';

import '../../app_info.dart';
import '../../data/updates/updates_inbox.dart';
import '../../data/updates/whats_new_notice.dart';
import '../../domain/notifications/news_item.dart';
import '../../domain/notifications/notifications_repository.dart';
import '../copy/data_copy.dart';
import '../copy/install_help_copy.dart';
import '../copy/other_version_copy.dart';
import '../copy/whats_new_pager_copy.dart' show kWhatsNewPagerTitle;
import '../whats_new/whats_new_content.dart' show hasWhatsNewContentFor;

class UpdatesNewsRepository implements NotificationsRepository {
  /// [loadOnWatch] false: never start the inbox load (the bell's fallback
  /// outside the scope; the app's own start-up loads the inbox).
  UpdatesNewsRepository(
    this._inbox, {
    this.loadOnWatch = true,
    String Function()? installedVersion,
    bool Function(String versionName)? hasContentFor,
  })  : _installedVersion = installedVersion ?? (() => AppInfo.versionName),
        _hasContentFor = hasContentFor ?? hasWhatsNewContentFor {
    _inbox.unreadCount.addListener(_emit);
  }

  final UpdatesInbox _inbox;
  final bool loadOnWatch;
  final String Function() _installedVersion;
  final bool Function(String versionName) _hasContentFor;
  final Set<String> _readHere = {};
  final StreamController<List<NewsItem>> _changes = StreamController<List<NewsItem>>.broadcast();

  void dispose() {
    _inbox.unreadCount.removeListener(_emit);
    _changes.close();
  }

  List<NewsItem> _current() => [
        for (final n in _inbox.notices)
          NewsItem(
            id: n.tag,
            kind: n.whatsNew
                ? NewsKind.whatsNew
                : (n.welcome || n.backupPaused || n.otherVersion || n.installHelp)
                    ? NewsKind.notice
                    : NewsKind.update,
            title: n.welcome
                ? kWelcomeNoticeTitle
                : n.backupPaused
                    ? kBackupPausedNoticeTitle
                    : n.otherVersion
                        ? kOtherVersionNoticeTitle
                        : n.installHelp
                            ? kInstallHelpNoticeTitle
                            : n.whatsNew
                                ? kWhatsNewPagerTitle
                                : updateNoticeTitle(n.tag),
            body: n.otherVersion ? kOtherVersionNoticeBody : (n.installHelp ? kInstallHelpNoticeBody : null),
            permanent: n.otherVersion || n.installHelp,
            createdAt: n.receivedAt,
            readAt: (n.read || _readHere.contains(n.tag)) ? n.receivedAt : null,
            payload: n,
          ),
      ];

  void _emit() {
    if (!_changes.isClosed) _changes.add(_current());
  }

  @override
  Stream<List<NewsItem>> watchNews() async* {
    if (loadOnWatch) {
      // The first list is what the inbox holds now; a load that finishes later
      // (the inbox is loaded at start-up) is emitted when it is done.
      // Once loaded, an installed update swaps its row for the What's new item (0.2.1 #3).
      unawaited(_inbox.ensureLoaded().then((_) async {
        await WhatsNewNotice.swapIfInstalled(_inbox, _installedVersion(), hasContentFor: _hasContentFor);
        _emit();
      }));
    }
    yield _current();
    yield* _changes.stream;
  }

  @override
  Future<void> markRead(String id, DateTime at) async {
    if (!_inbox.notices.any((n) => n.tag == id)) return;
    _readHere.add(id);
    // The permanent notice and the What's new item are saved read at once, so a restart never lights the bell for them again.
    if (id == Notice.otherVersionTag || id == Notice.installHelpTag || id.startsWith(Notice.whatsNewTagPrefix)) await _inbox.markRead(id);
    if (_inbox.notices.every((n) => n.read || _readHere.contains(n.tag))) {
      await _inbox.markAllRead();
    }
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    if (id == Notice.otherVersionTag || id == Notice.installHelpTag) return; // permanent: never removed
    await _inbox.remove(id);
    _readHere.remove(id);
    _emit();
  }

  @override
  Future<void> completeUpdate(String updateId) => remove(updateId);
}
