// WBS row 17: an Airtime entry cannot move between its two categories (database
// trigger plus the DAO guard). Real in-memory database; invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:mmogo/domain/airtime/airtime_kind.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/restore_test_db.dart';

void main() {
  late Database db;
  late int myself;
  late int other;
  late int airtimeTx;

  Future<int> idOf(String key) async =>
      (await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [key])).first['id']! as int;

  Future<int> insertTx(String source, int cls, String code, {int? cost}) => db.insert('transactions', {
        'display_code': code,
        'source_type': source,
        'amount_cents': 500,
        'transaction_cost_cents': cost ?? 0,
        'classification_id': cls,
        'raw_parse_source': 'SMS_PARSE',
        'transaction_occurred_at': t0,
        'created_at': t0,
        if (source == 'SEND_MONEY') 'counterparty_label': 'Test Person',
        if (source == 'SEND_MONEY') 'counterparty_phone': '0700000001',
      });

  setUp(() async {
    db = await openTestDb();
    myself = await idOf(kAirtimeSeedMyself);
    other = await idOf(kAirtimeSeedOther);
    airtimeTx = await insertTx('AIRTIME', myself, 'AIR0000001');
  });
  tearDown(() => db.close());

  test('airtime_kind_trigger_blocks_move_myself_to_other', () async {
    await expectLater(
      db.update('transactions', {'classification_id': other}, where: 'id = ?', whereArgs: [airtimeTx]),
      throwsA(predicate((e) => '$e'.contains('airtime kind is locked'))),
    );
    expect((await db.query('transactions', where: 'id = ?', whereArgs: [airtimeTx])).single['classification_id'], myself);
  });

  test('airtime_kind_trigger_blocks_move_other_to_myself', () async {
    final inOther = await insertTx('AIRTIME', other, 'AIR0000002');
    await expectLater(
      db.update('transactions', {'classification_id': myself}, where: 'id = ?', whereArgs: [inOther]),
      throwsA(predicate((e) => '$e'.contains('airtime kind is locked'))),
    );
  });

  test('airtime_kind_trigger_allows_non_airtime_class_change', () async {
    final family = await idOf('SEND_MONEY:family_friends');
    final rent = await idOf('SEND_MONEY:rent');
    final sm = await insertTx('SEND_MONEY', family, 'SMX0000001', cost: 700);
    await db.update('transactions', {'classification_id': rent}, where: 'id = ?', whereArgs: [sm]);
    expect((await db.query('transactions', where: 'id = ?', whereArgs: [sm])).single['classification_id'], rent);
    // An airtime update that keeps its category is also fine.
    await db.update('transactions', {'classification_id': myself, 'amount_cents': 900}, where: 'id = ?', whereArgs: [airtimeTx]);
  });

  test('transaction_dao_update_airtime_category_change_throws_before_trigger', () async {
    await expectLater(
      TransactionDao.update(db,
          id: airtimeTx, amountCents: 500, transactionOccurredAt: t0, classificationId: other, transactionCostCents: 0),
      throwsA(isA<ArgumentError>()),
    );
    // Same category: the update goes through.
    await TransactionDao.update(db,
        id: airtimeTx, amountCents: 700, transactionOccurredAt: t0, classificationId: myself, transactionCostCents: 0);
    expect((await db.query('transactions', where: 'id = ?', whereArgs: [airtimeTx])).single['amount_cents'], 700);
  });

  test('an insert into either airtime category is allowed', () async {
    await insertTx('AIRTIME', other, 'AIR0000003');
    await insertTx('AIRTIME', myself, 'AIR0000004');
  });

  // Judge J-row17 data verdict, condition 1 / note (b): the kind-lock trigger keys on
  // NEW.source_type, so a type change must not open a path between the two kinds.
  Future<Map<String, Object?>> rowOf(int id) async =>
      (await db.query('transactions', where: 'id = ?', whereArgs: [id])).single;

  Future<int> plainSendMoney(int cls, String code) => db.insert('transactions', {
        'display_code': code,
        'source_type': 'SEND_MONEY',
        'amount_cents': 500,
        'transaction_cost_cents': 0,
        'classification_id': cls,
        'raw_parse_source': 'SMS_PARSE',
        'transaction_occurred_at': t0,
        'created_at': t0,
      });

  test('type_change_to_airtime_with_other_kind_category_is_blocked_by_kind_lock', () async {
    final family = await idOf('SEND_MONEY:family_friends');
    final sm = await plainSendMoney(family, 'SMT0000001');
    await expectLater(
      db.update('transactions', {'source_type': 'AIRTIME', 'classification_id': other}, where: 'id = ?', whereArgs: [sm]),
      throwsA(predicate((e) => '$e'.contains('airtime kind is locked'))),
    );
    final r = await rowOf(sm);
    expect(r['source_type'], 'SEND_MONEY');
    expect(r['classification_id'], family);
  });

  test('type_change_to_airtime_with_myself_category_is_also_blocked_pinned', () async {
    // Any classification change on a row whose NEW type is AIRTIME is refused,
    // including SEND_MONEY -> AIRTIME into For myself.
    final family = await idOf('SEND_MONEY:family_friends');
    final sm = await plainSendMoney(family, 'SMT0000002');
    await expectLater(
      db.update('transactions', {'source_type': 'AIRTIME', 'classification_id': myself}, where: 'id = ?', whereArgs: [sm]),
      throwsA(predicate((e) => '$e'.contains('airtime kind is locked'))),
    );
    expect((await rowOf(sm))['source_type'], 'SEND_MONEY');
  });

  test('type_change_away_from_airtime_with_new_group_category_outcome_pinned', () async {
    final family = await idOf('SEND_MONEY:family_friends');
    await db.update('transactions', {'source_type': 'SEND_MONEY', 'classification_id': family},
        where: 'id = ?', whereArgs: [airtimeTx]);
    final r = await rowOf(airtimeTx);
    // Pinned: the DB allows it (our trigger keys on NEW.source_type; the scope trigger is satisfied).
    expect(r['source_type'], 'SEND_MONEY');
    expect(r['classification_id'], family);
  });

  test('type_change_away_from_airtime_keeping_airtime_group_category_is_refused_by_scope_trigger', () async {
    for (final cls in [myself, other]) {
      await expectLater(
        db.update('transactions', {'source_type': 'SEND_MONEY', 'classification_id': cls},
            where: 'id = ?', whereArgs: [airtimeTx]),
        throwsA(predicate((e) => '$e'.contains('does not belong to the group matching source_type'))),
      );
    }
    final r = await rowOf(airtimeTx);
    expect(r['source_type'], 'AIRTIME');
    expect(r['classification_id'], myself);
  });

  test('type_change_alone_away_from_airtime_without_new_category_is_refused_pinned', () async {
    await expectLater(
      db.update('transactions', {'source_type': 'SEND_MONEY'}, where: 'id = ?', whereArgs: [airtimeTx]),
      throwsA(predicate((e) => '$e'.contains('does not belong to the group matching source_type'))),
    );
    expect((await rowOf(airtimeTx))['source_type'], 'AIRTIME');
  });
}
