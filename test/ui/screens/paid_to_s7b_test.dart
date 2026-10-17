// S7b (PT1) — Paid to, the new look on the five-type domain, driven against
// FakeAnalyticsDb: expand/collapse pills, counts that agree everywhere, the
// Pochi and Withdrawal sections, the Not recorded line, the Withdrawn hero, the
// four sorts, search by phone / account / agent number, the recipient sheet
// (Month per week, Year per month, closing, focus) and the Analytics hand-off
// for Pochi and Withdrawal recipients. The 0.1.1 basics are in
// paid_to_screen_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

const _pochi = 'POCHI_LA_BIASHARA';
const _wd = 'AGENT_WITHDRAWAL';

Map<String, Object?> _tx(
  int id,
  String type,
  int day,
  int ksh, {
  String? label,
  String? phone,
  String? agent,
  String? account,
  int cost = 0,
  String cls = 'Family/Friends',
  int month = 9,
}) {
  final r = fakeTx(
    id: id,
    at: DateTime(2026, month, day, 10),
    type: type,
    amountCents: ksh * 100,
    costCents: cost * 100,
    label: label,
    phone: phone,
    account: account,
    agentNumber: agent,
    classification: cls,
  );
  r['counterparty_label'] = label; // fakeTx invents a name when none is given
  r['counterparty_phone'] = phone;
  return r;
}

/// Sep 2026 (the screen's month), "now" Thu 24 Sep. Recipients: SM ANN (two phone forms, Rent), BOB;
/// PB DSTV; BG NAIVAS; Pochi MAMA MBOGA (two phone forms), JUICE BAR (name only); agents JOY AGENT
/// (number 314159, twice) and KAMAU AGENT (name only). Not recorded: SM 300, Pochi 100, Withdrawal 500.
/// Never listed: Airtime and Cash. Aug: ANN 700.
///  Paid out: 5,000 (10 payments, cost 62) to 6 recipients, + 2 agents (cost of withdrawals 120).
List<Map<String, Object?>> _rows() => [
  _tx(1, 'SEND_MONEY', 3, 1000, label: 'ANN', phone: '0722114455', cost: 20, cls: 'Rent'),
  _tx(2, 'SEND_MONEY', 10, 500, label: 'ANN', phone: '+254722114455', cost: 10, cls: 'Rent'),
  _tx(3, 'SEND_MONEY', 20, 300, label: 'BOB', phone: '0733000001'),
  _tx(4, 'PAYBILL', 23, 1200, label: 'DSTV KENYA', account: '5566', cost: 15, cls: 'Shopping'),
  _tx(5, 'BUY_GOODS', 24, 850, label: 'NAIVAS', cls: 'Shopping'),
  _tx(6, _pochi, 5, 400, label: 'MAMA MBOGA', phone: '0744000009', cost: 5),
  _tx(7, _pochi, 15, 200, label: 'MAMA MBOGA', phone: '254744000009', cost: 3),
  _tx(8, _pochi, 9, 150, label: 'JUICE BAR'),
  _tx(9, _pochi, 11, 100, cost: 2),
  _tx(10, _wd, 4, 2000, label: 'JOY AGENT', agent: '314159', cost: 30),
  _tx(11, _wd, 18, 3000, label: 'JOY AGENT', agent: '314159', cost: 45),
  _tx(12, _wd, 12, 1000, label: 'KAMAU AGENT', cost: 25),
  _tx(13, _wd, 13, 500, cost: 20),
  _tx(14, 'SEND_MONEY', 14, 300, cost: 7),
  _tx(15, 'AIRTIME', 2, 100),
  _tx(16, 'CASH', 8, 50),
  _tx(17, 'SEND_MONEY', 15, 700, label: 'ANN', phone: '0722114455', cost: 10, cls: 'Rent', month: 8),
];

final _opened = <AnalyticsRouteArgs>[];

