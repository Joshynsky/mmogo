// P-Home-13: back from the background (paused, then resumed) Home re-queries,
// and the figures stay put when nothing changed. Fake db, invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/home/home_period.dart';
import 'package:mmogo/domain/money/spent_amount.dart';
import 'package:mmogo/ui/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime(2026, 9, 24, 9, 30);

class _Db implements Database {
  int total = 120000;
  String label = 'Invented Shop';
  int queries = 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    queries++;
    if (sql.contains('GROUP BY source_type')) {
      return [
        {'source_type': 'PAYBILL', 'total': total, 'cost': 0, 'withdrawn': 0, 'n': 1},
      ];
    }
    if (sql.contains('JOIN classifications')) {
      return [
        {
          'id': 1,
          'display_code': 'C1',
          'source_type': 'PAYBILL',
          'amount_cents': total,
          'counterparty_label': label,
          'transaction_occurred_at': _now.millisecondsSinceEpoch,
          'transaction_cost_cents': 0,
          'agent_number': null,
          'classification_name': 'Lunch',
        },
      ];
    }
    if (sql.contains(kSpentCentsSql)) {
      final start = arguments!.first as int;
      final cur = {for (final p in HomePeriod.values) p.bounds(_now).$1};
      return [
        {'total': cur.contains(start) ? total : 0},
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
  tester.view.physicalSize = const Size(392, 1600) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: HomeScreen(db: db, clock: () => _now, startUpdates: () async {})));
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// The legal path the engine takes: resumed, inactive, hidden, paused and back.
void _pause(WidgetTester tester) {
  for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void _resume(WidgetTester tester) {
  for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

Future<void> _background(WidgetTester tester) async {
  _pause(tester);
  await tester.pump();
  _resume(tester);
  await tester.pump();
  await tester.pumpAndSettle();
}

String _total(WidgetTester t) => t.widget<Text>(find.byKey(const Key('homeTotal'))).data ?? '';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'tour_seen_$homeTourId': true}));

  testWidgets('P-Home-13: after paused then resumed, the new total and the new first row show', (tester) async {
    final db = _Db();
    await _pump(tester, db);
    final before = _total(tester);
    expect(find.text('Invented Shop'), findsOneWidget);

    db.total = 345000;
    db.label = 'Changed Kiosk';
    await _background(tester);

    expect(_total(tester), isNot(before));
    expect(find.text('Changed Kiosk'), findsOneWidget);
    expect(find.text('Invented Shop'), findsNothing);
  });

  testWidgets('P-Home-13: a resume with no data change re-queries and leaves the figures as they were, no loading state', (tester) async {
    final db = _Db();
    await _pump(tester, db);
    final before = _total(tester);
    final queriesBefore = db.queries;

    _pause(tester);
    await tester.pump();
    _resume(tester);
    await tester.pump(); // the frame right after resume, before the query settles
    expect(_total(tester), before, reason: 'no flicker: the figures stay while the re-query runs');
    expect(find.text('Invented Shop'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(db.queries, greaterThan(queriesBefore), reason: 'resume did re-query');
    expect(_total(tester), before);
    expect(find.text('Invented Shop'), findsOneWidget);
  });
}
