// Tests for lib/ui/widgets/coach_tour.dart and the tour_seen_* prefs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/data/prefs/app_prefs.dart';
import 'package:mpesa_tracker/ui/widgets/coach_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _k1 = GlobalKey();
final _k2 = GlobalKey();
final _k3 = GlobalKey();
final _unlaid = GlobalKey(); // never attached to a widget

class _Host extends StatelessWidget {
  const _Host({required this.steps, this.replay = false});

  final List<CoachStep> steps;
  final bool replay;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              const SizedBox(height: 40),
              SizedBox(key: _k1, height: 40, child: const Text('one')),
              const Spacer(),
              SizedBox(key: _k2, height: 40, child: const Text('two')),
              SizedBox(key: _k3, height: 40, child: const Text('three')),
              TextButton(
                key: const Key('launch'),
                onPressed: () => replay
                    ? CoachTour.start(context, pageId: 'p', steps: steps)
                    : CoachTour.maybeStart(context, pageId: 'p', steps: steps),
                child: const Text('launch'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<CoachStep> _steps({VoidCallback? onAction}) => [
  CoachStep(target: _k1, text: 'First'),
  CoachStep(target: _k2, text: 'Second'),
  CoachStep(
    target: _k3,
    text: 'Third',
    actionLabel: 'Take me there',
    onAction: onAction,
  ),
];

Future<void> _launch(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('launch')));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Next advances and updates the counter; last step shows Done', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(steps: _steps()));
    await _launch(tester);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    await tester.tap(find.byKey(coachTourNextKey));
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    await tester.tap(find.byKey(coachTourNextKey));
    await tester.pump();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('Done marks seen and closes; second maybeStart does nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(steps: _steps()));
    await _launch(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(coachTourNextKey));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byKey(coachTourBubbleKey), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getBool('tour_seen_p'),
      isTrue,
    );
    await _launch(tester);
    expect(find.byKey(coachTourBubbleKey), findsNothing);
  });

  testWidgets('Skip marks seen and closes', (tester) async {
    await tester.pumpWidget(_Host(steps: _steps()));
    await _launch(tester);
    await tester.tap(find.byKey(coachTourSkipKey));
    await tester.pumpAndSettle();
    expect(find.byKey(coachTourBubbleKey), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getBool('tour_seen_p'),
      isTrue,
    );
  });

  testWidgets('start replays even when already seen', (tester) async {
    SharedPreferences.setMockInitialValues({'tour_seen_p': true});
    await tester.pumpWidget(_Host(steps: _steps(), replay: true));
    await _launch(tester);
    expect(find.byKey(coachTourBubbleKey), findsOneWidget);
    expect(find.byKey(coachTourStepCounterKey), findsOneWidget);
  });

  testWidgets('action button shows only on its step and fires its callback', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(_Host(steps: _steps(onAction: () => fired++)));
    await _launch(tester);
    expect(find.byKey(coachTourActionKey), findsNothing);
    await tester.tap(find.byKey(coachTourNextKey));
    await tester.pump();
    await tester.tap(find.byKey(coachTourNextKey));
    await tester.pump();
    expect(find.byKey(coachTourActionKey), findsOneWidget);
    await tester.tap(find.byKey(coachTourActionKey));
    await tester.pumpAndSettle();
    expect(fired, 1);
    expect(find.byKey(coachTourBubbleKey), findsNothing);
  });

  testWidgets('a null or unlaid target does not crash and centres the bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      _Host(
        steps: [
          CoachStep(target: _unlaid, text: 'Lost'),
          const CoachStep(target: null, text: 'None'),
        ],
      ),
    );
    await _launch(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Lost'), findsOneWidget);
    final c = tester.getCenter(find.byKey(coachTourBubbleKey));
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect((c.dx - view.width / 2).abs(), lessThan(1));
    expect((c.dy - view.height / 2).abs(), lessThan(40));
    await tester.tap(find.byKey(coachTourNextKey));
    await tester.pump();
    expect(find.text('None'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final b in Brightness.values) {
    testWidgets('renders on 320x568 without overflow (${b.name}, large text)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      tester.platformDispatcher.platformBrightnessTestValue = b;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(_Host(steps: _steps(onAction: () {})));
      await _launch(tester);
      for (var i = 0; i < 3; i++) {
        expect(tester.takeException(), isNull);
        final r = tester.getRect(find.byKey(coachTourBubbleKey));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(320));
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.bottom, lessThanOrEqualTo(568));
        if (i < 2) {
          await tester.tap(find.byKey(coachTourNextKey));
          await tester.pump();
        }
      }
    });
  }

  group('AppPrefs tour flags', () {
    test('read/mark round trip, default false', () async {
      expect(await AppPrefs.readTourSeen('a'), isFalse);
      await AppPrefs.markTourSeen('a');
      expect(await AppPrefs.readTourSeen('a'), isTrue);
      expect(await AppPrefs.readTourSeen('b'), isFalse);
    });

    test('resetAllTours clears tour_seen_* only', () async {
      SharedPreferences.setMockInitialValues({
        'tour_seen_a': true,
        'tour_seen_b': true,
        'hint_seen_x': true,
        AppPrefs.keyUserDisplayName: 'Shyn',
      });
      await AppPrefs.resetAllTours();
      expect(await AppPrefs.readTourSeen('a'), isFalse);
      expect(await AppPrefs.readTourSeen('b'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hint_seen_x'), isTrue);
      expect(prefs.getString(AppPrefs.keyUserDisplayName), 'Shyn');
    });
  });
}
