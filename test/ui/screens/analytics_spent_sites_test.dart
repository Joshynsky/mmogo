// SP3/SP4/SP6: the Dart spending sites in Analytics, one test per site, over
// invented rows that include a withdrawal: the hero total (AnalyticsView),
// the By-type panel, the Where-it-went panel and the transaction list
// subtotals. A withdrawal adds 0 everywhere; its fee still counts as fees.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/ui/screens/analytics/analytics_filters.dart';
import 'package:mmogo/ui/screens/analytics/analytics_view.dart';
import 'package:mmogo/ui/screens/analytics/swipe_chart.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mmogo/ui/screens/analytics/transaction_list.dart';
import 'package:mmogo/ui/screens/analytics/type_breakdown.dart';
import 'package:mmogo/ui/screens/analytics/where_breakdown.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/analytics/chart_blocks.dart' show WhereItWentStyle;
import 'package:mmogo/ui/theme/app_colors.dart';

import '../../support/fake_analytics_db.dart';

final _now = DateTime(2026, 10, 14, 12); // a Wednesday, invented

AnalyticsTransactionRow _row(int id, String type, int amount, int? fee, String cls, {DateTime? at}) =>
    AnalyticsTransactionRow(
      id: id,
      displayCode: 'AV$id',
      sourceType: type,
      amountCents: amount,
      counterpartyLabel: type == 'CASH' || type == 'AIRTIME' ? null : 'Invented',
      counterpartyPhone: null,
      paybillAccountNumber: null,
      classificationId: id,
      classificationName: cls,
      occurredAt: at ?? _now,
      transactionCostCents: fee,
    );

