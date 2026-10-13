// C-A2 (S3b): the DAO validates `agent_number` BEFORE insert, so a database
// CHECK failure is never the first line of defence. Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _fresh() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) async {
            await AppSchema.createSchema(db);
            await AppSchema.seed(db);
          }));
}

Future<int> _classId(Database db, String seedKey) async => (await db
        .rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [seedKey]))
    .first['id'] as int;

NewTransactionInput _input(String type, int cls, String code, String? agent) => NewTransactionInput(
      displayCode: code,
      sourceType: type,
      amountCents: 10000,
      transactionCostCents: 0,
      counterpartyLabel: null,
      counterpartyPhone: null,
      paybillAccountNumber: null,
      agentNumber: agent,
      classificationId: cls,
      rawParseSource: 'MANUAL',
      transactionOccurredAt: 1790000000000,
    );

void main() {
  late Database db;
  late int withdrawal;
  late int sendMoney;
  setUp(() async {
    db = await _fresh();
    withdrawal = await _classId(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
    sendMoney = await _classId(db, 'SEND_MONEY:rent');
  });
  tearDown(() => db.close());

  Future<int> rows() async => (await db.rawQuery('SELECT COUNT(*) FROM transactions')).first.values.first as int;

  test('valid: null, 1 digit and 20 digits on a Withdrawal row are stored as given', () async {
    for (final (i, agent) in [null, '7', '12345678901234567890'].indexed) {
      final id = await TransactionDao.insert(db, _input('AGENT_WITHDRAWAL', withdrawal, 'TSTW00000$i', agent));
      final row = (await db.query('transactions', where: 'id = ?', whereArgs: [id])).single;
      expect(row['agent_number'], agent);
    }
  });

  test('invalid values are refused with ArgumentError BEFORE any insert, and the message never holds the value',
      () async {
    final bad = ['', ' 123', '12 34', '12a', '12\n', '１２３', '1' * 21, '+123', '12-34'];
    for (final agent in bad) {
      Object? error;
      try {
        await TransactionDao.insert(db, _input('AGENT_WITHDRAWAL', withdrawal, 'TSTBAD0001', agent));
      } catch (e) {
        error = e;
      }
      expect(error, isA<ArgumentError>(), reason: 'value ${agent.codeUnits}');
      expect('$error', isNot(contains(agent.isEmpty ? '\u0000' : agent)));
    }
    expect(await rows(), 0, reason: 'nothing reached the table');
  });

  test('an agent number on a non-Withdrawal row is refused with ArgumentError', () async {
    Object? error;
    try {
      await TransactionDao.insert(db, _input('SEND_MONEY', sendMoney, 'TSTSM00001', '123456'));
    } catch (e) {
      error = e;
    }
    expect(error, isA<ArgumentError>());
    expect(await rows(), 0);
  });

  test('NEGATIVE CONTROL: bypassing the guard (a raw insert) is stopped by the CHECK as a '
      'DatabaseException, not an ArgumentError, so the guard test above can fail', () async {
    Object? error;
    try {
      await db.insert('transactions', {
        'display_code': 'TSTRAW0001', 'source_type': 'AGENT_WITHDRAWAL', 'amount_cents': 100,
        'transaction_cost_cents': 0, 'agent_number': '12a', 'classification_id': withdrawal,
        'raw_parse_source': 'MANUAL', 'transaction_occurred_at': 1, 'created_at': 1,
      });
    } catch (e) {
      error = e;
    }
    expect(error, isA<DatabaseException>());
    expect(error, isNot(isA<ArgumentError>()));
  });

  test('checkAgentNumber accepts exactly what the CHECK accepts (digit boundary 1..20)', () {
    for (final ok in ['0', '9', '1' * 20]) {
      TransactionDao.checkAgentNumber(sourceType: 'AGENT_WITHDRAWAL', agentNumber: ok);
    }
    expect(() => TransactionDao.checkAgentNumber(sourceType: 'AGENT_WITHDRAWAL', agentNumber: '1' * 21),
        throwsArgumentError);
    expect(() => TransactionDao.checkAgentNumber(sourceType: 'AIRTIME', agentNumber: '1'), throwsArgumentError);
    TransactionDao.checkAgentNumber(sourceType: 'AIRTIME', agentNumber: null);
  });
}
