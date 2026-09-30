// Integration tests for lib/data/db/home_dashboard_dao.dart against a real
// in-memory sqlite3 database (same sqflite_common_ffi backend
// test/data/schema_test.dart uses) — no mocked SQL. Verifies the actual
// period-scoping/aggregation queries this slice adds, in particular that
// the `deleted_at IS NULL` filter genuinely excludes a soft-deleted row
// from every aggregate and from the recent list, not just that the
// screen doesn't crash on an empty table.
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/db/home_dashboard_dao.dart';
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

Future<int> _classificationId(Database db, String groupCode, String name) async {
  final rows = await db.rawQuery(
    '''
    SELECT c.id FROM classifications c
    JOIN classification_groups g ON g.id = c.group_id
    WHERE g.code = ? AND c.name = ?
    ''',
    [groupCode, name],
  );
  return rows.first['id'] as int;
}

Future<int> _insertTx(
  Database db, {
  required String displayCode,
  required String sourceType,
  required int classificationId,
  required int amountCents,
  required int occurredAtMs,
  int? deletedAtMs,
}) {
  return db.insert('transactions', {
    'display_code': displayCode,
    'source_type': sourceType,
    'amount_cents': amountCents,
    'transaction_cost_cents': sourceType == 'CASH' ? null : 100,
    'counterparty_label': sourceType == 'CASH' ? null : 'Test Counterparty',
    'counterparty_phone': sourceType == 'SEND_MONEY' ? '0700000000' : null,
    'paybill_account_number': sourceType == 'PAYBILL' ? '12345' : null,
    'classification_id': classificationId,
    'raw_parse_source': 'MANUAL',
    'transaction_occurred_at': occurredAtMs,
    'created_at': occurredAtMs,
    'deleted_at': deletedAtMs,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dayMs = 86400000;
  final anchor = DateTime(2026, 9, 18, 12); // fixed reference "now"

  group('sumAmountCents / sourceTypeTotals — period scoping', () {
    test('only sums rows within [startMs, endMs], excludes rows outside the window', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');

      final inRangeMs = anchor.millisecondsSinceEpoch;
      final outOfRangeMs = anchor.subtract(const Duration(days: 40)).millisecondsSinceEpoch;

      await _insertTx(
        db,
        displayCode: 'IN-RANGE',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 10000,
        occurredAtMs: inRangeMs,
      );
      await _insertTx(
        db,
        displayCode: 'OUT-OF-RANGE',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 99999,
        occurredAtMs: outOfRangeMs,
      );

      final start = anchor.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
      final end = anchor.add(const Duration(days: 1)).millisecondsSinceEpoch;

      final total = await HomeDashboardDao.sumAmountCents(db, startMs: start, endMs: end);
      expect(total, 10000);
      await db.close();
    });

    test('a soft-deleted row (deleted_at set) is excluded from the period total', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');
      final nowMs = anchor.millisecondsSinceEpoch;

      await _insertTx(
        db,
        displayCode: 'ACTIVE',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 5000,
        occurredAtMs: nowMs,
      );
      await _insertTx(
        db,
        displayCode: 'SOFT-DELETED',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 999999,
        occurredAtMs: nowMs,
        deletedAtMs: nowMs - 60000, // deleted 1 minute ago, still within grace window
      );

      final start = anchor.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final end = anchor.add(const Duration(hours: 1)).millisecondsSinceEpoch;

      final total = await HomeDashboardDao.sumAmountCents(db, startMs: start, endMs: end);
      // Must equal ONLY the active row -- the soft-deleted row's huge
      // amount must not leak into the total despite still being within
      // its 1-hour restore grace window (it is excluded
      // immediately, not just after the purge sweep).
      expect(total, 5000);
      await db.close();
    });

    test('sourceTypeTotals groups correctly per source_type and sums transaction cost', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');
      final buyId = await _classificationId(db, 'BUY_GOODS', 'Shopping');
      final nowMs = anchor.millisecondsSinceEpoch;

      await _insertTx(
        db,
        displayCode: 'S1',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 10000,
        occurredAtMs: nowMs,
      );
      await _insertTx(
        db,
        displayCode: 'S2',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 20000,
        occurredAtMs: nowMs,
      );
      await _insertTx(
        db,
        displayCode: 'B1',
        sourceType: 'BUY_GOODS',
        classificationId: buyId,
        amountCents: 5000,
        occurredAtMs: nowMs,
      );

      final start = anchor.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final end = anchor.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final totals = await HomeDashboardDao.sourceTypeTotals(db, startMs: start, endMs: end);

      expect(totals['SEND_MONEY']!.totalCents, 30000);
      expect(totals['SEND_MONEY']!.costCents, 200); // 2 rows x 100 cost each
      expect(totals['BUY_GOODS']!.totalCents, 5000);
      expect(totals.containsKey('PAYBILL'), isFalse);
      expect(totals.containsKey('CASH'), isFalse);
      await db.close();
    });
  });

  group('recentTransactions', () {
    test('excludes soft-deleted rows and orders most-recent-first', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');
      final nowMs = anchor.millisecondsSinceEpoch;

      final olderId = await _insertTx(
        db,
        displayCode: 'OLDER',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 1000,
        occurredAtMs: nowMs - 2 * dayMs,
      );
      final newerId = await _insertTx(
        db,
        displayCode: 'NEWER',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 2000,
        occurredAtMs: nowMs - dayMs,
      );
      await _insertTx(
        db,
        displayCode: 'MOST-RECENT-BUT-DELETED',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 3000,
        occurredAtMs: nowMs,
        deletedAtMs: nowMs - 1000,
      );

      final recent = await HomeDashboardDao.recentTransactions(db, limit: 5);
      expect(recent.map((t) => t.id), [newerId, olderId]);
      await db.close();
    });

    test('respects the limit argument', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');
      final nowMs = anchor.millisecondsSinceEpoch;

      for (var i = 0; i < 7; i++) {
        await _insertTx(
          db,
          displayCode: 'TX$i',
          sourceType: 'SEND_MONEY',
          classificationId: sendId,
          amountCents: 1000 + i,
          occurredAtMs: nowMs - i * dayMs,
        );
      }

      final recent = await HomeDashboardDao.recentTransactions(db, limit: 5);
      expect(recent, hasLength(5));
      await db.close();
    });

    test('a CASH row displays as "Cash — <classification name>"', () async {
      final db = await _openFreshDb();
      final cashClassificationId = await _classificationId(db, 'BUY_GOODS', 'Groceries');
      final nowMs = anchor.millisecondsSinceEpoch;

      await _insertTx(
        db,
        displayCode: 'CASH-20260918-1200',
        sourceType: 'CASH',
        classificationId: cashClassificationId,
        amountCents: 4000,
        occurredAtMs: nowMs,
      );

      final recent = await HomeDashboardDao.recentTransactions(db, limit: 5);
      expect(recent, hasLength(1));
      expect(recent.first.displayName, 'Cash — Groceries');
      await db.close();
    });
  });
}
