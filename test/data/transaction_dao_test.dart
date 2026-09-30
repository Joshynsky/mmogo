// Integration tests for lib/data/db/transaction_dao.dart against a real
// in-memory sqlite3 database (same sqflite_common_ffi backend
// test/data/schema_test.dart/classification_dao_test.dart use) — no mocked
// SQL. This is the first test suite to ever write a real row into
// `transactions`: proves the two representative field-sets this dispatch's
// brief names (one Cash-shaped, one SMS-parsed-M-Pesa-shaped) round-trip
// every column correctly, including the NOT NULL/CHECK-constrained columns
// the schema defines, and that the real group-scope guard triggers
// (T1) are actually exercised (not bypassed) by a genuine insert.
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/data/db/schema.dart';
import 'package:mpesa_tracker/data/db/transaction_dao.dart';
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

Future<Map<String, Object?>> _readBack(Database db, int id) async {
  final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
  return rows.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransactionDao.insert — Cash-shaped field-set', () {
    test('round-trips every column correctly, incl. the CASH-specific NULLs', () async {
      final db = await _openFreshDb();
      // Cash may reference any *enabled* group's classification — pick a
      // real seeded Send Money one, exercising the trigger's CASH branch.
      final classificationId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Transport');
      final occurredAt = DateTime(2026, 9, 18, 14, 30).millisecondsSinceEpoch;

      final input = NewTransactionInput(
        displayCode: 'CASH-20260918-1430',
        sourceType: 'CASH',
        amountCents: 50000,
        transactionCostCents: null,
        counterpartyLabel: null,
        counterpartyPhone: null,
        paybillAccountNumber: null,
        classificationId: classificationId,
        rawParseSource: 'MANUAL',
        transactionOccurredAt: occurredAt,
      );

      final id = await TransactionDao.insert(db, input);
      expect(id, greaterThan(0));

      final row = await _readBack(db, id);
      expect(row['display_code'], 'CASH-20260918-1430');
      expect(row['source_type'], 'CASH');
      expect(row['amount_cents'], 50000);
      expect(row['transaction_cost_cents'], isNull);
      expect(row['counterparty_label'], isNull);
      expect(row['counterparty_phone'], isNull);
      expect(row['paybill_account_number'], isNull);
      expect(row['classification_id'], classificationId);
      expect(row['raw_parse_source'], 'MANUAL');
      expect(row['transaction_occurred_at'], occurredAt);
      expect(row['deleted_at'], isNull);
      expect(row['created_at'], isNotNull);
      await db.close();
    });
  });

  group('TransactionDao.insert — SMS-parsed-M-Pesa-shaped field-set (Send Money)', () {
    test('round-trips every column correctly, incl. counterparty_phone and no paybill account', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Family/Friends');
      final occurredAt = DateTime(2026, 9, 17, 14, 15).millisecondsSinceEpoch;

      final input = NewTransactionInput(
        displayCode: 'THA7K2P9QX',
        sourceType: 'SEND_MONEY',
        amountCents: 150000,
        transactionCostCents: 2200,
        counterpartyLabel: 'JOHN KAMAU',
        counterpartyPhone: '0798630424',
        paybillAccountNumber: null,
        classificationId: classificationId,
        rawParseSource: 'SMS_PARSE',
        transactionOccurredAt: occurredAt,
      );

      final id = await TransactionDao.insert(db, input);
      expect(id, greaterThan(0));

      final row = await _readBack(db, id);
      expect(row['display_code'], 'THA7K2P9QX');
      expect(row['source_type'], 'SEND_MONEY');
      expect(row['amount_cents'], 150000);
      expect(row['transaction_cost_cents'], 2200);
      expect(row['counterparty_label'], 'JOHN KAMAU');
      expect(row['counterparty_phone'], '0798630424');
      expect(row['paybill_account_number'], isNull);
      expect(row['classification_id'], classificationId);
      expect(row['raw_parse_source'], 'SMS_PARSE');
      expect(row['transaction_occurred_at'], occurredAt);
      expect(row['deleted_at'], isNull);
      await db.close();
    });
  });

  group('TransactionDao.insert — real constraint enforcement, not pre-validated in Dart', () {
    test(
      'inserting a non-cash transaction whose classification belongs to a mismatched group '
      'throws a real DatabaseException (group-scope guard trigger), not a silent success',
      () async {
        final db = await _openFreshDb();
        // "Rent Payment" only exists under PAYBILL/BUY_GOODS, not SEND_MONEY.
        final paybillClassificationId = await _classificationId(
          db,
          groupCode: 'PAYBILL',
          name: 'Rent Payment',
        );

        final input = NewTransactionInput(
          displayCode: 'THA7K2P9QX',
          sourceType: 'SEND_MONEY',
          amountCents: 100000,
          transactionCostCents: 1000,
          counterpartyLabel: 'JANE DOE',
          counterpartyPhone: '0700000000',
          paybillAccountNumber: null,
          classificationId: paybillClassificationId,
          rawParseSource: 'SMS_PARSE',
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
        );

        await expectLater(
          () => TransactionDao.insert(db, input),
          throwsA(isA<DatabaseException>()),
        );
        final rows = await db.query('transactions');
        expect(rows, isEmpty);
        await db.close();
      },
    );

    test(
      'inserting a CASH transaction referencing a disabled group (Pochi) throws a real '
      'DatabaseException — the guard trigger\'s CASH/enabled branch',
      () async {
        final db = await _openFreshDb();
        // Pochi has no seeded classifications this round, so
        // insert one directly to exercise the disabled-group branch.
        final pochiGroupId = (await db.query(
          'classification_groups',
          where: 'code = ?',
          whereArgs: ['POCHI_LA_BIASHARA'],
        )).first['id'] as int;
        final pochiClassificationId = await db.insert('classifications', {
          'group_id': pochiGroupId,
          'name': 'Test Pochi Classification',
          'active': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });

        final input = NewTransactionInput(
          displayCode: 'CASH-20260918-0900',
          sourceType: 'CASH',
          amountCents: 20000,
          transactionCostCents: null,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: pochiClassificationId,
          rawParseSource: 'MANUAL',
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
        );

        await expectLater(
          () => TransactionDao.insert(db, input),
          throwsA(isA<DatabaseException>()),
        );
        await db.close();
      },
    );

    test(
      'inserting a second non-Cash transaction with a display_code already recorded throws a real '
      'DatabaseException (D5 unique index), not a swallowed/handled error',
      () async {
        final db = await _openFreshDb();
        final classificationId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Rent');
        final input = NewTransactionInput(
          displayCode: 'THA7K2P9QX',
          sourceType: 'SEND_MONEY',
          amountCents: 100000,
          transactionCostCents: 1000,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: classificationId,
          rawParseSource: 'MANUAL',
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
        );
        await TransactionDao.insert(db, input);

        await expectLater(
          () => TransactionDao.insert(db, input),
          throwsA(isA<DatabaseException>()),
        );
        await db.close();
      },
    );
  });

  group('TransactionDao.mpesaCodeExists — D5', () {
    test('false for a code never recorded', () async {
      final db = await _openFreshDb();
      expect(await TransactionDao.mpesaCodeExists(db, code: 'THA7K2P9QX'), isFalse);
      await db.close();
    });

    test('true once a non-Cash row with that code has been inserted', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, groupCode: 'PAYBILL', name: 'Shopping');
      await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'TGB1234567',
          sourceType: 'PAYBILL',
          amountCents: 200000,
          transactionCostCents: 0,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: classificationId,
          rawParseSource: 'MANUAL',
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      expect(await TransactionDao.mpesaCodeExists(db, code: 'TGB1234567'), isTrue);
      await db.close();
    });

    test('false for a CASH code, even if it matches an existing Cash row (CASH is exempt)', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Transport');
      await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'CASH-20260919-1430',
          sourceType: 'CASH',
          amountCents: 50000,
          transactionCostCents: null,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: classificationId,
          rawParseSource: 'MANUAL',
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      expect(await TransactionDao.mpesaCodeExists(db, code: 'CASH-20260919-1430'), isFalse);
      await db.close();
    });

    test('false once the recorded row is soft-deleted (deleted rows free their code)', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Rent');
      final id = await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'THA7K2P9QX',
          sourceType: 'SEND_MONEY',
          amountCents: 100000,
          transactionCostCents: 1000,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: classificationId,
          rawParseSource: 'MANUAL',
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await db.update(
        'transactions',
        {'deleted_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(await TransactionDao.mpesaCodeExists(db, code: 'THA7K2P9QX'), isFalse);
      await db.close();
    });
  });

  group('TransactionDao.update — T13 Analytics edit', () {
    test('non-Cash (SEND_MONEY): amount/date/classification/label/phone/cost all round-trip', () async {
      final db = await _openFreshDb();
      final originalClassId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Family/Friends');
      final newClassId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Rent');
      final id = await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'THA7K2P9QX',
          sourceType: 'SEND_MONEY',
          amountCents: 150000,
          transactionCostCents: 2200,
          counterpartyLabel: 'JOHN KAMAU',
          counterpartyPhone: '0798630424',
          paybillAccountNumber: null,
          classificationId: originalClassId,
          rawParseSource: 'SMS_PARSE',
          transactionOccurredAt: DateTime(2026, 9, 17, 14, 15).millisecondsSinceEpoch,
        ),
      );

      final newOccurredAt = DateTime(2026, 9, 18, 9, 0).millisecondsSinceEpoch;
      await TransactionDao.update(
        db,
        id: id,
        amountCents: 175000,
        transactionOccurredAt: newOccurredAt,
        classificationId: newClassId,
        counterpartyLabel: 'JOHN K. KAMAU',
        counterpartyPhone: '0711222333',
        transactionCostCents: 2500,
      );

      final row = await _readBack(db, id);
      expect(row['amount_cents'], 175000);
      expect(row['transaction_occurred_at'], newOccurredAt);
      expect(row['classification_id'], newClassId);
      expect(row['counterparty_label'], 'JOHN K. KAMAU');
      expect(row['counterparty_phone'], '0711222333');
      expect(row['transaction_cost_cents'], 2500);
      // Untouched, not-editable columns stay exactly as inserted.
      expect(row['display_code'], 'THA7K2P9QX');
      expect(row['source_type'], 'SEND_MONEY');
      expect(row['raw_parse_source'], 'SMS_PARSE');
      expect(row['paybill_account_number'], isNull);
      await db.close();
    });

    test('PAYBILL: writes paybill_account_number, never touches counterparty_phone', () async {
      final db = await _openFreshDb();
      final classId = await _classificationId(db, groupCode: 'PAYBILL', name: 'Shopping');
      final id = await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'THC9L4K7TV',
          sourceType: 'PAYBILL',
          amountCents: 350000,
          transactionCostCents: 3300,
          counterpartyLabel: 'DSTV KENYA',
          counterpartyPhone: null,
          paybillAccountNumber: '9988771',
          classificationId: classId,
          rawParseSource: 'SMS_PARSE',
          transactionOccurredAt: DateTime(2026, 9, 15).millisecondsSinceEpoch,
        ),
      );

      await TransactionDao.update(
        db,
        id: id,
        amountCents: 360000,
        transactionOccurredAt: DateTime(2026, 9, 16).millisecondsSinceEpoch,
        classificationId: classId,
        counterpartyLabel: 'DSTV KENYA LTD',
        paybillAccountNumber: '1122334',
        transactionCostCents: 3400,
      );

      final row = await _readBack(db, id);
      expect(row['paybill_account_number'], '1122334');
      expect(row['counterparty_phone'], isNull);
      expect(row['counterparty_label'], 'DSTV KENYA LTD');
      await db.close();
    });

    test('CASH: only amount/date/classification are touched — cost/label/phone/account stay NULL', () async {
      final db = await _openFreshDb();
      final originalClassId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Transport');
      final newClassId = await _classificationId(db, groupCode: 'PAYBILL', name: 'Groceries');
      final id = await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'CASH-20260918-1430',
          sourceType: 'CASH',
          amountCents: 50000,
          transactionCostCents: null,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: originalClassId,
          rawParseSource: 'MANUAL',
          transactionOccurredAt: DateTime(2026, 9, 18, 14, 30).millisecondsSinceEpoch,
        ),
      );

      await TransactionDao.update(
        db,
        id: id,
        amountCents: 60000,
        transactionOccurredAt: DateTime(2026, 9, 19, 8, 0).millisecondsSinceEpoch,
        classificationId: newClassId,
      );

      final row = await _readBack(db, id);
      expect(row['amount_cents'], 60000);
      expect(row['classification_id'], newClassId);
      expect(row['transaction_cost_cents'], isNull);
      expect(row['counterparty_label'], isNull);
      expect(row['counterparty_phone'], isNull);
      expect(row['paybill_account_number'], isNull);
      expect(row['source_type'], 'CASH');
      expect(row['display_code'], 'CASH-20260918-1430');
      await db.close();
    });

    test(
      'a mismatched-group classification re-pick throws a real DatabaseException '
      '(group-scope guard trigger, UPDATE branch) — the row is left unchanged',
      () async {
        final db = await _openFreshDb();
        final classId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Rent');
        final mismatchedClassId = await _classificationId(db, groupCode: 'PAYBILL', name: 'Rent Payment');
        final id = await TransactionDao.insert(
          db,
          NewTransactionInput(
            displayCode: 'THD2Q6W1XY',
            sourceType: 'SEND_MONEY',
            amountCents: 200000,
            transactionCostCents: 2500,
            counterpartyLabel: null,
            counterpartyPhone: null,
            paybillAccountNumber: null,
            classificationId: classId,
            rawParseSource: 'SMS_PARSE',
            transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        await expectLater(
          () => TransactionDao.update(
            db,
            id: id,
            amountCents: 200000,
            transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
            classificationId: mismatchedClassId,
          ),
          throwsA(isA<DatabaseException>()),
        );
        final row = await _readBack(db, id);
        expect(row['classification_id'], classId); // unchanged
        await db.close();
      },
    );

    test(
      'a paired-optionality CHECK violation (label set, phone left null on a SEND_MONEY row) '
      'surfaces as a real DatabaseException, not swallowed',
      () async {
        final db = await _openFreshDb();
        final classId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Transport');
        // Originally no identity captured at all (both NULL) — a legitimate,
        // schema-valid starting state (opt-in capture, T6).
        final id = await TransactionDao.insert(
          db,
          NewTransactionInput(
            displayCode: 'THG3H8J5KL',
            sourceType: 'SEND_MONEY',
            amountCents: 75000,
            transactionCostCents: 1500,
            counterpartyLabel: null,
            counterpartyPhone: null,
            paybillAccountNumber: null,
            classificationId: classId,
            rawParseSource: 'SMS_PARSE',
            transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        await expectLater(
          () => TransactionDao.update(
            db,
            id: id,
            amountCents: 75000,
            transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
            classificationId: classId,
            counterpartyLabel: 'NEW LABEL', // set...
            counterpartyPhone: null, // ...but phone left null: paired CHECK violation
            transactionCostCents: 1500,
          ),
          throwsA(isA<DatabaseException>()),
        );
        await db.close();
      },
    );

    test('updating a non-existent id throws (defensive pre-read guard, not a silent no-op)', () async {
      final db = await _openFreshDb();
      await expectLater(
        () => TransactionDao.update(
          db,
          id: 999999,
          amountCents: 1000,
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
          classificationId: 1,
        ),
        throwsA(isA<StateError>()),
      );
      await db.close();
    });
  });

  group('TransactionDao.softDelete / restore — T13', () {
    test('softDelete stamps deleted_at (non-null, epoch millis); restore clears it back to NULL', () async {
      final db = await _openFreshDb();
      final classId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Rent');
      final id = await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'THE5R8T3UV',
          sourceType: 'SEND_MONEY',
          amountCents: 64000,
          transactionCostCents: 0,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: classId,
          rawParseSource: 'SMS_PARSE',
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      var row = await _readBack(db, id);
      expect(row['deleted_at'], isNull);

      final before = DateTime.now().millisecondsSinceEpoch;
      await TransactionDao.softDelete(db, id: id);
      row = await _readBack(db, id);
      expect(row['deleted_at'], isNotNull);
      expect(row['deleted_at'] as int, greaterThanOrEqualTo(before));

      await TransactionDao.restore(db, id: id);
      row = await _readBack(db, id);
      expect(row['deleted_at'], isNull);
      await db.close();
    });

    test('a soft-deleted row is excluded from a deleted_at IS NULL read (every other read in this codebase)', () async {
      final db = await _openFreshDb();
      final classId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Rent');
      final id = await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'THF1S4D7GH',
          sourceType: 'SEND_MONEY',
          amountCents: 120000,
          transactionCostCents: 1500,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: classId,
          rawParseSource: 'SMS_PARSE',
          transactionOccurredAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await TransactionDao.softDelete(db, id: id);

      final visible = await db.query('transactions', where: 'deleted_at IS NULL AND id = ?', whereArgs: [id]);
      expect(visible, isEmpty);
      await db.close();
    });
  });

  group('TransactionDao.purgeExpiredSoftDeletes — T13', () {
    test('hard-deletes only rows soft-deleted more than 1 hour ago; returns the count purged', () async {
      final db = await _openFreshDb();
      final classId = await _classificationId(db, groupCode: 'SEND_MONEY', name: 'Rent');
      final now = DateTime.now().millisecondsSinceEpoch;

      Future<int> insertAt(int deletedAt) async {
        final id = await TransactionDao.insert(
          db,
          NewTransactionInput(
            displayCode: 'CASH-${deletedAt}test',
            sourceType: 'CASH',
            amountCents: 10000,
            transactionCostCents: null,
            counterpartyLabel: null,
            counterpartyPhone: null,
            paybillAccountNumber: null,
            classificationId: classId,
            rawParseSource: 'MANUAL',
            transactionOccurredAt: now,
          ),
        );
        await db.update('transactions', {'deleted_at': deletedAt}, where: 'id = ?', whereArgs: [id]);
        return id;
      }

      final expiredId = await insertAt(now - 3700000); // 1h 1m40s ago -> expired
      final freshId = await insertAt(now - 60000); // 1 minute ago -> still in grace window
      final neverDeletedId = await TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'THG3H8J5KL',
          sourceType: 'SEND_MONEY',
          amountCents: 20000,
          transactionCostCents: 500,
          counterpartyLabel: null,
          counterpartyPhone: null,
          paybillAccountNumber: null,
          classificationId: classId,
          rawParseSource: 'SMS_PARSE',
          transactionOccurredAt: now,
        ),
      );

      final purgedCount = await TransactionDao.purgeExpiredSoftDeletes(db);
      expect(purgedCount, 1);

      final remaining = await db.query('transactions');
      final remainingIds = remaining.map((r) => r['id'] as int).toSet();
      expect(remainingIds.contains(expiredId), isFalse);
      expect(remainingIds.contains(freshId), isTrue);
      expect(remainingIds.contains(neverDeletedId), isTrue);
      await db.close();
    });

    test('a second sweep with nothing newly expired purges 0 rows', () async {
      final db = await _openFreshDb();
      final purgedCount = await TransactionDao.purgeExpiredSoftDeletes(db);
      expect(purgedCount, 0);
      await db.close();
    });
  });
}
