// DB2 (S3a): the frozen 0.1.1 (version 2) fixture, the frozen 12-entry seed
// list, the diff against the live 0.1.1 createSchema + seed, and the guard that
// the v1 -> v2 step never reads the live seed list.
//
// RETIRE/RETARGET AT S3b: the "live equals frozen" tests compare the frozen v2
// fixture with the LIVE createSchema/seed. They are meant to fail the moment S3b
// switches createSchema to version 3; S3b replaces the live side with the
// release-tag text. Everything else here stays.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
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
    Future<void> Function(Database) create, Future<void> Function(Database) seed) async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 2,
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

  test('the frozen list equals the fixture list and the live 0.1.1 list entry by entry', () {
    expect(AppMigrations.v2SeedClassifications, AppSchemaV2.seedClassifications);
    expect(AppMigrations.v2SeedClassifications, AppSchema.seedClassifications,
        reason: 'live is still the 12 of 0.1.1 (S3b retargets this line)');
    expect(AppMigrations.v2SeedClassifications.map((s) => s.seedKey).toSet(), hasLength(12));
  });

  test('diff: frozen v2 createSchema + seed vs live 0.1.1 createSchema + seed is EMPTY', () async {
    final live = await _mem(AppSchema.createSchema, AppSchema.seed);
    final frozen = await _mem(AppSchemaV2.createSchema, AppSchemaV2.seed);
    final a = await dumpAll(live);
    final b = await dumpAll(frozen);
    expect(a.length, greaterThan(30), reason: 'the dump actually holds the schema and rows');
    expect(b, a);
    await live.close();
    await frozen.close();
  });

  test('NEGATIVE CONTROL: a one-character DDL change makes the diff non-empty', () async {
    final live = await _mem(AppSchema.createSchema, AppSchema.seed);
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
