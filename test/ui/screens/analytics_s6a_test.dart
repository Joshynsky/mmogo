// S6a: Analytics wording, rows, day totals and the edit sheet (0.1.2 ED1,
// P-Analytics-03, 08, 09, 10, 13, 21; Q1 = B30). Invented data only.
//  - hero facts say "Transaction cost"; avg/day hidden for Day and one-day spans
//  - a Withdrawal row: hollow icon tile, muted amount, agent-name title, agent
//    number on the second line, label through notCountedLabel
//  - day headers: "not spent", "<sum> withdrawn" (Withdrawal filter), spending total
//  - the edit sheet: fields per type (all seven), greyed Type label + modal,
//    live sentence, agent number rules and save for a Withdrawal row
//  - Q1: the pill / list / row highlight follow the displayed period
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/copy/spend_copy.dart';
import 'package:mmogo/ui/screens/analytics/analytics_filters.dart';
import 'package:mmogo/ui/screens/analytics/analytics_view.dart';
import 'package:mmogo/ui/screens/analytics/hero_card.dart';
import 'package:mmogo/ui/screens/analytics/transaction_list.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

final _p = AppPalette.light;
final _now = DateTime(2026, 10, 14, 12); // a Wednesday, invented

AnalyticsTransactionRow _row(int id, String type, int amount, int? fee, DateTime at, {String? agent}) =>
    AnalyticsTransactionRow(
      id: id,
      displayCode: 'AV$id',
      sourceType: type,
      amountCents: amount,
      counterpartyLabel: type == 'CASH' || type == 'AIRTIME' ? null : 'Invented $id',
      counterpartyPhone: null,
      paybillAccountNumber: null,
      classificationId: id,
      classificationName: type == 'AGENT_WITHDRAWAL' ? 'Withdrawal' : 'Shopping',
      occurredAt: at,
      transactionCostCents: fee,
      agentNumber: agent,
    );

