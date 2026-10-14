// P-Analytics-20: back from the background (paused, then resumed) Analytics
// re-queries, and keeps the period the user was viewing. Fake db, invented data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Future<FakeAnalyticsDb> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = FakeAnalyticsDb(analyticsSampleRows());
  await tester.pumpWidget(MaterialApp(home: AnalyticsScreen(db: db, clock: () => analyticsTestNow)));
  await tester.pumpAndSettle();
  return db;
}

/// The legal path the engine takes: resumed, inactive, hidden, paused and back.
void _pause(WidgetTester tester) {
  for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void _resume(WidgetTester tester) {
  for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

Future<void> _background(WidgetTester tester) async {
  _pause(tester);
  await tester.pump();
  _resume(tester);
  await tester.pump();
  await tester.pumpAndSettle();
}

String _txt(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data ?? '';
String _periodValue(WidgetTester t) =>
    t.widget<Text>(find.descendant(of: find.byKey(const Key('analyticsPeriodValue')), matching: find.byType(Text))).data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('P-Analytics-20: after paused then resumed, the new total and the new first row show', (tester) async {
    final db = await _pump(tester);
    final before = _txt(tester, 'analyticsTotal');
    expect(find.byKey(const Key('analyticsRow-1')), findsOneWidget);

    // A newer transaction this week, becoming the first row.
    db.transactions.add(fakeTx(id: 77, at: DateTime(2026, 9, 24, 12), amountCents: 500000, label: 'NEW PARTY'));
    await _background(tester);

    expect(_txt(tester, 'analyticsTotal'), isNot(before));
    expect(find.byKey(const Key('analyticsRow-77')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('analyticsRow-77'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('analyticsRow-1'))).dy));
  });

  testWidgets('P-Analytics-20: the period the user stepped to is kept after resume, and a resume with no change leaves the figures', (tester) async {
    final db = await _pump(tester);
    await tester.tap(find.byKey(const Key('analyticsPrev')));
    await tester.pumpAndSettle();
    expect(_periodValue(tester), '14–20 Sep');
    final total = _txt(tester, 'analyticsTotal');
    final queries = db.windows.length;

    await _background(tester);
    expect(db.windows.length, greaterThan(queries), reason: 'resume did re-query');
    expect(_periodValue(tester), '14–20 Sep', reason: 'the period is not reset to now');
    expect(_txt(tester, 'analyticsTotal'), total);

    db.transactions.add(fakeTx(id: 78, at: DateTime(2026, 9, 16, 12), amountCents: 100000, label: 'EARLIER PARTY'));
    await _background(tester);
    expect(_periodValue(tester), '14–20 Sep');
    expect(find.byKey(const Key('analyticsRow-78')), findsOneWidget);
    expect(_txt(tester, 'analyticsTotal'), isNot(total));
  });
}
