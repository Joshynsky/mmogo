// 0.1.2 S8c-1: what the Add form hands to the database, proved on a real
// in-memory sqlite (the widget tests use a fake). AddDraft.toInput is the one
// place the screen builds the row, so the DB CHECKs (agent_number only on a
// Withdrawal, digits only 1..20; labels; fee) are exercised on exactly that
// output. A bad agent number must come out as null and never reach
// TransactionDao.checkAgentNumber. Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:mmogo/ui/screens/add/add_draft.dart';
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

Future<int> _classId(Database db, String seedKey) async =>
    (await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [seedKey])).first['id'] as int;

AddDraft _draft({
  String src = 'MPESA',
  required String type,
  bool capture = true,
  String amount = '2,000.00',
  String fee = '',
  String code = 'ABC1D2E3F4',
  String name = '',
  String sub = '',
  int? cls,
}) =>
    AddDraft(
      src: src,
      type: type,
      captureIdentity: capture,
      amountText: amount,
      feeText: fee,
      codeText: code,
      nameText: name,
      subText: sub,
      codeDuplicate: false,
      classificationId: cls,
    );

NewTransactionInput _input(AddDraft d) =>
    d.toInput(cashCode: 'CASH-20261015-0900', rawParseSource: 'MANUAL', occurredAtMillis: 1790000000000);

