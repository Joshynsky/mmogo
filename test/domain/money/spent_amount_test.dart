// SP1: the one spent rule. The Dart function and the SQL expression are run
// over the same (type, amount, fee) table, the SQL on real SQLite, and must
// agree row by row.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/money/spent_amount.dart';

import '../../support/spent_test_data.dart';

/// The rule table (reading A): type, amount, fee, expected spent.
const _table = <(String, int, int?, int)>[
  ('SEND_MONEY', 10000, 500, 10000),
  ('PAYBILL', 25050, 0, 25050),
  ('BUY_GOODS', 7000, 0, 7000),
  ('POCHI_LA_BIASHARA', 12000, 500, 12000),
  ('AIRTIME', 5000, 0, 5000),
  ('CASH', 3000, null, 3000),
  ('AGENT_WITHDRAWAL', 100000, 2900, 0),
  ('AGENT_WITHDRAWAL', 5000, 1100, 0),
];

void main() {
  test('spentCents follows the rule table (withdrawal 0, everything else its amount)', () {
    for (final (type, amount, fee, expected) in _table) {
      expect(spentCents(type, amount, fee), expected, reason: '$type $amount fee $fee');
    }
  });

  test('isWithdrawal is true only for AGENT_WITHDRAWAL', () {
    for (final t in spentTestTypes) {
      expect(isWithdrawal(t), t == 'AGENT_WITHDRAWAL', reason: t);
    }
    expect(isWithdrawal('agent_withdrawal'), isFalse);
  });

  test('the SQL expression and spentCents agree over the whole table on real SQLite', () async {
    final db = await openSpentTestDb();
    addTearDown(db.close);
    var i = 0;
    for (final (type, amount, fee, _) in _table) {
      i++;
      await insertSpentTx(
        db,
        code: 'SPT$i',
        sourceType: type,
        amountCents: amount,
        feeCents: fee ?? 0,
        occurredAtMs: 1760000000000 + i,
      );
    }
    final rows = await db.rawQuery(
      'SELECT source_type, amount_cents, transaction_cost_cents AS fee, $kSpentCentsSql AS spent '
      'FROM transactions ORDER BY id',
    );
    expect(rows, hasLength(_table.length));
    for (var k = 0; k < rows.length; k++) {
      final r = rows[k];
      final dart = spentCents(r['source_type']! as String, r['amount_cents']! as int, r['fee'] as int?);
      expect(r['spent'], dart, reason: 'row $k ${r['source_type']}');
      expect(r['spent'], _table[k].$4, reason: 'row $k table');
    }
    // The aliased form is the same expression.
    final aliased = await db.rawQuery('SELECT ${spentCentsSqlFor('t')} AS spent FROM transactions t ORDER BY t.id');
    expect([for (final r in aliased) r['spent']], [for (final row in _table) row.$4]);
  });

  test('the SQL fragment names no column but source_type and amount_cents', () {
    expect(kSpentCentsSql, contains("source_type = 'AGENT_WITHDRAWAL'"));
    expect(kSpentCentsSql, isNot(contains('transaction_cost_cents')));
  });

  test('the checker itself can fail: a wrong expected value is caught', () async {
    // Negative case for the table: a withdrawal counted in full must not match.
    expect(spentCents('AGENT_WITHDRAWAL', 5000, 1100), isNot(5000));
    final db = await openSpentTestDb();
    addTearDown(db.close);
    await insertSpentTx(
      db,
      code: 'SPN1',
      sourceType: 'AGENT_WITHDRAWAL',
      amountCents: 5000,
      feeCents: 1100,
      occurredAtMs: 1760000000000,
    );
    final raw = await db.rawQuery('SELECT SUM(amount_cents) AS s FROM transactions');
    // A raw SUM(amount_cents) over a withdrawal is exactly the bug the rule removes.
    expect(raw.first['s'], 5000);
    final ruled = await db.rawQuery('SELECT SUM($kSpentCentsSql) AS s FROM transactions');
    expect(ruled.first['s'], 0);
  });
}
