// A small in-memory stand-in for the database, for the T27 Add-screen widget
// tests (test/ui/screens/add/add_screen_test.dart).
//
// A real sqflite_common_ffi Database hangs inside testWidgets in this
// environment (see manage_classifications_screen_test.dart's header) — same
// reason test/support/fake_analytics_db.dart exists for Analytics. This one
// answers exactly the calls the new Add screen's DAOs make, matched on table
// name / SQL text, not a SQL engine:
//  - ClassificationDao.fetchGroups / fetchActiveClassifications /
//    fetchFlatActiveClassifications / createClassification;
//  - CounterpartyDao.lookup / upsertOnConfirm / setAutoApply;
//  - TransactionDao.mpesaCodeExists / insert.
// The real SQL behind each is proven against in-memory sqlite in
// test/data/classification_dao_test.dart, test/data/counterparty_dao_test
// .dart and test/data/transaction_dao_test.dart — this fake exists only to
// drive the real widget/interaction logic deterministically.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeAddDb implements Database {
  FakeAddDb();

  final groups = <Map<String, Object?>>[
    {'id': 1, 'code': 'SEND_MONEY', 'display_name': 'Send Money', 'enabled': 1},
    {'id': 2, 'code': 'PAYBILL', 'display_name': 'Paybill', 'enabled': 1},
    {'id': 3, 'code': 'BUY_GOODS', 'display_name': 'Buy Goods', 'enabled': 1},
    {'id': 4, 'code': 'POCHI_LA_BIASHARA', 'display_name': 'Pochi La Biashara', 'enabled': 0},
  ];

  final classifications = <Map<String, Object?>>[
    {'id': 101, 'group_id': 1, 'name': 'Family/Friends', 'active': 1},
    {'id': 102, 'group_id': 1, 'name': 'Rent', 'active': 1},
    {'id': 105, 'group_id': 2, 'name': 'Utilities', 'active': 1},
    {'id': 109, 'group_id': 3, 'name': 'Shopping', 'active': 1},
  ];

  /// `counterparty_classification_map` rows.
  final counterpartyMap = <Map<String, Object?>>[];

  final transactions = <Map<String, Object?>>[];

  final List<Map<String, Object?>> insertedTransactions = [];
  final List<Map<String, Object?>> upsertCalls = [];
  final List<Map<String, Object?>> autoApplyCalls = [];

  int _nextClassificationId = 900;
  int _nextTransactionId = 1;

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
        ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
    }
    if (table == 'transactions') {
      // TransactionDao.mpesaCodeExists.
      final code = whereArgs![0] as String;
      final match = transactions.where(
        (t) => t['display_code'] == code && t['source_type'] != 'CASH' && t['deleted_at'] == null,
      );
      return match.isEmpty ? const [] : [
        {'id': match.first['id']},
      ];
    }
    throw UnsupportedError('FakeAddDb.query: unexpected table "$table"');
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final args = arguments ?? const [];
    if (sql.contains('FROM classifications c')) {
      final enabledGroupIds = groups.where((g) => g['enabled'] == 1).map((g) => g['id']).toSet();
      return classifications.where((c) => c['active'] == 1 && enabledGroupIds.contains(c['group_id'])).toList()
        ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    }
    if (sql.contains('FROM counterparty_classification_map')) {
      final sourceType = args[0] as String;
      final key = args[1] as String;
      final match = counterpartyMap.where((m) => m['source_type'] == sourceType && m['counterparty_key'] == key);
      if (match.isEmpty) return const [];
      final row = match.first;
      final classification = classifications.firstWhere((c) => c['id'] == row['classification_id']);
      final group = groups.firstWhere((g) => g['id'] == classification['group_id']);
      return [
        {
          'classification_id': classification['id'],
          'auto_apply': row['auto_apply'],
          'classification_name': classification['name'],
          'group_display_name': group['display_name'],
        },
      ];
    }
    throw UnsupportedError('FakeAddDb.rawQuery: unexpected sql "$sql"');
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'classifications') {
      final id = _nextClassificationId++;
      classifications.add({'id': id, 'group_id': values['group_id'], 'name': values['name'], 'active': 1});
      return id;
    }
    if (table == 'transactions') {
      final id = _nextTransactionId++;
      final row = {...values, 'id': id};
      transactions.add(row);
      insertedTransactions.add(row);
      return id;
    }
    throw UnsupportedError('FakeAddDb.insert: unexpected table "$table"');
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('INSERT INTO counterparty_classification_map')) {
      final args = arguments!;
      final sourceType = args[0] as String;
      final key = args[1] as String;
      final classificationId = args[2] as int;
      final updatedAt = args[3];
      upsertCalls.add({'source_type': sourceType, 'counterparty_key': key, 'classification_id': classificationId});
      final existing = counterpartyMap.where((m) => m['source_type'] == sourceType && m['counterparty_key'] == key);
      if (existing.isNotEmpty) {
        existing.first['classification_id'] = classificationId;
        existing.first['updated_at'] = updatedAt;
      } else {
        counterpartyMap.add({
          'source_type': sourceType,
          'counterparty_key': key,
          'classification_id': classificationId,
          'auto_apply': 0,
          'updated_at': updatedAt,
        });
      }
      return 1;
    }
    throw UnsupportedError('FakeAddDb.rawInsert: unexpected sql "$sql"');
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'counterparty_classification_map') {
      final sourceType = whereArgs![0] as String;
      final key = whereArgs[1] as String;
      autoApplyCalls.add({'source_type': sourceType, 'counterparty_key': key});
      final match = counterpartyMap.where((m) => m['source_type'] == sourceType && m['counterparty_key'] == key);
      if (match.isEmpty) return 0;
      match.first['auto_apply'] = 1;
      return 1;
    }
    throw UnsupportedError('FakeAddDb.update: unexpected table "$table"');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
