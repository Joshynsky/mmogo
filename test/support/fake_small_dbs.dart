// Two tiny stand-in Databases for the S11b text-size matrix (a real sqflite
// database hangs inside testWidgets here): Profile's one summary query, and
// Recently deleted's list query. Invented rows only.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Profile: LocalDataSummaryDao's aggregate (count, min, max).
class FakeSummaryDb implements Database {
  FakeSummaryDb(this.occurredAt);
  final List<int> occurredAt;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {
      'tx_count': occurredAt.length,
      'min_occurred_at': occurredAt.isEmpty ? null : occurredAt.reduce((a, b) => a < b ? a : b),
      'max_occurred_at': occurredAt.isEmpty ? null : occurredAt.reduce((a, b) => a > b ? a : b),
    },
  ];

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Recently deleted: the soft-deleted list; purge deletes nothing.
class FakeDeletedDb implements Database {
  FakeDeletedDb(this.count);
  final int count;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (var i = 1; i <= count; i++)
        {
          'id': i,
          'display_code': 'THA7K2P9Q$i',
          'source_type': i.isEven ? 'PAYBILL' : 'SEND_MONEY',
          'amount_cents': 150000 * i,
          'counterparty_label': 'JOHN KAMAU WITH A LONG NAME $i',
          'classification_name': 'Family/Friends',
          'deleted_at': now - i * 60000,
        },
    ];
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
