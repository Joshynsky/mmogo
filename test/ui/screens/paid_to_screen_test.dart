// T22 — Paid to (lib/ui/screens/paid_to_screen.dart; was parties_screen.dart,
// T15), driven against FakeAnalyticsDb (a real sqflite_common_ffi Database
// hangs inside testWidgets here). The grouping/sorting/counting rules are
// unit-tested in test/domain/paid_to/; this file covers the screen's wiring:
// the period pill, the "Paid out" card, type pills, sections + See all, the
// Filter & sort sheet and its chips, search, the Not recorded line (S7b: it
// replaces the 0.1.1 "Unnamed" rows), no Cash, the recipient sheet and the
// Analytics hand-off arguments. The S7b look (pills, Pochi, Withdrawal,
// recipient sheet in depth) is in paid_to_s7b_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Map<String, Object?> _unnamed(int id, DateTime at, int amountCents, {int costCents = 0}) =>
    fakeTx(id: id, at: at, amountCents: amountCents, costCents: costCents)
      ..['counterparty_label'] = null
      ..['counterparty_phone'] = null;

/// The Analytics sample rows plus, in Sep 2026: two Send Money payments with no
/// captured receiver (Family/Friends: Not recorded), a second JOHN KAMAU
/// payment (same phone as row 1's default, so one recipient), ALICE and CAROL.
///  Sep (non-cash): 1500 + 850 + 1200 + 2000 + 640 + 500 + 300 + 1000 + 100 + 50
///  = Ksh 8,140 to 7 recipients, 10 payments (2 of them Not recorded).
///  Aug: PETER OTIENO 1750.
List<Map<String, Object?>> _rows() => [
  ...analyticsSampleRows(),
  _unnamed(20, DateTime(2026, 9, 10, 20), 50000, costCents: 700),
  _unnamed(21, DateTime(2026, 9, 12, 20), 30000),
  fakeTx(id: 22, at: DateTime(2026, 9, 5, 19), label: 'JOHN KAMAU', phone: '07000001', amountCents: 100000, costCents: 1300),
  fakeTx(id: 23, at: DateTime(2026, 9, 20, 9), label: 'ALICE', amountCents: 10000, classification: 'Rent', classificationId: 102),
  fakeTx(id: 24, at: DateTime(2026, 9, 8, 9), label: 'CAROL', amountCents: 5000),
];

final _opened = <AnalyticsRouteArgs>[];

