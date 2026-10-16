// S11b AX1c / CB5 (H7): colour is never the only signal.
//   - By type tiles (addendum B1): every tile prints its name, its percent and
//     its amount as text, always visible (the "one tap away in text" bar is met
//     with zero taps), at 1.0 and 1.3, light and dark; the tile's semantics label
//     holds the name and the amount; a tap still TOGGLES the type filter.
//   - Each chart colour has its type name beside it: the swatch on the tile is the
//     same colour the chart draws that type in (the By type tiles are the chart's
//     legend; the chart card itself has no per-series legend, see the deviations).
//   - Up / down changes carry an arrow in text; Home's bars carry a label; the
//     Add and Paid to pills carry letters or the name.
// Invented rows, fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/domain/analytics/analytics_change.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/format/money.dart';
import 'package:mmogo/domain/format/source_types.dart';
import 'package:mmogo/ui/screens/analytics/analytics_filters.dart';
import 'package:mmogo/ui/screens/analytics/analytics_view.dart';
import 'package:mmogo/ui/screens/analytics/type_breakdown.dart';
import 'package:mmogo/ui/screens/add/add_screen.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/home_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/widgets/type_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y_matrix.dart';
import '../../support/fake_add_db.dart';
import '../../support/fake_analytics_db.dart';
import '../../support/fake_home_db.dart';

final _now = DateTime(2026, 10, 14, 12);

AnalyticsTransactionRow _row(int id, String type, int amount) => AnalyticsTransactionRow(
  id: id,
  displayCode: 'AV$id',
  sourceType: type,
  amountCents: amount,
  counterpartyLabel: null,
  counterpartyPhone: null,
  paybillAccountNumber: null,
  classificationId: id,
  classificationName: 'Shopping',
  occurredAt: _now,
  transactionCostCents: null,
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

// Seven types, a different amount each so the text is unique per tile.
final _rows = [
  _row(1, 'SEND_MONEY', 1100000),
  _row(2, 'PAYBILL', 2200000),
  _row(3, 'BUY_GOODS', 3300000),
  _row(4, 'CASH', 1400000),
  _row(5, 'POCHI_LA_BIASHARA', 1500000),
  _row(6, 'AGENT_WITHDRAWAL', 600000000),
  _row(7, 'AIRTIME', 1700000),
];

/// The cents a tile shows for [code] (the withdrawal tile shows the cash taken out).
int _shown(String code) {
  final v = _view(_rows);
  final rows = v.inc.where((r) => r.sourceType == code);
  return rows.fold<int>(0, (s, r) => s + (code == 'AGENT_WITHDRAWAL' ? r.withdrawn : r.spent));
}

Future<void> _pumpPanel(
  WidgetTester t,
  A11yVariant v, {
  ValueChanged<String>? onToggle,
  String? typeFilter,
}) async {
  final palette = v.dark ? AppPalette.dark : AppPalette.light;
  await pumpA11y(
    t,
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: AnalyticsTypePanel(
          palette: palette,
          view: _view(_rows),
          filters: AnalyticsFilters.handOff(type: typeFilter, classification: null),
          onToggleType: onToggle ?? (_) {},
        ),
      ),
    ),
    variant: v,
  );
}

