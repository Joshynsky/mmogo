import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migration_v3_ddl.dart';
import 'migration_v3_rekey.dart';

/// §DATA.DB.MIGRATION_V3 — `_toV3`, the 0.1.1 -> 0.1.2 upgrade (S3b, DB4).
///
/// CRITICAL: this rebuilds `transactions` and `classification_groups` in the
/// real data of every 0.1.1 user. It runs inside sqflite's single `onUpgrade`
/// transaction (a throw rolls the whole file back to version 2), with
/// `PRAGMA foreign_keys = OFF` (set in `openMmogoDatabase`'s `onConfigure`,
/// because the pragma is a no-op inside a transaction).
///
/// Step list (one label per step, also the failure-injection points):
///   0  pre             capture the pre-state (read only); FK must be OFF
///   1  drop_triggers   drop both group-scope guard triggers
///   2  groups_*        rebuild `classification_groups` (6-code CHECK), ids kept
///   3  tx_*            rebuild `transactions` with the FROZEN 13 old columns
///   4  seq_restore     restore both AUTOINCREMENT counters
///   5  index_1..5      recreate the five `transactions` indexes
///   6  trigger_1..2    recreate the two triggers
///   6a rekey_*         SEND_MONEY learned-receiver phone re-key (CRITICAL)
///   7  group_ins_*     insert groups AGENT_WITHDRAWAL, AIRTIME if absent
///   8  pochi_*         enable the Pochi group; guarded rename to 'Pochi'
///   9  seed_N_*        five seeds: adopt an active user row, else insert
///   10 fk_check, invariants   integrity_check, foreign_key_check, digests
///
/// No pre-v3 copy of the database file is made (architecture.md E2/E9 and
/// decisions.md: declined; rollback is the transaction, the tests and the user's
/// own backup file).

/// FROZEN: the 13 `transactions` columns of version 2, in table order. The copy
/// in step 3 names exactly these. Using the live (14-column) list would raise
/// "no such column: agent_number" against the v2 table and make every 0.1.1
/// database unopenable. Never edit; a test proves it is not the live list.
const List<String> kV2TxColumns = [
  'id',
  'display_code',
  'source_type',
  'amount_cents',
  'transaction_cost_cents',
  'counterparty_label',
  'counterparty_phone',
  'paybill_account_number',
  'classification_id',
  'raw_parse_source',
  'transaction_occurred_at',
  'created_at',
  'deleted_at',
];

/// Adopt: a plain ACTIVE user row (no seed key) in the seed's group with the
/// seed's name becomes the built-in. Positional `?` only: [seedKey, name, group,
/// seedKey]. Case variants, inactive rows and other groups are not touched.
const String kV3AdoptSeedSql =
    'UPDATE classifications SET seed_key = ? '
    'WHERE seed_key IS NULL AND active = 1 AND name = ? '
    'AND group_id = (SELECT id FROM classification_groups WHERE code = ?) '
    'AND NOT EXISTS (SELECT 1 FROM classifications WHERE seed_key = ?)';

/// Insert the seed unless a row already holds its key. Positional `?` only:
/// [name, createdAt, seedKey, group, seedKey].
const String kV3InsertSeedSql =
    'INSERT INTO classifications (group_id, name, active, created_at, seed_key) '
    'SELECT g.id, ?, 1, ?, ? FROM classification_groups g '
    'WHERE g.code = ? AND NOT EXISTS (SELECT 1 FROM classifications WHERE seed_key = ?)';

/// Insert a group unless its code exists. Positional `?`: [code, displayName,
/// enabled, createdAt, code].
const String kV3InsertGroupSql =
    'INSERT INTO classification_groups (code, display_name, enabled, created_at) '
    'SELECT ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM classification_groups WHERE code = ?)';

/// Guarded Pochi rename (a value changed by anything else is never overwritten).
const String kV3PochiRenameSql =
    "UPDATE classification_groups SET display_name = 'Pochi' "
    "WHERE code = 'POCHI_LA_BIASHARA' AND display_name = 'Pochi La Biashara'";

/// Failure-injection hook (DBE T6.2): awaited ahead of each step with its label.
/// A test sets it to throw at one label; null in the app.
@visibleForTesting
Future<void> Function(String label)? migrateToV3Hook;

/// The re-key report of the most recent `_toV3` run in this process (counts only).
/// DB8 prints it for the real-copy gate. Null until a migration ran.
PhoneRekeyReport? lastPhoneRekeyReport;

