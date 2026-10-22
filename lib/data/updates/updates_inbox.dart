import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_info.dart';
import 'release_info.dart';
import 'untrusted_text.dart';

/// One "a newer mmogo exists" message. [notes] is already sanitised.
class Notice {
  const Notice({
    required this.tag,
    required this.notes,
    required this.receivedAt,
    this.read = false,
    this.welcome = false,
    this.backupPaused = false,
    this.otherVersion = false,
    this.whatsNew = false,
  });

  /// The tag of the greeting notice (B49). It is not a version.
  static const welcomeTag = 'Welcome';

  /// The tag of the "auto-backup is paused" notice (B52). Not a version.
  static const backupPausedTag = 'BackupPaused';

  /// The tag of the "other version of mmogo" notice (standard build only). Not
  /// a version.
  static const otherVersionTag = 'OtherVersion';

  /// The tag prefix of the "What's new in mmogo X" notice; the version follows
  /// it. Not a release (never an update row).
  static const whatsNewTagPrefix = 'WhatsNew:';
  static String whatsNewTagFor(String version) => '$whatsNewTagPrefix$version';

  final String tag;
  final String notes;
  final DateTime receivedAt;
  final bool read;

  /// The first-launch greeting: not a release, so no "See what's new" button
  /// and it is never removed for being older than the installed version.
  final bool welcome;

  /// Auto-backup paused itself (B52): not a release either, opens Backup and
  /// restore instead of the mmogo page. Its wording is not stored.
  final bool backupPaused;

  /// The one-time pointer to the second version of mmogo. Permanent: once read
  /// it stays in the list as a read item, it is never dismissed or removed. Its
  /// wording is not stored (see `other_version_copy.dart`).
  final bool otherVersion;

  /// The in-app pointer to the What's new pages of one version (added once per
  /// version, when the pages are due). Opening it shows the pages read-only.
  /// Its wording is not stored.
  final bool whatsNew;

  Notice copyWith({bool? read}) => Notice(
        tag: tag,
        notes: notes,
        receivedAt: receivedAt,
        read: read ?? this.read,
        welcome: welcome,
        backupPaused: backupPaused,
        otherVersion: otherVersion,
        whatsNew: whatsNew,
      );

  Map<String, Object?> toJson() => {
        'tag': tag,
        'notes': notes,
        'receivedAt': receivedAt.millisecondsSinceEpoch,
        'read': read,
        if (welcome) 'welcome': true,
        if (backupPaused) 'backup_paused': true,
        if (otherVersion) 'other_version': true,
        if (whatsNew) 'whats_new': true,
      };

  /// `null` when the stored map is unusable (wrong types, bad tag).
  static Notice? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final tag = raw['tag'];
    final notes = raw['notes'];
    final at = raw['receivedAt'];
    final read = raw['read'];
    final welcome = raw['welcome'] == true;
    final backupPaused = raw['backup_paused'] == true;
    if (tag is! String) return null;
    final otherVersion = raw['other_version'] == true;
    final whatsNew = raw['whats_new'] == true;
    if ((welcome ? 1 : 0) + (backupPaused ? 1 : 0) + (otherVersion ? 1 : 0) + (whatsNew ? 1 : 0) > 1) return null;
    if (welcome) {
      if (tag != welcomeTag) return null;
    } else if (backupPaused) {
      if (tag != backupPausedTag) return null;
    } else if (otherVersion) {
      if (tag != otherVersionTag) return null;
    } else if (whatsNew) {
      if (!tag.startsWith(whatsNewTagPrefix) || ReleaseInfo.parseVersion(tag.substring(whatsNewTagPrefix.length)) == null) return null;
    } else if (ReleaseInfo.parseVersion(tag) == null) {
      return null;
    }
    if (at is! int) return null;
    return Notice(
      tag: tag,
      notes: notes is String ? UntrustedText.sanitize(notes) : '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(at),
      read: read == true,
      welcome: welcome,
      backupPaused: backupPaused,
      otherVersion: otherVersion,
      whatsNew: whatsNew,
    );
  }
}

/// The Updates inbox (Lead ruling F1): a JSON list in `shared_preferences`
/// key [storageKey], not in SQLite, so it is outside every backup and
/// restore. Newest first, one notice per release, at most [maxNotices]
/// (the oldest is dropped). A corrupt or oversized stored value is treated
/// as empty. Notices that are not newer than the installed version are
/// removed at [load] (the user has updated).
class UpdatesInbox {
  UpdatesInbox({String Function()? installedVersion})
      : _installedVersion = installedVersion ?? (() => AppInfo.versionName);

  static final UpdatesInbox instance = UpdatesInbox();

  static const storageKey = 'updates_inbox_v1';
  static const maxNotices = 10;

  /// Anything larger than this is not something this app wrote.
  static const maxStoredChars = 64 * 1024;
  static const _prefsTimeout = Duration(seconds: 2);

  final String Function() _installedVersion;

  /// The unread count the bell listens to.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  List<Notice> _notices = const [];
  Future<void>? _loading;
  bool _hadStoredValue = false;

  /// True when the last [load] found any stored inbox value (even an empty
  /// or unreadable one). B49 shows the welcome notice only when it is false.
  bool get hadStoredValue => _hadStoredValue;

  /// Reset app (0.1.2 S9b-1): forgets the cached notices and the "loaded"
  /// state so the next [ensureLoaded] reads the (now wiped) storage again.
  /// Writes nothing.
  void resetForRestart() {
    _notices = const [];
    _loading = null;
    _hadStoredValue = false;
    unreadCount.value = 0;
  }

