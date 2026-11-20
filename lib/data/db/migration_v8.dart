import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migration_v8_ddl.dart';

/// §DATA.DB.MIGRATION_V8 — version 7 -> 8 (0.2.1, "recorded automatically" marker).
///
/// Additive: one `transactions` column, a partial index and two guard triggers from
/// `kV8Statements` (the same list a fresh install runs). Runs inside sqflite's single
/// `onUpgrade` transaction: any throw rolls the file back to version 7. Idempotent: the
/// column is added only when missing, the rest is `IF NOT EXISTS`.
///
/// Checked at the end: every old row is still there with the same amount, and no row reads
/// flagged (old rows are not back-filled).
Future<void> migrateToV8(DatabaseExecutor db) async {
  final before = await _fingerprint(db);
  final cols = {
    for (final c in await db.rawQuery('PRAGMA table_info(transactions)')) c['name'] as String,
  };
  for (final sql in kV8Statements) {
    if (sql == kV8AddRecordedColumn && cols.contains(kRecordedAutoColumnName)) continue;
    await db.execute(sql);
  }
  final after = await _fingerprint(db);
  if (after != before) throw StateError('v8: the existing transactions changed');
  final odd = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM transactions WHERE recorded_automatically != 0',
  );
  if (odd.first['n'] != 0) throw StateError('v8: an old row did not read 0');
}

/// Row count and the id/amount pairs: what this step must leave alone.
Future<String> _fingerprint(DatabaseExecutor db) async {
  final rows = await db.rawQuery('SELECT id, amount_cents FROM transactions ORDER BY id');
  return rows.map((r) => '${r['id']}:${r['amount_cents']}').join(',');
}
