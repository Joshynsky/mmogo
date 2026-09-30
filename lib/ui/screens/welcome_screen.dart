import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/prefs/app_prefs.dart';
import '../shell/routes.dart';
import '../theme/app_colors.dart';

/// How long Welcome stays visible before continuing on its own (PM
/// decision, 2026-09-24; mock v5: `setTimeout(..., 3000)`). Counted from the
/// moment Welcome's first frame is actually on screen, not from `initState`
/// (see [waitForFirstFramePresented]).
const welcomeDuration = Duration(seconds: 3);

/// Upper bound on the wait for the engine to report the first rasterised
/// frame (see [waitForFirstFramePresented]). The engine always reports it
/// on a real device; the cap only guarantees Welcome can never sit there
/// forever if it somehow didn't (tap-to-continue works regardless).
const welcomeRasterWaitCap = Duration(seconds: 5);

/// Completes at the end of the frame currently being built (or the next
/// one): the widget tree has been built, laid out and painted and the
/// scene handed to the engine. It does NOT mean the frame has been
/// rasterised and shown yet.
Future<void> waitForFrameBuilt() {
  final built = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) => built.complete());
  return built.future;
}

/// Completes once Welcome's first frame is actually on screen: first the
/// post-frame callback of the frame that built Welcome, then the engine's
/// "first frame rasterised" signal ([WidgetsBinding.waitUntilFirstFrameRasterized],
/// which is when Android removes the native launch screen). A post-frame
/// callback alone fires when the UI thread hands the scene over, which on
/// a cold debug launch can still be well before the raster thread has
/// drawn it; the rasterised signal is the closest thing to "the user can
/// see it". Only the app's first frame is waited for: once it has been
/// rasterised this is just the post-frame wait. Bounded by
/// [welcomeRasterWaitCap].
Future<void> waitForFirstFramePresented() async {
  await waitForFrameBuilt();
  final binding = WidgetsBinding.instance;
  if (binding.firstFrameRasterized) return;
  await binding.waitUntilFirstFrameRasterized.timeout(welcomeRasterWaitCap, onTimeout: () {});
}

/// What Welcome waits on before starting its [welcomeDuration] timer.
/// Tests swap this for [waitForFrameBuilt] (the widget-test binding has no
/// rasteriser, so it never reports a rasterised frame) or for a gate they
/// control.
@visibleForTesting
Future<void> Function() welcomeFirstFramePresented = waitForFirstFramePresented;

/// T16 — the Welcome screen, shown on EVERY launch, even after onboarding is
/// done (PM direct decision, 2026-09-24; onboarding
/// mock, screen 0): the surface
/// colour, a centred tint circle reading "Welcome" (the logo placeholder until a logo
/// exists) and "Tap to continue". Continues [welcomeDuration] after it is
/// first on screen, or on tap, whichever comes first (a tap works even
/// before the timer has started).
///
/// Launch cost: the onboarding-flag read starts in `initState`, in parallel
/// with the first frame and the timer, so the route decision is normally
/// ready long before the timer fires; AppPrefs' own 2s bounded timeout is
/// shorter than [welcomeDuration], so even a stuck preference store does
/// not hold Welcome past it. Welcome touches no database: Home's T13
/// purge + bootstrap still run in Home's own `initState`, before Home
/// renders any totals, exactly as before.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final Future<bool> _onboardingComplete;
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _onboardingComplete = AppPrefs.readOnboardingComplete();
    _startTimerOncePresented();
  }

  /// Starts the auto-continue timer only once Welcome is actually on
  /// screen (T16 device-check defect, 2026-09-24: started in `initState`,
  /// the timer fired before the slow first debug frame was shown, so
  /// Welcome was never seen). Skipped if the user already tapped or the
  /// screen is gone.
  Future<void> _startTimerOncePresented() async {
    await welcomeFirstFramePresented();
    if (!mounted || _leaving) return;
    _timer = Timer(welcomeDuration, _continue);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    final done = await _onboardingComplete;
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(done ? Routes.home : Routes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    // Follows the chosen palette (T26 app-wide) and the phone's light/dark
    // setting; Ocean & Sun's own tokens are mock v3's own values.
    final palette = AppPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.overlayStyleWithNavBar(palette.surface),
      child: Scaffold(
        backgroundColor: palette.surface,
        body: Semantics(
          button: true,
          label: 'Welcome. Tap to continue',
          excludeSemantics: true,
          onTap: _continue,
          child: GestureDetector(
            key: const Key('welcome-screen'),
            behavior: HitTestBehavior.opaque,
            onTap: _continue,
            child: SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 150,
                    height: 150,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                    // FittedBox: at large text scales the word shrinks to
                    // stay inside the circle instead of overflowing it.
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Welcome',
                          style: TextStyle(
                            color: palette.tintInk,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.26,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Tap to continue',
                    style: TextStyle(fontSize: 12, color: palette.mutedInk),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
