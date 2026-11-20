import 'package:flutter/foundation.dart' show kDebugMode;

import '../../app_info.dart';
import 'release_info.dart';
import 'updates_inbox.dart';

/// 0.2.1 #3 — DEBUG ONLY. Puts a release notice one patch newer than the installed version into the
/// Updates inbox, so the News "Update" row and the Updates page "Update" button can be checked on a
/// phone with no real newer release. Does nothing (returns null) unless `kDebugMode`, so a release
/// build can never seed it. Returns the seeded version, or null when nothing was added.
Future<String?> seedNewerReleaseNotice(UpdatesInbox inbox, {String? installedVersionName, DateTime? now}) async {
  if (!kDebugMode) return null;
  final parts = ReleaseInfo.parseVersion(installedVersionName ?? AppInfo.versionName);
  if (parts == null || parts.length < 3) return null;
  final tag = '${parts[0]}.${parts[1]}.${parts[2] + 1}';
  final added = await inbox.add(Notice(
    tag: tag,
    notes: 'Debug test notice',
    receivedAt: now ?? DateTime.now(),
  ));
  return added ? tag : null;
}
