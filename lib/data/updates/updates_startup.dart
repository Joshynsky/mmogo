import 'dart:async';

import 'update_check_service.dart';
import 'updates_inbox.dart';
import 'welcome_notice.dart';

/// What the app does about updates when Home opens (B27 + B49), in order:
/// load the inbox (the bell dot), add the first-launch welcome notice when it
/// applies, then start the weekly check WITHOUT waiting for it. The check does
/// nothing unless the switch is on and a week has passed since the last
/// successful one. Never throws; the caller does not await the network part.
Future<void> startUpdates({UpdatesInbox? inbox, UpdateCheckService? service, DateTime? now}) async {
  final box = inbox ?? UpdatesInbox.instance;
  try {
    await box.load();
    await WelcomeNotice.addIfFirstLaunch(box, now: now);
  } catch (_) {}
  unawaited((service ?? UpdateCheckService.instance).maybeCheck(now: now));
}
