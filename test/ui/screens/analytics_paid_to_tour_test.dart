// Coach tours on Analytics and Paid to (lib/ui/screens/analytics/tour.dart,
// paid_to/paid_to_screen.dart), driven through the same `db:` / `clock:` seams
// and FakeAnalyticsDb the other screen tests use. "Now" is Thu 24 Sep 2026.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:mmogo/ui/widgets/coach_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
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

  group('Analytics', () {
    Widget screen({List<Map<String, Object?>>? rows}) =>
        AnalyticsScreen(db: FakeAnalyticsDb(rows ?? analyticsSampleRows()), clock: () => analyticsTestNow);

    testWidgets('first visit: 4 steps ending on the swipe row; Done marks it seen', (tester) async {
      await _pump(tester, screen());
      expect(find.text('1 of 4'), findsOneWidget);
      expect(find.textContaining('Change the period'), findsOneWidget);
      await _next(tester);
      expect(find.textContaining('Tap a bar to zoom in'), findsOneWidget);
      await _next(tester);
      expect(find.textContaining('filter the list'), findsOneWidget);
      await _next(tester);
      expect(find.text('4 of 4'), findsOneWidget);
      expect(find.textContaining('Swipe right to edit'), findsOneWidget);
      expect(await _seen('analytics'), isNull);
      await _next(tester); // Done
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      expect(await _seen('analytics'), isTrue);
    });

    testWidgets('no transactions: the row step is left out', (tester) async {
      await _pump(tester, screen(rows: const []));
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('already seen: no tour; the header ? replays it', (tester) async {
      SharedPreferences.setMockInitialValues({'tour_seen_analytics': true});
      await _pump(tester, screen());
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      await tester.tap(find.byKey(const Key('pageHelpButton')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 4'), findsOneWidget);
    });
  });

  group('Paid to', () {
    Widget screen({List<Map<String, Object?>>? rows}) =>
        PaidToScreen(db: FakeAnalyticsDb(rows ?? analyticsSampleRows()), clock: () => analyticsTestNow);

    testWidgets('first visit: search, a recipient (Take me there), then Done', (tester) async {
      await _pump(tester, screen());
      expect(find.byKey(coachTourBubbleKey), findsOneWidget);
      expect(find.textContaining('Find someone'), findsOneWidget);
      await _next(tester);
      expect(find.textContaining('Tap a name'), findsOneWidget);
      expect(find.byKey(coachTourActionKey), findsOneWidget);
      // Every remaining step is optional (See all only exists with > 3 people);
      // walk to the end whatever the count is.
      while (find.byKey(coachTourBubbleKey).evaluate().isNotEmpty) {
        await _next(tester);
      }
      expect(await _seen('paid_to'), isTrue);
    });

    testWidgets('with a type of more than 3 recipients: a third step spotlights "See all"', (tester) async {
      // analyticsSampleRows() has 3 Send Money recipients; add two more so
      // one type has 5 and the "See all" link exists.
      final rows = [
        ...analyticsSampleRows(),
        fakeTx(id: 30, at: DateTime(2026, 9, 22, 10), label: 'ALICE WAMBUI', phone: '0711000001', amountCents: 10000),
        fakeTx(id: 31, at: DateTime(2026, 9, 23, 10), label: 'BOB OMONDI', phone: '0711000002', amountCents: 20000),
      ];
      await _pump(tester, screen(rows: rows));
      expect(find.byKey(const Key('paidToSeeAll-SEND_MONEY')), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      await _next(tester);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.byKey(coachTourActionKey), findsOneWidget); // Take me there
      await _next(tester);
      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.textContaining('See all lists everyone'), findsOneWidget);
      expect(find.byKey(coachTourActionKey), findsNothing);
      expect(find.text('Done'), findsOneWidget);

      // Back works, and the tour finishes normally from the last step.
      await tester.tap(find.byKey(coachTourBackKey));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);
      await _next(tester);
      await _next(tester); // Done
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      expect(await _seen('paid_to'), isTrue);
    });

    testWidgets('no payments: no automatic tour, but the ? still replays the search step', (tester) async {
      await _pump(tester, screen(rows: const []));
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      await tester.tap(find.byKey(const Key('pageHelpButton')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1'), findsOneWidget);
    });

    testWidgets('the static caption is gone (the tour says it)', (tester) async {
      SharedPreferences.setMockInitialValues({'tour_seen_paid_to': true});
      await _pump(tester, screen());
      expect(find.text('Tap a name to see every payment to them'), findsNothing);
    });
  });
}
