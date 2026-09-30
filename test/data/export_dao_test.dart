// Integration tests for lib/data/db/export_dao.dart against a real
// in-memory sqlite3 database (same sqflite_common_ffi backend
// analytics_dao_test.dart/home_dashboard_dao_test.dart use) — no mocked
// SQL. Covers T10's own explicit requirements (CSV export needs no
// table of its own):
//   - the join is transactions JOIN classifications JOIN
//     classification_groups;
//   - deleted_at IS NULL is genuinely enforced (a soft-deleted row is
//     excluded from both the count and the export, not just hidden);
//   - counterparty_phone appears in the output alongside
//     counterparty_label/paybill_account_number;
//   - the CSV content/row-count itself, against seeded data.
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/db/export_dao.dart';
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
  String? counterpartyLabel,
  String? counterpartyPhone,
  String? paybillAccountNumber,
  int? transactionCostCents,
  int? deletedAtMs,
}) {
  return db.insert('transactions', {
    'display_code': displayCode,
    'source_type': sourceType,
    'amount_cents': amountCents,
    'transaction_cost_cents': sourceType == 'CASH' ? null : (transactionCostCents ?? 100),
    'counterparty_label': counterpartyLabel,
    'counterparty_phone': counterpartyPhone,
    'paybill_account_number': paybillAccountNumber,
    'classification_id': classificationId,
    'raw_parse_source': 'MANUAL',
    'transaction_occurred_at': occurredAtMs,
    'created_at': occurredAtMs,
    'deleted_at': deletedAtMs,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final anchor = DateTime(2026, 9, 22, 14, 30);
  final nowMs = anchor.millisecondsSinceEpoch;

  group('ExportDao.activeTransactionCount', () {
    test('counts only non-soft-deleted rows', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Family/Friends');

      await _insertTx(
        db,
        displayCode: 'S1',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 1000,
        occurredAtMs: nowMs,
        counterpartyLabel: 'JANE',
        counterpartyPhone: '0700000000',
      );
      await _insertTx(
        db,
        displayCode: 'S2-DELETED',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 5000,
        occurredAtMs: nowMs,
        counterpartyLabel: 'GHOST',
        counterpartyPhone: '0711111111',
        deletedAtMs: nowMs - 1000,
      );

      expect(await ExportDao.activeTransactionCount(db), 1);
      await db.close();
    });

    test('returns 0 on an empty/all-deleted table', () async {
      final db = await _openFreshDb();
      expect(await ExportDao.activeTransactionCount(db), 0);
      await db.close();
    });
  });

  group('ExportDao.activeTransactions — join + filter', () {
    test(
      'joins transactions -> classifications -> classification_groups, includes '
      'counterparty_phone alongside counterparty_label/paybill_account_number, and '
      'excludes soft-deleted rows',
      () async {
        final db = await _openFreshDb();
        final sendId = await _classificationId(db, 'SEND_MONEY', 'Rent');
        final payId = await _classificationId(db, 'PAYBILL', 'Shopping');

        await _insertTx(
          db,
          displayCode: 'SEND1',
          sourceType: 'SEND_MONEY',
          classificationId: sendId,
          amountCents: 150000,
          transactionCostCents: 2500,
          occurredAtMs: nowMs,
          counterpartyLabel: 'JOHN KAMAU',
          counterpartyPhone: '0798630424',
        );
        await _insertTx(
          db,
          displayCode: 'PAY1',
          sourceType: 'PAYBILL',
          classificationId: payId,
          amountCents: 200000,
          transactionCostCents: 3000,
          occurredAtMs: nowMs - 60000,
          counterpartyLabel: 'LOOP BIZ',
          paybillAccountNumber: '464332',
        );
        await _insertTx(
          db,
          displayCode: 'DELETED1',
          sourceType: 'SEND_MONEY',
          classificationId: sendId,
          amountCents: 999999,
          occurredAtMs: nowMs,
          counterpartyLabel: 'GHOST',
          counterpartyPhone: '0711111111',
          deletedAtMs: nowMs - 1000,
        );

        final rows = await ExportDao.activeTransactions(db);

        expect(rows, hasLength(2));
        // most-recent-first
        expect(rows[0].displayCode, 'SEND1');
        expect(rows[1].displayCode, 'PAY1');

        final send = rows[0];
        expect(send.groupDisplayName, 'Send Money');
        expect(send.classificationName, 'Rent');
        expect(send.counterpartyLabel, 'JOHN KAMAU');
        expect(send.counterpartyPhone, '0798630424');
        expect(send.paybillAccountNumber, isNull);
        expect(send.amountCents, 150000);
        expect(send.transactionCostCents, 2500);

        final pay = rows[1];
        expect(pay.groupDisplayName, 'Paybill');
        expect(pay.classificationName, 'Shopping');
        expect(pay.counterpartyLabel, 'LOOP BIZ');
        expect(pay.paybillAccountNumber, '464332');
        expect(pay.counterpartyPhone, isNull);

        expect(rows.map((r) => r.displayCode), isNot(contains('DELETED1')));
        await db.close();
      },
    );

    test('a CASH row (no counterparty) still joins correctly, with a null transaction cost', () async {
      final db = await _openFreshDb();
      final buyId = await _classificationId(db, 'BUY_GOODS', 'Groceries');

      await _insertTx(
        db,
        displayCode: 'CASH-20260922-1200',
        sourceType: 'CASH',
        classificationId: buyId,
        amountCents: 50000,
        occurredAtMs: nowMs,
      );

      final rows = await ExportDao.activeTransactions(db);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.groupDisplayName, 'Buy Goods');
      expect(row.classificationName, 'Groceries');
      expect(row.counterpartyLabel, isNull);
      expect(row.counterpartyPhone, isNull);
      expect(row.paybillAccountNumber, isNull);
      expect(row.transactionCostCents, isNull);
      await db.close();
    });
  });

  group('ExportDao.toCsv', () {
    test('formats header + row count matching seeded data, with correct decimal amounts', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Transport');

      await _insertTx(
        db,
        displayCode: 'SEND1',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 150050,
        transactionCostCents: 2500,
        occurredAtMs: nowMs,
        counterpartyLabel: 'JOHN KAMAU',
        counterpartyPhone: '0798630424',
      );

      final rows = await ExportDao.activeTransactions(db);
      final csv = ExportDao.toCsv(rows);
      final lines = csv.split('\r\n')..removeWhere((l) => l.isEmpty);

      expect(lines, hasLength(2)); // header + 1 data row
      expect(lines[0], ExportDao.csvHeader.join(','));
      expect(lines[1], contains('2026-09-22 14:30'));
      expect(lines[1], contains('SEND_MONEY'));
      expect(lines[1], contains('Send Money'));
      expect(lines[1], contains('Transport'));
      expect(lines[1], contains('JOHN KAMAU'));
      expect(lines[1], contains('0798630424'));
      expect(lines[1], contains('1500.50')); // amount_cents 150050 -> 1500.50
      expect(lines[1], contains('25.00')); // transaction_cost_cents 2500 -> 25.00
      expect(lines[1], contains('SEND1'));
      await db.close();
    });

    test('quotes a field containing a comma (RFC 4180-style)', () async {
      final db = await _openFreshDb();
      final buyId = await _classificationId(db, 'BUY_GOODS', 'Shopping');
      await _insertTx(
        db,
        displayCode: 'B1',
        sourceType: 'BUY_GOODS',
        classificationId: buyId,
        amountCents: 1000,
        occurredAtMs: nowMs,
        counterpartyLabel: 'Naivas, Westlands',
      );

      final rows = await ExportDao.activeTransactions(db);
      final csv = ExportDao.toCsv(rows);
      expect(csv, contains('"Naivas, Westlands"'));
      await db.close();
    });

    test('empty row list produces just the header line', () {
      final csv = ExportDao.toCsv(const []);
      expect(csv.trim(), ExportDao.csvHeader.join(','));
    });
  });
}
