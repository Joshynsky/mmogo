import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migration_v3_ddl.dart' show kV3Triggers;
import 'migration_v7_ddl.dart';

/// §DATA.DB.MIGRATION_V7 - version 6 -> 7 (0.2.1): the empty "Cash" category group.
///
/// Why a migration and not a lazy insert: `classification_groups.code` has a CHECK list of
/// six codes, and SQLite cannot alter a CHECK, so adding a code rebuilds that one small table
/// (the same steps `_toV3` uses, ids kept). Doing that on the first "+ New" would put a table
/// rebuild inside a user tap, and a restore or the Manage tab could meet a missing group first.
/// Runs inside sqflite's single `onUpgrade` transaction (a throw rolls the file back to 6),
/// with `PRAGMA foreign_keys = OFF` (set by `openMmogoDatabase`; a no-op inside a transaction).
///
/// Steps: drop the two group-scope guard triggers (they name `classification_groups`, and
/// RENAME re-parses them), rebuild the table with the 7-code CHECK, restore the AUTOINCREMENT
/// counter, recreate the triggers, insert the group (enabled, ZERO categories), then check
/// integrity, foreign keys, and that every old group keeps its id and code and no
/// classification or transaction changed. Idempotent: a table that already allows the code is
/// not rebuilt, and the group is inserted only when absent.
Future<void> migrateToV7(DatabaseExecutor db) async {
  final fk = (await db.rawQuery('PRAGMA foreign_keys')).first.values.first as int?;
  if (fk != 0) throw StateError('_toV7 needs PRAGMA foreign_keys = OFF (table rebuild)');

  final preGroups = await _groupCodesById(db);
  final preClassCount = await _count(db, 'classifications');
  final preTxCount = await _count(db, 'transactions');
  final now = DateTime.now().millisecondsSinceEpoch;

  final master = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='table' AND name='classification_groups'");
  final alreadyAllows = master.isNotEmpty && ((master.first['sql'] as String?) ?? '').contains(kCashUseGroupCode);
  if (!alreadyAllows) {
    final seq = await db.rawQuery("SELECT seq FROM sqlite_sequence WHERE name = 'classification_groups'");
    await db.execute('DROP TRIGGER IF EXISTS trg_transactions_classification_scope_ins');
    await db.execute('DROP TRIGGER IF EXISTS trg_transactions_classification_scope_upd');
    await db.execute(kV7GroupsDdl.replaceFirst('CREATE TABLE classification_groups', 'CREATE TABLE classification_groups_new'));
    await db.execute(
        'INSERT INTO classification_groups_new (id, code, display_name, enabled, created_at) '
        'SELECT id, code, display_name, enabled, created_at FROM classification_groups');
    await db.execute('DROP TABLE classification_groups');
    await db.execute('ALTER TABLE classification_groups_new RENAME TO classification_groups');
    if (seq.isNotEmpty) {
      final old = seq.first['seq']! as int;
      final cur = await db.rawQuery("SELECT seq FROM sqlite_sequence WHERE name = 'classification_groups'");
      if (cur.isEmpty) {
        await db.rawInsert("INSERT INTO sqlite_sequence (name, seq) VALUES ('classification_groups', ?)", [old]);
      } else if ((cur.first['seq']! as int) < old) {
        await db.rawUpdate("UPDATE sqlite_sequence SET seq = ? WHERE name = 'classification_groups'", [old]);
      }
    }
    for (final trigger in kV3Triggers) {
      await db.execute(trigger);
    }
  }

  await db.rawInsert(
    'INSERT INTO classification_groups (code, display_name, enabled, created_at) '
    'SELECT ?, ?, 1, ? WHERE NOT EXISTS (SELECT 1 FROM classification_groups WHERE code = ?)',
    [kCashUseGroupCode, kCashUseGroupName, now, kCashUseGroupCode],
  );

  final integrity = await db.rawQuery('PRAGMA integrity_check');
  if (integrity.length != 1 || integrity.first.values.first != 'ok') {
    throw StateError('_toV7: integrity_check failed');
  }
  if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
    throw StateError('_toV7: foreign_key_check found a violation');
  }
  final post = await _groupCodesById(db);
  for (final e in preGroups.entries) {
    if (post[e.key] != e.value) throw StateError('_toV7: a group id/code changed');
  }
  final hadGroup = preGroups.containsValue(kCashUseGroupCode);
  if (post.length != preGroups.length + (hadGroup ? 0 : 1)) {
    throw StateError('_toV7: unexpected group count ${post.length}');
  }
  if (await _count(db, 'classifications') != preClassCount) throw StateError('_toV7: classifications changed');
  if (await _count(db, 'transactions') != preTxCount) throw StateError('_toV7: transactions changed');
}

Future<int> _count(DatabaseExecutor db, String table) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']! as int;

Future<Map<int, String>> _groupCodesById(DatabaseExecutor db) async {
  final rows = await db.rawQuery('SELECT id, code FROM classification_groups');
  return {for (final r in rows) r['id']! as int: r['code']! as String};
}
