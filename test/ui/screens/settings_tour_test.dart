// Settings' coach tour (lib/ui/screens/settings_screen.dart; S9a: the "Show
// tips again" row left Settings, Help and tips on Profile replays the guides,
// and the tour names Manage categories), against a minimal fake Database that
// only answers the transaction count (see settings_screen_test.dart for why a
// real one cannot be used inside testWidgets).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/coach_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AppPaletteScope(
        controller: AppPaletteController(),
        child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(coachTourNextKey));
  await tester.pumpAndSettle();
}

Future<bool?> _seen(String id) async => (await SharedPreferences.getInstance()).getBool('tour_seen_$id');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CoachTour.autoStartDisabled = false;
  });
  tearDown(() => CoachTour.autoStartDisabled = true);

  // S9a: step 2 now sits on the Adding entries card and offers Manage
  // categories (was "Manage classifications" on the Your data card); step 3 is
  // the Your data card. The old step 3 ("Show tips again replays these guides")
  // named a row that no longer exists.
  testWidgets('first visit: 3 steps; the adding step offers Manage categories', (tester) async {
    await _pump(tester);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.textContaining('colour palette'), findsOneWidget);
    await _next(tester);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.byKey(coachTourActionKey), findsOneWidget);
    expect(find.text('Open Manage categories'), findsOneWidget);
    expect(find.textContaining('classification'), findsNothing);
    await _next(tester);
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.textContaining('Show tips again'), findsNothing);
    expect(find.textContaining('CSV'), findsWidgets);
    await _next(tester); // Done
    expect(find.byKey(coachTourBubbleKey), findsNothing);
    expect(await _seen(settingsTourId), isTrue);
  });

  testWidgets('already seen: no tour, and no header ? button (B48: Help and tips is in Profile)', (tester) async {
    SharedPreferences.setMockInitialValues({'tour_seen_$settingsTourId': true});
    await _pump(tester);
    expect(find.byKey(coachTourBubbleKey), findsNothing);
    expect(find.byKey(const Key('pageHelpButton')), findsNothing);
  });

  testWidgets('Show tips again is not on Settings any more; the reset itself (Profile) still clears only tour flags', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_$settingsTourId': true,
      'tour_seen_home': true,
      'tour_seen_add': true,
      AppPrefs.keyAutoRecognizeClassifications: false,
    });
    await _pump(tester);
    await tester.drag(find.byKey(const Key('settingsScroll')), const Offset(0, -2000));
    await tester.pump();
    expect(find.text('Show tips again'), findsNothing);
    expect(find.text('Tips reset. The guides will show again.'), findsNothing);

    await AppPrefs.resetAllTours(); // what Profile's Help and tips calls
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('tour_seen_')), isEmpty);
    expect(prefs.getBool(AppPrefs.keyAutoRecognizeClassifications), isFalse);
  });
}
