// 0.1.2 S8c-3: (1) the fit-aware Analytics hero label of a Withdrawal agent ("Withdrawn from them" when it fits
// on one line beside the period pill, else "Withdrawn", no ellipsis), at 360 dp wide; (2) WD8c: the Withdrawal
// edit sheet's agent-name field (max 200, empty saves NULL; no other type gets a different field set).
// Invented data only. "Now" is Thu 24 Sep 2026.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

const _wd = 'AGENT_WITHDRAWAL';

List<Map<String, Object?>> _rows() {
  final wd = fakeTx(
    id: 1,
    at: DateTime(2026, 9, 4, 10),
    type: _wd,
    amountCents: 200000,
    costCents: 3000,
    label: 'JOY AGENT',
    agentNumber: '314159',
  );
  final sm = fakeTx(id: 3, at: DateTime(2026, 9, 10, 10), amountCents: 50000, costCents: 1000, label: 'ANN', phone: '0722114455');
  final pochi = fakeTx(id: 4, at: DateTime(2026, 9, 9, 10), type: 'POCHI_LA_BIASHARA', amountCents: 15000, label: 'JUICE BAR');
  pochi['counterparty_phone'] = null;
  wd['counterparty_phone'] = null;
  return [wd, sm, pochi];
}

Future<void> _openParty(WidgetTester tester, String type, String key, String name, {double scale = 1, double width = 360}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
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

String _label(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('analyticsSpentLabel'))).data!;

void main() {
  group('fit-aware hero label (Withdrawal agent)', () {
    // The label is never cut: its box is at least as wide as the text, on one line.
    void expectWhole(WidgetTester tester, String text) {
      expect(_label(tester), text);
      final finder = find.byKey(const Key('analyticsSpentLabel'));
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'one line');
      expect(paragraph.size.height, lessThan(26), reason: 'one line');
      final style = tester.widget<Text>(finder).style!;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(tester.element(finder)),
      )..layout();
      expect(paragraph.size.width, greaterThanOrEqualTo(painter.width - 0.5), reason: 'not cut, no ellipsis');
      expect(tester.takeException(), isNull);
    }

    testWidgets('360 dp, text scale 1.0: the pill takes the room, so "Withdrawn", whole, one line', (tester) async {
      await _openParty(tester, _wd, 'no|314159', 'JOY AGENT');
      expectWhole(tester, 'Withdrawn');
    });

    testWidgets('360 dp, text scale 1.3: "Withdrawn", whole, one line, no overflow', (tester) async {
      await _openParty(tester, _wd, 'no|314159', 'JOY AGENT', scale: 1.3);
      expectWhole(tester, 'Withdrawn');
    });

    testWidgets('600 dp, text scale 1.0: there is room beside the pill, so "Withdrawn from them"', (tester) async {
      await _openParty(tester, _wd, 'no|314159', 'JOY AGENT', width: 600);
      expectWhole(tester, 'Withdrawn from them');
    });

    testWidgets('600 dp, text scale 1.3: no longer fits, so "Withdrawn"', (tester) async {
      await _openParty(tester, _wd, 'no|314159', 'JOY AGENT', width: 600, scale: 1.3);
      expectWhole(tester, 'Withdrawn');
    });

    testWidgets('Send Money and Pochi recipient views still read "Paid to them" at both scales', (tester) async {
      for (final scale in [1.0, 1.3]) {
        await _openParty(tester, 'SEND_MONEY', '0722114455', 'ANN', scale: scale);
        expect(_label(tester), 'Paid to them', reason: 'Send Money at $scale');
        await _openParty(tester, 'POCHI_LA_BIASHARA', 'name|JUICE BAR', 'JUICE BAR', scale: scale);
        expect(_label(tester), 'Paid to them', reason: 'Pochi at $scale');
      }
    });
  });

  group('WD8c: the Withdrawal edit sheet agent-name field', () {
    Future<FakeAnalyticsDb> open(WidgetTester t, int id) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(400, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final at = DateTime(2026, 9, 24, 9);
      final db = FakeAnalyticsDb([
        fakeTx(
          id: 16,
          at: at,
          type: _wd,
          label: 'INVENTED AGENT',
          agentNumber: '123456',
          amountCents: 100000,
          costCents: 2900,
          classification: 'Withdrawal',
        ),
        fakeTx(id: 17, at: at.add(const Duration(hours: 2)), type: 'AIRTIME', amountCents: 5000, classification: 'Airtime'),
        fakeTx(id: 11, at: at.add(const Duration(hours: 3)), label: 'SEND PERSON', amountCents: 150000, costCents: 2200),
      ]);
      await t.pumpWidget(MaterialApp(home: AnalyticsScreen(db: db, clock: () => analyticsTestNow)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('analyticsRow-$id')));
      await t.pumpAndSettle();
      return db;
    }

    Future<void> drain(WidgetTester t) async {
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
    }

    testWidgets('the label field reads "Agent name", holds the stored name and is capped at 200', (t) async {
      await open(t, 16);
      expect(find.text('Agent name'), findsOneWidget);
      final field = find.byKey(const Key('editLabelField'));
      expect(t.widget<TextField>(field).controller!.text, 'INVENTED AGENT');
      await t.enterText(field, 'A' * 201);
      await t.pump();
      expect(t.widget<TextField>(field).controller!.text.length, 200);
    });

    testWidgets('an emptied label saves as NULL; amount, fee and agent number are unchanged', (t) async {
      final db = await open(t, 16);
      await t.enterText(find.byKey(const Key('editLabelField')), '   ');
      await t.pump();
      await t.tap(find.byKey(const Key('editSaveButton')));
      await t.pumpAndSettle();
      final row = db.byId(16);
      expect(row['counterparty_label'], isNull);
      expect(row['amount_cents'], 100000);
      expect(row['transaction_cost_cents'], 2900);
      expect(row['agent_number'], '123456');
      await drain(t);
    });

    testWidgets('a changed label is saved trimmed', (t) async {
      final db = await open(t, 16);
      await t.enterText(find.byKey(const Key('editLabelField')), '  KIOSK 7  ');
      await t.pump();
      await t.tap(find.byKey(const Key('editSaveButton')));
      await t.pumpAndSettle();
      expect(db.byId(16)['counterparty_label'], 'KIOSK 7');
      await drain(t);
    });

    testWidgets('Airtime has no label field; a Send Money sheet keeps "Receiver name"', (t) async {
      await open(t, 17);
      expect(find.byKey(const Key('editLabelField')), findsNothing);
      expect(find.text('Agent name'), findsNothing);
      await t.tap(find.byKey(const Key('editCancelButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('analyticsRow-11')));
      await t.pumpAndSettle();
      expect(find.text('Receiver name'), findsOneWidget);
      expect(find.text('Agent name'), findsNothing);
    });
  });
}
