// 0.1.2 S6b on Home (P-Home-06): the change line's progress cue early in This
// week / This month, the states of the signed mock (home.html 196-200), and the
// one-rule agreement with Analytics. Same fake-db approach as home_s5_test.dart.
// Invented numbers only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/home/home_period.dart';
import 'package:mmogo/domain/money/spent_amount.dart';
import 'package:mmogo/ui/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Db implements Database {
  _Db({required this.now, this.thisTotal = 0, this.priorTotal = 0});

  final DateTime now;
  final int thisTotal;
  final int priorTotal;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('GROUP BY source_type') || sql.contains('JOIN classifications')) return const [];
    if (sql.contains(kSpentCentsSql)) {
      final start = arguments!.first as int;
      final cur = {for (final p in HomePeriod.values) p.bounds(now).$1};
      return [
        {'total': cur.contains(start) ? thisTotal : priorTotal},
      ];
    }
    return const [];
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _Db db) async {
  tester.view.physicalSize = const Size(392, 850) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox()); // a fresh HomeScreen state each time
  await tester.pumpWidget(MaterialApp(home: HomeScreen(db: db, clock: () => db.now, startUpdates: () async {})));
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

Future<void> _cycle(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(const Key('homePeriodButton')));
    await tester.pumpAndSettle();
  }
}

String _diff(WidgetTester t) => t.widget<Text>(find.byKey(const Key('homeDiff'))).data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'tour_seen_$homeTourId': true}));

  group('This month', () {
    testWidgets('day 7 of 30: the cue "7/30", no change, with the words for a screen reader', (t) async {
      await _pump(t, _Db(now: DateTime(2026, 9, 7, 9), thisTotal: 300000, priorTotal: 200000));
      expect(_diff(t), '7/30');
      expect(find.textContaining('▲'), findsNothing);
      expect(find.bySemanticsLabel('Day 7 of 30. The change shows from the middle of the period'), findsOneWidget);
      expect(find.byTooltip('Day 7 of 30. The change shows from the middle of the period'), findsOneWidget);
    });

    testWidgets('the cue stops and the change starts at day 15 of a 30-day month', (t) async {
      await _pump(t, _Db(now: DateTime(2026, 9, 14, 9), thisTotal: 300000, priorTotal: 200000));
      expect(_diff(t), '14/30');
      await _pump(t, _Db(now: DateTime(2026, 9, 15, 9), thisTotal: 300000, priorTotal: 200000));
      expect(_diff(t), '▲ 50% vs last month');
    });

    testWidgets('a 31-day month shows the change from day 16', (t) async {
      await _pump(t, _Db(now: DateTime(2026, 8, 15, 9), thisTotal: 300000, priorTotal: 200000));
      expect(_diff(t), '15/31');
      await _pump(t, _Db(now: DateTime(2026, 8, 16, 9), thisTotal: 300000, priorTotal: 200000));
      expect(_diff(t), '▲ 50% vs last month');
    });

    testWidgets('equal totals: "= 0% vs last month"', (t) async {
      await _pump(t, _Db(now: DateTime(2026, 9, 24, 9), thisTotal: 200000, priorTotal: 200000));
      expect(_diff(t), '= 0% vs last month');
    });

    testWidgets('prior zero with spending, and nothing at all', (t) async {
      await _pump(t, _Db(now: DateTime(2026, 9, 24, 9), thisTotal: 200000, priorTotal: 0));
      expect(_diff(t), 'No spend in the prior period to compare');
      await _pump(t, _Db(now: DateTime(2026, 9, 24, 9)));
      expect(_diff(t), '—');
    });
  });

  group('This week', () {
    testWidgets('Wednesday (day 3 of 7): the cue "3/7"; Thursday: the change', (t) async {
      final wed = _Db(now: DateTime(2026, 9, 23, 9), thisTotal: 300000, priorTotal: 200000);
      await _pump(t, wed);
      await _cycle(t, 2); // Month -> Today -> This week
      expect(find.text('This week'), findsOneWidget);
      expect(_diff(t), '3/7');
      expect(find.bySemanticsLabel('Day 3 of 7. The change shows from the middle of the period'), findsOneWidget);
      await _pump(t, _Db(now: DateTime(2026, 9, 24, 9), thisTotal: 300000, priorTotal: 200000));
      await _cycle(t, 2);
      expect(_diff(t), '▲ 50% vs last week');
    });

    testWidgets('equal totals on a week: "—", never "= 0%"', (t) async {
      await _pump(t, _Db(now: DateTime(2026, 9, 25, 9), thisTotal: 200000, priorTotal: 200000));
      await _cycle(t, 2);
      expect(_diff(t), '—');
    });
  });

  group('Today', () {
    testWidgets('has no cue (the 10th is early in the month); compares with yesterday', (t) async {
      await _pump(t, _Db(now: DateTime(2026, 9, 10, 9), thisTotal: 300000, priorTotal: 200000));
      await _cycle(t, 1); // Month -> Today
      expect(find.text('Today'), findsOneWidget);
      expect(_diff(t), '▲ 50% vs yesterday');
    });

    testWidgets('equal totals: "= 0% vs yesterday"', (t) async {
      await _pump(t, _Db(now: DateTime(2026, 9, 24, 9), thisTotal: 200000, priorTotal: 200000));
      await _cycle(t, 1);
      expect(_diff(t), '= 0% vs yesterday');
    });
  });
}
