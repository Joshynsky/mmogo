import 'package:flutter/widgets.dart';

import '../data/backup/auto_backup_service.dart';
import '../data/prefs/app_prefs.dart';
import '../data/prefs/backup_prefs.dart';
import '../data/updates/update_check_service.dart';
import '../data/updates/updates_inbox.dart';
import 'shell/primary_shell.dart';
import 'theme/app_palette_scope.dart';

/// §APP.RESTART — the soft restart after "Reset app" (0.1.2 S9b-1, note
/// "Restart without a kill"). No UI of its own; S9b-2 calls
/// [RestartScope.restart] after a finished reset.

/// Returns every in-memory singleton to its fresh-install state. ONE function,
/// so the list cannot drift from the test that pins it:
///  - the palette controller reads the (now wiped) prefs again (ocean, system);
///  - the Updates inbox forgets its cached notices (and "loaded");
///  - `BackupPrefs.pausedNotifier` goes false;
///  - `AppPrefs.userDisplayNameRevision` is bumped (listeners re-read: no name);
///  - auto-backup is released and its queued count forgotten;
///  - the live PrimaryShell is forgotten;
///  - the update check may run again this "launch".
/// Writes nothing. Never calls `SharedPreferences.resetStatic`.
Future<void> resetInMemoryState({AppPaletteController? palette}) async {
  BackupPrefs.pausedNotifier.value = false;
  UpdatesInbox.instance.resetForRestart();
  AppPrefs.userDisplayNameRevision.value++;
  AutoBackupService.instance.resume();
  PrimaryShell.resetForRestart();
  UpdateCheckService.instance.resetForRestart();
  await palette?.load();
}

/// Wraps the app root. [restart] resets the singletons, then rebuilds
/// everything below under a NEW key, so the app starts over on Welcome with
/// no stale state, widget or database handle.
class RestartScope extends StatefulWidget {
  const RestartScope({super.key, required this.controller, required this.builder});

  /// The app's palette controller (reloaded by [resetInMemoryState]).
  final AppPaletteController controller;

  /// Builds the app root; called again under the new key.
  final Widget Function(AppPaletteController controller) builder;

  /// Runs the soft restart for the scope above [context]. False when there is
  /// none. The caller's own widget is gone afterwards: do not use its context.
  static Future<bool> restart(BuildContext context) async {
    final state = context.findAncestorStateOfType<_RestartScopeState>();
    if (state == null) return false;
    await state._restart();
    return true;
  }

  @override
  State<RestartScope> createState() => _RestartScopeState();
}

class _RestartScopeState extends State<RestartScope> {
  Key _key = UniqueKey();

  Future<void> _restart() async {
    await resetInMemoryState(palette: widget.controller);
    if (!mounted) return;
    setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.builder(widget.controller));
}
