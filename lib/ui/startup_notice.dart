import 'package:flutter/material.dart';

import '../data/maintenance/reset_resume.dart';
import 'copy/delete_data_copy.dart';
import 'shell/app_messenger.dart';

/// §APP.STARTUP_NOTICE — the one-time notice after a start-up "Reset app" that
/// did not finish (0.1.2 S9b-2, A4). Same wording as the Delete data failure.
///
/// Shown at most once per process: [shown] is static, so a `RestartScope`
/// restart (which rebuilds the app root) never shows it again. A completed
/// resume and an unreadable flag show nothing.
class StartupNotice {
  const StartupNotice._();

  /// True once the notice was shown (or decided against) in this process.
  static bool shown = false;

  /// Call after the first frame; shows a SnackBar through the app messenger.
  /// Returns whether a notice was shown.
  static bool maybeShow({ResetResumeOutcome? outcome}) {
    if (shown) return false;
    if ((outcome ?? ResetResume.lastOutcome) != ResetResumeOutcome.notFinished) return false;
    final messenger = appMessengerKey.currentState;
    if (messenger == null) return false;
    shown = true;
    messenger.showSnackBar(
      const SnackBar(
        key: Key('startupNotice'),
        content: Text(kDeleteStartupNotice),
        duration: Duration(seconds: 10),
      ),
    );
    return true;
  }

  @visibleForTesting
  static void resetForTest() => shown = false;
}
