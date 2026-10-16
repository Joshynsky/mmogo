import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'open_classifier.dart';

/// §DATA.DB.OPEN_EVIDENCE — the real [OpenEvidence]: reads the database FILE
/// at [path] with read-only, `singleInstance: false` opens (0.1.2 S10c).
///
/// Both arguments are required: nothing here can reach the real file by
/// omission. Every method may throw; the classifier bounds and catches each.
/// It never writes, never deletes and never opens the file read-write.
class FileOpenEvidence implements OpenEvidence {
  FileOpenEvidence({required this.path, required this.factory});

  final String path;
  final DatabaseFactory factory;

  @override
  Future<int?> headerUserVersion() async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final raf = await file.open();
    try {
      final head = await raf.read(100);
      if (head.length < 64) return null;
      // SQLite magic: "SQLite format 3\0"
      const magic = 'SQLite format 3';
      for (var i = 0; i < magic.length; i++) {
        if (head[i] != magic.codeUnitAt(i)) return null;
      }
      return (head[60] << 24) | (head[61] << 16) | (head[62] << 8) | head[63];
    } finally {
      await raf.close();
    }
  }

  Future<Database> _openReadOnly() =>
      factory.openDatabase(path, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));

  @override
  Future<OpenSnapshot?> takeSnapshot() async {
    final header = await headerUserVersion();
    if (header == null) return null;
    final db = await _openReadOnly();
    try {
      final uv = firstInt(await db.rawQuery('PRAGMA user_version'));
      if (uv != header) return null;
      final fk = (await db.rawQuery('PRAGMA foreign_key_check')).length;
      final facts = <String, String>{};

      final master = await db.rawQuery('SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name');
      facts['master'] = master.map((r) => '${r['type']}|${r['name']}|${r['tbl_name']}|${r['sql']}').join('\n');
      final tables = master
          .where((r) => r['type'] == 'table' && !(r['name'] as String).startsWith('sqlite_'))
          .map((r) => r['name'] as String)
          .toList();
      for (final t in tables) {
        final r = (await db.rawQuery('SELECT COUNT(*) AS c, SUM(id) AS s, MAX(id) AS m FROM "$t"')).first;
        facts['table:$t'] = '${r['c']}|${r['s']}|${r['m']}';
      }
      if (tables.contains('transactions')) {
        // Summed here, not in SQL: this is a file-integrity fact, not a spending total.
        var amounts = 0, fees = 0;
        for (final r in await db.rawQuery('SELECT amount_cents AS a, transaction_cost_cents AS f FROM transactions')) {
          amounts += (r['a'] as int?) ?? 0;
          fees += (r['f'] as int?) ?? 0;
        }
        facts['tx:sums'] = '$amounts|$fees';
        final per = await db.rawQuery(
          'SELECT source_type AS s, COUNT(*) AS c FROM transactions GROUP BY source_type ORDER BY source_type',
        );
        facts['tx:sources'] = per.map((x) => '${x['s']}=${x['c']}').join(',');
      }
      if (tables.contains('sqlite_sequence') || master.any((r) => r['name'] == 'sqlite_sequence')) {
        final seq = await db.rawQuery('SELECT name, seq FROM sqlite_sequence ORDER BY name');
        facts['sequence'] = seq.map((x) => '${x['name']}=${x['seq']}').join(',');
      }
      // Canary reads: the four tables the app reads first must be readable.
      for (final t in const [
        'transactions',
        'classifications',
        'counterparty_classification_map',
        'classification_groups',
      ]) {
        final rows = await db.rawQuery('SELECT * FROM "$t" ORDER BY id LIMIT 3');
        facts['canary:$t'] = rows.map((x) => x.values.join('|')).join('\n');
      }
      return OpenSnapshot(userVersion: uv ?? -1, fkViolationRows: fk, facts: facts);
    } finally {
      await db.close();
    }
  }

  @override
  Future<bool> fileIsClean(OpenSnapshot before) async {
    final wal = File('$path-wal');
    if (wal.existsSync() && wal.lengthSync() > 0) return false;
    final journal = File('$path-journal');
    if (journal.existsSync() && journal.lengthSync() > 0) return false;
    final db = await _openReadOnly();
    try {
      final qc = await db.rawQuery('PRAGMA quick_check');
      if (qc.length != 1 || qc.first.values.first != 'ok') return false;
      final fk = (await db.rawQuery('PRAGMA foreign_key_check')).length;
      return fk == before.fkViolationRows;
    } finally {
      await db.close();
    }
  }

  static int? firstInt(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.isEmpty) return null;
    final v = rows.first.values.first;
    return v is int ? v : null;
  }
}
