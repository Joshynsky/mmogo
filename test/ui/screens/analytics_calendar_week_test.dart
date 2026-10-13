// CW1 on the Analytics screen: "now" is Wednesday 14 Oct 2026, 12:00 (the week is
// Monday 12 to Sunday 18 Oct), with invented rows on Monday, Tuesday and
// Wednesday of this week, two in the week before and two in FUTURE days of this
// week (which must never count: data only up to today).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

final _wed = DateTime(2026, 10, 14, 12);

List<Map<String, Object?>> _rows({int weekBefore = 600000}) => [
  fakeTx(id: 1, at: DateTime(2026, 10, 12, 9), amountCents: 100000, costCents: 1000), // Mon
  fakeTx(id: 2, at: DateTime(2026, 10, 13, 9), amountCents: 200000, costCents: 1000), // Tue
  fakeTx(id: 3, at: DateTime(2026, 10, 14, 9), amountCents: 300000, costCents: 1000), // Wed
  fakeTx(id: 4, at: DateTime(2026, 10, 9, 9), amountCents: weekBefore - 200000, costCents: 1000), // Fri before
  fakeTx(id: 5, at: DateTime(2026, 10, 11, 9), amountCents: 200000, costCents: 1000), // Sun before
  fakeTx(id: 6, at: DateTime(2026, 10, 15, 9), amountCents: 900000, costCents: 1000), // Thu: a FUTURE day
  fakeTx(id: 7, at: DateTime(2026, 10, 18, 22), amountCents: 700000, costCents: 1000), // Sun night: future
];

Future<FakeAnalyticsDb> _pump(WidgetTester tester, {DateTime? now, List<Map<String, Object?>>? rows}) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = FakeAnalyticsDb(rows ?? _rows());
  await tester.pumpWidget(MaterialApp(home: AnalyticsScreen(db: db, clock: () => now ?? _wed)));
  await tester.pumpAndSettle();
  return db;
}

String _text(WidgetTester t, String key) => key == 'analyticsPeriodValue'
    ? t.widget<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text))).data!
    : t.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a Wednesday shows all seven days; data only Monday to Wednesday; the label is the WHOLE week', (t) async {
    final db = await _pump(t);
    expect(_text(t, 'analyticsPeriodValue'), '12–18 Oct');
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(Key('analyticsBar-$i')), findsOneWidget, reason: 'bar $i');
    }
    expect(find.byKey(const Key('analyticsBar-7')), findsNothing);
    // 1,000 + 2,000 + 3,000: the Thursday and Sunday-night rows are in the future.
    expect(_text(t, 'analyticsTotal'), '6,000.00');
    expect(find.text('3 transactions', findRichText: true), findsOneWidget);
    // Average over the 3 days so far (Monday to Wednesday), not over 7.
    expect(find.text('avg Ksh 2,000/day', findRichText: true), findsOneWidget);
    // The query itself stops at the end of today.
    final (start, end) = db.windows.last;
    expect(DateTime.fromMillisecondsSinceEpoch(start!), DateTime(2026, 10, 5));
    expect(DateTime.fromMillisecondsSinceEpoch(end!), DateTime(2026, 10, 14, 23, 59, 59, 999));
  });

  testWidgets('the caption reads "vs last week" against the WHOLE week before (6,000 vs 4,000)', (t) async {
    await _pump(t, rows: _rows(weekBefore: 400000));
    expect(find.text('▲ 50% vs last week'), findsOneWidget);
    expect(find.textContaining('prior week'), findsNothing);
    expect(find.textContaining('last 7 days'), findsNothing);
  });

  testWidgets('first day Sunday: the same Wednesday shows Sun 11 to Sat 17 Oct', (t) async {
    SharedPreferences.setMockInitialValues({'first_day_of_week': 7});
    await _pump(t);
    expect(_text(t, 'analyticsPeriodValue'), '11–17 Oct');
    // Sunday 11 Oct is now IN this week: 2,000 + 1,000 + 2,000 + 3,000.
    expect(_text(t, 'analyticsTotal'), '8,000.00');
  });

  testWidgets('a bad first-day value falls back to Monday', (t) async {
    SharedPreferences.setMockInitialValues({'first_day_of_week': 9});
    await _pump(t);
    expect(_text(t, 'analyticsPeriodValue'), '12–18 Oct');
  });

  testWidgets('pull to refresh from an old week shows the whole current calendar week', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('analyticsPrev')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('analyticsPrev')));
    await t.pumpAndSettle();
    expect(_text(t, 'analyticsPeriodValue'), '28 Sep – 4 Oct');
    await t.fling(find.byKey(const Key('analyticsScroll')), const Offset(0, 400), 1500);
    await t.pumpAndSettle();
    expect(_text(t, 'analyticsPeriodValue'), '12–18 Oct');
    expect(_text(t, 'analyticsTotal'), '6,000.00');
  });

  testWidgets('Sunday night to Monday: at 00:30 Monday 19 Oct the new week is empty and the old one is whole', (t) async {
    await _pump(t, now: DateTime(2026, 10, 19, 0, 30));
    expect(_text(t, 'analyticsPeriodValue'), '19–25 Oct');
    expect(_text(t, 'analyticsTotal'), '0.00');
    await t.tap(find.byKey(const Key('analyticsPrev')));
    await t.pumpAndSettle();
    expect(_text(t, 'analyticsPeriodValue'), '12–18 Oct');
    // 1,000 + 2,000 + 3,000 + Thursday 9,000 + Sunday night 7,000: all past now.
    expect(_text(t, 'analyticsTotal'), '22,000.00');
  });
}
