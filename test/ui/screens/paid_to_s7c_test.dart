// 0.1.2 S7c: (1) the recipient sheet's Analytics and Close buttons share one row, at 360 dp wide and
// text scale 1.3; (2) Analytics' recipient view of a Withdrawal agent reads "Withdrawn from them" with the
// cash taken out, while a Send Money and a Pochi recipient view still read "Paid to them" with the
// spending total. Invented data only. "Now" is Thu 24 Sep 2026.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart' show AnalyticsDao, cashOutTotal;
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

const _pochi = 'POCHI_LA_BIASHARA';
const _wd = 'AGENT_WITHDRAWAL';

List<Map<String, Object?>> _rows() {
  final wd1 = fakeTx(
    id: 1,
    at: DateTime(2026, 9, 4, 10),
    type: _wd,
    amountCents: 200000,
    costCents: 3000,
    label: 'JOY AGENT',
    agentNumber: '314159',
  );
  final wd2 = fakeTx(
    id: 2,
    at: DateTime(2026, 9, 18, 10),
    type: _wd,
    amountCents: 300000,
    costCents: 4500,
    label: 'JOY AGENT',
    agentNumber: '314159',
  );
  final sm = fakeTx(id: 3, at: DateTime(2026, 9, 10, 10), amountCents: 50000, costCents: 1000, label: 'ANN', phone: '0722114455');
  final pochi = fakeTx(id: 4, at: DateTime(2026, 9, 9, 10), type: _pochi, amountCents: 15000, label: 'JUICE BAR');
  for (final r in [wd1, wd2, pochi]) {
    r['counterparty_phone'] = null;
  }
  return [wd1, wd2, sm, pochi];
}

Future<void> _openAnalytics(WidgetTester tester, String type, String key, String name) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = FakeAnalyticsDb(_rows());
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: RouteSettings(
          name: settings.name,
          arguments: AnalyticsRouteArgs(
            type: type,
            partyKey: key,
            partyName: name,
            period: AnalyticsPeriod.month(DateTime(2026, 9, 1)),
          ),
        ),
        builder: (_) => AnalyticsScreen(db: db, clock: () => analyticsTestNow),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
}

String _t(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('recipient sheet buttons: one row', () {
    Future<void> openSheet(WidgetTester tester, {required double width, double scale = 1}) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final db = FakeAnalyticsDb(_rows());
      await tester.pumpWidget(MaterialApp(home: PaidToScreen(db: db, clock: () => analyticsTestNow)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paidToRow-$_wd|no|314159')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('paidToSheetAnalytics')));
      await tester.pumpAndSettle();
    }

    void expectSideBySide(WidgetTester tester) {
      final a = tester.getRect(find.byKey(const Key('paidToSheetAnalytics')));
      final c = tester.getRect(find.byKey(const Key('paidToSheetClose')));
      expect((a.top - c.top).abs(), lessThan(1), reason: 'same row');
      expect(c.left, greaterThan(a.right), reason: 'Close is to the right of Analytics');
      expect((a.width - c.width).abs(), lessThan(1), reason: 'equal widths');
      expect(a.height, greaterThanOrEqualTo(44));
      expect(c.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    }

    testWidgets('360 dp, text scale 1.0', (tester) async {
      await openSheet(tester, width: 360);
      expectSideBySide(tester);
      expect(find.text('See in Analytics'), findsOneWidget);
      // The screen-reader label keeps the full sentence.
      expect(find.bySemanticsLabel('See these payments in Analytics'), findsOneWidget);
    });

    testWidgets('360 dp, text scale 1.3: no overflow, still one row', (tester) async {
      await openSheet(tester, width: 360, scale: 1.3);
      expectSideBySide(tester);
    });

    testWidgets('Close still closes the sheet (the Analytics hand-off is covered in paid_to_s7b_test.dart)', (tester) async {
      await openSheet(tester, width: 360);
      await tester.tap(find.byKey(const Key('paidToSheetClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paidToSheetName')), findsNothing);
    });
  });

  group('Analytics recipient view', () {
    testWidgets('Withdrawal agent: "Withdrawn from them", the cash taken out, payments pill and cost stay', (
      tester,
    ) async {
      await _openAnalytics(tester, _wd, 'no|314159', 'JOY AGENT');
      expect(_t(tester, 'analyticsSpentLabel'), 'Withdrawn from them');
      expect(_t(tester, 'analyticsTotal'), '5,000.00');
      expect(find.text('2 payments'), findsOneWidget);
      expect(find.byKey(const Key('analyticsFactFees')), findsOneWidget);
      expect(find.textContaining('75'), findsWidgets, reason: 'transaction cost 30.00 + 45.00');
    });

    testWidgets('Send Money recipient: still "Paid to them" with the spending total', (tester) async {
      await _openAnalytics(tester, 'SEND_MONEY', '0722114455', 'ANN');
      expect(_t(tester, 'analyticsSpentLabel'), 'Paid to them');
      expect(_t(tester, 'analyticsTotal'), '500.00');
    });

    testWidgets('Pochi recipient: still "Paid to them" with the spending total', (tester) async {
      await _openAnalytics(tester, _pochi, 'name|JUICE BAR', 'JUICE BAR');
      expect(_t(tester, 'analyticsSpentLabel'), 'Paid to them');
      expect(_t(tester, 'analyticsTotal'), '150.00');
    });
  });

  test('cashOutTotal: the cash taken out at agents, nothing from other types (the spending rule is unchanged)', () async {
    final db = FakeAnalyticsDb(_rows());
    final rows = await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes);
    expect(cashOutTotal(rows), 500000);
    expect(cashOutTotal(rows.where((r) => r.sourceType != _wd)), 0);
    expect(rows.where((r) => r.sourceType == _wd).fold<int>(0, (s, r) => s + r.spent), 0);
  });
}
