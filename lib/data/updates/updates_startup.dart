import 'dart:async';

import 'other_version_notice.dart';
import 'update_check_service.dart';
import 'updates_inbox.dart';
import 'welcome_notice.dart';

/// What the app does about updates when Home opens (B27 + B49), in order:
/// load the inbox (the bell dot), add the first-launch welcome notice when it
/// applies, add the one-time other-version notice (standard build only; the
/// caller says), then start the weekly check WITHOUT waiting for it. The check
/// does nothing unless the switch is on and a week has passed since the last
/// successful one. Never throws; the caller does not await the network part.
Future<void> startUpdates({
  UpdatesInbox? inbox,
  UpdateCheckService? service,
  DateTime? now,
  bool otherVersionNotice = true, // the caller passes false in the auto-read build
}) async {
  final box = inbox ?? UpdatesInbox.instance;
  try {
    await box.load();
    await WelcomeNotice.addIfFirstLaunch(box, now: now);
    if (otherVersionNotice) await OtherVersionNotice.addIfNeeded(box, now: now);
  } catch (_) {}
  unawaited((service ?? UpdateCheckService.instance).maybeCheck(now: now));
}
