// S5: Home's cash-withdrawn line, the withdrawal-fee sub-line and the recent
// rows (fee note, hollow dot, muted amount, second line, screen-reader label).
// Same fake-db approach as home_screen_test.dart (real SQL is proven in
// test/data/home_s5_dao_test.dart). Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/mpesa_text.dart';
import 'package:mmogo/domain/home/home_period.dart';
import 'package:mmogo/domain/money/spent_amount.dart';
import 'package:mmogo/ui/copy/spend_copy.dart';
import 'package:mmogo/ui/screens/home_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime(2026, 9, 24, 9, 30);

class _Row {
  const _Row(this.id, this.type, this.cents, {this.fee, this.agent, this.label = 'Invented Shop'});
  final int id;
  final String type;
  final int cents;
  final int? fee;
  final String? agent;
  final String? label;
}

class _Db implements Database {
  _Db({required this.types, required this.rows});

  /// source_type -> (total, cost, withdrawn, count)
  final Map<String, (int, int, int, int)> types;
  final List<_Row> rows;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('GROUP BY source_type')) {
      return [
        for (final e in types.entries)
          {
            'source_type': e.key,
            'total': e.value.$1,
            'cost': e.value.$2,
            'withdrawn': e.value.$3,
            'n': e.value.$4,
          },
      ];
    }
    if (sql.contains('JOIN classifications')) {
      return [
        for (var i = 0; i < rows.length; i++)
          {
            'id': rows[i].id,
            'display_code': 'C${rows[i].id}',
            'source_type': rows[i].type,
            'amount_cents': rows[i].cents,
            'counterparty_label': rows[i].label,
            'transaction_occurred_at': _now.subtract(Duration(hours: i)).millisecondsSinceEpoch,
            'transaction_cost_cents': rows[i].fee,
            'agent_number': rows[i].agent,
            'classification_name': 'Lunch',
          },
      ];
    }
    if (sql.contains(kSpentCentsSql)) {
      final start = arguments!.first as int;
      final cur = {for (final p in HomePeriod.values) p.bounds(_now).$1};
      return [
        {'total': cur.contains(start) ? types.values.fold<int>(0, (s, t) => s + t.$1) : 0},
      ];
    }
    return const [];
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _Db db, {double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(392, 1600) * 3; // tall: every invented row fits whole
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(home: HomeScreen(db: db, clock: () => _now, startUpdates: () async {})));
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

AppPalette _pal(WidgetTester tester) => AppPalette.of(tester.element(find.byKey(const Key('homeSummaryCard'))));

