// Integration tests for lib/data/db/local_data_summary_dao.dart (T17,
// Profile's "Local data summary" card) against a real sqlite3 database —
// same sqflite_common_ffi backend/idiom every other DAO test in this suite
// uses, no mocked SQL. Covers:
//   - COUNT(*) and MIN/MAX(transaction_occurred_at) over active rows;
//   - deleted_at IS NULL is genuinely enforced (a soft-deleted row changes
//     neither the count nor the date range);
//   - an empty table yields count 0 + null range (Profile's "No data yet");
//   - databaseFileSizeBytes: a real on-disk file's size, and null (Profile's
//     "—") for an in-memory database rather than a throw.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/db/local_data_summary_dao.dart';
import 'package:mymog/data/db/schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

OpenDatabaseOptions _options() => OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await AppSchema.createSchema(db);
        await AppSchema.seed(db);
      },
    );

Future<Database> _openFreshDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: _options());
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
  required int occurredAtMs,
  int? deletedAtMs,
}) {
  return db.insert('transactions', {
    'display_code': displayCode,
    'source_type': sourceType,
    'amount_cents': 100000,
    'transaction_cost_cents': sourceType == 'CASH' ? null : 100,
    'counterparty_label': null,
    'counterparty_phone': null,
    'paybill_account_number': null,
    'classification_id': classificationId,
    'raw_parse_source': 'MANUAL',
    'transaction_occurred_at': occurredAtMs,
    'created_at': occurredAtMs,
    'deleted_at': deletedAtMs,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalDataSummaryDao.summary', () {
    test('empty table: count 0, null date range', () async {
      final db = await _openFreshDb();
      final s = await LocalDataSummaryDao.summary(db);
      expect(s.transactionCount, 0);
      expect(s.isEmpty, isTrue);
      expect(s.earliestOccurredAt, isNull);
      expect(s.latestOccurredAt, isNull);
      await db.close();
    });

    test('counts active rows and spans MIN..MAX(transaction_occurred_at), '
        'ignoring soft-deleted rows entirely', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');
      final earliest = DateTime(2026, 3, 4, 9, 15);
      final middle = DateTime(2026, 6, 10, 12);
      final latest = DateTime(2026, 9, 22, 18, 45);

      await _insertTx(db,
          displayCode: 'A1', sourceType: 'SEND_MONEY', classificationId: sendId,
          occurredAtMs: middle.millisecondsSinceEpoch);
      await _insertTx(db,
          displayCode: 'A2', sourceType: 'SEND_MONEY', classificationId: sendId,
          occurredAtMs: earliest.millisecondsSinceEpoch);
      await _insertTx(db,
          displayCode: 'A3', sourceType: 'CASH', classificationId: sendId,
          occurredAtMs: latest.millisecondsSinceEpoch);
      // Soft-deleted rows OUTSIDE the active range on both sides — if the
      // deleted_at filter were missing, count and both bounds would change.
      await _insertTx(db,
          displayCode: 'D1', sourceType: 'SEND_MONEY', classificationId: sendId,
          occurredAtMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
          deletedAtMs: latest.millisecondsSinceEpoch);
      await _insertTx(db,
          displayCode: 'D2', sourceType: 'SEND_MONEY', classificationId: sendId,
          occurredAtMs: DateTime(2027, 1, 1).millisecondsSinceEpoch,
          deletedAtMs: latest.millisecondsSinceEpoch);

      final s = await LocalDataSummaryDao.summary(db);
      expect(s.transactionCount, 3);
      expect(s.isEmpty, isFalse);
      expect(s.earliestOccurredAt, earliest);
      expect(s.latestOccurredAt, latest);
      await db.close();
    });

    test('only soft-deleted rows present reads as empty', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');
      await _insertTx(db,
          displayCode: 'D1', sourceType: 'SEND_MONEY', classificationId: sendId,
          occurredAtMs: 1000, deletedAtMs: 2000);
      final s = await LocalDataSummaryDao.summary(db);
      expect(s.transactionCount, 0);
      expect(s.earliestOccurredAt, isNull);
      expect(s.latestOccurredAt, isNull);
      await db.close();
    });
  });

  group('LocalDataSummaryDao.databaseFileSizeBytes', () {
    test('in-memory database yields null (rendered as "—"), never throws', () async {
      final db = await _openFreshDb();
      expect(await LocalDataSummaryDao.databaseFileSizeBytes(db), isNull);
      await db.close();
    });

    test('a real on-disk database yields its actual file size', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('t17_profile_size_');
      final path = p.join(dir.path, 'mymog.db');
      final db = await databaseFactoryFfi.openDatabase(path, options: _options());
      try {
        final size = await LocalDataSummaryDao.databaseFileSizeBytes(db);
        expect(size, isNotNull);
        expect(size, greaterThan(0));
        final wal = File('$path-wal');
        final expected = await File(path).length() + (await wal.exists() ? await wal.length() : 0);
        expect(size, expected);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    });
  });
}
