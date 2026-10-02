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
  });

  final String tag;
  final String notes;
  final DateTime receivedAt;
  final bool read;

  Notice copyWith({bool? read}) => Notice(
        tag: tag,
        notes: notes,
        receivedAt: receivedAt,
        read: read ?? this.read,
      );

  Map<String, Object?> toJson() => {
        'tag': tag,
        'notes': notes,
        'receivedAt': receivedAt.millisecondsSinceEpoch,
        'read': read,
      };

  /// `null` when the stored map is unusable (wrong types, bad tag).
  static Notice? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final tag = raw['tag'];
    final notes = raw['notes'];
    final at = raw['receivedAt'];
    final read = raw['read'];
    if (tag is! String || ReleaseInfo.parseVersion(tag) == null) return null;
    if (at is! int) return null;
    return Notice(
      tag: tag,
      notes: notes is String ? UntrustedText.sanitize(notes) : '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(at),
      read: read == true,
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

  /// Loads once; later calls share the first load. [add] and [markAllRead]
  /// call it, so a write can never replace a list that was not read yet.
  Future<void> ensureLoaded() => _loading ??= load();

  /// Newest first.
  List<Notice> get notices => List.unmodifiable(_notices);

  Future<SharedPreferences> _prefs() =>
      SharedPreferences.getInstance().timeout(_prefsTimeout);

  /// Reads the stored list; never throws. Drops notices that are not newer
  /// than the installed version and rewrites the list if anything changed.
  Future<void> load() async {
    List<Notice> parsed = const [];
    var changedOnLoad = false;
    try {
      final raw = (await _prefs()).getString(storageKey);
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
    final current = parsed
        .where((n) => ReleaseInfo.isNewerVersion(n.tag, installed))
        .take(maxNotices)
        .toList(growable: false);
    if (current.length != parsed.length) changedOnLoad = true;
    _notices = current;
    _publishCount();
    if (changedOnLoad) await _save();
  }

  /// Adds [notice] unless its release is already in the inbox. The notes are
  /// sanitised here (at store). Returns true when it was added. Never throws.
  Future<bool> add(Notice notice) async {
    try {
      await ensureLoaded();
      if (ReleaseInfo.parseVersion(notice.tag) == null) return false;
      final key = _key(notice.tag);
      if (_notices.any((n) => _key(n.tag) == key)) return false;
      final clean = Notice(
        tag: notice.tag,
        notes: UntrustedText.sanitize(notice.notes),
        receivedAt: notice.receivedAt,
        read: notice.read,
      );
      final next = [clean, ..._notices];
      _notices = List.unmodifiable(next.take(maxNotices));
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
