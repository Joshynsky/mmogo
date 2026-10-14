// S5: Home's withdrawn figure, the withdrawal fee part and the recent-row fee
// and agent number, on real SQLite over invented rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/home_dashboard_dao.dart';

import '../support/spent_test_data.dart';

const _t0 = 1760000000000;
const _from = _t0 - 1000;
const _to = _t0 + 100000;

void main() {
  test('cash withdrawn and its count come only from withdrawals; the spent total ignores them', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await insertSpentTx(db, code: 'A1', sourceType: 'SEND_MONEY', amountCents: 10000, feeCents: 500, occurredAtMs: _t0);
    await insertSpentTx(db, code: 'A2', sourceType: 'AGENT_WITHDRAWAL', amountCents: 300000, feeCents: 2900, occurredAtMs: _t0 + 1);
    await insertSpentTx(db, code: 'A3', sourceType: 'AGENT_WITHDRAWAL', amountCents: 50000, feeCents: 1100, occurredAtMs: _t0 + 2);
    final by = await HomeDashboardDao.sourceTypeTotals(db, startMs: _from, endMs: _to);
    final w = by['AGENT_WITHDRAWAL']!;
    expect(w.withdrawnCents, 350000);
    expect(w.count, 2);
    expect(w.totalCents, 0);
    expect(w.costCents, 4000);
    expect(by['SEND_MONEY']!.withdrawnCents, 0);
    expect(await HomeDashboardDao.sumAmountCents(db, startMs: _from, endMs: _to), 10000);
  });

  test('a period with no withdrawal has no withdrawal entry (no line on Home)', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await insertSpentTx(db, code: 'B1', sourceType: 'SEND_MONEY', amountCents: 10000, feeCents: 500, occurredAtMs: _t0);
    await insertSpentTx(db, code: 'B2', sourceType: 'AGENT_WITHDRAWAL', amountCents: 9000, feeCents: 1100, occurredAtMs: _t0 + 500000);
    final by = await HomeDashboardDao.sourceTypeTotals(db, startMs: _from, endMs: _to);
    expect(by.containsKey('AGENT_WITHDRAWAL'), isFalse);
  });

  test('Home fees (total and the withdrawal part) equal Analytics fees over the same rows', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await insertSpentTx(db, code: 'C1', sourceType: 'PAYBILL', amountCents: 20000, feeCents: 1000, occurredAtMs: _t0);
    await insertSpentTx(db, code: 'C2', sourceType: 'AGENT_WITHDRAWAL', amountCents: 100000, feeCents: 2900, occurredAtMs: _t0 + 1);
    await insertSpentTx(db, code: 'C3', sourceType: 'CASH', amountCents: 7000, feeCents: 0, occurredAtMs: _t0 + 2);
    final home = await HomeDashboardDao.sourceTypeTotals(db, startMs: _from, endMs: _to);
    final rows = await AnalyticsDao.itemizedTransactions(db, startMs: _from, endMs: _to, types: AnalyticsDao.allTypes);
    int fee(Iterable<AnalyticsTransactionRow> r) => r.fold<int>(0, (s, x) => s + (x.transactionCostCents ?? 0));
    expect(home.values.fold<int>(0, (s, t) => s + t.costCents), fee(rows));
    expect(home['AGENT_WITHDRAWAL']!.costCents, fee(rows.where((r) => r.sourceType == 'AGENT_WITHDRAWAL')));
    expect(home['AGENT_WITHDRAWAL']!.withdrawnCents, rows.fold<int>(0, (s, r) => s + r.withdrawn));
  });

  test('recent rows carry the fee (0 for Cash) and the agent number', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await insertSpentTx(db, code: 'D1', sourceType: 'SEND_MONEY', amountCents: 10000, feeCents: 500, occurredAtMs: _t0);
    final wid = await insertSpentTx(db, code: 'D2', sourceType: 'AGENT_WITHDRAWAL', amountCents: 100000, feeCents: 2900, occurredAtMs: _t0 + 1);
    await db.update('transactions', {'agent_number': '123456'}, where: 'id = ?', whereArgs: [wid]);
    await insertSpentTx(db, code: 'D3', sourceType: 'CASH', amountCents: 7000, feeCents: 0, occurredAtMs: _t0 + 2);
    final recent = await HomeDashboardDao.recentTransactions(db, limit: 10);
    final byCode = {for (final r in recent) r.displayCode: r};
    expect(byCode['D1']!.feeCents, 500);
    expect(byCode['D1']!.agentNumber, isNull);
    expect(byCode['D2']!.feeCents, 2900);
    expect(byCode['D2']!.agentNumber, '123456');
    expect(byCode['D2']!.displayName, 'Withdrawal');
    expect(byCode['D3']!.feeCents, 0);
  });
}
