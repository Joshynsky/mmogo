// 0.1.2 S4b (P-Analytics-07): the By-type panel shows ALL SEVEN types in the
// signed two-row swipeable strip, in sourceTypeOrder, with two pager dots.
// Invented rows only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/format/source_types.dart';
import 'package:mmogo/ui/screens/analytics/analytics_filters.dart';
import 'package:mmogo/ui/screens/analytics/analytics_view.dart';
import 'package:mmogo/ui/screens/analytics/type_breakdown.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/widgets/type_icon.dart';

final _now = DateTime(2026, 10, 14, 12);

AnalyticsTransactionRow _row(int id, String type, int amount, {String cls = 'Shopping'}) => AnalyticsTransactionRow(
  id: id,
  displayCode: 'AV$id',
  sourceType: type,
  amountCents: amount,
  counterpartyLabel: null,
  counterpartyPhone: null,
  paybillAccountNumber: null,
  classificationId: id,
  classificationName: cls,
  occurredAt: _now,
  transactionCostCents: null,
);

AnalyticsView _view(List<AnalyticsTransactionRow> rows) {
  final period = AnalyticsPeriod.month(_now, firstDay: 1);
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

// 7 types, amounts in cents: 10,000 / 20,000 / 30,000 / 10,000 / 20,000 / 5,000,000 (withdrawal) / 10,000
final _rows = [
  _row(1, 'SEND_MONEY', 1000000),
  _row(2, 'PAYBILL', 2000000),
  _row(3, 'BUY_GOODS', 3000000),
  _row(4, 'CASH', 1000000),
  _row(5, 'POCHI_LA_BIASHARA', 2000000),
  _row(6, 'AGENT_WITHDRAWAL', 500000000),
  _row(7, 'AIRTIME', 1000000),
];

Future<void> _pump(
  WidgetTester t,
  List<AnalyticsTransactionRow> rows, {
  String? typeFilter,
  String? classFilter,
  ValueChanged<String>? onToggle,
  double width = 390,
}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: AnalyticsTypePanel(
            palette: AppPalette.light,
            view: _view(rows),
            filters: AnalyticsFilters.handOff(type: typeFilter, classification: classFilter),
            onToggleType: onToggle ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('all seven tiles exist, in sourceTypeOrder, with the colour of their type', (t) async {
    await _pump(t, _rows);
    for (final (code, name) in sourceTypeOrder) {
      expect(find.byKey(Key('analyticsTypeTile-$code')), findsOneWidget, reason: code);
      expect(find.descendant(of: find.byKey(Key('analyticsTypeTile-$code')), matching: find.text(name)), findsOneWidget);
    }
    expect(sourceTypeOrder.length, 7);
    // Layout of the mock: column 1 = Send Money over Buy Goods, column 2 = Paybill over Cash,
    // column 3 = Pochi over Withdrawal, column 4 = Airtime (top row).
    Offset at(String c) => t.getTopLeft(find.byKey(Key('analyticsTypeTile-$c')));
    expect(at('SEND_MONEY').dy, lessThan(at('BUY_GOODS').dy));
    expect(at('SEND_MONEY').dx, at('BUY_GOODS').dx);
    expect(at('PAYBILL').dx, greaterThan(at('SEND_MONEY').dx));
    expect(at('CASH').dy, at('BUY_GOODS').dy);
    expect(at('POCHI_LA_BIASHARA').dy, at('SEND_MONEY').dy);
    expect(at('AGENT_WITHDRAWAL').dx, at('POCHI_LA_BIASHARA').dx);
    expect(at('AGENT_WITHDRAWAL').dy, greaterThan(at('POCHI_LA_BIASHARA').dy));
    expect(at('AIRTIME').dy, at('SEND_MONEY').dy);
    expect(at('AIRTIME').dx, greaterThan(at('POCHI_LA_BIASHARA').dx));
  });

  testWidgets('percentages are against the all-spending total and add to 100 (withdrawal adds 0)', (t) async {
    await _pump(t, _rows);
    // spent = 100,000 (the withdrawal's 5,000,000 is not in it): 10 / 20 / 30 / 10 / 20 / - / 10
    String pct(String c) => (t.widget<Text>(
      find.descendant(of: find.byKey(Key('analyticsTypeTile-$c')), matching: find.textContaining('%')),
    )).data!;
    final got = [for (final c in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'CASH', 'POCHI_LA_BIASHARA', 'AIRTIME']) pct(c)];
    expect(got, ['10%', '20%', '30%', '10%', '20%', '10%']);
    expect(got.fold<int>(0, (s, x) => s + int.parse(x.replaceAll('%', ''))), 100);
  });

  testWidgets('Withdrawal tile: the withdrawn amount, "tracked" instead of a percent, muted, never "spent"', (t) async {
    await _pump(t, _rows);
    final tile = find.byKey(const Key('analyticsTypeTile-AGENT_WITHDRAWAL'));
    expect(find.descendant(of: tile, matching: find.text('tracked')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Ksh 5,000,000.00')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Ksh 0.00')), findsNothing);
    expect(find.descendant(of: tile, matching: find.textContaining('%')), findsNothing);
    expect(find.textContaining('5,000,000'), findsOneWidget); // only on that tile
    expect(find.textContaining('spent'), findsNothing);
    final amount = t.widget<Text>(find.descendant(of: tile, matching: find.text('Ksh 5,000,000.00')));
    expect(amount.style!.color, AppPalette.light.mutedInk);
    expect(find.bySemanticsLabel(RegExp('Withdrawal, Ksh 5,000,000.00 withdrawn. Tracked, not spending')), findsOneWidget);
  });

  testWidgets('a period with no withdrawal: the Withdrawal tile says Ksh 0.00 (and still "tracked")', (t) async {
    await _pump(t, [for (final r in _rows) if (r.sourceType != 'AGENT_WITHDRAWAL') r]);
    final tile = find.byKey(const Key('analyticsTypeTile-AGENT_WITHDRAWAL'));
    expect(find.descendant(of: tile, matching: find.text('Ksh 0.00')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('tracked')), findsOneWidget);
  });

  testWidgets('a withdrawal changes neither the spent total nor any other tile (amounts, percentages)', (t) async {
    final without = [for (final r in _rows) if (r.sourceType != 'AGENT_WITHDRAWAL') r];
    String snapshot() => [
      for (final c in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'CASH', 'POCHI_LA_BIASHARA', 'AIRTIME'])
        [for (final w in t.widgetList<Text>(find.descendant(of: find.byKey(Key('analyticsTypeTile-$c')), matching: find.byType(Text)))) w.data].join('|'),
    ].join(';');
    await _pump(t, without);
    final before = snapshot();
    await _pump(t, _rows);
    expect(snapshot(), before);
    expect(_view(_rows).totalCents, _view(without).totalCents);
    expect(_view(_rows).totalCents, 10000000);
  });

  testWidgets('class filter: the Withdrawal tile follows it (only withdrawals of that class)', (t) async {
    await _pump(t, _rows, classFilter: 'Shopping');
    expect(find.descendant(of: find.byKey(const Key('analyticsTypeTile-AGENT_WITHDRAWAL')), matching: find.text('Ksh 5,000,000.00')), findsOneWidget);
    await _pump(t, _rows, classFilter: 'Nothing');
    expect(find.descendant(of: find.byKey(const Key('analyticsTypeTile-AGENT_WITHDRAWAL')), matching: find.text('Ksh 0.00')), findsOneWidget);
  });

  testWidgets('no spending at all: dashes, not NaN; Withdrawal still says tracked', (t) async {
    await _pump(t, [_row(1, 'AGENT_WITHDRAWAL', 100000)]);
    expect(find.text('Ksh 1,000.00'), findsOneWidget); // the withdrawn amount, on its own tile
    expect(find.text('—'), findsNWidgets(6));
    expect(find.text('tracked'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('swipe / dots: the strip starts on page 1, dot 2 moves to Pochi, Withdrawal and Airtime; dot 1 returns', (t) async {
    await _pump(t, _rows);
    final strip = find.byKey(const Key('analyticsTypeStrip'));
    final sc = t.state<ScrollableState>(find.descendant(of: strip, matching: find.byType(Scrollable)));
    expect(sc.position.pixels, 0);
    expect(sc.position.maxScrollExtent, greaterThan(0));
    // Pochi peeks (partly on screen) on page 1.
    expect(t.getTopLeft(find.byKey(const Key('analyticsTypeTile-POCHI_LA_BIASHARA'))).dx, lessThan(390));
    await t.tap(find.byKey(const Key('analyticsTypeDot1')));
    await t.pumpAndSettle();
    expect(sc.position.pixels, sc.position.maxScrollExtent);
    // Airtime fully on screen now.
    expect(t.getTopRight(find.byKey(const Key('analyticsTypeTile-AIRTIME'))).dx, lessThanOrEqualTo(390));
    await t.tap(find.byKey(const Key('analyticsTypeDot0')));
    await t.pumpAndSettle();
    expect(sc.position.pixels, 0);
  });

  testWidgets('a short swipe snaps to the nearest page', (t) async {
    await _pump(t, _rows);
    final strip = find.byKey(const Key('analyticsTypeStrip'));
    final sc = t.state<ScrollableState>(find.descendant(of: strip, matching: find.byType(Scrollable)));
    await t.drag(strip, const Offset(-60, 0));
    await t.pumpAndSettle();
    expect(sc.position.pixels, 0, reason: 'less than half a page snaps back');
    await t.drag(strip, const Offset(-250, 0));
    await t.pumpAndSettle();
    expect(sc.position.pixels, sc.position.maxScrollExtent);
  });

  testWidgets('the pager dots are 44 x 44 and named', (t) async {
    await _pump(t, _rows);
    for (final k in ['analyticsTypeDot0', 'analyticsTypeDot1']) {
      final s = t.getSize(find.byKey(Key(k)));
      expect(s.width, greaterThanOrEqualTo(44), reason: k);
      expect(s.height, greaterThanOrEqualTo(44), reason: k);
    }
    expect(find.bySemanticsLabel('Show Pochi, Withdrawal and Airtime'), findsOneWidget);
    expect(find.bySemanticsLabel('Show Send Money, Paybill, Buy Goods and Cash'), findsOneWidget);
  });

  testWidgets('tapping a tile on the second page filters by that type (single filter as in 0.1.1)', (t) async {
    final taps = <String>[];
    await _pump(t, _rows, onToggle: taps.add);
    await t.tap(find.byKey(const Key('analyticsTypeDot1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('analyticsTypeTile-AIRTIME')));
    await t.tap(find.byKey(const Key('analyticsTypeTile-AGENT_WITHDRAWAL')));
    expect(taps, ['AIRTIME', 'AGENT_WITHDRAWAL']);
  });

  testWidgets('the three new types have their own icon and colour in the tile', (t) async {
    await _pump(t, _rows);
    final p = AppPalette.light;
    for (final c in ['POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME']) {
      expect(sourceTypeIcon(c), isNot(sourceTypeIcon('CASH')));
      final bar = find.descendant(
        of: find.byKey(Key('analyticsTypeTile-$c')),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == p.typeColor(c),
        ),
      );
      expect(bar, findsOneWidget, reason: c);
    }
  });
}
