// S6a: the data layer under the Analytics rows and the edit sheet. A
// Withdrawal row's agent number is read by the list query and written by
// TransactionDao.update (digits only, 1 to 20, null clears; refused before the
// write otherwise). Real in-memory sqlite, invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _fresh() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 3,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await AppSchema.createSchema(db);
        await AppSchema.seed(db);
      },
    ),
  );
}

Future<int> _classId(Database db, String seedKey) async =>
    (await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [seedKey])).first['id'] as int;

const _at = 1790000000000;

Future<int> _insert(Database db, String type, int cls, String code,
        {String? label, String? agent, int cost = 0}) =>
    TransactionDao.insert(
      db,
      NewTransactionInput(
        displayCode: code,
        sourceType: type,
        amountCents: 100000,
        transactionCostCents: cost,
        counterpartyLabel: label,
        counterpartyPhone: null,
        paybillAccountNumber: null,
        agentNumber: agent,
        classificationId: cls,
        rawParseSource: 'MANUAL',
        transactionOccurredAt: _at,
      ),
    );

Future<Map<String, Object?>> _row(Database db, int id) async =>
    (await db.query('transactions', where: 'id = ?', whereArgs: [id])).single;

void main() {
  late Database db;
  late int wdClass;
  late int pochiClass;
  setUp(() async {
    db = await _fresh();
    wdClass = await _classId(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
    pochiClass = await _classId(db, 'POCHI_LA_BIASHARA:transport');
  });
  tearDown(() => db.close());

  test('itemizedTransactions returns the agent number of a Withdrawal row (null when it has none)', () async {
    await _insert(db, 'AGENT_WITHDRAWAL', wdClass, 'TSTW000001', label: 'INVENTED AGENT', agent: '123456');
    await _insert(db, 'AGENT_WITHDRAWAL', wdClass, 'TSTW000002', label: 'NO NUMBER AGENT');
    final rows = await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes);
    final byCode = {for (final r in rows) r.displayCode: r};
    expect(byCode['TSTW000001']!.agentNumber, '123456');
    expect(byCode['TSTW000002']!.agentNumber, isNull);
  });

  test('update on a Withdrawal row writes the agent name, agent number and cost; null clears the number', () async {
    final id = await _insert(db, 'AGENT_WITHDRAWAL', wdClass, 'TSTW000003', label: 'OLD AGENT', agent: '111');
    await TransactionDao.update(
      db,
      id: id,
      amountCents: 250000,
      transactionOccurredAt: _at,
      classificationId: wdClass,
      counterpartyLabel: 'NEW AGENT',
      transactionCostCents: 2900,
      agentNumber: '98765',
    );
    var row = await _row(db, id);
    expect(row['counterparty_label'], 'NEW AGENT');
    expect(row['agent_number'], '98765');
    expect(row['transaction_cost_cents'], 2900);
    expect(row['amount_cents'], 250000);

    await TransactionDao.update(
      db,
      id: id,
      amountCents: 250000,
      transactionOccurredAt: _at,
      classificationId: wdClass,
      counterpartyLabel: 'NEW AGENT',
      transactionCostCents: 2900,
    );
    row = await _row(db, id);
    expect(row['agent_number'], isNull, reason: 'a Withdrawal save without a number clears it');
  });

  test('a bad agent number is refused before any write and the row is left alone', () async {
    final id = await _insert(db, 'AGENT_WITHDRAWAL', wdClass, 'TSTW000004', label: 'AGENT', agent: '555');
    for (final bad in ['', '12a', '1' * 21, ' 12']) {
      await expectLater(
        TransactionDao.update(
          db,
          id: id,
          amountCents: 1,
          transactionOccurredAt: _at,
          classificationId: wdClass,
          counterpartyLabel: 'CHANGED',
          transactionCostCents: 0,
          agentNumber: bad,
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'value "$bad"',
      );
    }
    final row = await _row(db, id);
    expect(row['agent_number'], '555');
    expect(row['counterparty_label'], 'AGENT');
  });

  test('a non-Withdrawal row never stores an agent number: absent is fine, given is refused', () async {
    final id = await _insert(db, 'POCHI_LA_BIASHARA', pochiClass, 'TSTP000001', label: 'INVENTED SHOP');
    await TransactionDao.update(
      db,
      id: id,
      amountCents: 5000,
      transactionOccurredAt: _at,
      classificationId: pochiClass,
      counterpartyLabel: 'RENAMED SHOP',
      transactionCostCents: 7,
    );
    final row = await _row(db, id);
    expect(row['counterparty_label'], 'RENAMED SHOP');
    expect(row['agent_number'], isNull);
    await expectLater(
      TransactionDao.update(
        db,
        id: id,
        amountCents: 5000,
        transactionOccurredAt: _at,
        classificationId: pochiClass,
        counterpartyLabel: 'RENAMED SHOP',
        transactionCostCents: 7,
        agentNumber: '123',
      ),
      throwsA(isA<ArgumentError>()),
      reason: 'a number on a Pochi row is refused, never stored',
    );
  });
}
