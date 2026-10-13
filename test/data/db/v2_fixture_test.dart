// DB2 (S3a): the frozen 0.1.1 (version 2) fixture, the frozen 12-entry seed
// list, the diff against the live 0.1.1 createSchema + seed, and the guard that
// the v1 -> v2 step never reads the live seed list.
//
// RETARGETED AT S3b: S3a compared the frozen v2 fixture with the LIVE
// createSchema/seed (empty diff). S3b switched the live schema to version 3, so
// the 0.1.1 side is now pinned two ways without weakening it: (1) a content
// digest of the frozen fixture's whole dump (schema text, sequences, seed rows),
// computed when the diff against the live 0.1.1 code was still empty; (2) a
// test that migrating an empty v2 fixture with the REAL ladder gives exactly a
// fresh v3 database.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v3.dart' show kV2TxColumns;
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/schema_v1.dart';
import '../../fixtures/schema_v2.dart';
import '../../fixtures/v2_fixture.dart';

const _tables = [
  'classification_groups',
  'classifications',
  'transactions',
  'counterparty_classification_map',
];

/// sqlite_master (without sqlite_% objects) + sqlite_sequence + every row of
/// every table, one string per line, created_at dropped (seed uses the clock).
Future<List<String>> dumpAll(Database db) async {
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
  for (final t in _tables) {
    final cols = (await db.rawQuery('PRAGMA table_info($t)'))
        .map((c) => c['name']! as String)
        .where((c) => c != 'created_at')
        .toList();
    for (final r in await db.rawQuery('SELECT ${cols.join(',')} FROM $t ORDER BY id')) {
      out.add('R|$t|${cols.map((c) => '${r[c]}').join('|')}');
    }
  }
  return out;
}

Future<Database> _mem(
    Future<void> Function(Database) create, Future<void> Function(Database) seed,
    {int version = 2}) async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: version,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) async {
            await create(db);
            await seed(db);
          }));
}

