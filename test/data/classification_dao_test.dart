// Integration tests for lib/data/db/classification_dao.dart against a real
// in-memory sqlite3 database (same sqflite_common_ffi backend
// test/data/schema_test.dart/home_dashboard_dao_test.dart use) — no mocked
// SQL. Verifies the real per-group active-classification-list query and
// the real `idx_classifications_active_name` partial unique index
// (group_id, name) WHERE active = 1 constraint violation this dispatch's
// create-flow must surface, not pre-validate away in Dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/db/classification_dao.dart';
import 'package:mymog/data/db/schema.dart';
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

/// Inserts a real CASH transaction row referencing [classificationId] —
/// CASH is chosen because the group-scope guard trigger lets a cash
/// transaction reference any *enabled* group's classification (T1's
/// trigger), so this helper works regardless of which
/// seed group the test picks. [deletedAt] lets tests prove
/// `countTransactionsForClassification`'s `deleted_at IS NULL` filter.
Future<int> _insertCashTransaction(
  Database db, {
  required int classificationId,
  int? deletedAt,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return db.insert('transactions', {
    'display_code': 'CASH-20260101-0101',
    'source_type': 'CASH',
    'amount_cents': 1000,
    'transaction_cost_cents': null,
    'counterparty_label': null,
    'counterparty_phone': null,
    'paybill_account_number': null,
    'classification_id': classificationId,
    'raw_parse_source': 'MANUAL',
    'transaction_occurred_at': now,
    'created_at': now,
    'deleted_at': deletedAt,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fetchGroups', () {
    test('returns all 4 seeded groups, ordered by id, with correct enabled flags', () async {
      final db = await _openFreshDb();
      final groups = await ClassificationDao.fetchGroups(db);

      expect(groups, hasLength(4));
      expect(groups.map((g) => g.code), [
        'SEND_MONEY',
        'PAYBILL',
        'BUY_GOODS',
        'POCHI_LA_BIASHARA',
      ]);
      final byCode = {for (final g in groups) g.code: g};
      expect(byCode['SEND_MONEY']!.enabled, isTrue);
      expect(byCode['PAYBILL']!.enabled, isTrue);
      expect(byCode['BUY_GOODS']!.enabled, isTrue);
      // Pochi must still be RETURNED (not filtered out server-side) even
      // though disabled — it must always be visible, just
      // non-interactive; that's a UI concern, not a query-layer filter.
      expect(byCode['POCHI_LA_BIASHARA']!.enabled, isFalse);
      expect(byCode['POCHI_LA_BIASHARA']!.displayName, 'Pochi La Biashara');
      await db.close();
    });
  });

  group('fetchActiveClassifications — per-group active-classification-list', () {
    test('Send Money group returns exactly its 4 seeded active classifications', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final items = await ClassificationDao.fetchActiveClassifications(db, groupId: groupId);

      expect(items.map((c) => c.name).toList(), [
        'Family/Friends',
        'Groceries',
        'Rent',
        'Transport',
      ]);
      expect(items.every((c) => c.groupId == groupId), isTrue);
      await db.close();
    });

    test('Paybill and Buy Goods each return their own distinct 4-row set, not a merged list', () async {
      final db = await _openFreshDb();
      final paybillId = await _groupId(db, 'PAYBILL');
      final buyGoodsId = await _groupId(db, 'BUY_GOODS');

      final paybillItems = await ClassificationDao.fetchActiveClassifications(db, groupId: paybillId);
      final buyGoodsItems = await ClassificationDao.fetchActiveClassifications(db, groupId: buyGoodsId);

      expect(paybillItems.map((c) => c.name).toList(), [
        'Groceries',
        'Rent Payment',
        'Shopping',
        'Transport',
      ]);
      expect(buyGoodsItems.map((c) => c.name).toList(), [
        'Groceries',
        'Rent Payment',
        'Shopping',
        'Transport',
      ]);
      // Same names, but genuinely distinct rows (different ids) — group
      // scoping, not the same underlying classification shared visually.
      final paybillIds = paybillItems.map((c) => c.id).toSet();
      final buyGoodsIds = buyGoodsItems.map((c) => c.id).toSet();
      expect(paybillIds.intersection(buyGoodsIds), isEmpty);
      await db.close();
    });

    test('Pochi La Biashara group returns an empty list (no seeded classifications)', () async {
      final db = await _openFreshDb();
      final pochiId = await _groupId(db, 'POCHI_LA_BIASHARA');
      final items = await ClassificationDao.fetchActiveClassifications(db, groupId: pochiId);
      expect(items, isEmpty);
      await db.close();
    });

    test('a soft-deleted (active=0) classification is excluded from the list', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentRow = (await db.query(
        'classifications',
        where: 'group_id = ? AND name = ?',
        whereArgs: [groupId, 'Rent'],
      )).first;
      await db.update(
        'classifications',
        {'active': 0},
        where: 'id = ?',
        whereArgs: [rentRow['id']],
      );

      final items = await ClassificationDao.fetchActiveClassifications(db, groupId: groupId);
      expect(items.map((c) => c.name), isNot(contains('Rent')));
      expect(items, hasLength(3));
      await db.close();
    });
  });

  group('createClassification — real DB round-trip, no Dart-side pre-validation', () {
    test('inserts a new classification scoped to the given group', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');

      final id = await ClassificationDao.createClassification(db, groupId: groupId, name: 'Airtime');
      expect(id, greaterThan(0));

      final items = await ClassificationDao.fetchActiveClassifications(db, groupId: groupId);
      expect(items.map((c) => c.name), contains('Airtime'));
      await db.close();
    });

    test(
      'a duplicate active name in the same group throws a real DatabaseException '
      '(idx_classifications_active_name unique-constraint violation), not a simulated error',
      () async {
        final db = await _openFreshDb();
        final groupId = await _groupId(db, 'SEND_MONEY');

        // "Rent" already exists, active, under SEND_MONEY (T1 seed data) —
        // this is a genuine SQLite constraint violation, not a mocked
        // exception; asserted via isUniqueConstraintError(), the same real
        // API surface the widget's catch block checks.
        await expectLater(
          () => ClassificationDao.createClassification(db, groupId: groupId, name: 'Rent'),
          throwsA(isA<DatabaseException>().having(
            (e) => e.isUniqueConstraintError(),
            'isUniqueConstraintError()',
            isTrue,
          )),
        );
        await db.close();
      },
    );

    test('the same name IS allowed in a different group (per-group uniqueness, not global)', () async {
      final db = await _openFreshDb();
      final sendMoneyId = await _groupId(db, 'SEND_MONEY');
      final paybillId = await _groupId(db, 'PAYBILL');

      // "Airtime" doesn't exist yet in either group.
      await ClassificationDao.createClassification(db, groupId: sendMoneyId, name: 'Airtime');
      // Creating the identical name under a DIFFERENT group must succeed —
      // no cross-group collision.
      final id = await ClassificationDao.createClassification(db, groupId: paybillId, name: 'Airtime');
      expect(id, greaterThan(0));
      await db.close();
    });

    test(
      'a differently-cased name ("rent" vs seeded "Rent") is NOT rejected by the index '
      '— asserts the real BINARY-collation behavior, not an assumed case-insensitivity',
      () async {
        final db = await _openFreshDb();
        final groupId = await _groupId(db, 'SEND_MONEY');

        // SQLite's default UNIQUE index comparison is case-sensitive
        // (BINARY collation) unless the column/index specifies COLLATE
        // NOCASE — idx_classifications_active_name does
        // not specify a collation, so this insert must succeed. Verified
        // directly rather than assumed, per this project's own
        // citation-wording-verification doctrine.
        final id = await ClassificationDao.createClassification(db, groupId: groupId, name: 'rent');
        expect(id, greaterThan(0));
        await db.close();
      },
    );
  });

  // --- T8 additions: fetchInactive/rename/soft-delete/restore/count ------

  group('fetchInactiveClassifications', () {
    test('returns a soft-deleted classification, excludes active ones', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');
      await ClassificationDao.softDeleteClassification(db, id: rentId);

      final inactive = await ClassificationDao.fetchInactiveClassifications(db, groupId: groupId);
      expect(inactive.map((c) => c.name).toList(), ['Rent']);

      final active = await ClassificationDao.fetchActiveClassifications(db, groupId: groupId);
      expect(active.map((c) => c.name), isNot(contains('Rent')));
      await db.close();
    });

    test('empty group (Pochi, no seed rows) returns an empty inactive list', () async {
      final db = await _openFreshDb();
      final pochiId = await _groupId(db, 'POCHI_LA_BIASHARA');
      final inactive = await ClassificationDao.fetchInactiveClassifications(db, groupId: pochiId);
      expect(inactive, isEmpty);
      await db.close();
    });
  });

  group('renameClassification', () {
    test('updates the row name, reflected in the active list', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');

      await ClassificationDao.renameClassification(db, id: rentId, newName: 'Rent Payment (Cash)');

      final active = await ClassificationDao.fetchActiveClassifications(db, groupId: groupId);
      expect(active.map((c) => c.name), contains('Rent Payment (Cash)'));
      expect(active.map((c) => c.name), isNot(contains('Rent')));
      await db.close();
    });

    test(
      'renaming to a name already active in the same group throws a real unique-constraint '
      'DatabaseException',
      () async {
        final db = await _openFreshDb();
        final groupId = await _groupId(db, 'SEND_MONEY');
        final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');

        // "Transport" already exists active in this same group.
        await expectLater(
          () => ClassificationDao.renameClassification(db, id: rentId, newName: 'Transport'),
          throwsA(isA<DatabaseException>().having(
            (e) => e.isUniqueConstraintError(),
            'isUniqueConstraintError()',
            isTrue,
          )),
        );
        await db.close();
      },
    );
  });

  group('softDeleteClassification / restoreClassification round-trip', () {
    test('soft-delete moves a row from the active list to the inactive list', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');

      await ClassificationDao.softDeleteClassification(db, id: rentId);

      final active = await ClassificationDao.fetchActiveClassifications(db, groupId: groupId);
      final inactive = await ClassificationDao.fetchInactiveClassifications(db, groupId: groupId);
      expect(active.map((c) => c.name), isNot(contains('Rent')));
      expect(inactive.map((c) => c.name), contains('Rent'));
      await db.close();
    });

    test('restore moves a row back from the inactive list to the active list', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');
      await ClassificationDao.softDeleteClassification(db, id: rentId);

      await ClassificationDao.restoreClassification(db, id: rentId);

      final active = await ClassificationDao.fetchActiveClassifications(db, groupId: groupId);
      final inactive = await ClassificationDao.fetchInactiveClassifications(db, groupId: groupId);
      expect(active.map((c) => c.name), contains('Rent'));
      expect(inactive.map((c) => c.name), isNot(contains('Rent')));
      await db.close();
    });

    test(
      'restoring into a group that meanwhile gained a different active classification of the '
      'same name throws a real unique-constraint DatabaseException, not a silent overwrite',
      () async {
        final db = await _openFreshDb();
        final groupId = await _groupId(db, 'SEND_MONEY');
        final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');
        await ClassificationDao.softDeleteClassification(db, id: rentId);
        // A brand-new active "Rent" is created in the same group while the
        // old one sits soft-deleted.
        await ClassificationDao.createClassification(db, groupId: groupId, name: 'Rent');

        await expectLater(
          () => ClassificationDao.restoreClassification(db, id: rentId),
          throwsA(isA<DatabaseException>().having(
            (e) => e.isUniqueConstraintError(),
            'isUniqueConstraintError()',
            isTrue,
          )),
        );
        // The old row must remain inactive — the failed restore did not
        // silently leave it in an ambiguous state.
        final inactive = await ClassificationDao.fetchInactiveClassifications(db, groupId: groupId);
        expect(inactive.map((c) => c.id), contains(rentId));
        await db.close();
      },
    );
  });

  group('countTransactionsForClassification', () {
    test('returns 0 when no transactions reference the classification', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');

      final count = await ClassificationDao.countTransactionsForClassification(
        db,
        classificationId: rentId,
      );
      expect(count, 0);
      await db.close();
    });

    test('counts real transactions referencing the classification, excludes soft-deleted ones', () async {
      final db = await _openFreshDb();
      final groupId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: groupId, name: 'Rent');

      await _insertCashTransaction(db, classificationId: rentId);
      await _insertCashTransaction(db, classificationId: rentId);
      // A soft-deleted transaction referencing the same classification
      // must NOT inflate the count shown in the delete-confirmation
      // dialog (a soft-deleted transaction is excluded from
      // every total/aggregate immediately).
      await _insertCashTransaction(
        db,
        classificationId: rentId,
        deletedAt: DateTime.now().millisecondsSinceEpoch,
      );

      final count = await ClassificationDao.countTransactionsForClassification(
        db,
        classificationId: rentId,
      );
      expect(count, 2);
      await db.close();
    });
  });

  // --- T3 addition: fetchFlatActiveClassifications ------------------------

  group('fetchFlatActiveClassifications — Cash tab\'s flat, cross-group, deduplicated list', () {
    test(
      'deduplicates a name seeded under multiple enabled groups down to one row '
      '(T1 seed data already has "Transport"/"Groceries" under Send Money, Paybill, and Buy Goods)',
      () async {
        final db = await _openFreshDb();
        final items = await ClassificationDao.fetchFlatActiveClassifications(db);

        final names = items.map((c) => c.name).toList();
        // Exactly one "Transport" and one "Groceries", not three of each.
        expect(names.where((n) => n == 'Transport'), hasLength(1));
        expect(names.where((n) => n == 'Groceries'), hasLength(1));
        // Names unique to one group still appear exactly once.
        expect(names.where((n) => n == 'Family/Friends'), hasLength(1));
        expect(names.where((n) => n == 'Rent'), hasLength(1));
        expect(names.where((n) => n == 'Rent Payment'), hasLength(1));
        expect(names.where((n) => n == 'Shopping'), hasLength(1));
        await db.close();
      },
    );

    test(
      'a duplicate name is deduplicated case-insensitively, keeping the earliest-seeded '
      'group\'s row (deterministic tie-break, not an arbitrary pick)',
      () async {
        final db = await _openFreshDb();
        final sendMoneyId = await _groupId(db, 'SEND_MONEY');
        final transportId = await _classificationId(db, groupId: sendMoneyId, name: 'Transport');

        final items = await ClassificationDao.fetchFlatActiveClassifications(db);
        final transportItem = items.firstWhere((c) => c.name.toLowerCase() == 'transport');

        // Send Money's "Transport" (id lowest — seeded first, per schema.dart's
        // seed order) must be the row that survives dedup, not Paybill's or
        // Buy Goods' same-named copy.
        expect(transportItem.id, transportId);
        expect(transportItem.groupId, sendMoneyId);
        await db.close();
      },
    );

    test(
      'excludes classifications belonging to a disabled group (Pochi La Biashara), even when '
      'active — proving the enabled-groups-only filter, not just the default empty Pochi seed',
      () async {
        final db = await _openFreshDb();
        final pochiId = await _groupId(db, 'POCHI_LA_BIASHARA');
        // Pochi has no seeded classifications this round — insert one
        // directly (active=1) to prove exclusion is genuinely enforced by
        // the `g.enabled = 1` filter, not merely a byproduct of Pochi's
        // seed being empty.
        await db.insert('classifications', {
          'group_id': pochiId,
          'name': 'Pochi Test Classification',
          'active': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });

        final items = await ClassificationDao.fetchFlatActiveClassifications(db);
        expect(items.map((c) => c.name), isNot(contains('Pochi Test Classification')));
        await db.close();
      },
    );

    test('excludes soft-deleted (active=0) classifications from an enabled group', () async {
      final db = await _openFreshDb();
      final sendMoneyId = await _groupId(db, 'SEND_MONEY');
      final rentId = await _classificationId(db, groupId: sendMoneyId, name: 'Rent');
      await ClassificationDao.softDeleteClassification(db, id: rentId);

      final items = await ClassificationDao.fetchFlatActiveClassifications(db);
      expect(items.map((c) => c.name), isNot(contains('Rent')));
      await db.close();
    });

    test('final list is sorted alphabetically, case-insensitively, for display', () async {
      final db = await _openFreshDb();
      final items = await ClassificationDao.fetchFlatActiveClassifications(db);
      final names = items.map((c) => c.name.toLowerCase()).toList();
      final sorted = [...names]..sort();
      expect(names, sorted);
      await db.close();
    });
  });
}