/// `_toV3`. [txColumns] is a test seam (see [kV2TxColumns]); the app never
/// passes it.
Future<void> migrateToV3(
  DatabaseExecutor db, {
  List<String> txColumns = kV2TxColumns,
}) async {
  Future<void> at(String label) async {
    final h = migrateToV3Hook;
    if (h != null) await h(label);
  }

  // ---- 0. pre-state --------------------------------------------------------
  await at('pre');
  final fk = _int(await db.rawQuery('PRAGMA foreign_keys'));
  if (fk != 0) {
    throw StateError('_toV3 needs PRAGMA foreign_keys = OFF (table rebuild)');
  }
  final preCols = await db.rawQuery('PRAGMA table_info(transactions)');
  if (preCols.any((c) => c['name'] == 'agent_number')) {
    throw StateError('_toV3: transactions already has agent_number');
  }
  final preTx = await _txState(db);
  final preGroups = await _groupCodesById(db);
  final preBuiltIns = _int(await db.rawQuery(
      'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'));
  final preClassCount = _int(await db.rawQuery('SELECT COUNT(*) FROM classifications'));
  final preTxSeq = await _seq(db, 'transactions');
  final preGroupSeq = await _seq(db, 'classification_groups');
  final now = DateTime.now().millisecondsSinceEpoch;

  // ---- 1. triggers ---------------------------------------------------------
  await at('drop_triggers');
  await db.execute('DROP TRIGGER IF EXISTS trg_transactions_classification_scope_ins');
  await db.execute('DROP TRIGGER IF EXISTS trg_transactions_classification_scope_upd');

  // ---- 2. classification_groups (6-code CHECK) ------------------------------
  await at('groups_create');
  await db.execute(kV3GroupsDdl.replaceFirst(
      'CREATE TABLE classification_groups', 'CREATE TABLE classification_groups_new'));
  await at('groups_copy');
  await db.execute(
      'INSERT INTO classification_groups_new (id, code, display_name, enabled, created_at) '
      'SELECT id, code, display_name, enabled, created_at FROM classification_groups');
  await at('groups_drop');
  await db.execute('DROP TABLE classification_groups');
  await at('groups_rename');
  await db.execute('ALTER TABLE classification_groups_new RENAME TO classification_groups');

  // ---- 3. transactions (frozen 13-column copy) ------------------------------
  // `transactions` is referenced by no other table, so the old one is renamed
  // aside and the new one is created under its final name: the stored SQL text
  // is then identical to a fresh install's.
  await at('tx_rename_old');
  await db.execute('ALTER TABLE transactions RENAME TO transactions_old_v2');
  await at('tx_create');
  await db.execute(kV3TransactionsDdl);
  await at('tx_copy');
  final cols = txColumns.join(', ');
  await db.execute('INSERT INTO transactions ($cols) SELECT $cols FROM transactions_old_v2');
  await at('tx_drop');
  await db.execute('DROP TABLE transactions_old_v2');

  // ---- 4. AUTOINCREMENT counters --------------------------------------------
  await at('seq_restore');
  await _raiseSeq(db, 'transactions', preTxSeq);
  await _raiseSeq(db, 'classification_groups', preGroupSeq);

  // ---- 5. indexes, 6. triggers ----------------------------------------------
  for (var i = 0; i < kV3TransactionIndexes.length; i++) {
    await at('index_${i + 1}');
    await db.execute(kV3TransactionIndexes[i]);
  }
  for (var i = 0; i < kV3Triggers.length; i++) {
    await at('trigger_${i + 1}');
    await db.execute(kV3Triggers[i]);
  }

  // ---- 6a. phone re-key -------------------------------------------------------
  final report = await rekeySendMoneyKeys(db, before: at);
  lastPhoneRekeyReport = report;

  // ---- 7. new groups ----------------------------------------------------------
  const newGroupLabels = {'AGENT_WITHDRAWAL': 'group_ins_agent', 'AIRTIME': 'group_ins_airtime'};
  for (final g in kV3GroupSeeds) {
    final label = newGroupLabels[g.code];
    if (label == null) continue;
    await at(label);
    await db.rawInsert(kV3InsertGroupSql, [g.code, g.displayName, g.enabled, now, g.code]);
  }

  // ---- 8. Pochi ----------------------------------------------------------------
  await at('pochi_enable');
  await db.rawUpdate(
      "UPDATE classification_groups SET enabled = 1 WHERE code = 'POCHI_LA_BIASHARA'");
  await at('pochi_rename');
  await db.rawUpdate(kV3PochiRenameSql);

  // ---- 9. five seeds -------------------------------------------------------------
  for (var i = 0; i < kV3NewSeeds.length; i++) {
    final s = kV3NewSeeds[i];
    await at('seed_${i + 1}_adopt');
    await db.rawUpdate(kV3AdoptSeedSql, [s.seedKey, s.name, s.group, s.seedKey]);
    await at('seed_${i + 1}_insert');
    await db.rawInsert(kV3InsertSeedSql, [s.name, now, s.seedKey, s.group, s.seedKey]);
  }

  // ---- 10. checks -----------------------------------------------------------------
  await at('fk_check');
  final integrity = await db.rawQuery('PRAGMA integrity_check');
  if (integrity.length != 1 || integrity.first.values.first != 'ok') {
    throw StateError('_toV3: integrity_check failed');
  }
  final fkRows = await db.rawQuery('PRAGMA foreign_key_check');
  if (fkRows.isNotEmpty) {
    throw StateError('_toV3: foreign_key_check found ${fkRows.length} violation(s)');
  }

  await at('invariants');
  if (await _txState(db) != preTx) {
    throw StateError('_toV3: the transactions digest changed');
  }
  final cols14 = await db.rawQuery('PRAGMA table_info(transactions)');
  final agent = cols14.where((c) => c['name'] == 'agent_number').toList();
  if (cols14.length != 14 || agent.length != 1 || agent.first['notnull'] != 0) {
    throw StateError('_toV3: transactions is not the 14-column v3 shape');
  }
  if (_int(await db.rawQuery(
          'SELECT COUNT(*) FROM transactions WHERE agent_number IS NOT NULL')) !=
      0) {
    throw StateError('_toV3: agent_number is not NULL on migrated rows');
  }
  final postGroups = await _groupCodesById(db);
  for (final e in preGroups.entries) {
    if (postGroups[e.key] != e.value) {
      throw StateError('_toV3: a group id/code changed');
    }
  }
  if (postGroups.length != 6) {
    throw StateError('_toV3: expected 6 groups, found ${postGroups.length}');
  }
  final postBuiltIns = _int(await db.rawQuery(
      'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'));
  if (postBuiltIns != preBuiltIns + kV3NewSeeds.length) {
    throw StateError('_toV3: built-in count is $postBuiltIns, expected ${preBuiltIns + 5}');
  }
  final inserted = _int(await db.rawQuery('SELECT COUNT(*) FROM classifications')) - preClassCount;
  if (inserted < 0 || inserted > kV3NewSeeds.length) {
    throw StateError('_toV3: classifications changed by $inserted rows');
  }
}

