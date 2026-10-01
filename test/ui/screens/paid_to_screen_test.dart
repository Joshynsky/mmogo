// T22 — Paid to (lib/ui/screens/paid_to_screen.dart; was parties_screen.dart,
// T15), driven against FakeAnalyticsDb (a real sqflite_common_ffi Database
// hangs inside testWidgets here). The grouping/sorting/counting rules are
// unit-tested in test/domain/paid_to/paid_to_test.dart; this file covers the
// screen's wiring: the period pill, the "Paid out" card, type pills,
// sections + See all, the Filter & sort sheet and its chips, search, the
// unnamed rows (T15), no Cash, and the Analytics hand-off arguments.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';

import '../../support/fake_analytics_db.dart';

Map<String, Object?> _unnamed(int id, DateTime at, int amountCents, {int costCents = 0}) =>
    fakeTx(id: id, at: at, amountCents: amountCents, costCents: costCents)
      ..['counterparty_label'] = null
      ..['counterparty_phone'] = null;

/// The Analytics sample rows plus, in Sep 2026: two unnamed Send Money
/// payments (Family/Friends), a second JOHN KAMAU payment (same phone as
/// row 1's default, so one recipient) and ALICE.
///  Sep (non-cash): 1500 + 850 + 1200 + 2000 + 640 + 500 + 300 + 1000 + 100
///  = Ksh 8,090 to 7 recipients, 9 payments. Aug: PETER OTIENO 1750.
List<Map<String, Object?>> _rows() => [
  ...analyticsSampleRows(),
  _unnamed(20, DateTime(2026, 9, 10, 20), 50000, costCents: 700),
  _unnamed(21, DateTime(2026, 9, 12, 20), 30000),
  fakeTx(id: 22, at: DateTime(2026, 9, 5, 19), label: 'JOHN KAMAU', phone: '07000001', amountCents: 100000, costCents: 1300),
  fakeTx(id: 23, at: DateTime(2026, 9, 20, 9), label: 'ALICE', amountCents: 10000, classification: 'Rent', classificationId: 102),
];

final _opened = <AnalyticsRouteArgs>[];

