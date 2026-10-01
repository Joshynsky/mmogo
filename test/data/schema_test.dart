// Unit tests for the T1 schema/seed data (lib/data/db/schema.dart).
//
// Runs against a real in-memory SQLite database via sqflite_common_ffi
// (the same desktop FFI backend AppDatabase uses on Windows/Linux) — no
// mocking of SQL semantics; these are real CREATE TABLE/TRIGGER
// statements executed by real sqlite3, exercised exactly like the
// on-device schema would be.
//
// Covers the T1 slice's required correctness checks:
//   - seed data loads correctly (4 groups, 12 classifications, correct
//     enabled/group scoping)
//   - the two group-scope guard triggers reject a mismatched insert and
//     accept a valid one, for both the CASH-cross-group branch and the
//     non-CASH same-group branch, on both INSERT and UPDATE
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/schema.dart';
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

Future<int> _classificationId(Database db, String groupCode, String name) async {
  final rows = await db.rawQuery(
    '''
    SELECT c.id FROM classifications c
    JOIN classification_groups g ON g.id = c.group_id
    WHERE g.code = ? AND c.name = ?
    ''',
    [groupCode, name],
  );
  expect(rows, hasLength(1), reason: 'expected exactly one $groupCode/$name row');
  return rows.first['id'] as int;
}

