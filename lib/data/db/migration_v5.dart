import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/airtime/airtime_kind.dart';
import 'migration_v5_ddl.dart';

/// §DATA.DB.MIGRATION_V5 — version 4 -> 5 (WBS row 17, Airtime kinds).
///
/// DATA ONLY, no table change: the existing `AIRTIME:airtime` category is renamed
/// "For myself" (its id and every entry in it stay), the category "For another
/// number" is added, and the kind-lock trigger is created. Runs inside sqflite's
/// single `onUpgrade` transaction: any throw rolls the file back to its old
/// version and rows. Every statement is guarded, so a second run changes nothing.
///
/// [afterInsert] is a test seam that runs right after the new category exists, to
/// prove a late failure rolls the whole step back.
Future<void> migrateToV5(
  DatabaseExecutor db, {
  @visibleForTesting Future<void> Function(DatabaseExecutor db)? afterInsert,
}) async {
  final groupRows = await db.rawQuery("SELECT id FROM classification_groups WHERE code = 'AIRTIME'");
  if (groupRows.isEmpty) throw StateError('v5: the AIRTIME group is missing');
  final groupId = groupRows.first['id']! as int;

  final before = await _fingerprint(db);

  final myself = await _seedRow(db, kAirtimeSeedMyself);
  if (myself == null) throw StateError('v5: the AIRTIME:airtime category is missing');
  if (myself['group_id'] != groupId) throw StateError('v5: AIRTIME:airtime is not in the AIRTIME group');
  final other = await _seedRow(db, kAirtimeSeedOther);
  if (other != null && other['group_id'] != groupId) {
    throw StateError('v5: AIRTIME:for_another_number is not in the AIRTIME group');
  }

  // A user row (no seed key) that already holds one of the two names is renamed
  // "<name> (2)" (then (3)...), never deleted, so the active-name index cannot fail.
  for (final name in [kAirtimeNameMyself, kAirtimeNameOther]) {
    final clash = await db.rawQuery(
      'SELECT id FROM classifications WHERE group_id = ? AND seed_key IS NULL AND name = ? COLLATE BINARY AND active = 1',
      [groupId, name],
    );
    for (final r in clash) {
      final newName = await _freeName(db, groupId, name);
      await db.rawUpdate('UPDATE classifications SET name = ? WHERE id = ?', [newName, r['id']]);
    }
  }

  await db.rawUpdate(
    'UPDATE classifications SET name = ?, active = 1 WHERE seed_key = ?',
    [kAirtimeNameMyself, kAirtimeSeedMyself],
  );
  if (other == null) {
    await db.insert('classifications', {
      'group_id': groupId,
      'name': kAirtimeNameOther,
      'active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'seed_key': kAirtimeSeedOther,
    });
  } else {
    await db.rawUpdate(
      'UPDATE classifications SET name = ?, active = 1 WHERE seed_key = ?',
      [kAirtimeNameOther, kAirtimeSeedOther],
    );
  }
  if (afterInsert != null) await afterInsert(db);

  await db.execute(kAirtimeKindTriggerDdl);

  // Assertions: exactly one row per seed key, transactions untouched.
  for (final k in [kAirtimeSeedMyself, kAirtimeSeedOther]) {
    final n = await db.rawQuery('SELECT COUNT(*) AS n FROM classifications WHERE seed_key = ?', [k]);
    if (n.first['n'] != 1) throw StateError('v5: seed key $k is not on exactly one row');
  }
  final after = await _fingerprint(db);
  if (after != before) throw StateError('v5: the transactions table changed');
}

Future<Map<String, Object?>?> _seedRow(DatabaseExecutor db, String key) async {
  final rows = await db.rawQuery('SELECT id, group_id FROM classifications WHERE seed_key = ?', [key]);
  return rows.isEmpty ? null : rows.first;
}

Future<String> _freeName(DatabaseExecutor db, int groupId, String name) async {
  final taken = {
    for (final r in await db.rawQuery('SELECT name FROM classifications WHERE group_id = ?', [groupId]))
      (r['name']! as String).toLowerCase(),
  };
  for (var i = 2;; i++) {
    final candidate = '$name ($i)';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
  }
}

/// What must not change in this step: the column list, the row count, the amount
/// sum, and how many AIRTIME rows sit in the other-number category.
Future<String> _fingerprint(DatabaseExecutor db) async {
  final cols = await db.rawQuery('PRAGMA table_info(transactions)');
  // Summed here (not in SQL): this is a check of what the step left alone, not a spending total.
  final amounts = await db.rawQuery('SELECT amount_cents FROM transactions ORDER BY id');
  final sum = amounts.fold<int>(0, (a, r) => a + (r['amount_cents']! as int));
  final inOther = await db.rawQuery(
    "SELECT COUNT(*) AS n FROM transactions t JOIN classifications c ON c.id = t.classification_id "
    "WHERE t.source_type = 'AIRTIME' AND c.seed_key = ?",
    [kAirtimeSeedOther],
  );
  final notMyself = await db.rawQuery(
    "SELECT COUNT(*) AS n FROM transactions t WHERE t.source_type = 'AIRTIME' "
    "AND t.classification_id != (SELECT id FROM classifications WHERE seed_key = ?)",
    [kAirtimeSeedMyself],
  );
  return '${cols.map((c) => '${c['name']}|${c['type']}|${c['notnull']}|${c['dflt_value']}|${c['pk']}').join(';')}'
      '#${amounts.length}#$sum#${inOther.first['n']}#${notMyself.first['n']}';
}
