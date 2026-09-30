// A small in-memory stand-in for the database, for Analytics widget tests.
//
// A real sqflite_common_ffi Database hangs inside testWidgets in this
// environment (see manage_classifications_screen_test.dart's header), so the
// T21 Analytics widget tests drive the real screen against this fake. It
// answers exactly the calls the screen's DAOs make, matched on their SQL
// text — it is not a SQL engine:
//  - AnalyticsDao.firstOccurredAt (MIN over live rows);
//  - AnalyticsDao.occurredAtOf (the Home hand-off lookup);
//  - AnalyticsDao.itemizedTransactions (honours BETWEEN bounds, the
//    source_type IN (...) list, deleted_at IS NULL and newest-first order);
//  - TransactionDao.update / softDelete / restore;
//  - the edit form's classification pickers.
// The real SQL behind each is proven against in-memory sqlite in
// test/data/analytics_dao_test.dart and test/data/transaction_dao_test.dart.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeAnalyticsDb implements Database {
  FakeAnalyticsDb(this.transactions, {this.failLookup = false});

  /// Rows shaped like `transactions`, plus a `classification_name` column
  /// standing in for the classifications join.
  final List<Map<String, Object?>> transactions;
  final bool failLookup;

  final List<int> lookedUpIds = [];

  /// When set, `TransactionDao.update` / `restore` throw this (a
  /// DatabaseException in the tests that use it).
  Object? updateError;
  Object? restoreError;

  /// Every `(startMs, endMs)` window itemizedTransactions was asked for.
  final List<(int?, int?)> windows = [];

  final groups = <Map<String, Object?>>[
    {'id': 1, 'code': 'SEND_MONEY', 'display_name': 'Send Money', 'enabled': 1},
    {'id': 2, 'code': 'PAYBILL', 'display_name': 'Paybill', 'enabled': 1},
    {'id': 3, 'code': 'BUY_GOODS', 'display_name': 'Buy Goods', 'enabled': 1},
    {'id': 4, 'code': 'POCHI_LA_BIASHARA', 'display_name': 'Pochi La Biashara', 'enabled': 0},
  ];

  final classifications = <Map<String, Object?>>[
    {'id': 101, 'group_id': 1, 'name': 'Family/Friends', 'active': 1},
    {'id': 102, 'group_id': 1, 'name': 'Rent', 'active': 1},
    {'id': 105, 'group_id': 2, 'name': 'Rent Payment', 'active': 1},
    {'id': 106, 'group_id': 2, 'name': 'Shopping', 'active': 1},
    {'id': 109, 'group_id': 3, 'name': 'Rent Payment', 'active': 1},
    {'id': 110, 'group_id': 3, 'name': 'Shopping', 'active': 1},
  ];

  Map<String, Object?> byId(int id) => transactions.firstWhere((t) => t['id'] == id);

  String _classificationName(Map<String, Object?> t) {
    final explicit = t['classification_name'] as String?;
    if (explicit != null && t['_renamed'] != true) return explicit;
    final c = classifications.where((c) => c['id'] == t['classification_id']);
    return c.isEmpty ? (explicit ?? '?') : c.first['name'] as String;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final args = arguments ?? const [];
    final live = transactions.where((t) => t['deleted_at'] == null).toList();
    if (sql.contains('MIN(transaction_occurred_at)')) {
      if (live.isEmpty) {
        return [
          {'first_at': null},
        ];
      }
      final first = live.map((t) => t['transaction_occurred_at'] as int).reduce((a, b) => a < b ? a : b);
      return [
        {'first_at': first},
      ];
    }
    if (sql.contains('SELECT transaction_occurred_at FROM transactions WHERE id = ?')) {
      final id = args[0] as int;
      lookedUpIds.add(id);
      if (failLookup) throw StateError('simulated lookup failure');
      return [
        for (final t in live)
          if (t['id'] == id) {'transaction_occurred_at': t['transaction_occurred_at']},
      ];
    }
    if (sql.contains('FROM transactions t') && !sql.contains('GROUP BY')) {
      final bounded = sql.contains('BETWEEN');
      final start = bounded ? args[0] as int : null;
      final end = bounded ? args[1] as int : null;
      windows.add((start, end));
      final types = args.skip(bounded ? 2 : 0).cast<String>().toSet();
      final rows = live.where((t) {
        final at = t['transaction_occurred_at'] as int;
        if (bounded && (at < start! || at > end!)) return false;
        return types.contains(t['source_type']);
      }).toList()..sort((a, b) => (b['transaction_occurred_at'] as int).compareTo(a['transaction_occurred_at'] as int));
      return [
        for (final t in rows)
          {
            'id': t['id'],
            'display_code': t['display_code'],
            'source_type': t['source_type'],
            'amount_cents': t['amount_cents'],
            'counterparty_label': t['counterparty_label'],
            'counterparty_phone': t['counterparty_phone'],
            'paybill_account_number': t['paybill_account_number'],
            'classification_id': t['classification_id'],
            'classification_name': _classificationName(t),
            'transaction_occurred_at': t['transaction_occurred_at'],
            'transaction_cost_cents': t['transaction_cost_cents'],
          },
      ];
    }
    if (sql.contains('FROM classifications c') && sql.contains('JOIN classification_groups')) {
      // ClassificationDao.fetchFlatActiveClassifications
      final enabled = groups.where((g) => g['enabled'] == 1).map((g) => g['id']).toSet();
      final rows = classifications.where((c) => c['active'] == 1 && enabled.contains(c['group_id'])).toList()
        ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      return [
        for (final c in rows) {'id': c['id'], 'group_id': c['group_id'], 'name': c['name']},
      ];
    }
    throw UnsupportedError('FakeAnalyticsDb.rawQuery: unexpected sql "$sql"');
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (table == 'classification_groups') {
      return [...groups]..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    }
    if (table == 'classifications') {
      final groupId = whereArgs![0] as int;
      return classifications.where((c) => c['group_id'] == groupId && c['active'] == 1).toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    }
    if (table == 'transactions') {
      // TransactionDao.update's source_type pre-read.
      return [
        {'source_type': byId(whereArgs![0] as int)['source_type']},
      ];
    }
    throw UnsupportedError('FakeAnalyticsDb.query: unexpected table "$table"');
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table != 'transactions') throw UnsupportedError('FakeAnalyticsDb.update: unexpected table "$table"');
    final isRestore = values.length == 1 && values.containsKey('deleted_at') && values['deleted_at'] == null;
    if (isRestore && restoreError != null) throw restoreError!;
    if (!isRestore && !values.containsKey('deleted_at') && updateError != null) throw updateError!;
    final t = byId(whereArgs![0] as int);
    if (values.containsKey('classification_id') && values['classification_id'] != t['classification_id']) {
      t['_renamed'] = true;
    }
    t.addAll(values);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A transaction row for [FakeAnalyticsDb].
