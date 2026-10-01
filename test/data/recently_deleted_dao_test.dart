// Integration tests for lib/data/db/recently_deleted_dao.dart against a
// real in-memory sqlite3 database — same backend/idiom every other DAO test
// in this suite uses (schema_test.dart/transaction_dao_test.dart/etc.).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/recently_deleted_dao.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openFreshDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await AppSchema.createSchema(db);
        await AppSchema.seed(db);
      },
    ),
  );
  return db;
}

Future<int> _classificationId(Database db, {required String groupCode, required String name}) async {
  final rows = await db.rawQuery(
    '''
    SELECT c.id FROM classifications c
    JOIN classification_groups g ON g.id = c.group_id
    WHERE g.code = ? AND c.name = ? AND c.active = 1
    ''',
    [groupCode, name],
  );
  return rows.first['id'] as int;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deletedTransactions returns only soft-deleted rows, most-recently-deleted first', () async {
    final db = await _openFreshDb();
    final sendMoneyClassId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Rent');
    final cashClassId = await _classificationId(db, groupCode: 'PAYBILL', name: 'Groceries');
    final buyGoodsClassId = await _classificationId(db, groupCode: 'BUY_GOODS', name: 'Shopping');

    final activeId = await TransactionDao.insert(
      db,
      NewTransactionInput(
        displayCode: 'THA7K2P9QX',
        sourceType: 'SEND_MONEY',
        amountCents: 100000,
        transactionCostCents: 1000,
        counterpartyLabel: 'JOHN KAMAU',
        counterpartyPhone: '0798630424',
        paybillAccountNumber: null,
        classificationId: sendMoneyClassId,
        rawParseSource: 'SMS_PARSE',
        transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final olderDeletedId = await TransactionDao.insert(
      db,
      NewTransactionInput(
        displayCode: 'CASH-20260918-1430',
        sourceType: 'CASH',
        amountCents: 50000,
        transactionCostCents: null,
        counterpartyLabel: null,
        counterpartyPhone: null,
        paybillAccountNumber: null,
        classificationId: cashClassId,
        rawParseSource: 'MANUAL',
        transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final newerDeletedId = await TransactionDao.insert(
      db,
      NewTransactionInput(
        displayCode: 'THB3M8N2RS',
        sourceType: 'BUY_GOODS',
        amountCents: 85000,
        transactionCostCents: 0,
        counterpartyLabel: 'NAIVAS SUPERMARKET',
        counterpartyPhone: null,
        paybillAccountNumber: null,
        classificationId: buyGoodsClassId,
        rawParseSource: 'SMS_PARSE',
        transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('transactions', {'deleted_at': now - 5000}, where: 'id = ?', whereArgs: [olderDeletedId]);
    await db.update('transactions', {'deleted_at': now - 1000}, where: 'id = ?', whereArgs: [newerDeletedId]);

    final rows = await RecentlyDeletedDao.deletedTransactions(db);

    expect(rows.map((r) => r.id).toList(), [newerDeletedId, olderDeletedId]); // most-recent-first
    expect(rows.any((r) => r.id == activeId), isFalse); // active row excluded

    final cashRow = rows.firstWhere((r) => r.id == olderDeletedId);
    expect(cashRow.displayName, 'Cash — Groceries');
    expect(cashRow.displayCode, 'CASH-20260918-1430');

    final buyGoodsRow = rows.firstWhere((r) => r.id == newerDeletedId);
    expect(buyGoodsRow.displayName, 'NAIVAS SUPERMARKET');
    await db.close();
  });

  test('an empty (no soft-deletes) database returns an empty list', () async {
    final db = await _openFreshDb();
    final rows = await RecentlyDeletedDao.deletedTransactions(db);
    expect(rows, isEmpty);
    await db.close();
  });
}