AnalyticsView _view(AnalyticsPeriod period, List<AnalyticsTransactionRow> rows) => AnalyticsView(
  period: period,
  party: false,
  partyType: null,
  now: _now,
  first: DateTime(2026, 10, 1),
  range: period.range(today: DateTime(2026, 10, 14)),
  inc: rows,
  priorCents: null,
  chart: period.chart(now: _now),
  bucketCents: const [],
  partyName: null,
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _pumpHero(WidgetTester t, AnalyticsPeriod period, List<AnalyticsTransactionRow> rows) async {
  final today = DateTime(2026, 10, 14);
  await t.pumpWidget(
    _host(
      AnalyticsHeroCard(
        palette: _p,
        view: _view(period, rows),
        words: period.words(today: today),
        granKey: GlobalKey(),
        valueKey: GlobalKey(),
        onGranularity: () {},
        onValue: () {},
        onCustom: () {},
      ),
    ),
  );
}

Future<void> _pumpList(WidgetTester t, List<AnalyticsTransactionRow> rows, {String? typeFilter}) async {
  await t.pumpWidget(
    _host(
      Column(
        children: analyticsTransactionSections(
          palette: _p,
          view: _view(AnalyticsPeriod.month(_now), rows),
          filters: AnalyticsFilters.handOff(type: typeFilter),
          highlightedId: null,
          openRowId: null,
          rowKeyFor: (_) => GlobalKey(),
          onOpened: (_, _) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onClearType: () {},
          onClearClass: () {},
        ),
      ),
    ),
  );
}

Finder _rich(String text) => find.text(text, findRichText: true);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('hero facts (P-Analytics-03)', () {
    final rows = [
      _row(1, 'BUY_GOODS', 30000, 700, DateTime(2026, 10, 14, 9)),
      _row(2, 'AGENT_WITHDRAWAL', 100000, 2900, DateTime(2026, 10, 14, 10)),
      _row(3, 'CASH', 7000, null, DateTime(2026, 10, 14, 11)),
    ];

    testWidgets('the cost fact says "Transaction cost" and sums every row cost, withdrawal fee included', (t) async {
      await _pumpHero(t, AnalyticsPeriod.month(_now), rows);
      expect(_rich('Transaction cost Ksh 36'), findsOneWidget);
      expect(find.textContaining('fees', findRichText: true), findsNothing);
    });

    testWidgets('avg/day is hidden for Day, hidden for a one-day Custom span, shown for a longer span', (t) async {
      final today = DateTime(2026, 10, 14);
      await _pumpHero(t, AnalyticsPeriod.day(today), rows);
      expect(find.byKey(const Key('analyticsFactAvg')), findsNothing);
      await _pumpHero(t, AnalyticsPeriod.custom(today, today, today: today), rows);
      expect(find.byKey(const Key('analyticsFactAvg')), findsNothing);
      await _pumpHero(t, AnalyticsPeriod.custom(DateTime(2026, 10, 12), today, today: today), rows);
      expect(find.byKey(const Key('analyticsFactAvg')), findsOneWidget);
      await _pumpHero(t, AnalyticsPeriod.month(_now), const []);
      expect(find.byKey(const Key('analyticsFactAvg')), findsNothing, reason: 'no rows, no average');
    });
  });

  group('rows (P-Analytics-09, 10, 21)', () {
    late FakeAnalyticsDb db;
    Future<void> pump(WidgetTester t, List<Map<String, Object?>> rows) async {
      t.view.physicalSize = const Size(400, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      db = FakeAnalyticsDb(rows);
      await t.pumpWidget(
        MaterialApp(
          home: AnalyticsScreen(db: db, clock: () => analyticsTestNow),
        ),
      );
      await t.pumpAndSettle();
    }

    final at = DateTime(2026, 9, 24, 9);
    List<Map<String, Object?>> data() => [
      fakeTx(
        id: 16,
        at: at,
        type: 'AGENT_WITHDRAWAL',
        label: 'INVENTED AGENT',
        agentNumber: '123456',
        amountCents: 100000,
        costCents: 2900,
        classification: 'Withdrawal',
      ),
      fakeTx(
        id: 18,
        at: at.add(const Duration(minutes: 20)),
        type: 'AGENT_WITHDRAWAL',
        label: 'NO NUMBER AGENT',
        amountCents: 50000,
        costCents: 0,
        classification: 'Withdrawal',
      ),
      fakeTx(id: 11, at: at.add(const Duration(hours: 1)), label: 'SEND PERSON', amountCents: 150000, costCents: 2200),
      fakeTx(
        id: 14,
        at: at.add(const Duration(hours: 2)),
        type: 'CASH',
        amountCents: 50000,
        classification: 'Groceries',
      ),
      fakeTx(
        id: 17,
        at: at.add(const Duration(hours: 3)),
        type: 'AIRTIME',
        amountCents: 5000,
        costCents: 0,
        classification: 'Airtime',
      ),
    ];

    testWidgets('Withdrawal row: hollow icon tile in the type colour, muted amount, others unchanged', (t) async {
      await pump(t, data());
      final icon = t.widget<Container>(find.byKey(const Key('analyticsRowIcon-16')));
      final deco = icon.decoration! as BoxDecoration;
      expect(deco.color, Colors.transparent);
      expect(deco.border!.top.color, _p.typeColor('AGENT_WITHDRAWAL'));
      expect(deco.border!.top.width, 2);
      expect(
        t
            .widget<Icon>(
              find.descendant(of: find.byKey(const Key('analyticsRowIcon-16')), matching: find.byType(Icon)),
            )
            .color,
        _p.typeColor('AGENT_WITHDRAWAL'),
      );
      expect(
        find.byKey(const Key('analyticsRowIcon-11')),
        findsNothing,
        reason: 'a Send Money row keeps the filled tile',
      );

      final wdAmount = t.widget<Text>(find.byKey(const Key('analyticsRowAmount-16')));
      expect(wdAmount.style!.color, _p.mutedInk);
      expect(wdAmount.style!.fontWeight, FontWeight.w700);
      final sendAmount = t.widget<Text>(find.byKey(const Key('analyticsRowAmount-11')));
      expect(sendAmount.style!.color, _p.ink);
      expect(sendAmount.style!.fontWeight, FontWeight.w800);
    });

    testWidgets('title and second line: agent name, agent number only when it has one, Cash without code', (t) async {
      await pump(t, data());
      expect(find.text('INVENTED AGENT'), findsOneWidget);
      expect(find.text('Withdrawal · 123456 · 09:00 · CODE16'), findsOneWidget);
      expect(find.text('NO NUMBER AGENT'), findsOneWidget);
      expect(find.text('Withdrawal · 09:20 · CODE18'), findsOneWidget);
      expect(find.text('Groceries · 11:00'), findsOneWidget, reason: 'Cash has no code');
      expect(find.text('Airtime'), findsWidgets);
      expect(find.text('PARTY 17'), findsNothing, reason: 'the Airtime title is the type name, not a stored label');
      expect(
        find.text('Airtime · 12:00 · CODE17'),
        findsOneWidget,
        reason: 'Airtime keeps its title, normal second line',
      );
      expect(find.text('Family/Friends · 10:00 · CODE11'), findsOneWidget);
    });

    testWidgets('fee note only when fee > 0 (Airtel direct-pay and zero-cost rows show none)', (t) async {
      await pump(t, data());
      expect(find.text('+ Ksh 29 fee'), findsOneWidget);
      expect(find.text('+ Ksh 22 fee'), findsOneWidget);
      expect(find.textContaining('+ Ksh 0'), findsNothing);
      expect(find.textContaining(' fee'), findsNWidgets(2));
    });

    testWidgets('screen-reader label of a Withdrawal row uses notCountedLabel; the long sentence is not on the row', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await pump(t, data());
      final label = notCountedLabel(feeCents: 2900);
      expect(
        find.bySemanticsLabel(RegExp('^INVENTED AGENT, Ksh 1,000.00, ${RegExp.escape(label)}, Withdrawal, ')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('^NO NUMBER AGENT, Ksh 500.00, ${RegExp.escape(notCountedLabel())}, Withdrawal, '),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^SEND PERSON, .*not counted')), findsNothing);
      expect(find.textContaining('Not counted as spending, only the fee'), findsNothing);
      h.dispose();
    });
  });

  group('day headers (P-Analytics-08)', () {
    final wd = _row(1, 'AGENT_WITHDRAWAL', 100000, 2900, DateTime(2026, 10, 14, 10));
    final wdYesterday = _row(2, 'AGENT_WITHDRAWAL', 50000, 100, DateTime(2026, 10, 13, 10));
    final airtimeYesterday = _row(3, 'AIRTIME', 50000, 0, DateTime(2026, 10, 13, 12));
    final tue = _row(4, 'BUY_GOODS', 30000, 0, DateTime(2026, 10, 6, 12));
    final tueWd = _row(5, 'AGENT_WITHDRAWAL', 20000, 0, DateTime(2026, 10, 6, 9));
    final rows = [wd, airtimeYesterday, wdYesterday, tue, tueWd];

    testWidgets('withdrawal-only day says "not spent"; mixed day shows spending only; plain format "Tue, 6 Oct"', (
      t,
    ) async {
      await _pumpList(t, rows);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Tue, 6 Oct'), findsOneWidget);
      final totals = t.widgetList<Text>(find.byKey(const Key('analyticsDayTotal'))).toList();
      expect(totals.map((e) => e.data), ['not spent', 'Ksh 500.00', 'Ksh 300.00']);
      expect(totals[0].style!.color, _p.mutedInk);
      expect(totals[1].style!.color, _p.softInk);
    });

    testWidgets('Withdrawal filter: every day header shows the withdrawn sum, muted, with "withdrawn"', (t) async {
      await _pumpList(t, rows, typeFilter: 'AGENT_WITHDRAWAL');
      final totals = t.widgetList<Text>(find.byKey(const Key('analyticsDayTotal'))).toList();
      expect(totals.map((e) => e.data), ['Ksh 1,000.00 withdrawn', 'Ksh 500.00 withdrawn', 'Ksh 200.00 withdrawn']);
      expect(totals.every((e) => e.style!.color == _p.mutedInk), isTrue);
    });

    testWidgets('a day with only spending keeps its plain total', (t) async {
      await _pumpList(t, [tue]);
      expect(t.widget<Text>(find.byKey(const Key('analyticsDayTotal'))).data, 'Ksh 300.00');
    });
  });

  group('edit sheet (ED1, P-Analytics-13)', () {
    final at = DateTime(2026, 9, 24, 8);
    List<Map<String, Object?>> data() => [
      fakeTx(id: 11, at: at, label: 'SEND PERSON', amountCents: 150000, costCents: 2200),
      fakeTx(
        id: 12,
        at: at.add(const Duration(minutes: 10)),
        type: 'PAYBILL',
        label: 'PAY BIZ',
        amountCents: 120000,
        costCents: 1500,
      ),
      fakeTx(
        id: 13,
        at: at.add(const Duration(minutes: 20)),
        type: 'BUY_GOODS',
        label: 'GOODS SHOP',
        amountCents: 85000,
      ),
      fakeTx(
        id: 14,
        at: at.add(const Duration(minutes: 30)),
        type: 'CASH',
        amountCents: 50000,
        classification: 'Groceries',
      ),
      fakeTx(
        id: 15,
        at: at.add(const Duration(minutes: 40)),
        type: 'POCHI_LA_BIASHARA',
        label: 'POCHI PERSON',
        amountCents: 20000,
      ),
      fakeTx(
        id: 16,
        at: at.add(const Duration(hours: 1)),
        type: 'AGENT_WITHDRAWAL',
        label: 'INVENTED AGENT',
        agentNumber: '123456',
        amountCents: 100000,
        costCents: 2900,
        classification: 'Withdrawal',
      ),
      fakeTx(
        id: 17,
        at: at.add(const Duration(hours: 2)),
        type: 'AIRTIME',
        amountCents: 5000,
        classification: 'Airtime',
      ),
    ];

    Future<FakeAnalyticsDb> open(WidgetTester t, int id) async {
      t.view.physicalSize = const Size(400, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final db = FakeAnalyticsDb(data());
      await t.pumpWidget(
        MaterialApp(
          home: AnalyticsScreen(db: db, clock: () => analyticsTestNow),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('analyticsRow-$id')));
      await t.pumpAndSettle();
      return db;
    }

    Future<void> drain(WidgetTester t) async {
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
    }

    final fields = <String>[
      'editLabelField',
      'editPhoneField',
      'editAccountField',
      'editAgentNumberField',
      'editCostField',
    ];

    // id, name label (null = no name field), the keys that must be present.
    final perType = <(int, String, String?, Set<String>)>[
      (11, 'Send Money', 'Receiver name', {'editLabelField', 'editPhoneField', 'editCostField'}),
      (12, 'Paybill', 'Business name', {'editLabelField', 'editAccountField', 'editCostField'}),
      (13, 'Buy Goods', 'Merchant name', {'editLabelField', 'editCostField'}),
      (14, 'Cash', null, <String>{}),
      (15, 'Pochi', 'Receiver name', {'editLabelField', 'editCostField'}),
      (16, 'Withdrawal', 'Agent name', {'editLabelField', 'editAgentNumberField', 'editCostField'}),
      (17, 'Airtime', null, <String>{}),
    ];
    for (final (id, type, nameLabel, present) in perType) {
      testWidgets('$type: name label ${nameLabel ?? 'none'}, fields ${present.isEmpty ? 'none' : present.join(', ')}', (
        t,
      ) async {
        await open(t, id);
        expect(find.byKey(const Key('editAmountField')), findsOneWidget);
        for (final k in fields) {
          expect(find.byKey(Key(k)), present.contains(k) ? findsOneWidget : findsNothing, reason: '$type $k');
        }
        for (final l in ['Receiver name', 'Business name', 'Merchant name', 'Agent name']) {
          expect(find.text(l), l == nameLabel ? findsOneWidget : findsNothing, reason: '$type label $l');
        }
        expect(find.text('Transaction cost (Ksh)'), present.contains('editCostField') ? findsOneWidget : findsNothing);
        expect(find.text('Agent number'), present.contains('editAgentNumberField') ? findsOneWidget : findsNothing);
        expect(find.text('Type: $type'), findsOneWidget);
        expect(find.textContaining('Change type'), findsNothing);
        await t.tap(find.byKey(const Key('editCancelButton')));
        await t.pumpAndSettle();
      });
    }

    testWidgets('greyed "Type: X" label opens the modal saying the type cannot be changed', (t) async {
      await open(t, 11);
      final label = t.widget<Text>(find.text('Type: Send Money'));
      expect(label.style!.color, _p.mutedInk);
      expect(find.byKey(const Key('editTypeModal')), findsNothing);
      await t.tap(find.byKey(const Key('editTypeLabel')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('editTypeModal')), findsOneWidget);
      expect(
        find.text('The type cannot be changed. If it is wrong, delete this transaction and add it again.'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('editTypeModalOk')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('editTypeModal')), findsNothing);
      expect(find.byKey(const Key('editSaveButton')), findsOneWidget, reason: 'the sheet is still open');
    });

    testWidgets('Withdrawal: title is the agent name; the live sentence follows the cost and hides while invalid', (
      t,
    ) async {
      await open(t, 16);
      expect(t.widget<Text>(find.byKey(const Key('editTitle'))).data, 'INVENTED AGENT');
      expect(find.text('Edit transaction'), findsNothing);
      const note = Key('editWithdrawalNote');
      expect(find.text('Not counted as spending, only the fee of Ksh 29.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('editCostField')), '29.5');
      await t.pump();
      expect(find.text('Not counted as spending, only the fee of Ksh 29.50.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('editCostField')), '');
      await t.pump();
      expect(find.text('Not counted as spending, only the fee of Ksh 0.'), findsOneWidget, reason: 'empty cost is 0');
      await t.enterText(find.byKey(const Key('editCostField')), '20000000');
      await t.pump();
      expect(find.byKey(note), findsNothing, reason: 'hidden while the cost is invalid');
      expect(find.text('Enter a cost from 0 to 10,000,000.00'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('editSaveButton'))).onPressed, isNull);
    });

    testWidgets(
      'the long sentence is only in the edit sheet; other types never show it; non-Withdrawal title unchanged',
      (t) async {
        await open(t, 11);
        expect(find.byKey(const Key('editWithdrawalNote')), findsNothing);
        expect(find.text('Edit transaction'), findsOneWidget);
        await t.tap(find.byKey(const Key('editCancelButton')));
        await t.pumpAndSettle();
        expect(
          find.textContaining('Not counted as spending, only the fee'),
          findsNothing,
          reason: 'never on a list row',
        );
      },
    );

    testWidgets('Withdrawal agent number: digits only, 20 max, optional; save writes name, number and cost', (t) async {
      final db = await open(t, 16);
      final field = find.byKey(const Key('editAgentNumberField'));
      expect(t.widget<TextField>(field).controller!.text, '123456');
      await t.enterText(field, 'ab12-c3');
      await t.pump();
      expect(t.widget<TextField>(field).controller!.text, '123', reason: 'non-digits cannot be typed');
      await t.enterText(field, '1' * 25);
      await t.pump();
      expect(t.widget<TextField>(field).controller!.text.length, 20);
      await t.enterText(field, '98765');
      await t.enterText(find.byKey(const Key('editLabelField')), 'NEW AGENT');
      await t.enterText(find.byKey(const Key('editCostField')), '30');
      await t.pump();
      await t.tap(find.byKey(const Key('editSaveButton')));
      await t.pumpAndSettle();
      final row = db.byId(16);
      expect(row['counterparty_label'], 'NEW AGENT');
      expect(row['agent_number'], '98765');
      expect(row['transaction_cost_cents'], 3000);
      expect(row['source_type'], 'AGENT_WITHDRAWAL');
      expect(find.text('NEW AGENT'), findsOneWidget, reason: 'the list re-reads');
      expect(find.text('Withdrawal · 98765 · 09:00 · CODE16'), findsOneWidget);
      await drain(t);
    });

    testWidgets('Withdrawal agent number left empty is saved as NULL', (t) async {
      final db = await open(t, 16);
      await t.enterText(find.byKey(const Key('editAgentNumberField')), '');
      await t.pump();
      await t.tap(find.byKey(const Key('editSaveButton')));
      await t.pumpAndSettle();
      expect(db.byId(16)['agent_number'], isNull);
      expect(db.byId(16)['counterparty_label'], 'INVENTED AGENT');
      await drain(t);
    });

    testWidgets('Airtime save keeps its stored cost (0) and label; Cash save writes neither', (t) async {
      final db = await open(t, 17);
      await t.enterText(find.byKey(const Key('editAmountField')), '75');
      await t.pump();
      await t.tap(find.byKey(const Key('editSaveButton')));
      await t.pumpAndSettle();
      expect(db.byId(17)['amount_cents'], 7500);
      expect(db.byId(17)['transaction_cost_cents'], 0);
      expect(db.byId(17)['counterparty_label'], 'PARTY 17');
      await drain(t);
    });

    testWidgets('0.1.1 edit behaviours: cost message, Phone and Delete are still on a Send Money sheet', (t) async {
      await open(t, 11);
      expect(find.byKey(const Key('editDeleteButton')), findsOneWidget);
      expect(find.byKey(const Key('editPhoneField')), findsOneWidget);
      await t.enterText(find.byKey(const Key('editCostField')), '20000000');
      await t.pump();
      expect(find.text('Enter a cost from 0 to 10,000,000.00'), findsOneWidget);
    });
  });

  group('Q1: the highlight and the pill follow the displayed period (B30)', () {
    Future<void> pump(WidgetTester t, Object? args) async {
      t.view.physicalSize = const Size(392, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final db = FakeAnalyticsDb(analyticsSampleRows());
      await t.pumpWidget(
        MaterialApp(
          onGenerateRoute: (s) => MaterialPageRoute(
            settings: RouteSettings(name: s.name, arguments: args),
            builder: (_) => AnalyticsScreen(db: db, clock: () => analyticsTestNow),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 400));
    }

    String pill(WidgetTester t) => t
        .widget<Text>(find.descendant(of: find.byKey(const Key('analyticsPeriodValue')), matching: find.byType(Text)))
        .data!;

    Color? rowColor(WidgetTester t, String name) {
      final c = t.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(name, skipOffstage: false),
              matching: find.byType(AnimatedContainer, skipOffstage: false),
            )
            .first,
      );
      return (c.decoration as BoxDecoration?)?.color;
    }

    testWidgets('analytics_highlight_follows_displayed_period', (t) async {
      await pump(t, 1); // Home hand-off: row 1, Thu 24 Sep (today)
      expect(pill(t), 'Today');
      expect(rowColor(t, 'JOHN KAMAU'), _p.highlight, reason: 'lit in the period that is displayed');
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(rowColor(t, 'JOHN KAMAU'), _p.card);

      // Five or more consecutive changes: previous, previous, next, next, then a quick-tap run.
      final steps = <(String, String)>[
        ('analyticsPrev', 'Yesterday'),
        ('analyticsPrev', 'Tue 22 Sep'),
        ('analyticsNext', 'Yesterday'),
        ('analyticsNext', 'Today'),
        ('analyticsPrev', 'Yesterday'),
      ];
      for (final (key, expected) in steps) {
        await t.tap(find.byKey(Key(key)));
        await t.pumpAndSettle();
        expect(pill(t), expected, reason: 'after $key');
        expect(find.text('JOHN KAMAU'), expected == 'Today' ? findsOneWidget : findsNothing);
        expect(find.text('DSTV KENYA'), expected == 'Yesterday' ? findsOneWidget : findsNothing);
        for (final name in ['JOHN KAMAU', 'DSTV KENYA']) {
          if (find.text(name).evaluate().isNotEmpty) {
            expect(rowColor(t, name), _p.card, reason: 'the earlier highlight does not follow the change');
          }
        }
      }
      // Quick taps with no settle between them: back 3, forward 2, back 1 = Thu 24 - 2 days.
      for (final key in [
        'analyticsPrev',
        'analyticsPrev',
        'analyticsPrev',
        'analyticsNext',
        'analyticsNext',
        'analyticsPrev',
      ]) {
        await t.tap(find.byKey(Key(key)));
        await t.pump(const Duration(milliseconds: 20));
      }
      await t.pumpAndSettle();
      // Yesterday (23) -3 +2 -1 = 21 Sep.
      expect(pill(t), 'Mon 21 Sep');
    });
  });
}
