// T16 — Welcome screen (every launch) + the 4-step onboarding flow, built to
// the approved onboarding mock.
//
// Launch-routing tests pump the real app (`MpesaTrackerApp`) with its real
// route table. Once they land on Home, Home's own DB bootstrap hangs in
// `testWidgets` in this environment (the project's disclosed sqflite_ffi
// finding), so Home is asserted through its chrome (the "Paid to" nav label
// + the AppBar greeting), with durations instead of pumpAndSettle.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_info.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/main.dart';
import 'package:mmogo/ui/screens/onboarding_screen.dart';
import 'package:mmogo/ui/screens/welcome_screen.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for "Welcome's first frame is on screen" in widget tests: the
/// test binding has no rasteriser, so the real
/// [waitForFirstFramePresented] would only ever finish via its cap.
void _useBuiltFrameAsPresented() {
  welcomeFirstFramePresented = waitForFrameBuilt;
  addTearDown(() => welcomeFirstFramePresented = waitForFirstFramePresented);
}

Future<void> _passWelcome(WidgetTester tester) async {
  await tester.pump(welcomeDuration);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// After Skip / Get started: the async prefs writes, then the route
/// transition to Home.
Future<void> _settleToHome(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('onboarding-next')));
  await tester.pumpAndSettle();
}

bool _onHome(WidgetTester tester) => find.text('Paid to').evaluate().isNotEmpty;

/// OnboardingScreen alone, with a stub Home route, for layout / a11y tests.
Widget _onboardingApp({double textScale = 1.0, AssetBundle? bundle}) {
  Widget screen = const OnboardingScreen();
  if (bundle != null) screen = DefaultAssetBundle(bundle: bundle, child: screen);
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: screen,
    routes: {Routes.home: (_) => const Scaffold(body: Text('HOME STUB'))},
  );
}

class _FailingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('asset missing: $key');
}

