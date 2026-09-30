// Tests for lib/ui/widgets/coach_tour.dart and the tour_seen_* prefs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/prefs/app_prefs.dart';
import 'package:mymog/ui/widgets/coach_tour.dart';
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CoachTour.autoStartDisabled = false;
  });
  tearDown(() => CoachTour.autoStartDisabled = true);

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

  testWidgets('Back returns to the previous step; not shown on step 1', (tester) async {
    await tester.pumpWidget(_Host(steps: _steps()));
    await _launch(tester);
    expect(find.byKey(coachTourBackKey), findsNothing);
    await tester.tap(find.byKey(coachTourNextKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(coachTourNextKey));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    await tester.tap(find.byKey(coachTourBackKey));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    await tester.tap(find.byKey(coachTourBackKey));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.byKey(coachTourBackKey), findsNothing);
  });

  group('Take me there pauses instead of ending', () {
    List<CoachStep> stepsWithMiddleAction(VoidCallback onAction) => [
      CoachStep(target: _k1, text: 'First'),
      CoachStep(target: _k2, text: 'Second', actionLabel: 'Take me there', onAction: onAction),
      CoachStep(target: _k3, text: 'Third'),
    ];

    testWidgets('on a middle step: fires, closes, is NOT seen, and resumes at the next step', (tester) async {
      var fired = 0;
      await tester.pumpWidget(_Host(steps: stepsWithMiddleAction(() => fired++)));
      await _launch(tester);
      await tester.tap(find.byKey(coachTourNextKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(coachTourActionKey));
      await tester.pumpAndSettle();
      expect(fired, 1);
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      expect(await AppPrefs.readTourSeen('p'), isFalse);
      expect(await AppPrefs.readTourStep('p'), 2);

      // Back on the page: the tour carries on at step 3 and can still go Back.
      await _launch(tester);
      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.text('Third'), findsOneWidget);
      await tester.tap(find.byKey(coachTourBackKey));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);
      await tester.tap(find.byKey(coachTourNextKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(coachTourNextKey)); // Done
      await tester.pumpAndSettle();
      expect(await AppPrefs.readTourSeen('p'), isTrue);
      expect(await AppPrefs.readTourStep('p'), 0);
    });

    testWidgets('on the last step: it finishes the tour', (tester) async {
      await tester.pumpWidget(_Host(steps: _steps(onAction: () {})));
      await _launch(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(coachTourNextKey));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(coachTourActionKey));
      await tester.pumpAndSettle();
      expect(await AppPrefs.readTourSeen('p'), isTrue);
    });

    testWidgets('a saved step past the end (steps shrank) counts as finished', (tester) async {
      await AppPrefs.writeTourStep('p', 3);
      await tester.pumpWidget(_Host(steps: _steps()));
      await _launch(tester);
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      expect(await AppPrefs.readTourSeen('p'), isTrue);
    });

    testWidgets('never two overlays for one page', (tester) async {
      await tester.pumpWidget(_Host(steps: _steps()));
      await _launch(tester);
      await tester.tap(find.byKey(const Key('launch')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(coachTourBubbleKey), findsOneWidget);
    });
  });

  group('the tour steps aside when its page goes away', () {
    // A page whose visibility / presence the test controls.
    Widget pageHost(ValueNotifier<bool> shown, ValueNotifier<bool> tickers) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (_, on, _) => on
                    ? ValueListenableBuilder<bool>(
                        valueListenable: tickers,
                        builder: (_, t, _) => TickerMode(
                          enabled: t,
                          child: SizedBox(key: _k1, height: 40, child: const Text('page')),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              TextButton(
                key: const Key('launch'),
                onPressed: () => CoachTour.maybeStart(
                  context,
                  pageId: 'p',
                  steps: [
                    CoachStep(target: _k1, text: 'One'),
                    CoachStep(target: _k1, text: 'Two'),
                  ],
                ),
                child: const Text('launch'),
              ),
            ],
          ),
        ),
      ),
    );

    testWidgets('page hidden (another tab shown): pauses, not seen, resumes at the same step', (tester) async {
      final shown = ValueNotifier(true);
      final tickers = ValueNotifier(true);
      await tester.pumpWidget(pageHost(shown, tickers));
      await _launch(tester);
      await tester.tap(find.byKey(coachTourNextKey));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);

      tickers.value = false; // the shell switched to another tab
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      expect(await AppPrefs.readTourSeen('p'), isFalse);
      expect(await AppPrefs.readTourStep('p'), 1);

      tickers.value = true; // back on the tab
      await _launch(tester);
      expect(find.text('2 of 2'), findsOneWidget);
    });

    testWidgets('page removed (route popped): pauses too', (tester) async {
      final shown = ValueNotifier(true);
      final tickers = ValueNotifier(true);
      await tester.pumpWidget(pageHost(shown, tickers));
      await _launch(tester);
      expect(find.byKey(coachTourBubbleKey), findsOneWidget);

      shown.value = false;
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      expect(await AppPrefs.readTourSeen('p'), isFalse);
    });

    testWidgets('a target that was never built does not pause the tour', (tester) async {
      await tester.pumpWidget(_Host(steps: [CoachStep(target: _unlaid, text: 'Lost')]));
      await _launch(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(coachTourBubbleKey), findsOneWidget);
    });
  });

  testWidgets('the bubble sits just under the spotlighted target', (tester) async {
    await tester.pumpWidget(_Host(steps: _steps()));
    await _launch(tester);
    final target = tester.getRect(find.byKey(_k1));
    final bubble = tester.getRect(find.byKey(coachTourBubbleKey));
    // spotlight inflates the target by 6, the bubble sits 12 below that.
    expect(bubble.top, moreOrLessEquals(target.bottom + 6 + 12, epsilon: 1));
  });

  testWidgets('onEnter runs when each step becomes current, in order', (tester) async {
    final entered = <String>[];
    await tester.pumpWidget(
      _Host(
        steps: [
          CoachStep(target: _k1, text: 'First', onEnter: () => entered.add('one')),
          CoachStep(target: _k2, text: 'Second', onEnter: () => entered.add('two')),
        ],
      ),
    );
    await _launch(tester);
    expect(entered, ['one']);
    await tester.tap(find.byKey(coachTourNextKey));
    await tester.pumpAndSettle();
    expect(entered, ['one', 'two']);
  });

  testWidgets('autoStartDisabled stops maybeStart but not a replay', (tester) async {
    CoachTour.autoStartDisabled = true;
    await tester.pumpWidget(_Host(steps: _steps()));
    await _launch(tester);
    expect(find.byKey(coachTourBubbleKey), findsNothing);
    await tester.pumpWidget(_Host(steps: _steps(), replay: true));
    await _launch(tester);
    expect(find.byKey(coachTourBubbleKey), findsOneWidget);
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
