import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migration_v6_ddl.dart';

/// §DATA.DB.MIGRATION_V6 — version 5 -> 6 (0.2.1, withdrawal with a linked Cash entry).
///
/// Additive: two `transactions` columns, an index and four guard triggers from
/// `kV6Statements` (the same list a fresh install runs). Runs inside sqflite's single
/// `onUpgrade` transaction: any throw rolls the file back to version 5. Idempotent:
/// each column is added only when missing, the rest is `IF NOT EXISTS`.
///
/// Checked at the end: every old row is still there with the same amount, and reads
/// parent NULL and decided 0.
Future<void> migrateToV6(DatabaseExecutor db) async {
  final before = await _fingerprint(db);
  final cols = {
    for (final c in await db.rawQuery('PRAGMA table_info(transactions)')) c['name'] as String,
  };
  for (final sql in kV6Statements) {
    if (sql == kV6AddParentColumn && cols.contains(kParentColumnName)) continue;
    if (sql == kV6AddDecidedColumn && cols.contains(kCashOnlyDecidedColumnName)) continue;
    await db.execute(sql);
  }
  final after = await _fingerprint(db);
  if (after != before) throw StateError('v6: the existing transactions changed');
  final odd = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM transactions '
    'WHERE parent_transaction_id IS NOT NULL OR cash_only_decided != 0',
  );
  if (odd.first['n'] != 0) throw StateError('v6: an old row did not read NULL / 0');
}

/// Row count and the id/amount pairs: what this step must leave alone.
Future<String> _fingerprint(DatabaseExecutor db) async {
  final rows = await db.rawQuery('SELECT id, amount_cents FROM transactions ORDER BY id');
  return rows.map((r) => '${r['id']}:${r['amount_cents']}').join(',');
}
