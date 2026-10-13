// SP2/SP6: the SQL sites. Home's two queries and Analytics' rows are run on real
// SQLite over all seven source types: a withdrawal adds 0 to spent and its fee
// shows in fees, and Home and Analytics agree.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/home_dashboard_dao.dart';
import 'package:mmogo/domain/format/source_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/spent_test_data.dart';

const _t0 = 1760000000000; // an invented instant
const _from = _t0 - 1000;
const _to = _t0 + 100000;

Future<void> _seedAllSeven(Database db) async {
  // amount, fee per type; the withdrawal carries a fee of KSh 29.
  const rows = <(String, int, int)>[
    ('SEND_MONEY', 10000, 500),
    ('PAYBILL', 20000, 1000),
    ('BUY_GOODS', 30000, 0),
    ('POCHI_LA_BIASHARA', 40000, 700),
    ('AGENT_WITHDRAWAL', 100000, 2900),
    ('AIRTIME', 5000, 0),
    ('CASH', 7000, 0),
  ];
  var i = 0;
  for (final (type, amount, fee) in rows) {
    i++;
    await insertSpentTx(db, code: 'SS$i', sourceType: type, amountCents: amount, feeCents: fee, occurredAtMs: _t0 + i);
  }
}

void main() {
  test('Home total: a withdrawal adds 0, the other six types count their amounts', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await _seedAllSeven(db);
    final total = await HomeDashboardDao.sumAmountCents(db, startMs: _from, endMs: _to);
    expect(total, 10000 + 20000 + 30000 + 40000 + 5000 + 7000); // 112000, no 100000
  });

  test('Home per-type: withdrawal total 0 but its fee is in the cost column', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await _seedAllSeven(db);
    final by = await HomeDashboardDao.sourceTypeTotals(db, startMs: _from, endMs: _to);
    expect(by['AGENT_WITHDRAWAL']!.totalCents, 0);
    expect(by['AGENT_WITHDRAWAL']!.costCents, 2900);
    expect(by['AIRTIME']!.totalCents, 5000);
    expect(by['POCHI_LA_BIASHARA']!.totalCents, 40000);
    expect(by['CASH']!.totalCents, 7000);
    final fees = by.values.fold<int>(0, (s, t) => s + t.costCents);
    expect(fees, 500 + 1000 + 0 + 700 + 2900 + 0 + 0);
  });

  test('Analytics rows: allTypes covers all seven; spent sums to Home\'s total; fees include the withdrawal', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await _seedAllSeven(db);
    expect(AnalyticsDao.allTypes, {for (final t in spentTestTypes) t});
    expect(AnalyticsDao.allTypes.length, 7);
    final rows = await AnalyticsDao.itemizedTransactions(db, startMs: _from, endMs: _to, types: AnalyticsDao.allTypes);
    expect(rows, hasLength(7));
    final spent = rows.fold<int>(0, (s, r) => s + r.spent);
    expect(spent, await HomeDashboardDao.sumAmountCents(db, startMs: _from, endMs: _to));
    final fees = rows.fold<int>(0, (s, r) => s + (r.transactionCostCents ?? 0));
    final home = await HomeDashboardDao.sourceTypeTotals(db, startMs: _from, endMs: _to);
    expect(fees, home.values.fold<int>(0, (s, t) => s + t.costCents));
    final w = rows.firstWhere((r) => r.sourceType == 'AGENT_WITHDRAWAL');
    expect(w.amountCents, 100000); // the stored fact is kept
    expect(w.spent, 0);
    expect(w.transactionCostCents, 2900);
  });

  test('Home and Analytics agree type by type over all seven types', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await _seedAllSeven(db);
    final home = await HomeDashboardDao.sourceTypeTotals(db, startMs: _from, endMs: _to);
    final rows = await AnalyticsDao.itemizedTransactions(db, startMs: _from, endMs: _to, types: AnalyticsDao.allTypes);
    for (final (code, _) in sourceTypeOrder) {
      final a = rows.where((r) => r.sourceType == code).fold<int>(0, (s, r) => s + r.spent);
      expect(home[code]?.totalCents ?? 0, a, reason: code);
    }
  });

  test('soft-deleted rows stay out of spent and fees', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await insertSpentTx(db, code: 'SD1', sourceType: 'AIRTIME', amountCents: 5000, feeCents: 0, occurredAtMs: _t0);
    await insertSpentTx(db,
        code: 'SD2', sourceType: 'AGENT_WITHDRAWAL', amountCents: 9000, feeCents: 1100, occurredAtMs: _t0, deletedAtMs: _t0);
    expect(await HomeDashboardDao.sumAmountCents(db, startMs: _from, endMs: _to), 5000);
    final by = await HomeDashboardDao.sourceTypeTotals(db, startMs: _from, endMs: _to);
    expect(by.containsKey('AGENT_WITHDRAWAL'), isFalse);
  });

  test('sourceTypeOrder pins the seven types, the four 0.1.1 ones first and unmoved', () {
    expect([for (final (c, _) in sourceTypeOrder) c], [
      'SEND_MONEY',
      'PAYBILL',
      'BUY_GOODS',
      'CASH',
      'POCHI_LA_BIASHARA',
      'AGENT_WITHDRAWAL',
      'AIRTIME',
    ]);
    expect(sourceTypeName('AGENT_WITHDRAWAL'), 'Withdrawal');
    expect(sourceTypeName('AIRTIME'), 'Airtime');
    expect(sourceTypeName('POCHI_LA_BIASHARA'), 'Pochi');
  });
}