void main() {
  late Database db;
  late int withdrawal;
  late int airtime;
  setUp(() async {
    db = await _fresh();
    withdrawal = await _classId(db, AddDraft.fixedSeedKey('AGENT_WITHDRAWAL')!);
    airtime = await _classId(db, AddDraft.fixedSeedKey('AIRTIME')!);
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> rowOf(int id) async =>
      (await db.query('transactions', where: 'id = ?', whereArgs: [id])).single;

  test('the seed keys the screen looks up are the real built-in ones (no schema edit)', () async {
    final w = (await db.query('classifications', where: 'id = ?', whereArgs: [withdrawal])).single;
    final a = (await db.query('classifications', where: 'id = ?', whereArgs: [airtime])).single;
    expect(w['name'], 'Withdrawal');
    expect(a['name'], 'Airtime');
  });

  test('Withdrawal with agent name and number: stored; the amount comma is only display', () async {
    final d = _draft(type: 'AGENT_WITHDRAWAL', fee: '29', name: 'Demo Agent', sub: '765432', cls: withdrawal);
    final id = await TransactionDao.insert(db, _input(d));
    final row = await rowOf(id);
    expect(row['agent_number'], '765432');
    expect(row['counterparty_label'], 'Demo Agent');
    expect(row['amount_cents'], 200000);
    expect(row['transaction_cost_cents'], 2900);
    expect(row['source_type'], 'AGENT_WITHDRAWAL');
  });

  test('Withdrawal with the tick off: no agent number and no label are stored even if the fields hold values', () async {
    final d = _draft(type: 'AGENT_WITHDRAWAL', capture: false, fee: '0', name: 'Demo Agent', sub: '765432', cls: withdrawal);
    final row = await rowOf(await TransactionDao.insert(db, _input(d)));
    expect(row['agent_number'], isNull);
    expect(row['counterparty_label'], isNull);
    expect(row['transaction_cost_cents'], 0);
  });

  test('an agent number that is not 1..20 digits becomes null and never reaches the DAO check', () async {
    for (final bad in ['', '12a', '12 34', '1' * 21, '１２３', '+123']) {
      final d = _draft(type: 'AGENT_WITHDRAWAL', fee: '29', sub: bad, cls: withdrawal);
      expect(d.effectiveAgentNumber, isNull, reason: bad);
      final id = await TransactionDao.insert(db, _input(d)); // would throw ArgumentError if it carried the value
      expect((await rowOf(id))['agent_number'], isNull, reason: bad);
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
    final twenty = _draft(type: 'AGENT_WITHDRAWAL', fee: '29', sub: '1' * 20, cls: withdrawal);
    expect(twenty.effectiveAgentNumber, '1' * 20);
  });

  test('agent_number is written only for a Withdrawal (other types and Cash never carry it)', () async {
    final sm = await _classId(db, 'SEND_MONEY:rent');
    final send = _draft(type: 'SEND_MONEY', name: 'Jane', sub: '0712345678', cls: sm);
    expect(_input(send).agentNumber, isNull);
    final cash = _draft(src: 'CASH', type: 'AGENT_WITHDRAWAL', sub: '765432', cls: sm);
    expect(_input(cash).agentNumber, isNull);
  });

  test('Airtime: label null, fee 0 when nothing parsed, a parsed fee kept; no receiver ever stored', () async {
    final hand = _draft(type: 'AIRTIME', amount: '50', name: 'Typed Before', sub: '0712345678', cls: airtime);
    final row = await rowOf(await TransactionDao.insert(db, _input(hand)));
    expect(row['counterparty_label'], isNull);
    expect(row['counterparty_phone'], isNull);
    expect(row['agent_number'], isNull);
    expect(row['transaction_cost_cents'], 0);
    expect(row['amount_cents'], 5000);

    final parsed = _draft(type: 'AIRTIME', amount: '200.00', fee: '3.00', code: 'PT8N4W7Q2K', cls: airtime);
    final row2 = await rowOf(await TransactionDao.insert(db, _input(parsed)));
    expect(row2['transaction_cost_cents'], 300);
  });

  test('Pochi: the name is the label, no phone, no account', () async {
    final rows = await db.rawQuery(
        "SELECT c.id FROM classifications c JOIN classification_groups g ON g.id = c.group_id "
        "WHERE g.code = 'POCHI_LA_BIASHARA' AND c.active = 1 LIMIT 1");
    expect(rows, isNotEmpty, reason: 'the v3 seed has Pochi categories');
    final d = _draft(type: 'POCHI_LA_BIASHARA', name: 'Jane Sample', cls: rows.first['id'] as int);
    final row = await rowOf(await TransactionDao.insert(db, _input(d)));
    expect(row['counterparty_label'], 'Jane Sample');
    expect(row['counterparty_phone'], isNull);
    expect(row['paybill_account_number'], isNull);
  });

  group('rules', () {
    test('Withdrawal fee: empty is not valid, a typed 0 is, a bad value is not', () {
      expect(_draft(type: 'AGENT_WITHDRAWAL').feeCents, isNull);
      expect(_draft(type: 'AGENT_WITHDRAWAL', fee: '0').feeCents, 0);
      expect(_draft(type: 'AGENT_WITHDRAWAL', fee: '20000000').feeCents, isNull);
      expect(_draft(type: 'SEND_MONEY').feeCents, 0, reason: 'other types: empty = 0');
      expect(_draft(src: 'CASH', type: 'AGENT_WITHDRAWAL').feeCents, 0, reason: 'Cash ignores the M-Pesa type');
    });

    test('fee error timing: empty shows only once touched; a bad value at once; never on Airtime', () {
      final w = _draft(type: 'AGENT_WITHDRAWAL');
      expect(w.feeError(touched: false), isNull);
      expect(w.feeError(touched: true), 'Enter the fee. It can be 0 if you were not charged.');
      expect(_draft(type: 'AGENT_WITHDRAWAL', fee: '20000000').feeError(touched: false),
          'Enter a cost from 0 to 10,000,000.00');
      expect(_draft(type: 'AIRTIME').feeError(touched: true), isNull);
      expect(_draft(type: 'SEND_MONEY').feeError(touched: true), isNull);
    });

    test('the counterparty key stays empty for Withdrawal, Airtime and Pochi', () {
      for (final t in ['AGENT_WITHDRAWAL', 'AIRTIME', 'POCHI_LA_BIASHARA']) {
        expect(_draft(type: t, name: 'Someone', sub: '123').counterpartyKey, '', reason: t);
      }
    });

    test('agent name and number do not gate Review', () {
      final d = _draft(type: 'AGENT_WITHDRAWAL', fee: '29', cls: 1);
      expect(d.canReview, isTrue);
      expect(d.identityPairComplete, isTrue);
    });
  });
}
