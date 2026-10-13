// Whole-database dump for before/after comparisons (S3b): every sqlite_master
// row, every sqlite_sequence row, every row of every table, ALL columns
// (created_at included). Two equal dumps mean the files hold the same data.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const dumpTables = [
  'classification_groups',
  'classifications',
  'transactions',
  'counterparty_classification_map',
];

Future<List<String>> fullDump(DatabaseExecutor db) async {
  final out = <String>[];
  final master = await db.rawQuery(
      "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
      'ORDER BY type, name');
  for (final r in master) {
    out.add('M|${r['type']}|${r['name']}|${r['tbl_name']}|${r['sql']}');
  }
  for (final r in await db.rawQuery('SELECT name, seq FROM sqlite_sequence ORDER BY name')) {
    out.add('S|${r['name']}|${r['seq']}');
  }
  for (final t in dumpTables) {
    final cols = (await db.rawQuery('PRAGMA table_info($t)'))
        .map((c) => c['name']! as String)
        .toList();
    for (final r in await db.rawQuery('SELECT ${cols.join(',')} FROM $t ORDER BY id')) {
      out.add('R|$t|${cols.map((c) => '${r[c]}').join('|')}');
    }
  }
  return out;
}

/// Rows of the learned-receiver map as `source|key|class|auto|updated`, by id.
Future<List<String>> mapRows(DatabaseExecutor db) async => (await db.rawQuery(
        'SELECT source_type, counterparty_key, classification_id, auto_apply, updated_at '
        'FROM counterparty_classification_map ORDER BY id'))
    .map((r) => r.values.join('|'))
    .toList();