/// True when the body of `_toV2` in [migrationsSource] mentions the live
/// `AppSchema` (the defect this guard exists to catch).
bool toV2ReadsLiveSeedList(String migrationsSource) {
  final start = migrationsSource.indexOf('static Future<void> _toV2(');
  expect(start, greaterThan(-1), reason: '_toV2 not found');
  var depth = 0;
  var i = migrationsSource.indexOf('{', start);
  final bodyStart = i;
  for (; i < migrationsSource.length; i++) {
    final ch = migrationsSource[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  final body = migrationsSource.substring(bodyStart, i + 1);
  return body.contains('AppSchema') || body.contains('seedClassifications');
}

void main() {
  test('the frozen v2 seed list has exactly 12 entries (pin)', () {
    expect(AppMigrations.v2SeedClassifications, hasLength(12));
    expect(AppSchemaV2.seedClassifications, hasLength(12));
  });

  test('the frozen list equals the fixture list and the FIRST 12 of the live 17, entry by entry', () {
    expect(AppMigrations.v2SeedClassifications, AppSchemaV2.seedClassifications);
    expect(AppSchema.seedClassifications, hasLength(17));
    expect(AppMigrations.v2SeedClassifications, AppSchema.seedClassifications.take(12).toList());
    expect(AppMigrations.v2SeedClassifications.map((s) => s.seedKey).toSet(), hasLength(12));
  });

  /// FNV-1a 64-bit over the dump lines (no crypto package is allowed).
  int fnv(List<String> lines) {
    var h = 0xcbf29ce484222325;
    for (final c in lines.join('\n').codeUnits) {
      h ^= c;
      h *= 0x100000001b3;
    }
    return h;
  }

  // The digest was taken from the dump of the frozen fixture at S3b, when it
  // was still byte-for-byte equal to 0.1.1's createSchema + seed (S3a's diff was
  // empty; also re-proved against `git show v0.1.1:...schema.dart` in S3b).
  const frozenV2Digest = -4239865023994304132;

  test('the frozen v2 fixture still has the exact 0.1.1 shape (digest pin)', () async {
    final frozen = await _mem(AppSchemaV2.createSchema, AppSchemaV2.seed);
    final lines = await dumpAll(frozen);
    expect(lines.length, greaterThan(30), reason: 'the dump actually holds the schema and rows');
    expect(fnv(lines), frozenV2Digest);
    // and the facts the digest stands for, stated plainly
    expect(firstIntOf(await frozen.rawQuery('SELECT COUNT(*) FROM classification_groups')), 4);
    expect(firstIntOf(await frozen.rawQuery('SELECT COUNT(*) FROM classifications')), 12);
    expect(
        (await frozen.rawQuery('PRAGMA table_info(transactions)')).map((c) => c['name']).toList(),
        kV2TxColumns);
    await frozen.close();
  });

  test('an EMPTY v2 file migrated by the real ladder equals a FRESH v3 database', () async {
    final dir = Directory.systemTemp.createTempSync('mmogo_v2v3_');
    final path = '${dir.path}${Platform.pathSeparator}e.db';
    await (await buildV2Database(path, populate: false)).close();
    final migrated = await openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);
    final fresh = await _mem(AppSchema.createSchema, AppSchema.seed, version: 3);
    // SQLite quotes the table name when a table is renamed into place; that is the
    // only textual difference, and it is not a schema difference.
    // Untouched objects keep 0.1.1's formatting of the same statement, so
    // whitespace is collapsed before comparing.
    String norm(String l) => l
        .replaceAll('"classification_groups"', 'classification_groups')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('( ', '(')
        .replaceAll(' )', ')')
        .trim();
    // An INSERT .. SELECT of zero rows still leaves `transactions|0` in
    // sqlite_sequence (a fresh file has no row); both mean "next id is 1".
    bool notEmptySeq(String l) => l != 'S|transactions|0';
    final a = (await dumpAll(migrated)).map(norm).where(notEmptySeq).toList();
    final b = (await dumpAll(fresh)).map(norm).where(notEmptySeq).toList();
    expect(a.length, greaterThan(30));
    expect(a, b);
    await migrated.close();
    await fresh.close();
    dir.deleteSync(recursive: true);
  });

  test('NEGATIVE CONTROL: a one-character DDL change makes the diff non-empty', () async {
    final live = await _mem(AppSchemaV2.createSchema, AppSchemaV2.seed);
    final tampered = await _mem((db) async {
      await AppSchemaV2.createSchema(db);
      await db.execute('CREATE INDEX idx_extra ON transactions(amount_cents)');
    }, AppSchemaV2.seed);
    expect(await dumpAll(tampered), isNot(await dumpAll(live)));
    // and a changed seed name is caught as well
    final renamed = await _mem(AppSchemaV2.createSchema, (db) async {
      await AppSchemaV2.seed(db);
      await db.update('classifications', {'name': 'Rent!'}, where: 'id = 2');
    });
    expect(await dumpAll(renamed), isNot(await dumpAll(live)));
    await live.close();
    await tampered.close();
    await renamed.close();
  });

  test('the invented v2 fixture file is a healthy version-2 database', () async {
    final dir = Directory.systemTemp.createTempSync('mmogo_v2fx_');
    final db = await buildV2Database('${dir.path}${Platform.pathSeparator}v2.db');
    expect(firstIntOf(await db.rawQuery('PRAGMA user_version')), 2);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
    expect(firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM transactions')), 6);
    expect(firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM classifications')), 14);
    expect(
        firstIntOf(
            await db.rawQuery('SELECT COUNT(*) FROM counterparty_classification_map')),
        2);
    final sources = (await db.rawQuery('SELECT DISTINCT source_type FROM transactions'))
        .map((r) => r['source_type'])
        .toSet();
    expect(sources, {'SEND_MONEY', 'BUY_GOODS', 'PAYBILL', 'CASH'});
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('v1 -> v2 backfills seed_key from the FROZEN list (ids 1..12)', () async {
    final dir = Directory.systemTemp.createTempSync('mmogo_v1v2_');
    final path = '${dir.path}${Platform.pathSeparator}v1.db';
    sqfliteFfiInit();
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1,
            singleInstance: false,
            onCreate: (db, v) async {
              await AppSchemaV1.createSchema(db);
              await AppSchemaV1.seed(db);
            }));
    await v1.close();
    final db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 2, singleInstance: false, onUpgrade: AppMigrations.migrate));
    final keys = (await db.rawQuery('SELECT seed_key FROM classifications ORDER BY id'))
        .map((r) => r['seed_key'])
        .toList();
    expect(keys, AppMigrations.v2SeedClassifications.map((s) => s.seedKey).toList());
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('guard: _toV2 does not read the live seed list', () {
    final src = File('lib/data/db/migrations.dart').readAsStringSync();
    expect(toV2ReadsLiveSeedList(src), isFalse);
  });

  test('NEGATIVE CONTROL: the guard flags a _toV2 that reads the live list', () {
    final bad = File('lib/data/db/migrations.dart').readAsStringSync().replaceFirst(
        'i < _v2SeedClassifications.length', 'i < AppSchema.seedClassifications.length');
    expect(bad, contains('AppSchema.seedClassifications.length'));
    expect(toV2ReadsLiveSeedList(bad), isTrue);
  });
}
