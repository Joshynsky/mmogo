// 0.1.2 S9b-1: TransactionDao.restore returns the rows it changed and only
// touches a row that is STILL soft-deleted (a stale Undo changes nothing).
// In-memory database; plain test().
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/transaction_dao.dart';

import '../../support/restore_test_db.dart';

void main() {
  test('restore returns 1 for a soft-deleted row and clears deleted_at', () async {
    final db = await openTestDb();
    final cls = await seedId(db, 'SEND_MONEY:rent');
    final id = await addTx(db, code: 'AAA1111111', source: 'SEND_MONEY', classId: cls, deletedAt: t0 + 5);
    expect(await TransactionDao.restore(db, id: id), 1);
    expect((await db.query('transactions', where: 'id = ?', whereArgs: [id])).first['deleted_at'], isNull);
    await db.close();
  });

  test('restore returns 0 for a live row, a missing id and an id removed by Delete data', () async {
    final db = await openTestDb();
    final cls = await seedId(db, 'SEND_MONEY:rent');
    final live = await addTx(db, code: 'AAA1111111', source: 'SEND_MONEY', classId: cls);
    expect(await TransactionDao.restore(db, id: live), 0, reason: 'already live: nothing changed');
    expect(await TransactionDao.restore(db, id: 99999), 0);

    final gone = await addTx(db, code: 'AAA2222222', source: 'SEND_MONEY', classId: cls, deletedAt: t0 + 5);
    await db.delete('transactions');
    expect(await TransactionDao.restore(db, id: gone), 0);

    // AUTOINCREMENT: the stale id never lands on a newer row.
    final fresh = await addTx(db, code: 'AAA3333333', source: 'SEND_MONEY', classId: cls, deletedAt: t0 + 6);
    expect(fresh, greaterThan(gone));
    expect(await TransactionDao.restore(db, id: gone), 0);
    expect((await db.query('transactions', where: 'id = ?', whereArgs: [fresh])).first['deleted_at'], isNotNull);
    await db.close();
  });
}