Future<FakeAnalyticsDb> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>>? rows,
  bool realAnalytics = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(392, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  _opened.clear();
  final db = FakeAnalyticsDb(rows ?? _rows());
  await tester.pumpWidget(
    MaterialApp(
      home: PaidToScreen(db: db, clock: () => analyticsTestNow),
      onGenerateRoute: (settings) {
        if (settings.name != '/analytics') return null;
        _opened.add(settings.arguments! as AnalyticsRouteArgs);
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => realAnalytics
              ? AnalyticsScreen(db: db, clock: () => analyticsTestNow)
              : const Scaffold(body: Text('ANALYTICS')),
        );
      },
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Finder _rich(String s) => find.text(s, findRichText: true);

String _plain(Text t) => t.data ?? t.textSpan?.toPlainText() ?? '';

/// Every text under [key] (or the Text itself), joined with " | ".
String _text(WidgetTester tester, Key key) {
  final f = find.byKey(key);
  final w = f.evaluate().single.widget;
  if (w is Text) return _plain(w);
  return find
      .descendant(of: f, matching: find.byType(Text))
      .evaluate()
      .map((e) => _plain(e.widget as Text))
      .join(' | ');
}

/// Text inside the open bottom sheet only (the list behind it repeats the row's figures).
Finder _inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

String _row(WidgetTester tester, String key) => _text(tester, ValueKey('paidToRow-$key'));

Future<void> _applyFilter(WidgetTester tester, {String? cls, String? sort}) async {
  await tester.tap(find.byKey(const Key('paidToFilterButton')));
  await tester.pumpAndSettle();
  if (cls != null) await tester.tap(find.byKey(Key('paidToCat-$cls')));
  if (sort != null) await tester.tap(find.byKey(Key('paidToSort-$sort')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('paidToShow')));
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String? type) async {
  final k = find.byKey(Key('paidToTab-${type ?? 'all'}'));
  await tester.ensureVisible(k);
  await tester.pumpAndSettle();
  await tester.tap(k);
  await tester.pumpAndSettle();
}

/// The number of recipients in a section sub line ("2 people · 3 payments · ...").
int _sectionN(WidgetTester tester, String type) {
  final f = find.byKey(Key('paidToSectionSub-$type'));
  if (f.evaluate().isEmpty) return 0;
  return int.parse(_plain(tester.widget<Text>(f)).split(' ').first);
}

/// What the Filter sheet's button says for the current view + a draft (nothing changed), then closes it.
Future<String> _showLabel(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('paidToFilterButton')));
  await tester.pumpAndSettle();
  final label = _text(tester, const Key('paidToShow'));
  await tester.tapAt(const Offset(200, 20)); // the scrim: no change
  await tester.pumpAndSettle();
  return label;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('five pills: All open ("All 6", recipients only), the others collapsed to their codes', (tester) async {
    final sem = tester.ensureSemantics();
    await _pump(tester);
    expect(_rich('All 6'), findsOneWidget);
    for (final code in ['SM', 'PB', 'BG', 'P', 'W']) {
      expect(find.text(code), findsOneWidget, reason: code);
    }
    expect(find.text('Send Money 2'), findsNothing, reason: 'a collapsed pill shows no name and no count');
    // The full wording is in the aria label.
    expect(find.bySemanticsLabel('All, 6 recipients, 2 agents'), findsOneWidget);
    expect(find.bySemanticsLabel('Pochi, 2 recipients'), findsOneWidget);
    expect(find.bySemanticsLabel('Withdrawal, 2 agents'), findsOneWidget);

    await _tab(tester, _pochi);
    expect(_rich('Pochi 2'), findsOneWidget);
    expect(find.text('P'), findsNothing, reason: 'the open pill drops its code');
    expect(find.text('All'), findsOneWidget, reason: 'the previous pill collapses back to its code');
    expect(_rich('All 6'), findsNothing);

    await _tab(tester, _wd);
    expect(_rich('Withdrawal 2'), findsOneWidget); // W: its agents
    expect(find.text('P'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('sections: Pochi and Withdrawal by agent, the sub lines, and a Not recorded line per type', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('POCHI'), findsOneWidget);
    expect(find.text('2 businesses · 3 payments · Transaction cost Ksh 8'), findsOneWidget);
    expect(find.text('WITHDRAWAL · BY AGENT'), findsOneWidget);
    expect(find.text('2 agents · 3 withdrawals · Transaction cost Ksh 100'), findsOneWidget);
    expect(find.text('2 people · 3 payments · Transaction cost Ksh 30'), findsOneWidget);
    expect(find.text('1 bill · 1 payment · Transaction cost Ksh 15'), findsOneWidget);
    expect(find.text('1 shop · 1 payment · Transaction cost Ksh 0'), findsOneWidget);
    // Rows: the agent shows its number, the Pochi business its (local) phone or "Pochi".
    expect(_row(tester, '$_wd|no|314159'), contains('Last 18 Sep · Agent 314159'));
    expect(_row(tester, '$_wd|name|KAMAU AGENT'), contains('Agent number not recorded'));
    expect(_row(tester, '$_pochi|tel|0744000009'), contains('Last 15 Sep · 0744000009'));
    expect(_row(tester, '$_pochi|name|JUICE BAR'), contains('Last 9 Sep · Pochi'));
    // One muted line per type, plain in the overview when the type has recipients; no tap target.
    for (final t in ['SEND_MONEY', _pochi, _wd]) {
      expect(find.byKey(Key('paidToNotRecorded-$t')), findsOneWidget, reason: t);
    }
    expect(_text(tester, const Key('paidToNotRecorded-SEND_MONEY')), 'Not recorded · 1 payment · Ksh 300');
    expect(_text(tester, const Key('paidToNotRecorded-$_pochi')), 'Not recorded · 1 payment · Ksh 100');
    expect(_text(tester, const Key('paidToNotRecorded-$_wd')), 'Not recorded · 1 withdrawal · Ksh 500');
    expect(find.byKey(const Key('paidToNotRecorded-PAYBILL')), findsNothing, reason: 'nothing unrecorded there');
    expect(find.textContaining('Airtime'), findsNothing);
    expect(find.textContaining('Cash'), findsNothing);
  });

  testWidgets('the hero: Paid out with its cost lines, agents apart; the W pill reads Withdrawn', (tester) async {
    await _pump(tester);
    expect(_text(tester, const Key('paidToHeroLabel')), 'Paid out');
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '5,000.00'); // Not recorded money included
    expect(_rich('Transaction cost Ksh 62.00'), findsOneWidget);
    expect(_rich('to 6 recipients'), findsOneWidget); // Not recorded payments are not recipients
    expect(_rich('10 payments'), findsOneWidget);
    expect(_rich('+ 2 agents (cash out, not counted)'), findsOneWidget);
    expect(_rich('Transaction cost of withdrawals Ksh 120.00 (not in the figures above)'), findsOneWidget);

    await _tab(tester, _wd);
    expect(_text(tester, const Key('paidToHeroLabel')), 'Withdrawn');
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '6,500.00');
    expect(_rich('Transaction cost Ksh 120.00'), findsOneWidget);
    expect(_rich('from 2 agents'), findsOneWidget);
    expect(_rich('4 withdrawals'), findsOneWidget);
    expect(find.byKey(const Key('paidToFactAgents')), findsNothing);
    expect(find.byKey(const Key('paidToWithdrawalCost')), findsNothing);
    // Withdrawal list: both agents, the agent Not recorded line in its plain form (the type has agents).
    expect(find.text('JOY AGENT'), findsOneWidget);
    expect(find.text('KAMAU AGENT'), findsOneWidget);
    expect(find.text('Not recorded · 1 withdrawal · Ksh 500'), findsOneWidget);
    expect(
      find.byKey(const Key('paidToNotRecorded-SEND_MONEY')),
      findsNothing,
      reason: 'other types leave a type view',
    );
    expect(find.byKey(const Key('paidToNotRecorded-$_pochi')), findsNothing);
    expect(find.textContaining('Send Money · Not recorded'), findsNothing);

    await _tab(tester, null);
    expect(_text(tester, const Key('paidToHeroLabel')), 'Paid out');
  });

  testWidgets('counts agree: the All pill, the section headers, "Show N" and the hero, with a category and a search', (
    tester,
  ) async {
    await _pump(tester);

    Future<void> expectAgree(String situation, {required int rec, required int ag, required String show}) async {
      expect(_text(tester, const Key('paidToTab-all')), 'All $rec', reason: '$situation: pill');
      final secRec = [
        for (final t in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', _pochi]) _sectionN(tester, t),
      ].fold<int>(0, (a, b) => a + b);
      expect(secRec, rec, reason: '$situation: sections');
      expect(_sectionN(tester, _wd), ag, reason: '$situation: agents');
      expect(await _showLabel(tester), 'Show $show', reason: '$situation: Show N');
    }

    await expectAgree('no filter', rec: 6, ag: 2, show: '6 + 2 agents');
    expect(_rich('to 6 recipients'), findsOneWidget); // the hero agrees with the pill when nothing narrows

    await _applyFilter(tester, cls: 'Rent');
    await expectAgree('category Rent', rec: 1, ag: 0, show: '1');
    expect(_rich('to 6 recipients'), findsOneWidget, reason: 'the hero is the whole period');
    await tester.tap(find.byKey(const Key('paidToChipCategory')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('paidToSearch')), 'mama');
    await tester.pumpAndSettle();
    await expectAgree('search mama', rec: 1, ag: 0, show: '1');
    expect(_rich('to 6 recipients'), findsOneWidget, reason: 'the hero ignores the search');

    await tester.enterText(find.byKey(const Key('paidToSearch')), 'agent');
    await tester.pumpAndSettle();
    await expectAgree('search agent', rec: 0, ag: 2, show: '0 + 2 agents');
  });

  testWidgets('the W view: Show N counts agents; a type view counts its recipients', (tester) async {
    await _pump(tester);
    await _tab(tester, _wd);
    expect(await _showLabel(tester), 'Show 2 agents');
    await _tab(tester, _pochi);
    expect(await _showLabel(tester), 'Show 2');
    expect(_text(tester, const Key('paidToTab-$_pochi')), 'Pochi 2');
  });

  testWidgets(
    'Not recorded: with the type name when the type has no recipients, plain in a type view that has some; no tap',
    (tester) async {
      // A Send Money recipient, and a Buy Goods payment with no name: BG has no recipient at all.
      await _pump(
        tester,
        rows: [
          _tx(1, 'SEND_MONEY', 5, 500, label: 'ANN', phone: '0722114455', cost: 10),
          _tx(2, 'BUY_GOODS', 6, 300, cost: 3),
        ],
      );
      expect(_text(tester, const Key('paidToNotRecorded-BUY_GOODS')), 'Buy Goods · Not recorded · 1 payment · Ksh 300');
      expect(find.text('BUY GOODS'), findsNothing, reason: 'no section for a type without recipients');
      expect(find.byKey(const Key('paidToEmpty')), findsNothing);
      // The money and cost stay in the hero; the payment is not a recipient.
      expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '800.00');
      expect(_rich('to 1 recipients'), findsNothing);
      expect(_rich('to 1 recipient'), findsOneWidget);
      expect(_rich('2 payments'), findsOneWidget);
      expect(_rich('Transaction cost Ksh 13.00'), findsOneWidget);

      // BG type view: still with the type name (the type has no recipients); the pill count is 0.
      await _tab(tester, 'BUY_GOODS');
      expect(_rich('Buy Goods 0'), findsOneWidget);
      expect(_text(tester, const Key('paidToNotRecorded-BUY_GOODS')), 'Buy Goods · Not recorded · 1 payment · Ksh 300');
      expect(await _showLabel(tester), 'Show 0');

      // No tap: not a button, nothing opens.
      await tester.tap(find.byKey(const Key('paidToNotRecorded-BUY_GOODS')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paidToSheetName')), findsNothing);
      expect(_opened, isEmpty);

      // Hidden while searching.
      await tester.enterText(find.byKey(const Key('paidToSearch')), 'x');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paidToNotRecorded-BUY_GOODS')), findsNothing);
      expect(find.text('No one matches “x”.'), findsOneWidget);
    },
  );

  testWidgets('a type view with recipients shows the Not recorded line in its plain form', (tester) async {
    await _pump(tester);
    await _tab(tester, 'SEND_MONEY');
    expect(_text(tester, const Key('paidToNotRecorded-SEND_MONEY')), 'Not recorded · 1 payment · Ksh 300');
  });

  testWidgets('the Not recorded amounts follow the category; a term hides them', (tester) async {
    await _pump(tester);
    await _applyFilter(tester, cls: 'Family/Friends');
    // Family/Friends: BOB, MAMA, JUICE, JOY x2, KAMAU, and the three Not recorded rows are all that class.
    expect(find.byKey(const Key('paidToNotRecorded-SEND_MONEY')), findsOneWidget);
    await tester.tap(find.byKey(const Key('paidToChipCategory')));
    await tester.pumpAndSettle();
    await _applyFilter(tester, cls: 'Rent');
    expect(
      find.byKey(const Key('paidToNotRecorded-SEND_MONEY')),
      findsNothing,
      reason: 'the unrecorded payment is not Rent',
    );
    await tester.enterText(find.byKey(const Key('paidToSearch')), 'ann');
    await tester.pumpAndSettle();
    expect(find.textContaining('Not recorded'), findsNothing);
  });

  testWidgets('sorts: Transaction cost shows the fee first; Amount and Times paid keep the fee note; no note at 0', (
    tester,
  ) async {
    await _pump(tester);
    // Amount (default): total, then "n× · + Ksh X fee"; a recipient with no cost has no note.
    expect(_row(tester, 'SEND_MONEY|0722114455'), contains('Ksh 1,500.00'));
    expect(_row(tester, 'SEND_MONEY|0722114455'), contains('2× · + Ksh 30 fee'));
    expect(_row(tester, 'SEND_MONEY|0733000001').split(' | ').last, '1×');
    expect(_row(tester, 'SEND_MONEY|0722114455'), startsWith('1 |'), reason: 'ranked: the rank number');

    await _applyFilter(tester, sort: 'timesPaid');
    expect(_row(tester, 'SEND_MONEY|0722114455'), contains('2×'));
    expect(_row(tester, 'SEND_MONEY|0722114455'), contains('Ksh 1,500 · + Ksh 30 fee'));

    await _applyFilter(tester, sort: 'fees');
    expect(find.text('Sorted: Transaction cost'), findsOneWidget);
    expect(_row(tester, 'SEND_MONEY|0722114455'), contains('Ksh 30.00'));
    expect(_row(tester, 'SEND_MONEY|0722114455'), contains('2× · Ksh 1,500 paid'));
    // A withdrawal row reads "withdrawn".
    expect(_row(tester, '$_wd|no|314159'), contains('2× · Ksh 5,000 withdrawn'));
    expect(_row(tester, '$_wd|no|314159'), contains('Ksh 75.00'));

    await _applyFilter(tester, sort: 'recent');
    // Most recent: BOB (20 Sep) first, and no rank number in front of the name.
    expect(_row(tester, 'SEND_MONEY|0733000001'), startsWith('BOB'), reason: 'Most recent has no rank number');
  });

  testWidgets('the merge note shows when one recipient holds two written forms of a number', (tester) async {
    await _pump(tester);
    expect(find.text('Some recipients were combined because their numbers match'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('paidToSearch')), 'bob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paidToMergeNote')), findsNothing);
  });

  group('search', () {
    testWidgets('a phone in any written form finds the one recipient (two forms stored)', (tester) async {
      await _pump(tester);
      for (final term in ['0722114455', '+254722114455', '254722114455', '722114455', '0722 114 455']) {
        await tester.enterText(find.byKey(const Key('paidToSearch')), term);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('paidToRow-SEND_MONEY|0722114455')), findsOneWidget, reason: term);
        expect(find.byKey(const ValueKey('paidToRow-SEND_MONEY|0733000001')), findsNothing, reason: term);
        expect(_text(tester, const Key('paidToTab-all')), 'All 1', reason: term);
      }
    });

    testWidgets('account number, agent number and a Pochi phone', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('paidToSearch')), '5566');
      await tester.pumpAndSettle();
      expect(find.text('DSTV KENYA'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('paidToSearch')), '314159');
      await tester.pumpAndSettle();
      expect(find.text('JOY AGENT'), findsOneWidget);
      expect(find.text('KAMAU AGENT'), findsNothing);
      await tester.enterText(find.byKey(const Key('paidToSearch')), '+254744000009');
      await tester.pumpAndSettle();
      expect(find.text('MAMA MBOGA'), findsOneWidget);
    });

    testWidgets('empty texts: no match, and no payments', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('paidToSearch')), 'nobody');
      await tester.pumpAndSettle();
      expect(find.text('No one matches “nobody”.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('paidToSearch')), '');
      await tester.pumpAndSettle();
      expect(find.text('No payments in this period.'), findsNothing);
    });
  });

  testWidgets('a type pill keeps the category when the new type has it, and drops it when not', (tester) async {
    final rows = [
      for (var i = 0; i < 5; i++)
        _tx(i + 1, 'SEND_MONEY', 3 + i, 100 + i, label: 'P$i', phone: '07110000$i', cls: i < 2 ? 'Rent' : 'Gift'),
      _tx(20, 'BUY_GOODS', 4, 90, label: 'SHOP', cls: 'Gift'),
      _tx(21, 'PAYBILL', 4, 90, label: 'BILL', account: '1', cls: 'Bills'),
    ];
    await _pump(tester, rows: rows);
    await _applyFilter(tester, cls: 'Gift');
    expect(find.byKey(const Key('paidToChipCategory')), findsOneWidget);
    await _tab(tester, 'BUY_GOODS'); // Buy Goods has Gift: kept
    expect(find.byKey(const Key('paidToChipCategory')), findsOneWidget);
    expect(find.text('SHOP'), findsOneWidget);
    await _tab(tester, 'PAYBILL'); // Paybill has no Gift: dropped
    expect(find.byKey(const Key('paidToChipCategory')), findsNothing);
    expect(find.text('BILL'), findsOneWidget);
  });

  testWidgets('See all N drops an applied category (the category is on, See all is on the list)', (tester) async {
    // 5 Send Money recipients in two categories; the category limits the overview, See all must reset it.
    final rows = [
      for (var i = 0; i < 5; i++)
        _tx(i + 1, 'SEND_MONEY', 3 + i, 100 + i, label: 'P$i', phone: '07110000$i', cls: 'Gift'),
      for (var i = 0; i < 5; i++)
        _tx(10 + i, 'SEND_MONEY', 3 + i, 50 + i, label: 'Q$i', phone: '07220000$i', cls: 'Rent'),
    ];
    await _pump(tester, rows: rows);
    await _applyFilter(tester, cls: 'Gift');
    expect(find.byKey(const Key('paidToChipCategory')), findsOneWidget);
    expect(find.byKey(const Key('paidToSeeAll-SEND_MONEY')), findsOneWidget);
    await tester.tap(find.byKey(const Key('paidToSeeAll-SEND_MONEY')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paidToChipCategory')), findsNothing);
    expect(find.text('Q0'), findsOneWidget, reason: 'both categories are back');
    expect(_text(tester, const Key('paidToTab-SEND_MONEY')), 'Send Money 10');
  });

  group('recipient sheet', () {
    testWidgets('Month: the row\'s own figures, per-week bars, the combined numbers, the category', (tester) async {
      await _pump(tester);
      final rowText = _row(tester, 'SEND_MONEY|0722114455');
      await tester.tap(find.byKey(const ValueKey('paidToRow-SEND_MONEY|0722114455')));
      await tester.pumpAndSettle();
      expect(_text(tester, const Key('paidToSheetName')), 'ANN');
      expect(_inSheet(find.text('Send Money · 0722114455')), findsOneWidget);
      // The figures equal the row (Sep only: the Aug payment is outside the period).
      expect(rowText, contains('Ksh 1,500.00'));
      expect(_inSheet(find.text('Ksh 1,500.00')), findsOneWidget); // Total paid
      expect(find.text('TOTAL PAID'), findsOneWidget);
      expect(find.text('PAYMENTS'), findsOneWidget);
      expect(_inSheet(find.text('2')), findsOneWidget);
      expect(_inSheet(find.text('Ksh 750.00')), findsOneWidget); // Average
      expect(_inSheet(find.text('Ksh 30.00')), findsOneWidget); // Transaction cost
      expect(find.text('3 Sep 2026'), findsOneWidget); // First payment
      expect(find.text('10 Sep 2026'), findsOneWidget); // Last payment
      expect(find.byKey(const Key('paidToSheetCombined')), findsOneWidget);
      expect(_text(tester, const Key('paidToSheetCombined')), contains('+254722114455'));
      expect(_text(tester, const Key('paidToSheetCombined')), contains('0722114455'));
      // PER 7 DAYS for Month (R34): blocks 1-7 .. 29-30, value labels compact.
      expect(_rich('PER 7 DAYS · Sep 2026 (days 1–7, 8–14 ...)'), findsOneWidget);
      for (final l in ['1–7', '8–14', '15–21', '22–28', '29–30']) {
        expect(
          find.descendant(of: find.byKey(const Key('paidToSheetChart')), matching: find.text(l)),
          findsOneWidget,
          reason: l,
        );
      }
      expect(find.descendant(of: find.byKey(const Key('paidToSheetChart')), matching: find.text('1k')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('paidToSheetChart')), matching: find.text('500')),
        findsOneWidget,
      );
      expect(_text(tester, const Key('paidToSheetCat-Rent')), 'Rent | 2× · Ksh 1,500');
      expect(find.text('See in Analytics'), findsOneWidget); // S7c: shorter label, side by side with Close
    });

    testWidgets('Year: one bar per month; the figures grow by the August payment and still equal the row', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('paidToGranularity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Year').last);
      await tester.pumpAndSettle();
      final rowText = _row(tester, 'SEND_MONEY|0722114455');
      expect(rowText, contains('Ksh 2,200.00'));
      expect(rowText, contains('3× · + Ksh 40 fee'));
      await tester.tap(find.byKey(const ValueKey('paidToRow-SEND_MONEY|0722114455')));
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('Ksh 2,200.00')), findsOneWidget);
      expect(_inSheet(find.text('3')), findsOneWidget);
      expect(_rich('PER MONTH · 2026'), findsOneWidget);
      final chart = find.byKey(const Key('paidToSheetChart'));
      for (final m in ['Jan', 'Feb', 'Aug', 'Sep', 'Dec']) {
        expect(
          find.descendant(of: chart, matching: find.text(m)),
          findsOneWidget,
          reason: m,
        );
      }
      expect(find.descendant(of: chart, matching: find.text('700')), findsOneWidget); // Aug
      expect(find.descendant(of: chart, matching: find.text('1.5k')), findsOneWidget); // Sep
      expect(find.text('15–21'), findsNothing, reason: 'no week blocks in Year');
    });

    testWidgets('a Withdrawal agent: Total withdrawn and Withdrawals', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('paidToRow-$_wd|no|314159')));
      await tester.pumpAndSettle();
      expect(find.text('TOTAL WITHDRAWN'), findsOneWidget);
      expect(find.text('WITHDRAWALS'), findsOneWidget);
      expect(find.text('Withdrawal · Agent 314159'), findsOneWidget);
      expect(_inSheet(find.text('Ksh 5,000.00')), findsOneWidget);
      expect(find.byKey(const Key('paidToSheetCombined')), findsNothing, reason: 'one stored form only');
    });

    testWidgets('closes by Close, the X, a scrim tap and the Back key; focus returns to the tapped row', (
      tester,
    ) async {
      await _pump(tester);
      final rowKey = find.byKey(const ValueKey('paidToRow-SEND_MONEY|0733000001'));
      FocusNode rowFocus() =>
          tester.widget<InkWell>(find.descendant(of: rowKey, matching: find.byType(InkWell))).focusNode!;

      Future<void> open() async {
        await tester.tap(rowKey);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('paidToSheetName')), findsOneWidget);
      }

      Future<void> closed() async {
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('paidToSheetName')), findsNothing);
        expect(rowFocus().hasPrimaryFocus, isTrue, reason: 'focus is back on the row');
      }

      await open();
      await tester.ensureVisible(find.byKey(const Key('paidToSheetClose')));
      await tester.tap(find.byKey(const Key('paidToSheetClose')));
      await closed();

      await open();
      await tester.tap(find.byKey(const Key('paidToSheetX')));
      await closed();

      await open();
      await tester.tapAt(const Offset(200, 20));
      await closed();

      await open();
      await tester.binding.handlePopRoute(); // Android Back
      await closed();
      expect(_opened, isEmpty, reason: 'closing never leaves Paid to');
    });

    testWidgets('dark: the sheet lays out cleanly', (tester) async {
      await _pump(tester, brightness: Brightness.dark);
      await tester.tap(find.byKey(const ValueKey('paidToRow-SEND_MONEY|0722114455')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('paidToSheetName')), findsOneWidget);
    });
  });

  group('the Analytics hand-off for Pochi and Withdrawal: the Analytics view holds the Paid to row\'s payments', () {
    Future<void> check(WidgetTester tester, String rowKey, String paidToCount, String analyticsPayments) async {
      await _pump(tester, realAnalytics: true);
      final rowFinder = find.byKey(ValueKey('paidToRow-$rowKey'));
      expect(rowFinder, findsOneWidget);
      // The Paid to row's count is the leading "n×" of its second line.
      expect(_row(tester, rowKey), contains('$paidToCount×'));
      await tester.tap(rowFinder);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('paidToSheetAnalytics')));
      await tester.tap(find.byKey(const Key('paidToSheetAnalytics')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsOneWidget);
      expect(find.text(analyticsPayments), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('Pochi, two written phone forms (merged): 2 payments both sides', (tester) async {
      await check(tester, '$_pochi|tel|0744000009', '2', '2 payments');
      expect(_opened.single.type, _pochi);
      expect(_opened.single.partyKey, 'tel|0744000009');
    });

    testWidgets('Pochi by name only: 1 payment both sides', (tester) async {
      await check(tester, '$_pochi|name|JUICE BAR', '1', '1 payment');
      expect(_opened.single.partyKey, 'name|JUICE BAR');
    });

    testWidgets('Withdrawal by agent number: 2 withdrawals both sides', (tester) async {
      await check(tester, '$_wd|no|314159', '2', '2 payments');
      expect(_opened.single.type, _wd);
      expect(_opened.single.partyKey, 'no|314159');
    });

    testWidgets('Withdrawal by name (no number): 1 withdrawal both sides', (tester) async {
      await check(tester, '$_wd|name|KAMAU AGENT', '1', '1 payment');
      expect(_opened.single.partyKey, 'name|KAMAU AGENT');
    });
  });

  testWidgets('the hand-off carries the type, the period and the active category (the kept 0.1.1 behaviour)', (
    tester,
  ) async {
    await _pump(tester);
    await _applyFilter(tester, cls: 'Rent');
    await tester.tap(find.byKey(const ValueKey('paidToRow-SEND_MONEY|0722114455')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('paidToSheetAnalytics')));
    await tester.tap(find.byKey(const Key('paidToSheetAnalytics')));
    await tester.pumpAndSettle();
    final args = _opened.single;
    expect(args.type, 'SEND_MONEY');
    expect(args.partyKey, '0722114455');
    expect(args.partyName, 'ANN');
    expect(args.classification, 'Rent');
    expect(args.period!.granularity.name, 'month');
  });

  testWidgets('Airtime and Cash are never loaded: not listed, not counted, not in the hero', (tester) async {
    await _pump(tester, rows: [_tx(1, 'AIRTIME', 3, 100), _tx(2, 'CASH', 4, 50)]);
    expect(find.text('No payments in this period.'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '0.00');
  });

  testWidgets('pull to refresh keeps the type pill and clears the search', (tester) async {
    await _pump(tester);
    await _tab(tester, _pochi);
    await tester.enterText(find.byKey(const Key('paidToSearch')), 'mama');
    await tester.pumpAndSettle();
    await tester.fling(find.byKey(const Key('paidToTotal')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('paidToSearch'))).controller!.text, '');
    expect(_rich('Pochi 2'), findsOneWidget, reason: 'the type stays; the search is cleared');
  });
}
