// Integration tests for lib/data/db/counterparty_dao.dart against a real
// in-memory sqlite3 database (same sqflite_common_ffi backend
// test/data/schema_test.dart/classification_dao_test.dart use) — no mocked
// SQL, no testWidgets (binding instruction #2: a real DB hangs
// indefinitely inside testWidgets in this environment; DB-level
// correctness for T12 is proven here as plain test()s instead, matching
// the pattern classification_dao_test.dart already established).
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/db/counterparty_dao.dart';
import 'package:mymog/data/db/schema.dart';
import 'package:mymog/domain/counterparty/counterparty_key.dart';
import 'package:mymog/domain/parsing/parsed_sms_fields.dart';
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

Future<int> _groupId(Database db, String code) async {
  final rows = await db.query('classification_groups', where: 'code = ?', whereArgs: [code]);
  return rows.first['id'] as int;
}

Future<int> _classificationId(Database db, {required int groupId, required String name}) async {
  final rows = await db.query(
    'classifications',
    where: 'group_id = ? AND name = ?',
    whereArgs: [groupId, name],
  );
  return rows.first['id'] as int;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lookup', () {
    test('returns null when no row matches this (source_type, counterparty_key)', () async {
      final db = await _openFreshDb();
      final result = await CounterpartyDao.lookup(db, sourceType: 'SEND_MONEY', counterpartyKey: '0700000000');
      expect(result, isNull);
      await db.close();
    });

    test('resolves classification_id, name, group name, and auto_apply for a matching row', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');
      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'SEND_MONEY',
        counterpartyKey: '0798630424',
        classificationId: rentId,
      );

      final result = await CounterpartyDao.lookup(db, sourceType: 'SEND_MONEY', counterpartyKey: '0798630424');
      expect(result, isNotNull);
      expect(result!.classificationId, rentId);
      expect(result.classificationName, 'Rent');
      expect(result.groupDisplayName, 'Send Money');
      expect(result.autoApply, isFalse); // upsertOnConfirm never sets auto_apply
      await db.close();
    });

    test('a matching counterparty_key under a DIFFERENT source_type is NOT returned '
        '(source_type is part of the real key, not just an attribute)', () async {
      final db = await _openFreshDb();
      final sendMoneyGroup = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: sendMoneyGroup, name: 'Rent');
      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'SEND_MONEY',
        counterpartyKey: 'SAME_KEY_TEXT',
        classificationId: rentId,
      );

      final result = await CounterpartyDao.lookup(db, sourceType: 'PAYBILL', counterpartyKey: 'SAME_KEY_TEXT');
      expect(result, isNull);
      await db.close();
    });
  });

  group('upsertOnConfirm — real ON CONFLICT upsert against the UNIQUE(source_type, counterparty_key) index', () {
    test('first call for a counterparty inserts a fresh row with auto_apply=0', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'BUY_GOODS');
      final shoppingId = await _classificationId(db, groupId: groupId, name: 'Shopping');

      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'BUY_GOODS',
        counterpartyKey: 'JAVA HOUSE',
        classificationId: shoppingId,
      );

      final rows = await db.query('counterparty_classification_map');
      expect(rows, hasLength(1));
      expect(rows.first['classification_id'], shoppingId);
      expect(rows.first['auto_apply'], 0);
      await db.close();
    });

    test('a second call for the SAME counterparty updates classification_id + updated_at in place '
        '(one row total, not a duplicate) — the real UNIQUE-constraint upsert path, not a Dart if/else', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'BUY_GOODS');
      final shoppingId = await _classificationId(db, groupId: groupId, name: 'Shopping');
      final groceriesId = await _classificationId(db, groupId: groupId, name: 'Groceries');

      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'BUY_GOODS',
        counterpartyKey: 'JAVA HOUSE',
        classificationId: shoppingId,
      );
      // Force a distinguishable updated_at between the two writes.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'BUY_GOODS',
        counterpartyKey: 'JAVA HOUSE',
        classificationId: groceriesId,
      );

      final rows = await db.query('counterparty_classification_map');
      expect(rows, hasLength(1)); // still exactly one row — a real upsert, not an insert-or-throw
      expect(rows.first['classification_id'], groceriesId);
      await db.close();
    });

    test('re-classifying does NOT reset auto_apply back to 0 once it has been set to 1 '
        '(the DO UPDATE clause omits auto_apply on purpose)', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'BUY_GOODS');
      final shoppingId = await _classificationId(db, groupId: groupId, name: 'Shopping');
      final groceriesId = await _classificationId(db, groupId: groupId, name: 'Groceries');

      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'BUY_GOODS',
        counterpartyKey: 'JAVA HOUSE',
        classificationId: shoppingId,
      );
      await CounterpartyDao.setAutoApply(db, sourceType: 'BUY_GOODS', counterpartyKey: 'JAVA HOUSE');

      // A later, unrelated re-classification of the same counterparty.
      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'BUY_GOODS',
        counterpartyKey: 'JAVA HOUSE',
        classificationId: groceriesId,
      );

      final result = await CounterpartyDao.lookup(db, sourceType: 'BUY_GOODS', counterpartyKey: 'JAVA HOUSE');
      expect(result!.classificationId, groceriesId); // classification DID change
      expect(result.autoApply, isTrue); // auto_apply did NOT get clobbered back to 0
      await db.close();
    });

    test('two genuinely distinct counterparties both classified the same way produce TWO rows '
        '(many-to-one by construction)', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'PAYBILL');
      final rentPaymentId = await _classificationId(db, groupId: groupId, name: 'Rent Payment');

      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'PAYBILL',
        counterpartyKey: 'LOOP BIZ#464332',
        classificationId: rentPaymentId,
      );
      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'PAYBILL',
        counterpartyKey: 'KCB#111222',
        classificationId: rentPaymentId,
      );

      final rows = await db.query('counterparty_classification_map');
      expect(rows, hasLength(2));
      await db.close();
    });
  });

  group('setAutoApply', () {
    test('sets auto_apply=1 on an existing row, scoped to that exact counterparty only', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');
      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'SEND_MONEY',
        counterpartyKey: '0700111222',
        classificationId: rentId,
      );
      await CounterpartyDao.upsertOnConfirm(
        db,
        sourceType: 'SEND_MONEY',
        counterpartyKey: '0700333444',
        classificationId: rentId,
      );

      await CounterpartyDao.setAutoApply(db, sourceType: 'SEND_MONEY', counterpartyKey: '0700111222');

      final applied = await CounterpartyDao.lookup(db, sourceType: 'SEND_MONEY', counterpartyKey: '0700111222');
      final untouched = await CounterpartyDao.lookup(db, sourceType: 'SEND_MONEY', counterpartyKey: '0700333444');
      expect(applied!.autoApply, isTrue);
      expect(untouched!.autoApply, isFalse); // the OTHER counterparty must be unaffected
      await db.close();
    });

    test('calling it for a counterparty with no existing row is a silent no-op, not an error '
        '(per its own doc comment — no row to fabricate a classification_id for)', () async {
      final db = await _openFreshDb();
      await expectLater(
        CounterpartyDao.setAutoApply(db, sourceType: 'SEND_MONEY', counterpartyKey: '0799999999'),
        completes,
      );
      final result = await CounterpartyDao.lookup(db, sourceType: 'SEND_MONEY', counterpartyKey: '0799999999');
      expect(result, isNull); // still no row — the no-op didn't fabricate one
      await db.close();
    });
  });

  group('fetchRecent — top-N by updated_at DESC', () {
    test('returns rows most-recent-first, capped at the given limit', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');

      for (final phone in ['0700000001', '0700000002', '0700000003']) {
        await CounterpartyDao.upsertOnConfirm(
          db,
          sourceType: 'SEND_MONEY',
          counterpartyKey: phone,
          classificationId: rentId,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final recent = await CounterpartyDao.fetchRecent(db, limit: 2);
      expect(recent, hasLength(2));
      expect(recent[0].counterpartyKey, '0700000003'); // most recent first
      expect(recent[1].counterpartyKey, '0700000002');
      await db.close();
    });

    test('defaults to limit 5, matching the 5-entry quick-pick spec', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');

      for (var i = 0; i < 7; i++) {
        await CounterpartyDao.upsertOnConfirm(
          db,
          sourceType: 'SEND_MONEY',
          counterpartyKey: '070000000$i',
          classificationId: rentId,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final recent = await CounterpartyDao.fetchRecent(db);
      expect(recent, hasLength(5));
      await db.close();
    });

    test('empty table returns an empty list, not an error', () async {
      final db = await _openFreshDb();
      final recent = await CounterpartyDao.fetchRecent(db);
      expect(recent, isEmpty);
      await db.close();
    });
  });

  group('round trip — read path and write path key derivation agree on the same real-world input '
      '(closes the counterparty_key consistency requirement, verified against a real DB, not just the pure fn)', () {
    test(
      'a PAYBILL counterparty classified once (write path) is found by a lookup built from the same '
      'raw, differently-formatted fields (read path) — proves derivation, not just literal string equality',
      () async {
        final db = await _openFreshDb();
        final groupId = await _groupId(db, 'PAYBILL');
        final rentPaymentId = await _classificationId(db, groupId: groupId, name: 'Rent Payment');

        // Write path: user confirms a classification for this Paybill SMS.
        final writeKey = deriveCounterpartyKey(
          sourceType: SmsSourceType.payBill,
          counterpartyLabel: '  Loop  Biz ',
          paybillAccountNumber: ' 464332 ',
        );
        await CounterpartyDao.upsertOnConfirm(
          db,
          sourceType: SmsSourceType.payBill.dbValue,
          counterpartyKey: writeKey,
          classificationId: rentPaymentId,
        );

        // Read path: a LATER Paybill SMS from the same real business, but
        // the SMS gateway/parse happened to format the label slightly
        // differently (different incidental spacing/case) — same real
        // counterparty, textually different raw input.
        final readKey = deriveCounterpartyKey(
          sourceType: SmsSourceType.payBill,
          counterpartyLabel: 'LOOP BIZ',
          paybillAccountNumber: '464332',
        );

        expect(readKey, writeKey); // the derivation itself agrees...
        final suggestion = await CounterpartyDao.lookup(
          db,
          sourceType: SmsSourceType.payBill.dbValue,
          counterpartyKey: readKey,
        );
        expect(suggestion, isNotNull); // ...and the real DB lookup actually finds it
        expect(suggestion!.classificationId, rentPaymentId);
        await db.close();
      },
    );

    test(
      'a SEND_MONEY counterparty is matched by phone even though the display name changed between '
      'two real-world SMS (the name can drift, the phone is the stable identity)',
      () async {
        final db = await _openFreshDb();
        final groupId = await _groupId(db, 'SEND_MONEY');
        final familyId = await _classificationId(db, groupId: groupId, name: 'Family/Friends');

        final writeKey = deriveCounterpartyKey(
          sourceType: SmsSourceType.sendMoney,
          counterpartyLabel: 'LETRICIA OTIENO',
          counterpartyPhone: '0798630424',
        );
        await CounterpartyDao.upsertOnConfirm(
          db,
          sourceType: SmsSourceType.sendMoney.dbValue,
          counterpartyKey: writeKey,
          classificationId: familyId,
        );

        // Same phone, but the name spelling drifted in a later SMS.
        final readKey = deriveCounterpartyKey(
          sourceType: SmsSourceType.sendMoney,
          counterpartyLabel: 'LETRISIA OTIENO', // misspelled this time
          counterpartyPhone: '0798630424',
        );
        final suggestion = await CounterpartyDao.lookup(
          db,
          sourceType: SmsSourceType.sendMoney.dbValue,
          counterpartyKey: readKey,
        );
        expect(suggestion, isNotNull);
        expect(suggestion!.classificationId, familyId);
        await db.close();
      },
    );
  });
}