Future<void> _pump(WidgetTester tester, {Brightness brightness = Brightness.light, List<Map<String, Object?>>? rows}) async {
  tester.view.physicalSize = const Size(392, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  _opened.clear();
  await tester.pumpWidget(
    MaterialApp(
      home: PaidToScreen(db: FakeAnalyticsDb(rows ?? _rows()), clock: () => analyticsTestNow),
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('defaults: this month, the Paid out card, type pills, top 3 + See all, no Cash', (tester) async {
    await _pump(tester);
    expect(find.text('Paid to'), findsWidgets);
    expect(_text(tester, const Key('paidToGranularity')), 'Month');
    expect(_text(tester, const Key('paidToPeriodValue')), 'Sep 2026');
    // The Not recorded payments' money and cost are in the hero; they are not recipients.
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '8,140.00');
    expect(_rich('to 7 recipients'), findsOneWidget);
    expect(_rich('10 payments'), findsOneWidget);
    expect(_rich('Transaction cost Ksh 82.00'), findsOneWidget);
    expect(_rich('All 7'), findsOneWidget); // the open pill shows the recipient count only
    expect(find.text('SM'), findsOneWidget);
    expect(find.text('PB'), findsOneWidget);
    expect(find.text('BG'), findsOneWidget);
    expect(find.textContaining('Cash'), findsNothing);
    expect(find.text('PETER OTIENO'), findsNothing, reason: 'August is outside this month');

    // Send Money: JOHN 2500, MARY 2000, ALICE 100, CAROL 50 — top 3 on All.
    expect(find.text('SEND MONEY'), findsOneWidget);
    expect(find.text('4 people · 5 payments · Transaction cost Ksh 60'), findsOneWidget);
    expect(find.text('JOHN KAMAU'), findsOneWidget);
    expect(find.text('CAROL'), findsNothing);
    expect(find.text('See all 4 ›'), findsOneWidget);
    expect(find.text('2× · + Ksh 35 fee'), findsOneWidget); // JOHN

    // S7b: no "Unnamed" rows; one muted Not recorded line under the section instead.
    expect(find.textContaining('Unnamed'), findsNothing);
    expect(find.textContaining('Receiver not recorded'), findsNothing);
    expect(find.text('Not recorded · 2 payments · Ksh 800'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paidToSeeAll-SEND_MONEY')));
    await tester.pumpAndSettle();
    expect(find.text('CAROL'), findsOneWidget);
    expect(find.text('PAYBILL'), findsNothing, reason: 'one type now');
  });

  testWidgets('Filter & sort: a draft until Show, the badge, chips that remove', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('paidToFilterButton')));
    await tester.pumpAndSettle();
    expect(find.text('Filter & sort'), findsOneWidget);
    expect(_rich('CATEGORY · all types'), findsOneWidget);
    expect(find.text('Show 7'), findsOneWidget);
    expect(find.byKey(const Key('paidToSort-fees')), findsOneWidget, reason: 'S7b: all four sorts');
    await tester.tap(find.byKey(const Key('paidToCat-Rent')));
    await tester.pumpAndSettle();
    expect(find.text('Show 2'), findsOneWidget); // MARY + ALICE
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
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '8,140.00');

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
    expect(find.text('Show 2'), findsOneWidget);
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
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '9,890.00');

    await tester.tap(find.byKey(const Key('paidToGranularity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year').last);
    await tester.pumpAndSettle();
    expect(_text(tester, const Key('paidToPeriodValue')), '2026');
  });

  testWidgets('search narrows by name or phone; no match says so; the Not recorded line hides', (tester) async {
    await _pump(tester);
    expect(find.text('Not recorded · 2 payments · Ksh 800'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('paidToSearch')), 'mary');
    await tester.pumpAndSettle();
    expect(find.text('MARY WANJIKU'), findsOneWidget);
    expect(find.text('JOHN KAMAU'), findsNothing);
    expect(find.textContaining('Not recorded'), findsNothing, reason: 'hidden while a term is typed');
    await tester.enterText(find.byKey(const Key('paidToSearch')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No one matches “zzz”.'), findsOneWidget);
  });

  testWidgets('a row tap opens the recipient sheet INSIDE Paid to; the Analytics button hands off', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('MARY WANJIKU'));
    await tester.pumpAndSettle();
    expect(_opened, isEmpty, reason: 'a tap no longer leaves Paid to');
    expect(find.byKey(const Key('paidToSheetName')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('paidToSheetAnalytics')));
    await tester.tap(find.byKey(const Key('paidToSheetAnalytics')));
    await tester.pumpAndSettle();
    final named = _opened.single;
    expect(named.type, 'SEND_MONEY');
    expect(named.partyKey, '0712345678');
    expect(named.partyName, 'MARY WANJIKU');
    expect(named.period, AnalyticsPeriod.month(DateTime(2026, 9), firstDay: 1));
    expect(named.classification, isNull);

    Navigator.of(tester.element(find.text('ANALYTICS'))).pop();
    await tester.pumpAndSettle();
    // The Not recorded line is not a recipient: no tap, no sheet, no hand-off.
    await tester.tap(find.text('Not recorded · 2 payments · Ksh 800'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paidToSheetName')), findsNothing);
    expect(_opened, hasLength(1));
  });

  testWidgets('an empty period says so', (tester) async {
    await _pump(tester, rows: const []);
    expect(find.text('No payments in this period.'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('paidToTotal'))).data, '0.00');
  });

  testWidgets('dark: follows the phone, no layout errors', (tester) async {
    await _pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('JOHN KAMAU'), findsOneWidget);
    await tester.tap(find.text('JOHN KAMAU'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paidToSheetName')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