int _int(List<Map<String, Object?>> rows) => (rows.first.values.first as int?) ?? 0;

/// The T2.4 digest plus per-source counts and sums, as one comparable string.
Future<String> _txState(DatabaseExecutor db) async {
  final d = await db.rawQuery(
    'SELECT COUNT(*), SUM(id), SUM(amount_cents), SUM(IFNULL(transaction_cost_cents,0)), '
    'SUM(transaction_occurred_at), SUM(created_at), SUM(IFNULL(deleted_at,0)), '
    "SUM(length(IFNULL(counterparty_label,''))), SUM(length(IFNULL(counterparty_phone,''))), "
    "SUM(length(IFNULL(paybill_account_number,''))), SUM(classification_id) FROM transactions",
  );
  final s = await db.rawQuery(
    'SELECT source_type, COUNT(*), SUM(amount_cents), SUM(IFNULL(transaction_cost_cents,0)) '
    'FROM transactions GROUP BY source_type ORDER BY source_type',
  );
  return '${d.first.values.join('|')}\n${s.map((r) => r.values.join('|')).join('\n')}';
}

Future<Map<int, String>> _groupCodesById(DatabaseExecutor db) async {
  final rows = await db.rawQuery('SELECT id, code FROM classification_groups');
  return {for (final r in rows) r['id'] as int: r['code'] as String};
}

Future<int?> _seq(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery('SELECT seq FROM sqlite_sequence WHERE name = ?', [table]);
  return rows.isEmpty ? null : rows.first['seq'] as int;
}

/// Makes `sqlite_sequence.seq` for [table] at least [old] (never lowers it).
Future<void> _raiseSeq(DatabaseExecutor db, String table, int? old) async {
  if (old == null) return;
  final cur = await _seq(db, table);
  if (cur == null) {
    await db.rawInsert('INSERT INTO sqlite_sequence (name, seq) VALUES (?, ?)', [table, old]);
  } else if (cur < old) {
    await db.rawUpdate('UPDATE sqlite_sequence SET seq = ? WHERE name = ?', [old, table]);
  }
}
