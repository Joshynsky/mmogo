// Smoke test for T2's navigation shell entrypoint.
//
// Real domain/persistence tests live under test/data/ — this file only
// confirms the app widget tree builds, lands on Home with the primary
// chrome (5-item bottom nav + centered FAB) present, and that basic
// primary/secondary navigation actually routes. T1's old DB-debug-scaffold
// assertion is gone since T2 replaced that temporary scaffold with the
// real shell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/main.dart';
import 'package:mmogo/ui/screens/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T16: the app now launches on the Welcome screen every time, then routes
/// to Home only once onboarding is complete. These shell smoke tests are
/// about Home + navigation, so they start from a returning user (flag set)
/// and step past Welcome's ~3s auto-continue plus the route transition.
/// Pumped with durations, not pumpAndSettle: Home's body spinner never
/// settles while its (hung-in-test) DB load is pending.
Future<void> _launchToHome(WidgetTester tester) async {
  await tester.pumpWidget(const MpesaTrackerApp());
  await tester.pump(welcomeDuration);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// T20: with no display name, Home's greeting is just the time of day
/// ("Good morning" / "Good afternoon" / "Good evening"; no "Welcome back").
final _noNameGreeting = find.textContaining(RegExp(r'^Good (morning|afternoon|evening)$'));

/// A label in the primary bottom bar.
Finder _navTab(String label) =>
    find.descendant(of: find.byKey(const Key('primaryBottomNav')), matching: find.text(label));

void main() {
  // T17: Profile (pushed by the third test below) now reads the display
  // name from shared_preferences on open. Without a mock store, that
  // plugin call never completes in this environment and AppPrefs' bounded
  // 2s `.timeout` timer is left pending at teardown ("A Timer is still
  // pending...") — the same mock every other prefs-touching test in this
  // suite already installs (settings_screen_test.dart, etc.).
  //
  // T16: the onboarding-complete flag is set so launch routing goes
  // Welcome -> Home (the unset-flag path is covered in
  // test/ui/screens/onboarding_flow_test.dart).
  setUp(() => SharedPreferences.setMockInitialValues({AppPrefs.keyOnboardingComplete: true}));
  // Welcome's timer waits for its first frame to be on screen; the
  // widget-test binding has no rasteriser, so treat "built" as "presented"
  // (see test/ui/screens/onboarding_flow_test.dart for the real gate).
  setUp(() => welcomeFirstFramePresented = waitForFrameBuilt);
  tearDown(() => welcomeFirstFramePresented = waitForFirstFramePresented);

  testWidgets('App builds and lands on Home with the primary chrome', (
    WidgetTester tester,
  ) async {
    await _launchToHome(tester);

    expect(find.byType(MaterialApp), findsOneWidget);
    // Home's title is a personalized greeting (T20: "Good morning {name},"
    // etc.) -- no display name is set in this test environment, so the
    // time-of-day-only greeting is what should render, before Home's async DB load
    // even resolves (a single pump(), not pumpAndSettle()).
    expect(_noNameGreeting, findsOneWidget);
    // The 5 primary nav destinations should all be present. "Home" matches
    // twice on the Home screen specifically (the nav label + the
    // placeholder body's own title text), everything else once.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Paid to'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    // Add has no text label — it's the centered FAB, icon-only.
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('Tapping a primary nav item navigates to that destination', (
    WidgetTester tester,
  ) async {
    await _launchToHome(tester);

    // T9 (this dispatch) made Analytics a real screen that opens a genuine
    // `AppDatabase` connection on load -- per this project's disclosed
    // environment finding, a real `sqflite_common_ffi` `Database` hangs
    // indefinitely inside a `testWidgets` test, so this smoke test now
    // targets Profile instead (B48; its DB load just stays pending) to keep
    // testing the same thing (primary-nav routing) without tripping that
    // hang. Analytics' own real screen/interaction logic is covered by
    // `test/ui/screens/analytics_screen_test.dart` (fake DB) and
    // `test/data/analytics_dao_test.dart` (real in-memory sqlite3).
    await tester.tap(_navTab('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsWidgets);
    expect(find.byIcon(Icons.person_rounded), findsWidgets);
  });

  testWidgets('B48: Profile is a primary tab (bell, bottom bar, no back); '
      'its Settings row opens Settings as a secondary page and back returns', (WidgetTester tester) async {
    await _launchToHome(tester);

    await tester.tap(_navTab('Profile'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Updates'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byKey(const Key('primaryBottomNav')), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    // Secondary chrome: back arrow, title Settings, no bottom bar.
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Appearance'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const Key('primaryBottomNav')), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('primaryBottomNav')), findsOneWidget);
    expect(find.text('Help and tips'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });
}