Map<String, Object?> fakeTx({
  required int id,
  required DateTime at,
  String type = 'SEND_MONEY',
  int amountCents = 10000,
  int? costCents,
  String? label,
  String? phone,
  String? account,
  String classification = 'Family/Friends',
  int? classificationId,
  String? code,
  int? deletedAt,
}) {
  final isCash = type == 'CASH';
  return {
    'id': id,
    'display_code': code ?? (isCash ? 'CASH-$id' : 'CODE$id'),
    'source_type': type,
    'amount_cents': amountCents,
    'transaction_cost_cents': isCash ? null : (costCents ?? 0),
    'counterparty_label': isCash ? null : (label ?? 'PARTY $id'),
    'counterparty_phone': type == 'SEND_MONEY' ? (phone ?? '0700000$id') : null,
    'paybill_account_number': type == 'PAYBILL' ? (account ?? '12345') : null,
    'classification_id': classificationId ?? 101,
    'classification_name': classification,
    'transaction_occurred_at': at.millisecondsSinceEpoch,
    'deleted_at': deletedAt,
  };
}

/// "Now" for the Analytics widget tests: Thu 24 Sep 2026, 13:30 (the mock's
/// sample day).
final analyticsTestNow = DateTime(2026, 9, 24, 13, 30);

/// The mock's sample data (the PM's debug seed), on [analyticsTestNow]:
///  - last 7 days (18–24 Sep): 1500 + 850 + 1200 + 500 = Ksh 4,050, fees 37;
///  - the week before (11–17 Sep): 300 + 2000 = Ksh 2,300;
///  - older: 3 Sep (640) and 15 Aug (1750, the first transaction).
List<Map<String, Object?>> analyticsSampleRows() => [
  fakeTx(id: 1, at: DateTime(2026, 9, 24, 9), label: 'JOHN KAMAU', amountCents: 150000, costCents: 2200),
  fakeTx(
    id: 2,
    at: DateTime(2026, 9, 24, 11),
    type: 'BUY_GOODS',
    label: 'NAIVAS SUPERMARKET',
    amountCents: 85000,
    classification: 'Shopping',
    classificationId: 110,
  ),
  fakeTx(
    id: 3,
    at: DateTime(2026, 9, 23, 14),
    type: 'PAYBILL',
    label: 'DSTV KENYA',
    amountCents: 120000,
    costCents: 1500,
    classification: 'Shopping',
    classificationId: 106,
  ),
  fakeTx(id: 4, at: DateTime(2026, 9, 20, 17), type: 'CASH', amountCents: 50000, classification: 'Groceries'),
  fakeTx(id: 5, at: DateTime(2026, 9, 15, 18), type: 'CASH', amountCents: 30000, classification: 'Transport'),
  fakeTx(
    id: 6,
    at: DateTime(2026, 9, 15, 10),
    label: 'MARY WANJIKU',
    phone: '0712345678',
    amountCents: 200000,
    costCents: 2500,
    classification: 'Rent',
    classificationId: 102,
  ),
  fakeTx(
    id: 7,
    at: DateTime(2026, 9, 3, 8),
    type: 'BUY_GOODS',
    label: 'JAVA HOUSE',
    amountCents: 64000,
    classification: 'Groceries',
  ),
  fakeTx(
    id: 8,
    at: DateTime(2026, 8, 15, 12),
    label: 'PETER OTIENO',
    amountCents: 175000,
    costCents: 2500,
    classification: 'Rent',
    classificationId: 102,
  ),
];

/// A stand-in for a failed write (e.g. a CHECK or UNIQUE violation), for
/// tests of the friendly-message paths.
class FakeDatabaseException implements DatabaseException {
  FakeDatabaseException([this.message = 'UNIQUE constraint failed: transactions.display_code (2067)']);

  final String message;

  @override
  String toString() => 'SqfliteFfiException($message)';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