const _plain = {'SEND_MONEY': (350000, 4200, 0, 2), 'PAYBILL': (120000, 2000, 0, 1)};
const _withWd = {
  'SEND_MONEY': (350000, 4200, 0, 2),
  'PAYBILL': (120000, 2000, 0, 1),
  'AGENT_WITHDRAWAL': (0, 2900, 500000, 2),
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'tour_seen_$homeTourId': true}));

  group('summary card', () {
    testWidgets('no withdrawal: no cash line, no fee sub-line, label unchanged', (tester) async {
      await _pump(tester, _Db(types: _plain, rows: const []));
      expect(find.byKey(const Key('homeCashWithdrawn')), findsNothing);
      expect(find.textContaining('Cash withdrawn'), findsNothing);
      expect(find.byKey(const Key('homeCostWithdrawalFees')), findsNothing);
      expect(find.text(mpesaText('Transaction cost (all M-Pesa)')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('homeCost'))).data, 'Ksh 62.00');
    });

    testWidgets('a withdrawal adds the muted line and the sub-line; total, bars and cost total are unchanged', (
      tester,
    ) async {
      await _pump(tester, _Db(types: _withWd, rows: const []));
      // Spent total is the same 4,700 as without the withdrawal.
      expect(tester.widget<Text>(find.byKey(const Key('homeTotal'))).data, 'Ksh 4,700.00');
      final line = tester.widget<Text>(
        find.descendant(of: find.byKey(const Key('homeCashWithdrawn')), matching: find.byType(Text)),
      );
      expect(line.textSpan!.toPlainText(), 'Cash withdrawn: Ksh 5,000.00 (not counted)');
      final spans = (line.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans[1].style!.fontWeight, FontWeight.w700);
      expect(line.textSpan!.style!.color, _pal(tester).mutedInk);
      // Cost total = 42 + 20 + 29 (the withdrawal fee is inside it); the sub-line has no .00.
      expect(tester.widget<Text>(find.byKey(const Key('homeCost'))).data, 'Ksh 91.00');
      expect(tester.widget<Text>(find.byKey(const Key('homeCostWithdrawalFees'))).data, 'incl. Ksh 29 withdrawal fees');
      // Six bars, no Withdrawal bar, percentages from the spent total only.
      expect(find.byKey(const Key('homeTypeRow-AGENT_WITHDRAWAL')), findsNothing);
      final bar = tester.widget<AnimatedFractionallySizedBox>(find.byKey(const Key('homeBar-SEND_MONEY')));
      expect(bar.widthFactor, closeTo(350000 / 470000, 1e-9));
    });

    testWidgets('semantics: cash line says not counted; cost row adds the withdrawals part', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, _Db(types: _withWd, rows: const []));
      expect(find.bySemanticsLabel('Cash withdrawn, Ksh 5,000.00, not counted as spending'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Transaction cost, all M-Pesa, Ksh 91.00, including Ksh 29.00 for withdrawals'),
        findsOneWidget,
      );
      h.dispose();
    });

    testWidgets('withdrawals with no fee: cash line shows, fee sub-line hidden, no "including"', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(
        tester,
        _Db(types: const {'SEND_MONEY': (350000, 4200, 0, 1), 'AGENT_WITHDRAWAL': (0, 0, 100000, 1)}, rows: const []),
      );
      expect(find.byKey(const Key('homeCashWithdrawn')), findsOneWidget);
      expect(find.byKey(const Key('homeCostWithdrawalFees')), findsNothing);
      expect(find.bySemanticsLabel('Transaction cost, all M-Pesa, Ksh 42.00'), findsOneWidget);
      h.dispose();
    });
  });

  group('recent rows', () {
    const rows = [
      _Row(1, 'SEND_MONEY', 120000, fee: 2900, label: 'Invented Person'),
      _Row(2, 'AGENT_WITHDRAWAL', 500000, fee: 2900, agent: '654321', label: null),
      _Row(3, 'BUY_GOODS', 80000, fee: 0, label: 'Invented Shop'),
      _Row(4, 'AIRTIME', 5000, fee: 0, label: null),
      _Row(5, 'CASH', 7000, label: null),
    ];
    final db = _Db(types: _withWd, rows: rows);

    testWidgets('fee note only when fee > 0; a row is the same height with and without it', (tester) async {
      await _pump(tester, db);
      expect(tester.widget<Text>(find.byKey(const Key('homeRecentFee-1'))).data, '+ Ksh 29.00 fee');
      expect(find.byKey(const Key('homeRecentFee-2')), findsOneWidget);
      for (final id in [3, 4, 5]) {
        expect(find.byKey(Key('homeRecentFee-$id')), findsNothing, reason: 'row $id has no fee');
      }
      final h1 = tester.getSize(find.byKey(const Key('homeRecentRow-1'))).height;
      expect(tester.getSize(find.byKey(const Key('homeRecentRow-3'))).height, h1);
      expect(tester.getSize(find.byKey(const Key('homeRecentRow-5'))).height, h1);
      // The note sits under the amount, right edges aligned.
      final a = tester.getRect(find.byKey(const Key('homeRecentAmount-1')));
      final f = tester.getRect(find.byKey(const Key('homeRecentFee-1')));
      expect(f.top, greaterThanOrEqualTo(a.bottom));
      expect(f.right, closeTo(a.right, 0.5));
    });

    testWidgets('row height is the same with and without a fee at 130% text', (tester) async {
      await _pump(tester, db, textScale: 1.3);
      final h1 = tester.getSize(find.byKey(const Key('homeRecentRow-1'))).height;
      expect(tester.getSize(find.byKey(const Key('homeRecentRow-3'))).height, h1);
    });

    testWidgets('hollow dot and muted amount on the Withdrawal row only', (tester) async {
      await _pump(tester, db);
      final pal = _pal(tester);
      BoxDecoration dot(int id) =>
          tester.widget<Container>(find.byKey(Key('homeRecentDot-$id'))).decoration! as BoxDecoration;
      final wd = dot(2);
      expect(wd.color, Colors.transparent);
      expect(wd.border!.top.width, 2);
      expect(wd.border!.top.color, pal.typeColor('AGENT_WITHDRAWAL'));
      expect(dot(1).color, pal.typeColor('SEND_MONEY'));
      expect(dot(1).border, isNull);
      final wdAmt = tester.widget<Text>(find.byKey(const Key('homeRecentAmount-2'))).style!;
      expect(wdAmt.color, pal.mutedInk);
      expect(wdAmt.fontWeight, FontWeight.w600);
      final otherAmt = tester.widget<Text>(find.byKey(const Key('homeRecentAmount-1'))).style!;
      expect(otherAmt.color, pal.ink);
      expect(otherAmt.fontWeight, FontWeight.w700);
    });

    testWidgets('second line: Type, agent number when present, date; Withdrawal and Airtime titles are the type name', (
      tester,
    ) async {
      await _pump(tester, db);
      expect(find.text('Withdrawal · 654321 · 24 Sep'), findsOneWidget);
      expect(find.text('Send Money · 24 Sep'), findsOneWidget);
      expect(find.text('Airtime · 24 Sep'), findsOneWidget);
      Finder inList(String t) => find.descendant(of: find.byKey(const Key('homeRecentCard')), matching: find.text(t));
      expect(inList('Withdrawal'), findsOneWidget); // the title
      expect(inList('Airtime'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('homeRecentCard')), matching: find.textContaining('not counted')),
        findsNothing,
      ); // the long sentence is not printed on a row
    });

    testWidgets('screen reader: the Withdrawal row carries the long sentence, another row does not', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, db);
      final label = notCountedLabel(feeCents: 2900);
      expect(label, 'not counted as spending, only the fee of Ksh 29.00');
      expect(
        find.bySemanticsLabel('Withdrawal, Ksh 5,000.00, $label, Withdrawal, 654321, 24 Sep'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('not counted as spending, only the fee')), findsOneWidget);
      h.dispose();
    });

    test('notCountedLabel without a fee', () {
      expect(notCountedLabel(), 'not counted as spending');
    });
  });
}