  /// Loads once; later calls share the first load. [add] and [markAllRead]
  /// call it, so a write can never replace a list that was not read yet.
  Future<void> ensureLoaded() => _loading ??= load();

  /// Newest first.
  List<Notice> get notices => List.unmodifiable(_notices);

  /// At most [maxNotices] notices; the permanent other-version one is kept
  /// whatever its age and does not count toward the limit.
  static List<Notice> _capped(Iterable<Notice> list) {
    var room = maxNotices;
    return [
      for (final n in list)
        if (n.otherVersion || room-- > 0) n,
    ];
  }

  Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance().timeout(_prefsTimeout);

  /// Reads the stored list; never throws. Drops notices that are not newer
  /// than the installed version and rewrites the list if anything changed.
  Future<void> load() async {
    List<Notice> parsed = const [];
    var changedOnLoad = false;
    try {
      final raw = (await _prefs()).getString(storageKey);
      _hadStoredValue = raw != null;
      if (raw != null && raw.length <= maxStoredChars) {
        final json = jsonDecode(raw);
        if (json is List) {
          final seen = <String>{};
          final kept = <Notice>[];
          for (final item in json) {
            final n = Notice.tryFromJson(item);
            if (n == null || !seen.add(_key(n.tag))) {
              changedOnLoad = true;
              continue;
            }
            kept.add(n);
          }
          kept.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
          parsed = kept;
        }
      }
    } catch (_) {
      parsed = const [];
    }
    final installed = _installedVersion();
    final current = _capped(parsed.where(
      (n) => n.welcome || n.backupPaused || n.otherVersion || n.whatsNew || ReleaseInfo.isNewerVersion(n.tag, installed),
    ));
    if (current.length != parsed.length) changedOnLoad = true;
    _notices = current;
    _publishCount();
    if (changedOnLoad) await _save();
  }

  /// Adds [notice] unless its release is already in the inbox. The notes are
  /// sanitised here (at store). Returns true when it was added. Never throws.
  /// A backup-paused notice is the exception: it replaces any earlier one
  /// (put first, unread), so a second pause shows again.
  Future<bool> add(Notice notice) async {
    try {
      await ensureLoaded();
      if ((notice.welcome ? 1 : 0) + (notice.backupPaused ? 1 : 0) + (notice.otherVersion ? 1 : 0) + (notice.whatsNew ? 1 : 0) > 1) {
        return false;
      }
      if (notice.welcome) {
        if (notice.tag != Notice.welcomeTag) return false;
      } else if (notice.backupPaused) {
        if (notice.tag != Notice.backupPausedTag) return false;
      } else if (notice.otherVersion) {
        if (notice.tag != Notice.otherVersionTag) return false;
      } else if (notice.whatsNew) {
        if (!notice.tag.startsWith(Notice.whatsNewTagPrefix) ||
            ReleaseInfo.parseVersion(notice.tag.substring(Notice.whatsNewTagPrefix.length)) == null) {
          return false;
        }
      } else if (ReleaseInfo.parseVersion(notice.tag) == null) {
        return false;
      }
      final key = _key(notice.tag);
      if (!notice.backupPaused && _notices.any((n) => _key(n.tag) == key)) return false;
      final clean = Notice(
        tag: notice.tag,
        notes: UntrustedText.sanitize(notice.notes),
        receivedAt: notice.receivedAt,
        read: notice.backupPaused ? false : notice.read,
        welcome: notice.welcome,
        backupPaused: notice.backupPaused,
        otherVersion: notice.otherVersion,
        whatsNew: notice.whatsNew,
      );
      final others = notice.backupPaused ? _notices.where((n) => _key(n.tag) != key) : _notices;
      final next = [clean, ...others];
      _notices = List.unmodifiable(_capped(next));
      _publishCount();
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes the notice with [tag] (the backup-paused one, once the user has
  /// picked a folder again or turned auto-backup off). Returns true when one
  /// was removed. Never throws.
  Future<bool> remove(String tag) async {
    try {
      await ensureLoaded();
      final key = _key(tag);
      if (!_notices.any((n) => _key(n.tag) == key)) return false;
      _notices = List.unmodifiable(_notices.where((n) => _key(n.tag) != key));
      _publishCount();
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Marks every notice read (the Updates page calls this after its first
  /// frame). Never throws.
  Future<void> markAllRead() async {
    try {
      await ensureLoaded();
      if (_notices.every((n) => n.read)) return;
      _notices = List.unmodifiable(_notices.map((n) => n.copyWith(read: true)));
      _publishCount();
      await _save();
    } catch (_) {}
  }

  /// Marks the one notice with [tag] read and saves it (so a restart does not
  /// light the bell again). Never throws.
  Future<void> markRead(String tag) async {
    try {
      await ensureLoaded();
      final key = _key(tag);
      if (!_notices.any((n) => _key(n.tag) == key && !n.read)) return;
      _notices = List.unmodifiable(_notices.map((n) => _key(n.tag) == key ? n.copyWith(read: true) : n));
      _publishCount();
      await _save();
    } catch (_) {}
  }

  /// True when a notice for this release is already stored.
  bool contains(String tag) => _notices.any((n) => _key(n.tag) == _key(tag));

  void _publishCount() {
    unreadCount.value = _notices.where((n) => !n.read).length;
  }

  Future<void> _save() async {
    try {
      final p = await _prefs();
      await p
          .setString(storageKey, jsonEncode(_notices.map((n) => n.toJson()).toList()))
          .timeout(_prefsTimeout);
    } catch (_) {}
  }

  /// `v1.2.3` and `1.2.3` are the same release.
  static String _key(String tag) =>
      ReleaseInfo.parseVersion(tag)?.join('.') ?? tag;
}