AnalyticsView _view(List<AnalyticsTransactionRow> rows) {
  final period = AnalyticsPeriod.month(_now);
  return AnalyticsView(
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
}

final _rows = [
  _row(1, 'AIRTIME', 5000, 0, 'Airtime'),
  _row(2, 'AGENT_WITHDRAWAL', 100000, 2900, 'Withdrawal'),
  _row(3, 'BUY_GOODS', 30000, 0, 'Shopping'),
  _row(4, 'CASH', 7000, null, 'Shopping'),
];

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  final palette = AppPalette.light;

  test('AnalyticsView.totalCents counts the withdrawal as 0', () {
    expect(_view(_rows).totalCents, 5000 + 30000 + 7000);
    expect(_view([_rows[1]]).totalCents, 0);
  });

  test('fees (the hero sum of transactionCostCents) still include the withdrawal fee', () {
    final fees = _view(_rows).inc.fold<int>(0, (s, r) => s + (r.transactionCostCents ?? 0));
    expect(fees, 2900);
  });

  testWidgets('By type: Buy Goods and Cash tiles show their spend, percentages use the spent total', (t) async {
    await t.pumpWidget(
      _host(AnalyticsTypePanel(palette: palette, view: _view(_rows), filters: AnalyticsFilters.none, onToggleType: (_) {})),
    );
    // total = 42,000; Buy Goods 30,000 = 71%, Cash 7,000 = 17%.
    expect(find.text('Ksh 300.00'), findsOneWidget);
    expect(find.text('71%'), findsOneWidget);
    expect(find.text('Ksh 70.00'), findsOneWidget);
    expect(find.text('17%'), findsOneWidget);
    // The raw 1,000 shows only as the Withdrawal tile's own "withdrawn" figure,
    // muted, with 'tracked' in place of a percent (amended rule, 13-10-2026).
    final wd = find.byKey(const Key('analyticsTypeTile-AGENT_WITHDRAWAL'));
    expect(find.descendant(of: wd, matching: find.text('Ksh 1,000.00')), findsOneWidget);
    expect(find.descendant(of: wd, matching: find.text('tracked')), findsOneWidget);
    expect(find.text('Ksh 1,000.00'), findsOneWidget); // nowhere else
  });

  testWidgets('Where it went: the withdrawal class is not a spending row; Airtime is', (t) async {
    await t.pumpWidget(
      _host(
        AnalyticsWherePanel(
          palette: palette,
          ranking: analyticsWhereRanking(_view(_rows).inc, AnalyticsFilters.none),
          filters: AnalyticsFilters.none,
          style: WhereItWentStyle.button,
          onToggleClass: (_) {},
          onOpenSheet: () {},
        ),
      ),
    );
    expect(find.byKey(const Key('analyticsWhere-Withdrawal')), findsNothing);
    expect(find.byKey(const Key('analyticsWhere-Airtime')), findsOneWidget);
    expect(find.byKey(const Key('analyticsWhere-Shopping')), findsOneWidget);
    expect(find.textContaining('1,000'), findsNothing);
  });

  testWidgets('Transaction list: the day subtotal and the type chip use the spent amounts', (t) async {
    Future<void> pump(String? typeFilter) async {
      await t.pumpWidget(
        _host(
          Column(
            children: analyticsTransactionSections(
              palette: palette,
              view: _view(_rows),
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

    await pump(null);
    // Today's group: 50 + 300 + 70 = Ksh 420.00 (the withdrawal's 1,000 is not in it).
    expect(find.text('Ksh 420.00'), findsOneWidget);
    await pump('AGENT_WITHDRAWAL');
    // Changed 14-10-2026 (was 'Withdrawal · Ksh 0'): signed mock, 'X out'.
    expect(find.text('Withdrawal · Ksh 1,000 out'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Clear the Withdrawal filter, Ksh 1,000 withdrawn')), findsOneWidget);
    expect(find.textContaining('spent'), findsNothing);
    // Another type's chip keeps the spent subtotal (no ' out').
    await pump('BUY_GOODS');
    expect(find.text('Buy Goods · Ksh 300'), findsOneWidget);
    expect(find.textContaining(' out'), findsNothing);
  });

  testWidgets('Transaction list: Withdrawal + a class filter shows the withdrawn sum of the filtered rows', (t) async {
    final rows = [
      _row(1, 'AGENT_WITHDRAWAL', 100000, 2900, 'Withdrawal'),
      _row(2, 'AGENT_WITHDRAWAL', 50000, 2500, 'Shopping'),
      _row(3, 'AGENT_WITHDRAWAL', 20000, 1100, 'Shopping'),
      _row(4, 'BUY_GOODS', 30000, 0, 'Shopping'),
    ];
    await t.pumpWidget(
      _host(
        Column(
          children: analyticsTransactionSections(
            palette: palette,
            view: _view(rows),
            filters: AnalyticsFilters.handOff(type: 'AGENT_WITHDRAWAL', classification: 'Shopping'),
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
    // 500 + 200 withdrawn in Shopping; the 1,000 'Withdrawal' row and the Buy Goods row are out.
    expect(find.text('Withdrawal · Ksh 700 out'), findsOneWidget);
    expect(find.text('Shopping · Ksh 700 out'), findsOneWidget);
  });

  testWidgets('screen: prior total and chart buckets use the rule (a withdrawal adds 0), the fee stays in fees', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(400, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final rows = [
      // This week (Mon 12 - Wed 14 Oct): spend 2,000 and a withdrawal of 100,000 with a fee of 29.
      fakeTx(id: 1, at: DateTime(2026, 10, 14, 9), type: 'AIRTIME', amountCents: 200000, costCents: 0),
      fakeTx(id: 2, at: DateTime(2026, 10, 13, 9), type: 'AGENT_WITHDRAWAL', amountCents: 10000000, costCents: 2900),
      // The week before: spend 1,000 and a withdrawal of 80,000.
      fakeTx(id: 3, at: DateTime(2026, 10, 7, 9), type: 'BUY_GOODS', amountCents: 100000, costCents: 0),
      fakeTx(id: 4, at: DateTime(2026, 10, 8, 9), type: 'AGENT_WITHDRAWAL', amountCents: 8000000, costCents: 2500),
    ];
    final db = FakeAnalyticsDb(rows);
    // Thursday, not Wednesday: from S6b the change shows from day 4 of the week (Wednesday shows the cue "3/7").
    await t.pumpWidget(MaterialApp(home: AnalyticsScreen(db: db, clock: () => _now.add(const Duration(days: 1)))));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('analyticsTotal'))).data, '2,000.00');
    // 2,000 vs 1,000 = +100% (with the raw amounts it would be +26%).
    expect(find.text('▲ 100% vs last week'), findsOneWidget);
    // fees = the withdrawal's 29 (the airtime row has none).
    expect(find.text('Transaction cost Ksh 29', findRichText: true), findsOneWidget);
    // Chart buckets: Tue (index 1) holds only the withdrawal -> 0 for every type;
    // Wed (index 2) holds the 2,000 of Airtime (type index 6).
    final chart = t.widget<AnalyticsSwipeChart>(find.byType(AnalyticsSwipeChart));
    expect(chart.bucketCents[1].fold<int>(0, (s, c) => s + c), 0);
    expect(chart.bucketCents[2][6], 200000);
    expect(chart.bucketCents[2].fold<int>(0, (s, c) => s + c), 200000);
  });
}