Future<void> _pump(WidgetTester tester, {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(392, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  _opened.clear();
  await tester.pumpWidget(
    MaterialApp(
      home: PaidToScreen(db: FakeAnalyticsDb(_rows()), clock: () => analyticsTestNow),
      onGenerateRoute: (settings) {
        if (settings.name != '/analytics') return null;
        _opened.add(settings.arguments! as AnalyticsRouteArgs);
        return MaterialPageRoute(settings: settings, builder: (_) => const Scaffold(body: Text('ANALYTICS')));
      },
    ),
  );
  await tester.pumpAndSettle();
}

String? _text(WidgetTester tester, Key key) {
  final f = find.descendant(of: find.byKey(key), matching: find.byType(Text));
  return tester.widget<Text>(f.first).data;
}

Finder _rich(String s) => find.text(s, findRichText: true);

void main() {
  testWidgets('defaults: this month, the Paid out card, type pills, top 3 + See all, no Cash', (tester) async {
    await _pump(tester);
    expect(find.text('Paid to'), findsWidgets);
    expect(_text(tester, const Key('paidToGranularity')), 'Month');
    expect(_text(tester, const Key('paidToPeriodValue')), 'Sep 2026');
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '8,090.00');
    expect(_rich('to 7 recipients'), findsOneWidget);
    expect(_rich('9 payments'), findsOneWidget);
    expect(_rich('All 7'), findsOneWidget);
    expect(_rich('Send Money 4'), findsOneWidget);
    expect(_rich('Paybill 1'), findsOneWidget);
    expect(_rich('Buy Goods 2'), findsOneWidget);
    expect(find.textContaining('Cash'), findsNothing);
    expect(find.text('PETER OTIENO'), findsNothing, reason: 'August is outside this month');

    // Send Money: JOHN 2500, MARY 2000, Unnamed 800, ALICE 100 — top 3 on All.
    expect(find.text('SEND MONEY'), findsOneWidget);
    expect(find.text('4 people · 6 payments · fees Ksh 67'), findsOneWidget);
    expect(find.text('JOHN KAMAU'), findsOneWidget);
    expect(find.text('ALICE'), findsNothing);
    expect(find.text('See all 4 ›'), findsOneWidget);
    expect(find.text('2× · fees 35'), findsOneWidget); // JOHN

    // T15: the unnamed row, italic, never dropped.
    final unnamed = tester.widget<Text>(find.text('Unnamed · Family/Friends'));
    expect(unnamed.style!.fontStyle, FontStyle.italic);
    expect(find.textContaining('Receiver not recorded'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paidToSeeAll-SEND_MONEY')));
    await tester.pumpAndSettle();
    expect(find.text('ALICE'), findsOneWidget);
    expect(find.text('PAYBILL'), findsNothing, reason: 'one type now');
  });

  testWidgets('Filter & sort: a draft until Show, the badge, chips that remove', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('paidToFilterButton')));
    await tester.pumpAndSettle();
    expect(find.text('Filter & sort'), findsOneWidget);
    expect(_rich('CATEGORY · all types'), findsOneWidget);
    expect(find.text('Show 7 recipients'), findsOneWidget);
    await tester.tap(find.byKey(const Key('paidToCat-Rent')));
    await tester.pumpAndSettle();
    expect(find.text('Show 2 recipients'), findsOneWidget); // MARY + ALICE
    await tester.tap(find.byKey(const Key('paidToSort-timesPaid')));
    await tester.pumpAndSettle();
    // Nothing applied yet.
    expect(find.byKey(const Key('paidToFilterBadge')), findsNothing);
    await tester.tap(find.byKey(const Key('paidToShow')));
    await tester.pumpAndSettle();

    expect(_text(tester, const Key('paidToFilterBadge')), '2');
    expect(find.byKey(const Key('paidToChipCategory')), findsOneWidget);
    expect(find.text('Sorted: Times paid'), findsOneWidget);
    expect(find.text('MARY WANJIKU'), findsOneWidget);
    expect(find.text('JOHN KAMAU'), findsNothing);
    // The hero is the whole period, whatever the filter.
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '8,090.00');

    await tester.tap(find.byKey(const Key('paidToChipSort')));
    await tester.pumpAndSettle();
    expect(_text(tester, const Key('paidToFilterBadge')), '1');

    // Switching to a type without Rent drops the category.
    await tester.ensureVisible(find.byKey(const Key('paidToTab-BUY_GOODS'))); // the pills scroll sideways
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paidToTab-BUY_GOODS')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paidToFilterBadge')), findsNothing);
    expect(find.text('NAIVAS SUPERMARKET'), findsOneWidget);

    // Reset in the sheet clears the draft.
    await tester.tap(find.byKey(const Key('paidToFilterButton')));
    await tester.pumpAndSettle();
    expect(_rich('CATEGORY · in Buy Goods'), findsOneWidget);
    await tester.tap(find.byKey(const Key('paidToCat-Shopping')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paidToReset')));
    await tester.pumpAndSettle();
    expect(find.text('Show 2 recipients'), findsOneWidget);
  });

  testWidgets('pull to refresh: back to this month, search cleared, category + sort kept', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('paidToFilterButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paidToCat-Rent')));
    await tester.tap(find.byKey(const Key('paidToSort-timesPaid')));
    await tester.tap(find.byKey(const Key('paidToShow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paidToPeriodValue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('August 2026').last);
    await tester.pumpAndSettle();
    expect(_text(tester, const Key('paidToPeriodValue')), 'Aug 2026');
    expect(_text(tester, const Key('paidToFilterBadge')), '2', reason: 'a period change keeps the filters');
    await tester.enterText(find.byKey(const Key('paidToSearch')), 'peter');
    await tester.pumpAndSettle();

    await tester.fling(find.byKey(const Key('paidToTotal')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(_text(tester, const Key('paidToPeriodValue')), 'Sep 2026');
    expect(tester.widget<TextField>(find.byKey(const Key('paidToSearch'))).controller!.text, '');
    expect(_text(tester, const Key('paidToFilterBadge')), '2');
    expect(find.byKey(const Key('paidToChipCategory')), findsOneWidget);
    expect(find.text('Sorted: Times paid'), findsOneWidget);
  });

  testWidgets('the period pill: All time shows every month; Year', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('paidToGranularity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All time').last);
    await tester.pumpAndSettle();
    expect(_text(tester, const Key('paidToPeriodValue')), 'since Aug 2026');
    expect(find.text('PETER OTIENO'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '9,840.00');

    await tester.tap(find.byKey(const Key('paidToGranularity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year').last);
    await tester.pumpAndSettle();
    expect(_text(tester, const Key('paidToPeriodValue')), '2026');
  });

  testWidgets('search narrows by name or phone; no match says so', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('paidToSearch')), 'mary');
    await tester.pumpAndSettle();
    expect(find.text('MARY WANJIKU'), findsOneWidget);
    expect(find.text('JOHN KAMAU'), findsNothing);
    await tester.enterText(find.byKey(const Key('paidToSearch')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No one matches “zzz”.'), findsOneWidget);
  });

  testWidgets('a tap opens Analytics on this period: a recipient, or an unnamed row by classification', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('MARY WANJIKU'));
    await tester.pumpAndSettle();
    final named = _opened.single;
    expect(named.type, 'SEND_MONEY');
    expect(named.partyKey, '0712345678');
    expect(named.partyName, 'MARY WANJIKU');
    expect(named.period, AnalyticsPeriod.month(DateTime(2026, 9)));
    expect(named.classification, isNull);

    Navigator.of(tester.element(find.text('ANALYTICS'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unnamed · Family/Friends'));
    await tester.pumpAndSettle();
    final anon = _opened.last;
    expect(anon.type, 'SEND_MONEY');
    expect(anon.partyKey, isNull);
    expect(anon.classification, 'Family/Friends');
    expect(anon.period!.granularity, AnalyticsGranularity.month);
  });

  testWidgets('dark: follows the phone, no layout errors', (tester) async {
    await _pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('JOHN KAMAU'), findsOneWidget);
  });
}
