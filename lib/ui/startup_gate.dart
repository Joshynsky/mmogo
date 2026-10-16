import 'dart:async';

import 'package:flutter/material.dart';

import '../data/db/open_classifier.dart';
import '../data/db/open_stage.dart';
import 'screens/open_failure_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_palette_scope.dart';
import 'theme/app_theme.dart';

/// §APP.STARTUP_GATE — the open-failure gate (0.1.2 S10c, OF1 / DB7).
///
/// Sits between the RestartScope and the app root: `StartupGate(controller:,
/// open:, ..., child: MpesaTrackerApp(...))`. It runs after the reset resume
/// and the palette load (so the failure screen is themed), opens the database
/// ONCE (Home reuses that open), and shows [child] on success or the one
/// open-failure screen on a throw.
///
///  - Every seam is REQUIRED with no default, so no test can reach the real
///    database by omission.
///  - No timeout on the open itself (a slow legitimate upgrade is not a
///    failure); only the evidence probes are bounded.
///  - [beforeOpen] runs once per gate run, never per retry.
///  - No automatic retry anywhere: one open per user tap on Try again.
///  - Try again does not restart the app: the gate re-runs itself and builds
///    the child only on success.
///  - Its failure screen is its own minimal MaterialApp with NO
///    scaffoldMessengerKey (that belongs to the app root).
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.controller,
    required this.open,
    required this.readStage,
    required this.closeDatabase,
    required this.beforeOpen,
    required this.classify,
    required this.child,
  });

  final AppPaletteController controller;

  /// Opens the database (the open Home needs anyway). Throws on failure.
  final Future<void> Function() open;

  /// How far the last [open] got (E0).
  final OpenStage Function() readStage;

  /// Bounded close of the cached handle before a retry; failures are caught.
  final Future<void> Function() closeDatabase;

  /// Once per gate run: the pre-open snapshot, or null (no probes when the
  /// UPG-3 proof is not on record).
  final Future<OpenSnapshot?> Function() beforeOpen;

  final Future<OpenFailureKind> Function(Object error, OpenStage stage, OpenSnapshot? snapshot) classify;

  /// The app root, built only after a successful open.
  final Widget child;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

enum _Phase { opening, failed, ready }

class _StartupGateState extends State<StartupGate> {
  _Phase _phase = _Phase.opening;
  OpenFailureKind _kind = OpenFailureKind.other;
  OpenSnapshot? _snapshot;
  int _failedRetries = 0;
  bool _trying = false;

  @override
  void initState() {
    super.initState();
    _firstRun();
  }

  Future<void> _firstRun() async {
    try {
      _snapshot = await widget.beforeOpen();
    } catch (_) {
      _snapshot = null;
    }
    await _attempt();
  }

  /// One open. Success -> ready; a throw -> classified -> failed.
  Future<bool> _attempt() async {
    try {
      await widget.open();
      if (!mounted) return true;
      setState(() => _phase = _Phase.ready);
      return true;
    } catch (e) {
      // Only the class name is logged: never the message or a path.
      debugPrint('StartupGate: open failed (${e.runtimeType})');
      var kind = OpenFailureKind.other;
      try {
        kind = await widget.classify(e, widget.readStage(), _snapshot);
      } catch (_) {
        kind = OpenFailureKind.other;
      }
      if (!mounted) return false;
      setState(() {
        _kind = kind;
        _phase = _Phase.failed;
      });
      return false;
    }
  }

  Future<void> _tryAgain() async {
    if (_trying) return;
    setState(() => _trying = true);
    try {
      await widget.closeDatabase().timeout(const Duration(seconds: 10));
    } catch (_) {}
    final ok = await _attempt();
    if (!mounted) return;
    setState(() {
      _trying = false;
      if (!ok) _failedRetries++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.ready) return widget.child;
    return AppPaletteScope(
      controller: widget.controller,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final set = AppPalettes.byId(widget.controller.value);
          return MaterialApp(
            title: 'mmogo',
            theme: AppTheme.forPalette(set.light),
            darkTheme: AppTheme.forPalette(set.dark),
            themeMode: switch (widget.controller.appearance) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            debugShowCheckedModeBanner: false,
            home: _phase == _Phase.failed
                ? OpenFailureScreen(
                    kind: _kind,
                    failedRetries: _failedRetries,
                    trying: _trying,
                    onTryAgain: _tryAgain,
                  )
                : const _OpeningScaffold(),
          );
        },
      ),
    );
  }
}

/// The first frame while the open runs: a themed empty page.
class _OpeningScaffold extends StatelessWidget {
  const _OpeningScaffold();

  @override
  Widget build(BuildContext context) =>
      Scaffold(key: const Key('startupOpening'), backgroundColor: AppPalette.of(context).background);
}
