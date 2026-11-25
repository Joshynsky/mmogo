// F1 (0.2.2): HomeDashboardDao.withdrawalLeftoverCents on real SQLite, invented rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/home_dashboard_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/spent_test_data.dart';

const _t0 = 1760000000000;
const _from = _t0 - 1000;
const _to = _t0 + 100000;

Future<void> _link(Database db, int cashId, int withdrawalId) =>
    db.update('transactions', {'parent_transaction_id': withdrawalId}, where: 'id = ?', whereArgs: [cashId]);

Future<int> _leftover(Database db) => HomeDashboardDao.withdrawalLeftoverCents(db, startMs: _from, endMs: _to);

void main() {
  test('no withdrawal in the period: zero', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await insertSpentTx(db, code: 'A1', sourceType: 'SEND_MONEY', amountCents: 10000, feeCents: 0, occurredAtMs: _t0);
    expect(await _leftover(db), 0);
  });

  test('unlinked withdrawal: all of it; partly linked: the rest; fully linked: zero', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    final w = await insertSpentTx(db, code: 'B1', sourceType: 'AGENT_WITHDRAWAL', amountCents: 100000, feeCents: 2900, occurredAtMs: _t0);
    expect(await _leftover(db), 100000);
    final c1 = await insertSpentTx(db, code: 'B2', sourceType: 'CASH', amountCents: 50000, feeCents: 0, occurredAtMs: _t0 + 1);
    await _link(db, c1, w);
    expect(await _leftover(db), 50000);
    final c2 = await insertSpentTx(db, code: 'B3', sourceType: 'CASH', amountCents: 50000, feeCents: 0, occurredAtMs: _t0 + 2);
    await _link(db, c2, w);
    expect(await _leftover(db), 0, reason: 'two equal amounts are two entries');
  });

  test('over-linked never goes negative and does not reduce another withdrawal', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    final w1 = await insertSpentTx(db, code: 'C1', sourceType: 'AGENT_WITHDRAWAL', amountCents: 100000, feeCents: 0, occurredAtMs: _t0);
    await insertSpentTx(db, code: 'C2', sourceType: 'AGENT_WITHDRAWAL', amountCents: 50000, feeCents: 0, occurredAtMs: _t0 + 1);
    final c = await insertSpentTx(db, code: 'C3', sourceType: 'CASH', amountCents: 300000, feeCents: 0, occurredAtMs: _t0 + 2);
    await _link(db, c, w1);
    expect(await _leftover(db), 50000);
  });

  test('a deleted linked entry no longer counts; a deleted withdrawal is ignored; cash not linked is ignored', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    final w = await insertSpentTx(db, code: 'D1', sourceType: 'AGENT_WITHDRAWAL', amountCents: 100000, feeCents: 0, occurredAtMs: _t0);
    final gone = await insertSpentTx(db, code: 'D2', sourceType: 'CASH', amountCents: 40000, feeCents: 0, occurredAtMs: _t0 + 1);
    await _link(db, gone, w);
    await db.update('transactions', {'deleted_at': _t0 + 5}, where: 'id = ?', whereArgs: [gone]);
    await insertSpentTx(db, code: 'D3', sourceType: 'CASH', amountCents: 60000, feeCents: 0, occurredAtMs: _t0 + 2); // hand cash, not linked
    expect(await _leftover(db), 100000);
    final w2 = await insertSpentTx(db, code: 'D4', sourceType: 'AGENT_WITHDRAWAL', amountCents: 70000, feeCents: 0, occurredAtMs: _t0 + 3);
    await db.update('transactions', {'deleted_at': _t0 + 6}, where: 'id = ?', whereArgs: [w2]);
    expect(await _leftover(db), 100000);
  });

  test('only withdrawals inside the period count', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await insertSpentTx(db, code: 'E1', sourceType: 'AGENT_WITHDRAWAL', amountCents: 80000, feeCents: 0, occurredAtMs: _t0 + 500000);
    expect(await _leftover(db), 0);
  });
}