Color _swatch(WidgetTester t, String code) {
  final tile = find.byKey(Key('analyticsTypeTile-$code'));
  final box = find.descendant(
    of: tile,
    matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 10 && w.decoration is BoxDecoration),
  );
  return ((t.widget<Container>(box.first).decoration! as BoxDecoration).color)!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'tour_seen_add': true, 'tour_seen_home': true}));

  group('By type tiles: name and amount are text, always visible (B1)', () {
    for (final v in kA11yVariants) {
      testWidgets('every tile prints name, percent and amount (${v.name})', (t) async {
        addTearDown(t.view.reset);
        await _pumpPanel(t, v);
        for (final (code, name) in sourceTypeOrder) {
          final tile = find.byKey(Key('analyticsTypeTile-$code'));
          await t.ensureVisible(tile);
          await a11ySettle(t);
          expect(find.descendant(of: tile, matching: find.text(name)), findsOneWidget, reason: '$code name');
          expect(find.descendant(of: tile, matching: find.text(formatKsh(_shown(code)))), findsOneWidget, reason: '$code amount');
          // A percent, or "tracked" for the withdrawal tile.
          final pct = code == 'AGENT_WITHDRAWAL' ? find.text('tracked') : find.textContaining('%');
          expect(find.descendant(of: tile, matching: pct), findsOneWidget, reason: '$code percent');
        }
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('the semantics label of every tile holds its name and its amount', (t) async {
      final h = t.ensureSemantics();
      addTearDown(t.view.reset);
      await _pumpPanel(t, kA11yVariants[1]);
      for (final (code, name) in sourceTypeOrder) {
        final tile = find.byKey(Key('analyticsTypeTile-$code'));
        await t.ensureVisible(tile);
        await a11ySettle(t);
        final byLabel = find.bySemanticsLabel(RegExp('^${RegExp.escape(name)}, .*${RegExp.escape(formatKsh(_shown(code)))}'));
        expect(byLabel, findsOneWidget, reason: '$code: a semantics label with the name and the amount');
      }
      await t.pumpWidget(const SizedBox());
      h.dispose();
    });

    testWidgets('a tap still TOGGLES the type filter (it shows nothing new)', (t) async {
      addTearDown(t.view.reset);
      final toggled = <String>[];
      await _pumpPanel(t, kA11yVariants[0], onToggle: toggled.add);
      await t.tap(find.byKey(const Key('analyticsTypeTile-PAYBILL')));
      await t.pump();
      await t.tap(find.byKey(const Key('analyticsTypeTile-SEND_MONEY')));
      await t.pump();
      expect(toggled, ['PAYBILL', 'SEND_MONEY']);
    });
  });

  group('each chart colour has its type name beside it (CB5)', () {
    for (final (name, palette) in [('light', AppPalette.light), ('dark', AppPalette.dark)]) {
      testWidgets('the tile swatch is the chart colour of its type ($name)', (t) async {
        addTearDown(t.view.reset);
        await _pumpPanel(t, A11yVariant(name, 1.0, name == 'dark'));
        for (final (code, typeName) in sourceTypeOrder) {
          final tile = find.byKey(Key('analyticsTypeTile-$code'));
          await t.ensureVisible(tile);
          await a11ySettle(t);
          expect(_swatch(t, code), palette.typeColor(code), reason: '$typeName swatch = chart colour');
          expect(find.descendant(of: tile, matching: find.text(typeName)), findsOneWidget, reason: '$typeName beside it');
        }
      });
    }

    test('the seven type colours are seven different colours in every palette (a colour can name one type)', () {
      for (final p in [AppPalette.light, AppPalette.dark, AppPalette.leafLight, AppPalette.leafDark, AppPalette.indigoLight, AppPalette.indigoDark]) {
        final colours = {for (final (code, _) in sourceTypeOrder) p.typeColor(code).toARGB32()};
        expect(colours.length, 7, reason: '${p.brightness} palette');
      }
    });
  });

  group('direction and status carry text, not only colour', () {
    test('Analytics change pills read with an arrow (up and down)', () {
      final up = analyticsChange(
        granularity: AnalyticsGranularity.month,
        range: AnalyticsPeriod.month(DateTime(2026, 9, 1)).range(today: DateTime(2026, 10, 14)),
        today: DateTime(2026, 10, 14),
        totalCents: 200000,
        priorCents: 100000,
        vs: 'last month',
      );
      final down = analyticsChange(
        granularity: AnalyticsGranularity.month,
        range: AnalyticsPeriod.month(DateTime(2026, 9, 1)).range(today: DateTime(2026, 10, 14)),
        today: DateTime(2026, 10, 14),
        totalCents: 50000,
        priorCents: 100000,
        vs: 'last month',
      );
      expect(up!.text, startsWith('▲'));
      expect(down!.text, startsWith('▼'));
    });

    testWidgets('Home: every type bar has a text label beside it', (t) async {
      addTearDown(t.view.reset);
      final now = DateTime(2026, 9, 24, 9, 30);
      await pumpA11y(
        t,
        HomeScreen(
          db: FakeHomeDb(
            now: now,
            thisTotal: 1000000,
            priorTotal: 500000,
            types: const {'SEND_MONEY': (400000, 0), 'BUY_GOODS': (300000, 0), 'PAYBILL': (200000, 0), 'CASH': (100000, 0)},
            recentCount: 3,
          ),
          clock: () => now,
          startUpdates: () async {},
          showWhatsNew: (_) async {},
        ),
        variant: kA11yVariants[1],
      );
      for (final code in ['SEND_MONEY', 'BUY_GOODS', 'PAYBILL', 'CASH']) {
        final label = find.byKey(Key('homeTypeLabel-$code'));
        await t.scrollUntilVisible(label, 200, scrollable: find.byType(Scrollable).first);
        expect(find.descendant(of: label, matching: find.byType(Text)), findsWidgets, reason: code);
        final text = t.widgetList<Text>(find.descendant(of: label, matching: find.byType(Text))).map((w) => w.data ?? '').join(' ');
        expect(text.trim(), isNotEmpty, reason: '$code label');
      }
    });

    test('Analytics and Home rows: the type tile has its own icon shape per type (not only a colour)', () {
      final icons = {for (final (code, _) in sourceTypeOrder) sourceTypeIcon(code).codePoint};
      expect(icons.length, 7, reason: 'seven types, seven glyphs');
    });

    testWidgets('Analytics rows: the row announces its type name (the visible tile is an icon, the name is in the label)', (t) async {
      final h = t.ensureSemantics();
      addTearDown(t.view.reset);
      await pumpA11y(
        t,
        AnalyticsScreen(db: FakeAnalyticsDb(analyticsSampleRows()), clock: () => analyticsTestNow),
        variant: kA11yVariants[0],
      );
      for (final (id, name) in [(2, 'Buy Goods'), (3, 'Paybill')]) {
        final row = find.byKey(Key('analyticsRow-$id'));
        await t.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
        expect(find.bySemanticsLabel(RegExp(', ${RegExp.escape(name)}, ')), findsWidgets, reason: 'row $id announces "$name"');
      }
      await t.pumpWidget(const SizedBox());
      h.dispose();
    });

    testWidgets('Add: every type pill shows letters or the name, never a bare colour', (t) async {
      addTearDown(t.view.reset);
      await pumpA11y(t, AddScreen(db: FakeAddDb()), variant: kA11yVariants[0]);
      for (final type in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME']) {
        final pill = find.byKey(Key('addTypePill_$type'));
        await t.ensureVisible(pill);
        final text = t.widgetList<Text>(find.descendant(of: pill, matching: find.byType(Text))).map((w) => w.data ?? '').join();
        expect(text.trim(), isNotEmpty, reason: type);
      }
    });
  });
}
