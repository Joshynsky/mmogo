// Widget tests for the PM's 2026-09-24 direct decision: Analytics has no
// contextual hint bubble (hints stay on Home and Add only). Replaces
// T19's analytics_hint_test.dart. Proves no hint renders on Analytics even
// with no seen flag stored (the case that used to show it), that visiting
// Analytics writes no hint flag. T21 re-pointed these at the reworked period
// pill (the old T9 period controls and their Week link are gone; no hint was
// ever anchored to them after the 2026-09-24 removal). Always-empty fake
// Database.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/ui/screens/analytics_screen.dart';
import 'package:mpesa_tracker/ui/widgets/hint_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _EmptyDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The text T9/T19's Analytics hint used to show.
const _oldHintText = 'Tap Week again to switch to Month. Double-click Week for a custom date range.';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Widget _app({Object? args}) => MaterialApp(
      onGenerateRoute: (_) => MaterialPageRoute(
        settings: RouteSettings(name: '/', arguments: args),
        builder: (_) => AnalyticsScreen(db: _EmptyDb()),
      ),
    );

void _expectNoHint() {
  expect(find.byType(HintOverlayHost), findsNothing);
  expect(find.byType(HintBubble), findsNothing);
  expect(find.byKey(const ValueKey('hintBubble_analytics_hint')), findsNothing);
  expect(find.byKey(const Key('analyticsHintGotIt')), findsNothing);
  expect(find.text(_oldHintText), findsNothing);
  expect(find.text('Got it'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('no seen flag stored: no hint bubble renders, and no hint flag gets written',
      (tester) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    expect(find.byKey(const Key('analyticsPeriodValue')), findsOneWidget);
    _expectNoHint();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('hint_seen_')), isEmpty);
  });

  testWidgets('a stale hint_seen_analytics_hint flag from an older build changes nothing',
      (tester) async {
    SharedPreferences.setMockInitialValues({'hint_seen_analytics_hint': true});
    await tester.pumpWidget(_app());
    await _settle(tester);
    expect(find.byKey(const Key('analyticsPeriodValue')), findsOneWidget);
    _expectNoHint();
  });

  testWidgets('Home handoff (int id): still no hint', (tester) async {
    await tester.pumpWidget(_app(args: 42));
    await _settle(tester);
    expect(find.byKey(const Key('analyticsPeriodValue')), findsOneWidget);
    _expectNoHint();
  });

  testWidgets('party-filter mode: still no hint', (tester) async {
    await tester.pumpWidget(_app(args: const AnalyticsRouteArgs(type: 'SEND_MONEY', partyKey: 'p:0712345678')));
    await _settle(tester);
    // T22: the recipient (Paid to) view now shows the period pill.
    expect(find.byKey(const Key('analyticsPeriodValue')), findsOneWidget);
    _expectNoHint();
  });

  // T21: the fifth test here (T9's Yesterday/Today/Week tabs, the Week-tab
  // escalation and the Month · Custom link still working) was removed with
  // those controls; the reworked period pill is covered by
  // analytics_screen_test.dart.
}