Map<String, Object?> _baseTransaction({
  required String sourceType,
  required int classificationId,
  int amountCents = 10000,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return {
    'display_code': 'TEST-CODE',
    'source_type': sourceType,
    'amount_cents': amountCents,
    'transaction_cost_cents': sourceType == 'CASH' ? null : 500,
    'counterparty_label': sourceType == 'CASH' ? null : 'Test Counterparty',
    'counterparty_phone': sourceType == 'SEND_MONEY' ? '0700000000' : null,
    'paybill_account_number': sourceType == 'PAYBILL' ? '12345' : null,
    'classification_id': classificationId,
    'raw_parse_source': sourceType == 'CASH' ? 'MANUAL' : 'MANUAL',
    'transaction_occurred_at': now,
    'created_at': now,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('seed data', () {
    test('classification_groups has exactly 4 rows with correct enabled flags', () async {
      final db = await _openFreshDb();
      final rows = await db.query('classification_groups', orderBy: 'id');
      expect(rows, hasLength(4));

      final byCode = {for (final r in rows) r['code'] as String: r};
      expect(byCode['SEND_MONEY']!['enabled'], 1);
      expect(byCode['PAYBILL']!['enabled'], 1);
      expect(byCode['BUY_GOODS']!['enabled'], 1);
      expect(byCode['POCHI_LA_BIASHARA']!['enabled'], 0);

      await db.close();
    });

    test('classifications has exactly 12 rows, group-scoped correctly', () async {
      final db = await _openFreshDb();
      final rows = await db.rawQuery('''
        SELECT g.code AS group_code, c.name AS name
        FROM classifications c
        JOIN classification_groups g ON g.id = c.group_id
      ''');
      expect(rows, hasLength(12));

      final byGroup = <String, List<String>>{};
      for (final r in rows) {
        byGroup.putIfAbsent(r['group_code'] as String, () => []).add(r['name'] as String);
      }
      expect(byGroup['SEND_MONEY']!..sort(), ['Family/Friends', 'Groceries', 'Rent', 'Transport']);
      expect(byGroup['PAYBILL']!..sort(), ['Groceries', 'Rent Payment', 'Shopping', 'Transport']);
      expect(byGroup['BUY_GOODS']!..sort(), ['Groceries', 'Rent Payment', 'Shopping', 'Transport']);
      expect(byGroup.containsKey('POCHI_LA_BIASHARA'), isFalse);

      await db.close();
    });

    test('per-group uniqueness: same name in two different groups is allowed', () async {
      final db = await _openFreshDb();
      // "Transport" exists once under SEND_MONEY, once under PAYBILL, once
      // under BUY_GOODS — three active rows, not a collision.
      final rows = await db.query('classifications', where: 'name = ?', whereArgs: ['Transport']);
      expect(rows, hasLength(3));
      await db.close();
    });

    test('per-group uniqueness index rejects a duplicate active name within the same group', () async {
      final db = await _openFreshDb();
      final sendMoneyGroupId = (await db.query(
        'classification_groups',
        where: 'code = ?',
        whereArgs: ['SEND_MONEY'],
      )).first['id'] as int;

      // "Rent" already exists, active, under SEND_MONEY.
      expect(
        () => db.insert('classifications', {
          'group_id': sendMoneyGroupId,
          'name': 'Rent',
          'active': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('counterparty_classification_map is empty at seed', () async {
      final db = await _openFreshDb();
      final rows = await db.query('counterparty_classification_map');
      expect(rows, isEmpty);
      await db.close();
    });
  });

  group('group-scope guard trigger — INSERT', () {
    test('rejects a SEND_MONEY transaction referencing a Paybill-group classification', () async {
      final db = await _openFreshDb();
      final paybillClassificationId = await _classificationId(db, 'PAYBILL', 'Shopping');

      expect(
        () => db.insert(
          'transactions',
          _baseTransaction(sourceType: 'SEND_MONEY', classificationId: paybillClassificationId),
        ),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.toString(),
            'message',
            contains('does not belong to the group matching source_type'),
          ),
        ),
      );
      await db.close();
    });

    test('rejects a CASH transaction referencing a disabled-group (Pochi) classification', () async {
      final db = await _openFreshDb();
      final pochiGroupId = (await db.query(
        'classification_groups',
        where: 'code = ?',
        whereArgs: ['POCHI_LA_BIASHARA'],
      )).first['id'] as int;

      // Pochi has no seeded classifications (no default set is
      // defined this round) — insert one directly to exercise the
      // disabled-group branch of the trigger, exactly as a future Pochi
      // classification would if the group were ever enabled.
      final pochiClassificationId = await db.insert('classifications', {
        'group_id': pochiGroupId,
        'name': 'Test Pochi Classification',
        'active': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      expect(
        () => db.insert(
          'transactions',
          _baseTransaction(sourceType: 'CASH', classificationId: pochiClassificationId),
        ),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.toString(),
            'message',
            contains('belongs to a disabled group'),
          ),
        ),
      );
      await db.close();
    });

    test('accepts a valid SEND_MONEY transaction referencing a Send-Money-group classification', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');

      final id = await db.insert(
        'transactions',
        _baseTransaction(sourceType: 'SEND_MONEY', classificationId: classificationId),
      );
      expect(id, greaterThan(0));

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows, hasLength(1));
      await db.close();
    });

    test('accepts a valid CASH transaction referencing any enabled group (cross-group freedom)', () async {
      final db = await _openFreshDb();
      // Cash may draw from any *enabled* group's classification — here, a
      // Buy Goods classification, which is not a CASH-typed group at all.
      final classificationId = await _classificationId(db, 'BUY_GOODS', 'Shopping');

      final id = await db.insert(
        'transactions',
        _baseTransaction(sourceType: 'CASH', classificationId: classificationId),
      );
      expect(id, greaterThan(0));
      await db.close();
    });
  });

  group('group-scope guard trigger — UPDATE', () {
    test('rejects updating classification_id to one outside the current source_type group', () async {
      final db = await _openFreshDb();
      final sendMoneyClassificationId = await _classificationId(db, 'SEND_MONEY', 'Rent');
      final paybillClassificationId = await _classificationId(db, 'PAYBILL', 'Rent Payment');

      final id = await db.insert(
        'transactions',
        _baseTransaction(sourceType: 'SEND_MONEY', classificationId: sendMoneyClassificationId),
      );

      expect(
        () => db.update(
          'transactions',
          {'classification_id': paybillClassificationId},
          where: 'id = ?',
          whereArgs: [id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('accepts updating classification_id to a valid same-group classification', () async {
      final db = await _openFreshDb();
      final rentId = await _classificationId(db, 'SEND_MONEY', 'Rent');
      final familyFriendsId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');

      final id = await db.insert(
        'transactions',
        _baseTransaction(sourceType: 'SEND_MONEY', classificationId: rentId),
      );

      final updated = await db.update(
        'transactions',
        {'classification_id': familyFriendsId},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(updated, 1);
      await db.close();
    });
  });

  group('identity-capture CHECK constraints — T6 amendment (opt-in Send Money/Paybill identity)', () {
    test('accepts a SEND_MONEY row with genuinely NULL counterparty_label/phone (opted out)', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'SEND_MONEY', 'Transport');

      final id = await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'SEND_MONEY', classificationId: classificationId),
        'counterparty_label': null,
        'counterparty_phone': null,
      });
      expect(id, greaterThan(0));
      final row = (await db.query('transactions', where: 'id = ?', whereArgs: [id])).first;
      expect(row['counterparty_label'], isNull);
      expect(row['counterparty_phone'], isNull);
      await db.close();
    });

    test('accepts a PAYBILL row with genuinely NULL counterparty_label/paybill_account_number (opted out)', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'PAYBILL', 'Shopping');

      final id = await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'PAYBILL', classificationId: classificationId),
        'counterparty_label': null,
        'paybill_account_number': null,
      });
      expect(id, greaterThan(0));
      final row = (await db.query('transactions', where: 'id = ?', whereArgs: [id])).first;
      expect(row['counterparty_label'], isNull);
      expect(row['paybill_account_number'], isNull);
      await db.close();
    });

    test('D6: now ACCEPTS a BUY_GOODS row with a NULL counterparty_label (label is optional, per the '
        'T6 return-pass-2 PM decision superseding the earlier Buy-Goods-always-captures-merchant rule)',
        () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'BUY_GOODS', 'Shopping');

      final id = await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'BUY_GOODS', classificationId: classificationId),
        'counterparty_label': null,
      });
      expect(id, greaterThan(0));
      final row = (await db.query('transactions', where: 'id = ?', whereArgs: [id])).first;
      expect(row['counterparty_label'], isNull);
      await db.close();
    });

    test('rejects a SEND_MONEY row with label captured but phone left NULL (paired-optionality CHECK)', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'SEND_MONEY', 'Transport');

      expect(
        () => db.insert('transactions', {
          ..._baseTransaction(sourceType: 'SEND_MONEY', classificationId: classificationId),
          'counterparty_label': 'JOHN KAMAU',
          'counterparty_phone': null,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('rejects a PAYBILL row with label captured but account left NULL (paired-optionality CHECK)', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'PAYBILL', 'Shopping');

      expect(
        () => db.insert('transactions', {
          ..._baseTransaction(sourceType: 'PAYBILL', classificationId: classificationId),
          'counterparty_label': 'KPLC',
          'paybill_account_number': null,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });
  });

  group('D5: idx_transactions_mpesa_code — partial unique index on non-Cash, non-deleted display_code', () {
    test('rejects a second non-Cash row with the same display_code', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'SEND_MONEY', 'Rent');

      await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'SEND_MONEY', classificationId: classificationId),
        'display_code': 'THA7K2P9QX',
      });

      expect(
        () => db.insert('transactions', {
          ..._baseTransaction(sourceType: 'SEND_MONEY', classificationId: classificationId),
          'display_code': 'THA7K2P9QX',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('rejects a duplicate code across two DIFFERENT non-Cash source types (BUY_GOODS vs PAYBILL)', () async {
      final db = await _openFreshDb();
      final buyGoodsId = await _classificationId(db, 'BUY_GOODS', 'Shopping');
      final paybillId = await _classificationId(db, 'PAYBILL', 'Shopping');

      await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'BUY_GOODS', classificationId: buyGoodsId),
        'display_code': 'TGB1234567',
        'counterparty_label': 'Naivas',
      });

      expect(
        () => db.insert('transactions', {
          ..._baseTransaction(sourceType: 'PAYBILL', classificationId: paybillId),
          'display_code': 'TGB1234567',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    });

    test('allows two CASH rows sharing the same display_code (same-minute collision, expected/safe)', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'SEND_MONEY', 'Transport');

      final id1 = await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'CASH', classificationId: classificationId),
        'display_code': 'CASH-20260919-1430',
      });
      final id2 = await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'CASH', classificationId: classificationId),
        'display_code': 'CASH-20260919-1430',
      });
      expect(id1, isNot(id2));
      await db.close();
    });

    test('a soft-deleted row frees its code for reuse by a new non-Cash row', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'SEND_MONEY', 'Rent');

      final id1 = await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'SEND_MONEY', classificationId: classificationId),
        'display_code': 'THA7K2P9QX',
      });
      await db.update(
        'transactions',
        {'deleted_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id1],
      );

      final id2 = await db.insert('transactions', {
        ..._baseTransaction(sourceType: 'SEND_MONEY', classificationId: classificationId),
        'display_code': 'THA7K2P9QX',
      });
      expect(id2, greaterThan(0));
      await db.close();
    });
  });
}