/// T20: with no display name, Home's greeting is just the time of day
/// ("Good morning" / "Good afternoon" / "Good evening"; no "Welcome back").
final _noNameGreeting = find.textContaining(RegExp(r'^Good (morning|afternoon|evening)$'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _useBuiltFrameAsPresented();
  });

  group('AppPrefs onboarding flag', () {
    test('unset reads false; write persists true', () async {
      expect(await AppPrefs.readOnboardingComplete(), isFalse);
      expect(await AppPrefs.writeOnboardingComplete(), isTrue);
      expect(await AppPrefs.readOnboardingComplete(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppPrefs.keyOnboardingComplete), isTrue);
    });
  });

  group('Launch routing', () {
    test('Welcome stays up for 3 seconds (PM decision, mock v5)', () {
      expect(welcomeDuration, const Duration(seconds: 3));
    });

    testWidgets('flag unset: Welcome for 3s after its first frame, then onboarding step 1', (tester) async {
      // pumpWidget draws Welcome's first frame; the timer starts at its end.
      await tester.pumpWidget(const MpesaTrackerApp());
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Tap to continue'), findsOneWidget);

      // Still on Welcome at 2.9s.
      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Track every shilling'), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Welcome'), findsNothing);
      expect(find.text('Track every shilling'), findsOneWidget);
      expect(_onHome(tester), isFalse);
    });

    testWidgets("B31: a fresh install's Welcome silently marks this version's What's-new as seen", (tester) async {
      await tester.pumpWidget(const MpesaTrackerApp());
      await tester.pump();
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), isNull);
      await _passWelcome(tester);
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), AppInfo.versionName);
    });

    testWidgets("B31: an upgrader's Welcome (onboarding done) leaves the seen version unset", (tester) async {
      SharedPreferences.setMockInitialValues({AppPrefs.keyOnboardingComplete: true});
      await tester.pumpWidget(const MpesaTrackerApp());
      await tester.pump();
      await _passWelcome(tester);
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), isNull);
    });

    testWidgets('flag set: Welcome still shows, then Home (never onboarding)', (tester) async {
      SharedPreferences.setMockInitialValues({AppPrefs.keyOnboardingComplete: true});
      await tester.pumpWidget(const MpesaTrackerApp());
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);

      await _passWelcome(tester);
      expect(find.text('Welcome'), findsNothing);
      expect(find.text('Track every shilling'), findsNothing);
      expect(_onHome(tester), isTrue);
      expect(_noNameGreeting, findsOneWidget);
    });

    testWidgets('flag set: still on Welcome at 2.9s, Home after 3s', (tester) async {
      SharedPreferences.setMockInitialValues({AppPrefs.keyOnboardingComplete: true});
      await tester.pumpWidget(const MpesaTrackerApp());
      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.text('Welcome'), findsOneWidget);
      expect(_onHome(tester), isFalse);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Welcome'), findsNothing);
      expect(_onHome(tester), isTrue);
    });

    testWidgets('the timer does not start (or navigate) until the first frame is presented', (tester) async {
      // A gate standing in for a slow first frame (the cold debug launch
      // on the Pixel_8 emulator took >3s to show anything).
      final presented = Completer<void>();
      welcomeFirstFramePresented = () => presented.future;
      await tester.pumpWidget(const MpesaTrackerApp());

      // Far longer than welcomeDuration: nothing moves while the frame is
      // not on screen yet.
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Track every shilling'), findsNothing);

      // Presented now: the full 3s runs from here.
      presented.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Track every shilling'), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Welcome'), findsNothing);
      expect(find.text('Track every shilling'), findsOneWidget);
    });

    testWidgets('a tap before the timer has started continues at once, with no second navigation', (tester) async {
      final presented = Completer<void>();
      welcomeFirstFramePresented = () => presented.future;
      await tester.pumpWidget(const MpesaTrackerApp());
      await tester.tap(find.byKey(const Key('welcome-screen')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Track every shilling'), findsOneWidget);

      // The late "presented" signal must not start a timer that navigates
      // again (a second pushReplacement would replace onboarding).
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.text('Paste an M-Pesa SMS'), findsOneWidget);
      presented.complete();
      await tester.pump();
      await tester.pump(welcomeDuration * 2);
      await tester.pumpAndSettle();
      expect(find.text('Paste an M-Pesa SMS'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
    });

    testWidgets('tapping Welcome continues immediately, without waiting 3s', (tester) async {
      await tester.pumpWidget(const MpesaTrackerApp());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('welcome-screen')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Track every shilling'), findsOneWidget);
      // The cancelled auto-continue timer must not navigate a second time.
      await tester.pump(welcomeDuration);
      await tester.pumpAndSettle();
      expect(find.text('Track every shilling'), findsOneWidget);
    });
  });

  group('waitForFirstFramePresented (the real gate)', () {
    testWidgets('waits for a built frame, then for the rasterised first frame, bounded by the cap', (tester) async {
      await tester.pumpWidget(const SizedBox());
      var done = false;
      unawaited(waitForFirstFramePresented().then((_) => done = true));
      // Welcome calls it from initState, i.e. while a frame is being
      // built; here a frame has to be asked for explicitly.
      tester.binding.scheduleFrame();

      // Nothing before a frame has been built.
      await Future<void>.microtask(() {}); // flush microtasks; no frame
      expect(done, isFalse);

      // Frame built, but the widget-test binding has no rasteriser, so the
      // engine never reports a rasterised first frame: it keeps waiting...
      await tester.pump();
      expect(tester.binding.firstFrameRasterized, isFalse);
      expect(done, isFalse);
      await tester.pump(welcomeRasterWaitCap - const Duration(milliseconds: 1));
      expect(done, isFalse);

      // ...until the cap, so Welcome can never be held forever.
      await tester.pump(const Duration(milliseconds: 1));
      expect(done, isTrue);
    });

    testWidgets('waitForFrameBuilt completes at the end of the next frame, not before', (tester) async {
      await tester.pumpWidget(const SizedBox());
      var done = false;
      unawaited(waitForFrameBuilt().then((_) => done = true));
      // Welcome calls it from initState, i.e. while a frame is being
      // built; here a frame has to be asked for explicitly.
      tester.binding.scheduleFrame();
      await Future<void>.microtask(() {}); // flush microtasks; no frame
      expect(done, isFalse);
      await tester.pump();
      expect(done, isTrue);
    });
  });

  group('Onboarding steps', () {
    testWidgets('Next walks all 4 steps with verbatim copy; Back only from step 2', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_onboardingApp());
      await tester.pumpAndSettle();

      // Step 1
      expect(find.text('Track every shilling'), findsOneWidget);
      expect(find.text('Your M-Pesa and cash spending, in one place.'), findsOneWidget);
      expect(find.text('It all stays on this phone. No account needed.'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 1 of 4'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-back')), findsNothing);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // Step 2 — the 3-frame parse strip
      await _tapNext(tester);
      expect(find.text('Paste an M-Pesa SMS'), findsOneWidget);
      expect(
        find.text(
          'Copy the confirmation SMS, paste it into Add, and the details fill themselves in. '
          'You confirm before anything is saved.',
        ),
        findsOneWidget,
      );
      for (final caption in [
        'Copy the M-Pesa SMS',
        'Tap Parse M-Pesa message and paste',
        'Details filled in, ready to confirm',
      ]) {
        expect(find.textContaining(caption, findRichText: true), findsOneWidget);
      }
      for (final asset in [OnboardingAssets.step2Copy, OnboardingAssets.step2Paste, OnboardingAssets.step2Filled]) {
        expect(find.byKey(ValueKey('onboarding-img:$asset')), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Step 2 of 4'), findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);

      // Step 3
      await _tapNext(tester);
      expect(find.text('Cash counts too'), findsOneWidget);
      expect(find.text('Paid in cash? Switch to the Cash tab and add it yourself.'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 3 of 4'), findsOneWidget);

      // Step 4 — name form, "Get started"
      await _tapNext(tester);
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Optional. You can change it anytime in Profile.'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-name-field')), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const Key('onboarding-name-field')));
      expect(field.maxLength, 30);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.bySemanticsLabel('Step 4 of 4'), findsOneWidget);

      // Back returns to step 3, then step 2.
      await tester.tap(find.byKey(const Key('onboarding-back')));
      await tester.pumpAndSettle();
      expect(find.text('Cash counts too'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-back')));
      await tester.pumpAndSettle();
      expect(find.text('Paste an M-Pesa SMS'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('system back goes to the previous step, not out of onboarding', (tester) async {
      await tester.pumpWidget(_onboardingApp());
      await tester.pumpAndSettle();
      await _tapNext(tester);
      expect(find.text('Paste an M-Pesa SMS'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Track every shilling'), findsOneWidget);
    });

    testWidgets('never auto-skips: onboarding stays put with no input', (tester) async {
      await tester.pumpWidget(_onboardingApp());
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Track every shilling'), findsOneWidget);
      expect(await AppPrefs.readOnboardingComplete(), isFalse);
    });
  });

  group('Finishing', () {
    Future<void> toNameStep(WidgetTester tester) async {
      await tester.pumpWidget(const MpesaTrackerApp());
      await _passWelcome(tester);
      await _tapNext(tester);
      await _tapNext(tester);
      await _tapNext(tester);
      expect(find.text('What should we call you?'), findsOneWidget);
    }

    testWidgets('Get started with a name saves it trimmed via writeUserDisplayName, sets the flag, lands on Home', (
      tester,
    ) async {
      final revisionBefore = AppPrefs.userDisplayNameRevision.value;
      await toNameStep(tester);
      await tester.enterText(find.byKey(const Key('onboarding-name-field')), '  Joshua  ');
      await tester.tap(find.text('Get started'));
      await _settleToHome(tester);

      expect(_onHome(tester), isTrue);
      expect(await AppPrefs.readUserDisplayName(), 'Joshua');
      // The T17 notifier Home listens to was bumped (proves the write went
      // through AppPrefs.writeUserDisplayName, not a raw setString).
      expect(AppPrefs.userDisplayNameRevision.value, revisionBefore + 1);
      expect(await AppPrefs.readOnboardingComplete(), isTrue);
    });

    testWidgets('Get started with an empty/whitespace name writes no name', (tester) async {
      final revisionBefore = AppPrefs.userDisplayNameRevision.value;
      await toNameStep(tester);
      await tester.enterText(find.byKey(const Key('onboarding-name-field')), '   ');
      await tester.tap(find.text('Get started'));
      await _settleToHome(tester);

      expect(_onHome(tester), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(AppPrefs.keyUserDisplayName), isFalse);
      expect(AppPrefs.userDisplayNameRevision.value, revisionBefore);
      expect(_noNameGreeting, findsOneWidget);
      expect(await AppPrefs.readOnboardingComplete(), isTrue);
    });

    testWidgets('Skip sets the flag, saves no name (even one typed), lands on Home', (tester) async {
      final revisionBefore = AppPrefs.userDisplayNameRevision.value;
      await toNameStep(tester);
      await tester.enterText(find.byKey(const Key('onboarding-name-field')), 'Amina');
      await tester.tap(find.text('Skip'));
      await _settleToHome(tester);

      expect(_onHome(tester), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(AppPrefs.keyUserDisplayName), isFalse);
      expect(AppPrefs.userDisplayNameRevision.value, revisionBefore);
      expect(await AppPrefs.readOnboardingComplete(), isTrue);
    });

    testWidgets('Skip from step 1; the flag persists, so the next launch goes Welcome -> Home', (tester) async {
      await tester.pumpWidget(const MpesaTrackerApp());
      await _passWelcome(tester);
      await tester.tap(find.text('Skip'));
      await _settleToHome(tester);
      expect(_onHome(tester), isTrue);

      // "Relaunch": tear the tree down and start the app again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MpesaTrackerApp());
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      await _passWelcome(tester);
      expect(find.text('Track every shilling'), findsNothing);
      expect(_onHome(tester), isTrue);
    });
  });

  group('Image slots', () {
    test('every slot is a real file under a pubspec-registered assets folder', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/onboarding/'));
      expect(OnboardingAssets.all, hasLength(6));
      for (final path in OnboardingAssets.all) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      expect(
        OnboardingAssets.all.map((p) => p.split('/').last),
        ['step1.png', 'step2_1.png', 'step2_2.png', 'step2_3.png', 'step3.png', 'step4.png'],
      );
    });

    testWidgets('a missing/failed asset falls back to the plain tint area without crashing', (tester) async {
      await tester.pumpWidget(_onboardingApp(bundle: _FailingBundle()));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('onboarding-img-fallback:${OnboardingAssets.step1}')), findsOneWidget);
      expect(find.text('Track every shilling'), findsOneWidget);

      // The 3-frame strip degrades the same way.
      await _tapNext(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final asset in [OnboardingAssets.step2Copy, OnboardingAssets.step2Paste, OnboardingAssets.step2Filled]) {
        expect(find.byKey(ValueKey('onboarding-img-fallback:$asset')), findsOneWidget);
      }
    });
  });

  group('Accessibility / layout', () {
    void useSmallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('no overflow on any step at 1.3x text on a 360x640 phone', (tester) async {
      useSmallPhone(tester);
      await tester.pumpWidget(_onboardingApp(textScale: 1.3));
      await tester.pumpAndSettle();
      for (var i = 0; i < onboardingStepCount; i++) {
        expect(tester.takeException(), isNull, reason: 'step ${i + 1}');
        // On this short phone at 1.3x the body can be taller than the 44%
        // under the image; the page scrolls rather than overflowing, so
        // the nav row may need scrolling into view.
        if (i < onboardingStepCount - 1) {
          await tester.ensureVisible(find.byKey(const Key('onboarding-next')));
          await tester.pumpAndSettle();
          await _tapNext(tester);
        }
      }
      expect(find.text('Get started'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Welcome has no overflow at 1.3x text on a 360x640 phone', (tester) async {
      useSmallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const WelcomeScreen(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Welcome'), findsOneWidget);
      // Let the auto-continue timer fire (route is unregistered here, so
      // just unmount before it can navigate).
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Next, Back and Skip are at least 48px tall', (tester) async {
      await tester.pumpWidget(_onboardingApp());
      await tester.pumpAndSettle();
      await _tapNext(tester);
      final next = tester.getSize(find.byKey(const Key('onboarding-next')));
      final back = tester.getSize(find.byKey(const Key('onboarding-back')));
      final skip = tester.getSize(find.byKey(const Key('onboarding-skip')));
      expect(next.height, greaterThanOrEqualTo(48));
      expect(back.width, greaterThanOrEqualTo(48));
      expect(back.height, greaterThanOrEqualTo(48));
      expect(skip.height, greaterThanOrEqualTo(48));
      expect(skip.width, greaterThanOrEqualTo(48));
    });

    testWidgets('chevron icons (mock v5): Back, Next and the step-2 strip; icons stay out of semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_onboardingApp());
      await tester.pumpAndSettle();
      final next = find.byKey(const Key('onboarding-next'));
      expect(find.descendant(of: next, matching: find.byIcon(Icons.chevron_right_rounded)), findsOneWidget);
      expect(find.text('→'), findsNothing);

      await _tapNext(tester);
      final back = find.byKey(const Key('onboarding-back'));
      final backIcon = find.descendant(of: back, matching: find.byIcon(Icons.chevron_left_rounded));
      expect(backIcon, findsOneWidget);
      expect(find.byKey(const Key('onboarding-strip-chevron')), findsNWidgets(2));
      expect(find.text('←'), findsNothing);
      expect(find.text('→'), findsNothing);

      // Colours: backInk / onPrimary / tintInk.
      final palette = AppPalette.light;
      expect(tester.widget<Icon>(backIcon).color, palette.backInk);
      expect(
        tester.widget<Icon>(find.descendant(of: next, matching: find.byIcon(Icons.chevron_right_rounded))).color,
        palette.onPrimary,
      );
      for (final icon in tester.widgetList<Icon>(find.byKey(const Key('onboarding-strip-chevron')))) {
        expect(icon.color, palette.tintInk);
      }

      // Back chevron: vertically centred, optically nudged 1-2px left of
      // the circle's centre; the circle itself is still 48x48.
      expect(tester.getSize(back), const Size(48, 48));
      final circle = tester.getCenter(back);
      final chevron = tester.getCenter(backIcon);
      expect(chevron.dy, moreOrLessEquals(circle.dy, epsilon: 0.01));
      expect(circle.dx - chevron.dx, inInclusiveRange(1, 2));

      // Semantics labels unchanged: the icons add nothing.
      expect(tester.getSemantics(back).label, 'Back');
      expect(tester.getSemantics(next).label, 'Next');
      semantics.dispose();
    });

    testWidgets('a focused Next button shows a visible focus ring', (tester) async {
      await tester.pumpWidget(_onboardingApp());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding-focus-ring')), findsNothing);

      final node = Focus.of(tester.element(find.text('Next')));
      node.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue, reason: node.toString());
      expect(find.byKey(const Key('onboarding-focus-ring')), findsOneWidget);
    });
  });
}
