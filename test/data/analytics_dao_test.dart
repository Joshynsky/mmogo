// Integration tests for lib/data/db/analytics_dao.dart against a real
// in-memory sqlite3 database (same sqflite_common_ffi backend
// home_dashboard_dao_test.dart / schema_test.dart use) — no mocked SQL.
//
// Covers: the itemized query does NOT exclude a soft-deleted-but-still-
// referenced classification's rows (a binding ruling), the
// period scoping (deleted_at IS NULL + BETWEEN bounds), the type filter
// (source_type IN (...)), and that the party filter agrees with Paid to's
// grouping.
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/db/analytics_dao.dart';
import 'package:mymog/data/db/schema.dart';
import 'package:mymog/data/db/transaction_dao.dart';
import 'package:mymog/domain/analytics/analytics_period.dart';
import 'package:mymog/domain/paid_to/paid_to.dart';
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
  int? deletedAtMs,
}) {
  return db.insert('transactions', {
    'display_code': displayCode,
    'source_type': sourceType,
    'amount_cents': amountCents,
    'transaction_cost_cents': sourceType == 'CASH' ? null : 100,
    'counterparty_label': sourceType == 'CASH'
        ? null
        : (counterpartyLabel ?? 'Test Counterparty'),
    'counterparty_phone': sourceType == 'SEND_MONEY' ? (counterpartyPhone ?? '0700000000') : null,
    'paybill_account_number': sourceType == 'PAYBILL' ? (paybillAccountNumber ?? '12345') : null,
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
  final anchor = DateTime(2026, 9, 18, 12);

  group('itemizedTransactions — period scoping + deleted_at filter', () {
    test('only returns rows within [startMs, endMs], most-recent-first', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Rent');
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
        displayCode: 'OUT-OF-RANGE',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 99999,
        occurredAtMs: nowMs - 40 * dayMs,
      );

      final start = anchor.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      final end = anchor.millisecondsSinceEpoch;
      final items = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: start,
        endMs: end,
        types: AnalyticsDao.allTypes,
      );

      expect(items.map((i) => i.id), [newerId, olderId]);
      await db.close();
    });

    test('excludes soft-deleted rows (deleted_at IS NOT NULL)', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Rent');
      final nowMs = anchor.millisecondsSinceEpoch;

      await _insertTx(
        db,
        displayCode: 'ACTIVE',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 1000,
        occurredAtMs: nowMs,
      );
      await _insertTx(
        db,
        displayCode: 'DELETED',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 5000,
        occurredAtMs: nowMs,
        deletedAtMs: nowMs - 1000,
      );

      final start = anchor.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final end = anchor.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final items = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: start,
        endMs: end,
        types: AnalyticsDao.allTypes,
      );

      expect(items, hasLength(1));
      expect(items.single.displayCode, 'ACTIVE');
      await db.close();
    });

    test(
      'a transaction referencing a soft-deleted (active=0) classification still renders, '
      'with that classification\'s real name',
      () async {
        final db = await _openFreshDb();
        final classificationId = await _classificationId(db, 'BUY_GOODS', 'Groceries');
        final nowMs = anchor.millisecondsSinceEpoch;

        await _insertTx(
          db,
          displayCode: 'BG-SOFT-DELETED-CLASS',
          sourceType: 'BUY_GOODS',
          classificationId: classificationId,
          amountCents: 3000,
          occurredAtMs: nowMs,
        );
        await db.update('classifications', {'active': 0}, where: 'id = ?', whereArgs: [classificationId]);

        final start = anchor.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
        final end = anchor.add(const Duration(hours: 1)).millisecondsSinceEpoch;
        final items = await AnalyticsDao.itemizedTransactions(
          db,
          startMs: start,
          endMs: end,
          types: AnalyticsDao.allTypes,
        );

        expect(items, hasLength(1));
        expect(items.single.classificationName, 'Groceries');
        await db.close();
      },
    );

    test('startMs/endMs both null means all-time (party-filter mode)', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Rent');
      final nowMs = anchor.millisecondsSinceEpoch;

      await _insertTx(
        db,
        displayCode: 'FAR-PAST',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 1000,
        occurredAtMs: nowMs - 400 * dayMs,
      );
      await _insertTx(
        db,
        displayCode: 'RECENT',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 2000,
        occurredAtMs: nowMs,
      );

      final items = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: null,
        endMs: null,
        types: AnalyticsDao.allTypes,
      );

      expect(items, hasLength(2));
      await db.close();
    });
  });

  group('type filter (source_type IN (...))', () {
    test('itemizedTransactions only returns rows whose source_type is in the active set', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Rent');
      final buyId = await _classificationId(db, 'BUY_GOODS', 'Shopping');
      final payId = await _classificationId(db, 'PAYBILL', 'Shopping');
      final nowMs = anchor.millisecondsSinceEpoch;

      await _insertTx(db, displayCode: 'S1', sourceType: 'SEND_MONEY', classificationId: sendId, amountCents: 1000, occurredAtMs: nowMs);
      await _insertTx(db, displayCode: 'B1', sourceType: 'BUY_GOODS', classificationId: buyId, amountCents: 2000, occurredAtMs: nowMs);
      await _insertTx(db, displayCode: 'P1', sourceType: 'PAYBILL', classificationId: payId, amountCents: 3000, occurredAtMs: nowMs);

      final start = anchor.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final end = anchor.add(const Duration(hours: 1)).millisecondsSinceEpoch;

      final items = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: start,
        endMs: end,
        types: {'SEND_MONEY', 'PAYBILL'},
      );

      expect(items.map((i) => i.displayCode).toSet(), {'S1', 'P1'});
      await db.close();
    });

    test('an empty active-types set returns zero rows (all bubbles toggled off)', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Rent');
      final nowMs = anchor.millisecondsSinceEpoch;
      await _insertTx(db, displayCode: 'S1', sourceType: 'SEND_MONEY', classificationId: sendId, amountCents: 1000, occurredAtMs: nowMs);

      final items = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: anchor.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        endMs: anchor.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        types: {},
      );
      expect(items, isEmpty);
      await db.close();
    });

  });

  group('party filter (disclosed placeholder contract)', () {
    test('SEND_MONEY party filter matches on trimmed counterparty_phone', () async {
      final db = await _openFreshDb();
      final sendId = await _classificationId(db, 'SEND_MONEY', 'Rent');
      final nowMs = anchor.millisecondsSinceEpoch;

      await _insertTx(
        db,
        displayCode: 'MATCH',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 1000,
        occurredAtMs: nowMs,
        counterpartyPhone: '0798630424',
      );
      await _insertTx(
        db,
        displayCode: 'NO-MATCH',
        sourceType: 'SEND_MONEY',
        classificationId: sendId,
        amountCents: 9999,
        occurredAtMs: nowMs,
        counterpartyPhone: '0711111111',
      );

      final items = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: null,
        endMs: null,
        types: AnalyticsDao.allTypes,
        partyType: 'SEND_MONEY',
        partyKey: '0798630424',
      );

      expect(items, hasLength(1));
      expect(items.single.displayCode, 'MATCH');
      await db.close();
    });

    test('PAYBILL party filter matches on label#account', () async {
      final db = await _openFreshDb();
      final payId = await _classificationId(db, 'PAYBILL', 'Shopping');
      final nowMs = anchor.millisecondsSinceEpoch;

      await _insertTx(
        db,
        displayCode: 'MATCH',
        sourceType: 'PAYBILL',
        classificationId: payId,
        amountCents: 1000,
        occurredAtMs: nowMs,
        counterpartyLabel: 'loop biz',
        paybillAccountNumber: '464332',
      );
      await _insertTx(
        db,
        displayCode: 'NO-MATCH-DIFFERENT-ACCOUNT',
        sourceType: 'PAYBILL',
        classificationId: payId,
        amountCents: 9999,
        occurredAtMs: nowMs,
        counterpartyLabel: 'LOOP BIZ',
        paybillAccountNumber: '999999',
      );

      final items = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: null,
        endMs: null,
        types: AnalyticsDao.allTypes,
        partyType: 'PAYBILL',
        partyKey: 'LOOP BIZ#464332',
      );

      expect(items, hasLength(1));
      expect(items.single.displayCode, 'MATCH');
      await db.close();
    });

    test('agrees with Paid to grouping: irregular internal whitespace is ONE recipient, same rows', () async {
      final db = await _openFreshDb();
      final payId = await _classificationId(db, 'PAYBILL', 'Shopping');
      final nowMs = anchor.millisecondsSinceEpoch;
      Future<void> pay(String code, String label, String account, int cents) => _insertTx(
        db,
        displayCode: code,
        sourceType: 'PAYBILL',
        classificationId: payId,
        amountCents: cents,
        occurredAtMs: nowMs,
        counterpartyLabel: label,
        paybillAccountNumber: account,
      );
      await pay('P1', 'LOOP  BIZ', '464332', 1000);
      await pay('P2', 'LOOP   BIZ', '464332', 4000);
      await pay('P3', 'ANOTHER BIZ', '111111', 777);

      final all = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: null,
        endMs: null,
        types: AnalyticsDao.allTypes,
      );
      final groups = groupPaidTo([
        for (final r in all)
          PaidToPayment(
            sourceType: r.sourceType,
            amountCents: r.amountCents,
            feeCents: r.transactionCostCents ?? 0,
            occurredAt: r.occurredAt,
            classificationName: r.classificationName,
            label: r.counterpartyLabel,
            phone: r.counterpartyPhone,
            account: r.paybillAccountNumber,
          ),
      ]);
      expect(groups, hasLength(2));
      final loop = groups.singleWhere((g) => g.count == 2);
      expect(loop.partyKey, 'LOOP BIZ#464332');
      expect(loop.totalCents, 5000);

      // Analytics' party filter, given the key Paid to hands it, returns
      // exactly the rows Paid to grouped under that recipient.
      final filtered = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: null,
        endMs: null,
        types: AnalyticsDao.allTypes,
        partyType: loop.sourceType,
        partyKey: loop.partyKey,
      );
      expect(filtered.map((i) => i.displayCode).toSet(), {'P1', 'P2'});
      expect(filtered.fold<int>(0, (s, r) => s + r.amountCents), loop.totalCents);
      await db.close();
    });
  });

  group('occurredAtOf — T9 Home handoff lookup', () {
    test('returns the live row transaction_occurred_at', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'BUY_GOODS', 'Shopping');
      final at = anchor.subtract(const Duration(days: 40)).millisecondsSinceEpoch;
      final id = await _insertTx(
        db,
        displayCode: 'OLDROW0001',
        sourceType: 'BUY_GOODS',
        classificationId: classificationId,
        amountCents: 5000,
        occurredAtMs: at,
      );

      final result = await AnalyticsDao.occurredAtOf(db, id: id);
      expect(result, DateTime.fromMillisecondsSinceEpoch(at));
      await db.close();
    });

    test('returns null for a soft-deleted row and for an id that does not exist', () async {
      final db = await _openFreshDb();
      final classificationId = await _classificationId(db, 'BUY_GOODS', 'Shopping');
      final nowMs = anchor.millisecondsSinceEpoch;
      final deletedId = await _insertTx(
        db,
        displayCode: 'DELROW0001',
        sourceType: 'BUY_GOODS',
        classificationId: classificationId,
        amountCents: 5000,
        occurredAtMs: nowMs - 10 * dayMs,
        deletedAtMs: nowMs,
      );

      expect(await AnalyticsDao.occurredAtOf(db, id: deletedId), isNull);
      expect(await AnalyticsDao.occurredAtOf(db, id: deletedId + 1000), isNull);
      await db.close();
    });
  });

  group('T21 — firstOccurredAt, Where it went, delete + Undo', () {
    test('firstOccurredAt: the earliest live transaction; null when there are none', () async {
      final db = await _openFreshDb();
      expect(await AnalyticsDao.firstOccurredAt(db), isNull);
      final cls = await _classificationId(db, 'BUY_GOODS', 'Shopping');
      final nowMs = anchor.millisecondsSinceEpoch;
      await _insertTx(
        db,
        displayCode: 'A1',
        sourceType: 'BUY_GOODS',
        classificationId: cls,
        amountCents: 100,
        occurredAtMs: nowMs - 5 * dayMs,
      );
      // An even older row that is soft-deleted doesn't count.
      await _insertTx(
        db,
        displayCode: 'A2',
        sourceType: 'BUY_GOODS',
        classificationId: cls,
        amountCents: 100,
        occurredAtMs: nowMs - 30 * dayMs,
        deletedAtMs: nowMs,
      );
      expect(await AnalyticsDao.firstOccurredAt(db), DateTime.fromMillisecondsSinceEpoch(nowMs - 5 * dayMs));
      await db.close();
    });

    test('Where it went merges the same name across types and still counts soft-deleted classifications', () async {
      final db = await _openFreshDb();
      final paybillShopping = await _classificationId(db, 'PAYBILL', 'Shopping');
      final buyShopping = await _classificationId(db, 'BUY_GOODS', 'Shopping');
      final rent = await _classificationId(db, 'SEND_MONEY', 'Rent');
      final nowMs = anchor.millisecondsSinceEpoch;
      await _insertTx(
        db,
        displayCode: 'W1',
        sourceType: 'PAYBILL',
        classificationId: paybillShopping,
        amountCents: 120000,
        occurredAtMs: nowMs,
      );
      await _insertTx(
        db,
        displayCode: 'W2',
        sourceType: 'BUY_GOODS',
        classificationId: buyShopping,
        amountCents: 85000,
        occurredAtMs: nowMs - dayMs,
      );
      await _insertTx(
        db,
        displayCode: 'W3',
        sourceType: 'SEND_MONEY',
        classificationId: rent,
        amountCents: 150000,
        occurredAtMs: nowMs - 2 * dayMs,
      );
      // Rent is soft-deleted as a classification: its history still counts.
      await db.update('classifications', {'active': 0}, where: 'id = ?', whereArgs: [rent]);

      final (s, e) = AnalyticsPeriod.lastSevenDays(anchor).range(today: anchor).bounds;
      final rows = await AnalyticsDao.itemizedTransactions(db, startMs: s, endMs: e, types: AnalyticsDao.allTypes);
      final where = groupSpendByName(rows.map((r) => (r.classificationName, r.amountCents)));
      expect(where.map((w) => w.name), ['Shopping', 'Rent']);
      expect(where.first.cents, 205000);
      expect(where.first.count, 2);
      expect(where.last.cents, 150000);
      await db.close();
    });

    test('a soft-deleted row leaves every total at once, and Undo (restore) brings it back', () async {
      final db = await _openFreshDb();
      final cls = await _classificationId(db, 'BUY_GOODS', 'Groceries');
      final nowMs = anchor.millisecondsSinceEpoch;
      final id = await _insertTx(
        db,
        displayCode: 'U1',
        sourceType: 'BUY_GOODS',
        classificationId: cls,
        amountCents: 5000,
        occurredAtMs: nowMs,
      );
      await _insertTx(
        db,
        displayCode: 'U2',
        sourceType: 'BUY_GOODS',
        classificationId: cls,
        amountCents: 7000,
        occurredAtMs: nowMs - dayMs,
      );
      final (s, e) = AnalyticsPeriod.lastSevenDays(anchor).range(today: anchor).bounds;
      Future<int> total() async => (await AnalyticsDao.itemizedTransactions(
        db,
        startMs: s,
        endMs: e,
        types: AnalyticsDao.allTypes,
      )).fold<int>(0, (sum, r) => sum + r.amountCents);

      expect(await total(), 12000);
      await TransactionDao.softDelete(db, id: id);
      expect(await total(), 7000);
      expect(await AnalyticsDao.occurredAtOf(db, id: id), isNull);
      await TransactionDao.restore(db, id: id);
      expect(await total(), 12000);
      await db.close();
    });
  });
}
