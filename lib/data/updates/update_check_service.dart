import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../app_info.dart';
import '../prefs/update_prefs.dart';
import 'update_check_client.dart';
import 'updates_inbox.dart';

/// Policy for the weekly update check (architecture D7). It only TELLS the
/// user a newer version exists; it never downloads or installs anything.
///
/// - Switch off (read at call time): returns before any client is built.
/// - Due when never checked, when a week has passed since the last
///   SUCCESSFUL check, or when the stored time is in the future (clock set
///   back; due once, and a success rewrites it).
/// - At most one attempt per app launch (an in-memory flag), no retry loop.
/// - A failed or offline attempt writes NO timestamp: the week is not used up.
/// - Silent on every failure; [maybeCheck] never throws.
///
/// The request carries nothing about the user (see [UpdateCheckClient]).
class UpdateCheckService {
  UpdateCheckService({
    UpdateCheckSource Function()? clientFactory,
    UpdatesInbox? inbox,
    String Function()? installedVersion,
  })  : _clientFactory = clientFactory ?? UpdateCheckClient.new,
        _inbox = inbox ?? UpdatesInbox.instance,
        _installedVersion = installedVersion ?? (() => AppInfo.versionName);

  static final UpdateCheckService instance = UpdateCheckService();

  static const interval = Duration(days: 7);

  final UpdateCheckSource Function() _clientFactory;
  final UpdatesInbox _inbox;
  final String Function() _installedVersion;

  bool _attemptedThisLaunch = false;

  /// True while a call is deciding or running; closes the window where two
  /// calls could both pass the checks before either sets the launch flag.
  bool _busy = false;

  /// Call once on app start and do not await it on the startup path.
  /// Returns true only when a check completed successfully.
  Future<bool> maybeCheck({DateTime? now}) async {
    if (_attemptedThisLaunch || _busy) return false;
    _busy = true;
    try {
      if (!await UpdatePrefs.readEnabled()) return false;

      final at = now ?? DateTime.now();
      final last = await UpdatePrefs.readLastCheckAt();
      if (!_isDue(last, at)) return false;

      // Set before the request so a second call in this process, even while
      // this one is still running, makes no request.
      _attemptedThisLaunch = true;

      final info = await _clientFactory().fetchLatest();
      await _inbox.ensureLoaded();
      if (info.isNewerThan(_installedVersion()) && !_inbox.contains(info.tag)) {
        await _inbox.add(Notice(tag: info.tag, notes: info.notes, receivedAt: at));
      }
      await UpdatePrefs.writeLastCheckAt(at);
      return true;
    } catch (e) {
      // Silent for the user; only the exception type in debug builds.
      assert(() {
        debugPrint('UpdateCheckService: check failed (${e.runtimeType})');
        return true;
      }());
      return false;
    } finally {
      _busy = false;
    }
  }

  static bool _isDue(DateTime? last, DateTime now) {
    if (last == null) return true;
    if (last.isAfter(now)) return true;
    return now.difference(last) >= interval;
  }
}
