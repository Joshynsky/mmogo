// 0.1.2 S6c on the Analytics screen: the type SET and class SET filters (tiles
// toggle, one chip per set, the percentage rule), the Categories button and
// sheet (draft, Clear, Close, Apply), the Where it went styles (Button preview,
// Strip + See all), the empty text, the clear on a period change, and the
// hatched withdrawals on the chart. Same fake-db approach as
// analytics_s6b_test.dart. "Now" is Thu 24 Sep 2026; this week is 21-27 Sep.
// Invented data only.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart' show niceAxisMax;
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

// Spent this week: Send Money 1,500 (Rent), Buy Goods 850 (Groceries), Paybill 1,200
// (Shopping), Cash 300 (Transport) = 3,850; and a cash withdrawal of 5,000 on Wed 23.
List<Map<String, Object?>> _week() => [
  fakeTx(id: 1, at: DateTime(2026, 9, 24, 9), amountCents: 150000, classification: 'Rent'),
  fakeTx(id: 2, at: DateTime(2026, 9, 24, 11), type: 'BUY_GOODS', amountCents: 85000, classification: 'Groceries'),
  fakeTx(id: 3, at: DateTime(2026, 9, 23, 14), type: 'PAYBILL', amountCents: 120000, classification: 'Shopping'),
  fakeTx(id: 4, at: DateTime(2026, 9, 22, 10), type: 'CASH', amountCents: 30000, classification: 'Transport'),
  fakeTx(
    id: 5,
    at: DateTime(2026, 9, 23, 8),
    type: 'AGENT_WITHDRAWAL',
    amountCents: 500000,
    classification: 'Withdrawal',
    agentNumber: '123456',
  ),
];

// Nine categories (so the sheet has a search box), the largest K8.
List<Map<String, Object?>> _nine() => [
  for (var i = 0; i < 9; i++)
    fakeTx(id: 20 + i, at: DateTime(2026, 9, 22, 8 + i), amountCents: 10000 * (i + 1), classification: 'K$i'),
];

Future<FakeAnalyticsDb> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>>? rows,
  Object? args,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(const SizedBox()); // a clean tree when a test pumps twice
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = FakeAnalyticsDb(rows ?? _week());
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: RouteSettings(name: settings.name, arguments: args),
        builder: (_) => AnalyticsScreen(db: db, clock: () => analyticsTestNow),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

Future<void> _whereTab(WidgetTester t) => _tap(t, 'analyticsTabWhere');
Future<void> _typeTab(WidgetTester t) => _tap(t, 'analyticsTabType');

Finder _chip(String key) => find.byKey(Key(key));
String _chipText(WidgetTester t, String key) =>
    t.widget<Text>(find.descendant(of: _chip(key), matching: find.byType(Text))).data!;
String _tilePercent(WidgetTester t, String code) {
  final texts = t.widgetList<Text>(find.descendant(of: find.byKey(Key('analyticsTypeTile-$code')), matching: find.byType(Text)));
  return texts.map((x) => x.data!).firstWhere((s) => s.endsWith('%') || s == '—' || s == 'tracked');
}

String _total(WidgetTester t) => t.widget<Text>(find.byKey(const Key('analyticsTotal'))).data!;

void main() {
  group('the type set (TL1)', () {
    testWidgets('tiles toggle in and out; one chip names the first and counts the rest', (t) async {
      await _pump(t);
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      expect(_chipText(t, 'analyticsFilterChipType'), 'Send Money · Ksh 1,500');
      await _tap(t, 'analyticsTypeTile-PAYBILL');
      expect(_chipText(t, 'analyticsFilterChipType'), 'Send Money + 1 more · Ksh 2,700');
      expect(find.text('JOHN'), findsNothing);
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      expect(_chipText(t, 'analyticsFilterChipType'), 'Paybill · Ksh 1,200');
      await _tap(t, 'analyticsTypeTile-PAYBILL');
      expect(_chip('analyticsFilterChipType'), findsNothing);
    });

    testWidgets('the list shows the OR of the picked types', (t) async {
      await _pump(t);
      expect(find.text('PARTY 1'), findsOneWidget);
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      await _tap(t, 'analyticsTypeTile-PAYBILL');
      expect(find.text('PARTY 1'), findsOneWidget);
      expect(find.text('PARTY 3'), findsOneWidget);
      expect(find.text('PARTY 2'), findsNothing, reason: 'Buy Goods is not in the set');
      expect(find.text('PARTY 4'), findsNothing);
    });

    testWidgets('the chip remove clears the whole type set and leaves the class set', (t) async {
      await _pump(t);
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      await _tap(t, 'analyticsTypeTile-PAYBILL');
      await _whereTab(t);
      await _tap(t, 'analyticsWhere-Shopping');
      expect(_chip('analyticsFilterChipType'), findsOneWidget);
      expect(_chip('analyticsFilterChipClass'), findsOneWidget);
      await _tap(t, 'analyticsFilterChipType');
      expect(_chip('analyticsFilterChipType'), findsNothing);
      expect(_chip('analyticsFilterChipClass'), findsOneWidget);
      expect(_chipText(t, 'analyticsFilterChipClass'), 'Shopping · Ksh 1,200');
    });

    testWidgets('percentages: against the whole spending, then the selected types total with dashes', (t) async {
      await _pump(t);
      expect(_tilePercent(t, 'SEND_MONEY'), '39%');
      expect(_tilePercent(t, 'AGENT_WITHDRAWAL'), 'tracked');
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      await _tap(t, 'analyticsTypeTile-PAYBILL');
      expect(_tilePercent(t, 'SEND_MONEY'), '56%'); // 1,500 of 2,700
      expect(_tilePercent(t, 'PAYBILL'), '44%');
      expect(_tilePercent(t, 'BUY_GOODS'), '—');
      expect(_tilePercent(t, 'CASH'), '—');
      expect(_tilePercent(t, 'AGENT_WITHDRAWAL'), 'tracked', reason: 'never a percentage');
      expect(_total(t), '3,850.00', reason: 'the Spent total does not follow the filter');
    });

    testWidgets('Withdrawal in the set stays "tracked" and adds nothing to the others', (t) async {
      await _pump(t, args: const AnalyticsRouteArgs(type: 'AGENT_WITHDRAWAL'));
      expect(_chipText(t, 'analyticsFilterChipType'), 'Withdrawal · Ksh 5,000 out');
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      expect(_chipText(t, 'analyticsFilterChipType'), 'Withdrawal + 1 more · Ksh 1,500', reason: 'not exactly {Withdrawal}: no "out"');
      expect(_tilePercent(t, 'SEND_MONEY'), '100%');
      expect(_tilePercent(t, 'AGENT_WITHDRAWAL'), 'tracked');
      expect(_tilePercent(t, 'PAYBILL'), '—');
    });

    testWidgets('day headers: withdrawn sum only when the type set is exactly {Withdrawal}', (t) async {
      List<String> totals() => [for (final w in t.widgetList<Text>(find.byKey(const Key('analyticsDayTotal')))) w.data!];
      await _pump(t, args: const AnalyticsRouteArgs(type: 'AGENT_WITHDRAWAL'));
      expect(totals(), ['Ksh 5,000.00 withdrawn']);
      await _tap(t, 'analyticsTypeTile-CASH');
      // {Withdrawal, Cash}: the usual rule again, Tue 22 spent 300 and Wed 23 only a withdrawal.
      expect(totals(), containsAll(['Ksh 300.00', 'not spent']));
      expect(totals().any((x) => x.contains('withdrawn')), isFalse);
    });

    testWidgets('tiles say selected or not selected to a screen reader', (t) async {
      final h = t.ensureSemantics();
      await _pump(t);
      expect(find.bySemanticsLabel(RegExp(r'^Send Money, Ksh 1,500\.00\. Tap to add to the selection$')), findsOneWidget);
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      expect(
        find.bySemanticsLabel(RegExp(r'^Send Money, Ksh 1,500\.00\. Selected; tap to remove from the selection$')),
        findsOneWidget,
      );
      h.dispose();
    });

    testWidgets('a hand-off from Home or Paid to is a set of one each', (t) async {
      await _pump(t, args: const AnalyticsRouteArgs(type: 'PAYBILL', classification: 'Shopping'));
      expect(_chipText(t, 'analyticsFilterChipType'), 'Paybill · Ksh 1,200');
      expect(_chipText(t, 'analyticsFilterChipClass'), 'Shopping · Ksh 1,200');
      await _tap(t, 'analyticsTypeTile-CASH');
      expect(_chipText(t, 'analyticsFilterChipType'), 'Paybill + 1 more · Ksh 1,200', reason: 'Cash is a Transport row; the AND with Shopping leaves the Paybill row');
    });
  });

  group('the class set (MS1) and the empty text', () {
    testWidgets('preview rows toggle categories in and out of one set, one chip', (t) async {
      await _pump(t);
      await _whereTab(t);
      await _tap(t, 'analyticsWhere-Rent');
      await _tap(t, 'analyticsWhere-Shopping');
      expect(_chipText(t, 'analyticsFilterChipClass'), 'Rent + 1 more · Ksh 2,700');
      expect(find.text('PARTY 2'), findsNothing);
      await _tap(t, 'analyticsWhere-Rent');
      expect(_chipText(t, 'analyticsFilterChipClass'), 'Shopping · Ksh 1,200');
      await _tap(t, 'analyticsFilterChipClass');
      expect(_chip('analyticsFilterChipClass'), findsNothing);
    });

    testWidgets('By type amounts follow the class set; Where it went follows the type set', (t) async {
      await _pump(t);
      await _whereTab(t);
      await _tap(t, 'analyticsWhere-Rent');
      await _typeTab(t);
      expect(find.descendant(of: _chip('analyticsTypeTile-SEND_MONEY'), matching: find.text('Ksh 1,500.00')), findsOneWidget);
      expect(find.descendant(of: _chip('analyticsTypeTile-PAYBILL'), matching: find.text('Ksh 0.00')), findsOneWidget);
      await _tap(t, 'analyticsTypeTile-BUY_GOODS');
      await _whereTab(t);
      expect(_chip('analyticsWhere-Groceries'), findsOneWidget);
      expect(_chip('analyticsWhere-Shopping'), findsNothing, reason: 'Shopping is a Paybill row; only Buy Goods is picked');
    });

    testWidgets('no row matches: "No <types> (<categories>) transactions in this period."', (t) async {
      await _pump(t);
      await _whereTab(t);
      await _tap(t, 'analyticsWhere-Rent');
      await _tap(t, 'analyticsWhere-Groceries');
      await _typeTab(t);
      await _tap(t, 'analyticsTypeTile-CASH');
      await _tap(t, 'analyticsTypeTile-PAYBILL');
      // Rent is Send Money, Groceries is Buy Goods: neither is a Cash or Paybill row.
      expect(find.text('No Cash or Paybill (Rent or Groceries) transactions in this period.'), findsOneWidget);
    });

    testWidgets('categories alone read without brackets', (t) async {
      await _pump(t, args: const AnalyticsRouteArgs(type: 'CASH', classification: 'Rent'));
      expect(find.text('No Cash (Rent) transactions in this period.'), findsOneWidget);
    });

    testWidgets('a filter clears on a period change', (t) async {
      await _pump(t);
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      await _tap(t, 'analyticsTypeTile-PAYBILL');
      await _whereTab(t);
      await _tap(t, 'analyticsWhere-Shopping');
      expect(_chip('analyticsFilterChipType'), findsOneWidget);
      await _tap(t, 'analyticsPrev');
      expect(_chip('analyticsFilterChipType'), findsNothing);
      expect(_chip('analyticsFilterChipClass'), findsNothing);
    });

    testWidgets('filters survive a rebuild that is not a period change (the tab switch)', (t) async {
      await _pump(t);
      await _tap(t, 'analyticsTypeTile-SEND_MONEY');
      await _tap(t, 'analyticsTypeTile-PAYBILL');
      await _whereTab(t);
      await _typeTab(t);
      expect(_chipText(t, 'analyticsFilterChipType'), 'Send Money + 1 more · Ksh 2,700');
    });
  });

  group('the Categories button and sheet', () {
    testWidgets('the button exists only on Where it went, with a count badge', (t) async {
      await _pump(t);
      expect(_chip('analyticsCategoriesButton'), findsNothing);
      final tabsBefore = t.getSize(find.byKey(const Key('analyticsTabType')));
      await _whereTab(t);
      expect(_chip('analyticsCategoriesButton'), findsOneWidget);
      expect(_chip('analyticsCategoriesBadge'), findsNothing, reason: 'nothing selected, no badge');
      expect(t.getSize(find.byKey(const Key('analyticsTabType'))), tabsBefore, reason: 'the tab switch keeps its width on both tabs');
      await _tap(t, 'analyticsWhere-Rent');
      await _tap(t, 'analyticsWhere-Shopping');
      expect(find.descendant(of: _chip('analyticsCategoriesBadge'), matching: find.text('2')), findsOneWidget);
      await _typeTab(t);
      expect(_chip('analyticsCategoriesButton'), findsNothing);
    });

    testWidgets('the button is at the right end of the tab row and reads its count to a screen reader', (t) async {
      final h = t.ensureSemantics();
      await _pump(t);
      await _whereTab(t);
      expect(find.bySemanticsLabel('Choose categories, none selected'), findsOneWidget);
      expect(t.getCenter(_chip('analyticsCategoriesButton')).dx, greaterThan(t.getCenter(find.byKey(const Key('analyticsTabWhere'))).dx));
      expect(t.getSize(find.ancestor(of: _chip('analyticsCategoriesButton'), matching: find.byType(SizedBox)).first).width, greaterThanOrEqualTo(44));
      await _tap(t, 'analyticsWhere-Rent');
      expect(find.bySemanticsLabel('Choose categories, 1 selected'), findsOneWidget);
      h.dispose();
    });

    testWidgets('the button is off when the period has no categories', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, rows: const []);
      await _whereTab(t);
      expect(find.bySemanticsLabel('Choose categories, nothing to choose in this period'), findsOneWidget);
      await t.tap(_chip('analyticsCategoriesButton'));
      await t.pumpAndSettle();
      expect(find.text('Categories (0)'), findsNothing);
      h.dispose();
    });

    testWidgets('the sheet: ranked list, draft ticks stay open, Apply (n) commits', (t) async {
      await _pump(t);
      await _whereTab(t);
      await _tap(t, 'analyticsCategoriesButton');
      expect(find.text('Categories (4)'), findsOneWidget);
      expect(find.text('Total of these: Ksh 3,850 in this period'), findsOneWidget);
      expect(t.getTopLeft(_chip('analyticsCatRow-Rent')).dy, lessThan(t.getTopLeft(_chip('analyticsCatRow-Shopping')).dy));
      expect(t.getTopLeft(_chip('analyticsCatRow-Shopping')).dy, lessThan(t.getTopLeft(_chip('analyticsCatRow-Transport')).dy));
      expect(find.byKey(const Key('analyticsCatSearch')), findsNothing, reason: '8 or fewer: no search');
      expect(find.descendant(of: _chip('analyticsCatApply'), matching: find.text('Close')), findsOneWidget);
      await _tap(t, 'analyticsCatRow-Rent');
      await _tap(t, 'analyticsCatRow-Transport');
      expect(find.text('Categories (4)'), findsOneWidget, reason: 'the sheet stays open');
      expect(find.descendant(of: _chip('analyticsCatApply'), matching: find.text('Apply (2)')), findsOneWidget);
      expect(_chip('analyticsFilterChipClass'), findsNothing, reason: 'nothing is applied before Apply');
      await _tap(t, 'analyticsCatApply');
      expect(find.text('Categories (4)'), findsNothing);
      expect(_chipText(t, 'analyticsFilterChipClass'), 'Rent + 1 more · Ksh 1,800');
    });

    testWidgets('Close, the scrim and the header link throw the draft away', (t) async {
      await _pump(t);
      await _whereTab(t);
      // header Close link
      await _tap(t, 'analyticsCategoriesButton');
      await _tap(t, 'analyticsCatRow-Rent');
      await _tap(t, 'analyticsCatClose');
      expect(_chip('analyticsFilterChipClass'), findsNothing);
      // scrim tap
      await _tap(t, 'analyticsCategoriesButton');
      await _tap(t, 'analyticsCatRow-Rent');
      await t.tapAt(const Offset(200, 20));
      await t.pumpAndSettle();
      expect(find.text('Categories (4)'), findsNothing);
      expect(_chip('analyticsFilterChipClass'), findsNothing);
      // the system Back
      await _tap(t, 'analyticsCategoriesButton');
      await _tap(t, 'analyticsCatRow-Rent');
      Navigator.of(t.element(_chip('analyticsCatClose'))).pop();
      await t.pumpAndSettle();
      expect(_chip('analyticsFilterChipClass'), findsNothing);
      // and once applied, a discarded change does not undo it
      await _tap(t, 'analyticsCategoriesButton');
      await _tap(t, 'analyticsCatRow-Rent');
      await _tap(t, 'analyticsCatApply');
      await _tap(t, 'analyticsCategoriesButton');
      await _tap(t, 'analyticsCatRow-Shopping');
      await _tap(t, 'analyticsCatClose');
      expect(_chipText(t, 'analyticsFilterChipClass'), 'Rent · Ksh 1,500');
    });

    testWidgets('Clear applies at once and closes; the committed ticks start ticked', (t) async {
      await _pump(t);
      await _whereTab(t);
      await _tap(t, 'analyticsWhere-Rent');
      await _tap(t, 'analyticsCategoriesButton');
      expect(find.descendant(of: _chip('analyticsCatTick-Rent'), matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
      expect(find.descendant(of: _chip('analyticsCatTick-Shopping'), matching: find.byIcon(Icons.check_rounded)), findsNothing);
      await _tap(t, 'analyticsCatClear');
      expect(find.text('Categories (4)'), findsNothing);
      expect(_chip('analyticsFilterChipClass'), findsNothing);
    });

    testWidgets('Clear is off with nothing ticked and nothing committed', (t) async {
      await _pump(t);
      await _whereTab(t);
      await _tap(t, 'analyticsCategoriesButton');
      expect(t.widget<FilledButton>(_chip('analyticsCatClear')).onPressed, isNull);
      await _tap(t, 'analyticsCatRow-Rent');
      expect(t.widget<FilledButton>(_chip('analyticsCatClear')).onPressed, isNotNull);
    });

    testWidgets('search appears above 8 categories and filters the list', (t) async {
      await _pump(t, rows: _nine());
      await _whereTab(t);
      await _tap(t, 'analyticsCategoriesButton');
      expect(find.byKey(const Key('analyticsCatSearch')), findsOneWidget);
      await t.enterText(find.byKey(const Key('analyticsCatSearch')), 'k7');
      await t.pumpAndSettle();
      expect(_chip('analyticsCatRow-K7'), findsOneWidget);
      expect(_chip('analyticsCatRow-K1'), findsNothing);
      await t.enterText(find.byKey(const Key('analyticsCatSearch')), 'zzz');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('analyticsCatNone')), findsOneWidget);
    });

    testWidgets('the ticks survive a search (the draft is the whole set, not the visible rows)', (t) async {
      await _pump(t, rows: _nine());
      await _whereTab(t);
      await _tap(t, 'analyticsCategoriesButton');
      await _tap(t, 'analyticsCatRow-K8');
      await t.enterText(find.byKey(const Key('analyticsCatSearch')), 'k1');
      await t.pumpAndSettle();
      await _tap(t, 'analyticsCatRow-K1');
      expect(find.descendant(of: _chip('analyticsCatApply'), matching: find.text('Apply (2)')), findsOneWidget);
    });
  });

  group('Where it went styles', () {
    testWidgets('Button (default): the top 3 largest first, "N categories" opens the sheet', (t) async {
      await _pump(t, rows: _nine());
      await _whereTab(t);
      for (final k in ['K8', 'K7', 'K6']) {
        expect(_chip('analyticsWhere-$k'), findsOneWidget);
      }
      expect(_chip('analyticsWhere-K5'), findsNothing);
      expect(t.getTopLeft(_chip('analyticsWhere-K8')).dy, lessThan(t.getTopLeft(_chip('analyticsWhere-K7')).dy));
      expect(find.text('9 categories'), findsOneWidget);
      await _tap(t, 'analyticsWhereCount');
      expect(find.text('Categories (9)'), findsOneWidget);
    });

    testWidgets('a selected preview row is tinted and says selected to a screen reader', (t) async {
      final h = t.ensureSemantics();
      await _pump(t);
      await _whereTab(t);
      await _tap(t, 'analyticsWhere-Rent');
      expect(find.bySemanticsLabel(RegExp(r'^Rent, 1 transaction, Ksh 1,500\.00\. Selected; tap to remove from the selection$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Shopping, 1 transaction, Ksh 1,200\.00\. Tap to add to the selection$')), findsOneWidget);
      Tristate toggled(String label) => t.getSemantics(find.bySemanticsLabel(RegExp('^$label,'))).flagsCollection.isToggled;
      expect(toggled('Rent'), Tristate.isTrue);
      expect(toggled('Shopping'), Tristate.isFalse);
      h.dispose();
    });

    testWidgets('Strip: two rows, top 6, then "See all N" (only above 6), no Categories button', (t) async {
      await _pump(t, rows: _nine(), prefs: {'where_it_went_style': 'strip'});
      await _whereTab(t);
      expect(_chip('analyticsCategoriesButton'), findsNothing);
      expect(_chip('analyticsWhereStrip'), findsOneWidget);
      for (final k in ['K8', 'K7', 'K6', 'K5', 'K4', 'K3']) {
        expect(_chip('analyticsWhere-$k'), findsOneWidget, reason: k);
      }
      expect(_chip('analyticsWhere-K2'), findsNothing, reason: 'only the top 6 are cards');
      // columns of two: K8 over K7
      expect(t.getTopLeft(_chip('analyticsWhere-K8')).dx, t.getTopLeft(_chip('analyticsWhere-K7')).dx);
      expect(t.getTopLeft(_chip('analyticsWhere-K8')).dy, lessThan(t.getTopLeft(_chip('analyticsWhere-K7')).dy));
      expect(find.text('See all 9'), findsOneWidget);
      // a card toggles, the others fade
      await _tap(t, 'analyticsWhere-K8');
      expect(_chipText(t, 'analyticsFilterChipClass'), 'K8 · Ksh 900');
      final fadedOpacity = t.widget<Opacity>(find.descendant(of: _chip('analyticsWhere-K7'), matching: find.byType(Opacity)).first).opacity;
      expect(fadedOpacity, 0.5);
      await t.ensureVisible(_chip('analyticsWhereSeeAll')); // the last card sits past the right edge
      await t.pumpAndSettle();
      await _tap(t, 'analyticsWhereSeeAll');
      expect(find.text('Categories (9)'), findsOneWidget);
    });

    testWidgets('Strip: 6 or fewer categories have no "See all"', (t) async {
      await _pump(t, prefs: {'where_it_went_style': 'strip'});
      await _whereTab(t);
      expect(_chip('analyticsWhere-Rent'), findsOneWidget);
      expect(_chip('analyticsWhereSeeAll'), findsNothing);
    });

    testWidgets('a junk style value gives the Button style', (t) async {
      await _pump(t, prefs: {'where_it_went_style': 'grid'});
      await _whereTab(t);
      expect(_chip('analyticsCategoriesButton'), findsOneWidget);
    });

    testWidgets('a period with no spending says there is nothing to break down', (t) async {
      await _pump(t, rows: const []);
      await _whereTab(t);
      expect(find.text('Nothing to break down in this period.'), findsOneWidget);
    });
  });

  group('hatched withdrawals in the chart (P-Analytics-06)', () {
    List<RRect> bars(WidgetTester t) {
      final cp = t.widget<CustomPaint>(find.byKey(const Key('analyticsChartPaint')));
      final canvas = TestRecordingCanvas();
      cp.painter!.paint(canvas, const Size(320, 146));
      final out = [
        for (final i in canvas.invocations)
          if (i.invocation.memberName == #clipRRect) i.invocation.positionalArguments[0] as RRect,
      ]..sort((a, b) => a.left.compareTo(b.left));
      return out;
    }

    int hatchLines(WidgetTester t) {
      final cp = t.widget<CustomPaint>(find.byKey(const Key('analyticsChartPaint')));
      final canvas = TestRecordingCanvas();
      cp.painter!.paint(canvas, const Size(320, 146));
      return canvas.invocations
          .where((i) => i.invocation.memberName == #drawLine && (i.invocation.positionalArguments[2] as Paint).strokeWidth == 2.0)
          .length;
    }

    String legend(WidgetTester t) => t.widget<Text>(find.byKey(const Key('analyticsChartLegend'))).data!;

    testWidgets('off (default): no hatch, bars are spending only, the legend says withdrawals are not shown', (t) async {
      await _pump(t);
      expect(hatchLines(t), 0);
      final b = bars(t);
      expect(b, hasLength(3), reason: 'Tue, Wed and Thu have spending');
      expect(b[1].height, closeTo(b[2].height * 1200 / 2350, 0.01), reason: 'the Wednesday withdrawal adds no height');
      expect(legend(t), 'Cash withdrawn is not shown here (not spending)');
    });

    testWidgets('on: a hatched segment tops the bar, the height includes it, the legend says what it is', (t) async {
      await _pump(t, prefs: {'show_withdrawals_in_chart': true});
      expect(hatchLines(t), greaterThan(0));
      expect(legend(t), 'Hatched = cash withdrawn, not spent');
      final b = bars(t);
      // Tue 22 (Cash 300), Wed 23 (Paybill 1,200 + withdrawn 5,000), Thu 24 (Send Money 1,500 + Buy Goods 850).
      expect(b, hasLength(3));
      expect(b[1].height, closeTo(b[2].height * 6200 / 2350, 0.01), reason: 'Wednesday is 1,200 spent plus 5,000 hatched');
      expect(b[0].height, closeTo(b[2].height * 300 / 2350, 0.01));
      expect(b[1].height, closeTo(6200 / niceAxisMax(6200) * 106, 0.01), reason: 'the axis is scaled to the bar with the hatch, so it stays inside the chart');
    });

    testWidgets('on or off, the Spent total, the average and every percentage exclude the withdrawal', (t) async {
      await _pump(t);
      final totalOff = _total(t);
      final shareOff = _tilePercent(t, 'SEND_MONEY');
      expect(find.textContaining('avg Ksh 963/day', findRichText: true), findsOneWidget, reason: '3,850 over the 4 days so far');
      await _pump(t, prefs: {'show_withdrawals_in_chart': true});
      expect(_total(t), totalOff);
      expect(totalOff, '3,850.00');
      expect(find.textContaining('avg Ksh 963/day', findRichText: true), findsOneWidget);
      expect(_tilePercent(t, 'SEND_MONEY'), shareOff);
    });

    testWidgets('the dashed average line stays on spending, hatch on or off', (t) async {
      // Live days Mon-Thu: (0 + 300 + 1,200 + 2,350) / 4 = 962.5, against Thursday's 2,350 bar.
      double avgOverThursday(WidgetTester t) {
        final cp = t.widget<CustomPaint>(find.byKey(const Key('analyticsChartPaint')));
        final canvas = TestRecordingCanvas();
        cp.painter!.paint(canvas, const Size(320, 146));
        final ys = {
          for (final i in canvas.invocations)
            if (i.invocation.memberName == #drawLine && ((i.invocation.positionalArguments[2] as Paint).strokeWidth - 1.2).abs() < 0.001)
              (i.invocation.positionalArguments[0] as Offset).dy,
        };
        expect(ys, hasLength(1));
        return (118 - ys.single) / bars(t).last.height; // 118 = the baseline of the chart space
      }

      await _pump(t);
      expect(avgOverThursday(t), closeTo(962.5 / 2350, 0.002));
      await _pump(t, prefs: {'show_withdrawals_in_chart': true});
      expect(avgOverThursday(t), closeTo(962.5 / 2350, 0.002));
    });

    testWidgets('a bar with a withdrawal says it to a screen reader', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, prefs: {'show_withdrawals_in_chart': true});
      expect(find.bySemanticsLabel(RegExp(r'Ksh 1,200\.00 spent, Ksh 5,000\.00 withdrawn \(not spent\)$')), findsOneWidget);
      h.dispose();
      final h2 = t.ensureSemantics();
      await _pump(t);
      expect(find.bySemanticsLabel(RegExp(r'withdrawn \(not spent\)')), findsNothing);
      h2.dispose();
    });

    testWidgets('a period with no withdrawal has no hatch line in its legend, either way', (t) async {
      await _pump(t, rows: [..._week()]..removeAt(4), prefs: {'show_withdrawals_in_chart': true});
      expect(find.byKey(const Key('analyticsChartLegend')), findsNothing);
      expect(hatchLines(t), 0);
    });

    testWidgets('the hatch legend joins the part-week note with " · "', (t) async {
      // Month by weeks, Sep 2026: the first and last weeks are part weeks.
      await _pump(t, prefs: {'show_withdrawals_in_chart': true});
      await t.tap(find.byKey(const Key('analyticsGranularity')));
      await t.pumpAndSettle();
      await t.tap(find.text('Month').last);
      await t.pumpAndSettle();
      expect(legend(t), 'Striped bar = part week (fewer than 7 days in this month) · Hatched = cash withdrawn, not spent');
    });

    testWidgets('only withdrawals in the period: the hatched bar shows, the chart is not "empty"', (t) async {
      final onlyWd = [_week()[4]];
      await _pump(t, rows: onlyWd, prefs: {'show_withdrawals_in_chart': true});
      expect(find.byKey(const Key('analyticsChartEmpty')), findsNothing);
      expect(hatchLines(t), greaterThan(0));
      await _pump(t, rows: onlyWd);
      expect(find.byKey(const Key('analyticsChartEmpty')), findsOneWidget);
    });
  });
}
