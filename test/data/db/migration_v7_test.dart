// 0.2.1 (PM #33): schema v7 = the empty "Cash" category group (`CASH_USE`) a withdrawal's chips
// use. `classification_groups` is rebuilt for its 7-code CHECK. Real temp ffi files; invented rows.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v7.dart';
import 'package:mmogo/data/db/migration_v7_ddl.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/v2_fixture.dart';

late Directory _dir;
int _n = 0;
String _path(String name) => '${_dir.path}/${name}_${_n++}.db';

Future<Database> _openLive(String path) => openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);

Future<Database> _openAt(String path, int version) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false, version: version);

Future<int> _uv(Database db) async => firstIntOf(await db.rawQuery('PRAGMA user_version'))!;

Future<int> _count(Database db, String sql, [List<Object?> args = const []]) async =>
    firstIntOf(await db.rawQuery(sql, args))!;

String _norm(Object? v) =>
    '$v'.replaceAll('"', '').replaceAll(RegExp(r'\s+'), ' ').replaceAll('( ', '(').replaceAll(' )', ')').trim();

Future<List<Map<String, Object?>>> _groups(Database db) => db.rawQuery('SELECT * FROM classification_groups ORDER BY id');

Future<List<String>> _objects(Database d) async => [
      for (final r in await d.rawQuery('SELECT type, name, tbl_name, sql FROM sqlite_master '
          "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"))
        _norm(r.values.join('|')),
    ];

/// A real version-6 file (a v2 fixture climbed to 6) holding a withdrawal and a linked Cash entry
/// whose category sits in Send Money (an entry made before the Cash list existed).
Future<String> _v6File() async {
  final path = _path('v6');
  await (await buildV2Database(path)).close();
  final db = await _openAt(path, 6);
  final withdrawal = await db.rawQuery("SELECT id FROM classifications WHERE seed_key = 'AGENT_WITHDRAWAL:cash_withdrawal'");
  final rent = await db.rawQuery("SELECT id FROM classifications WHERE seed_key = 'SEND_MONEY:rent'");
  final w = await db.insert('transactions', {
    'display_code': 'WDR0000001',
    'source_type': 'AGENT_WITHDRAWAL',
    'amount_cents': 500000,
    'transaction_cost_cents': 3500,
    'agent_number': '123456',
    'classification_id': withdrawal.first['id'],
    'raw_parse_source': 'SMS_PARSE',
    'transaction_occurred_at': kFixtureNow,
    'created_at': kFixtureNow,
  });
  await db.insert('transactions', {
    'display_code': 'CASH-20260101-0199',
    'source_type': 'CASH',
    'amount_cents': 100000,
    'classification_id': rent.first['id'],
    'raw_parse_source': 'MANUAL',
    'transaction_occurred_at': kFixtureNow,
    'created_at': kFixtureNow + 1,
    'parent_transaction_id': w,
  });
  await db.close();
  return path;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    _dir = Directory.systemTemp.createTempSync('mmogo_v7_');
  });
  tearDownAll(() {
    try {
      _dir.deleteSync(recursive: true);
    } on FileSystemException {
      // a handle still closing on Windows: the OS cleans the temp folder later
    }
  });

  test('the live version is 8 and the ladder has step 7', () {
    expect(kDbVersion, 8);
    expect(AppMigrations.steps.keys.last, 8);
  });

  test('a fresh install has the Cash group (enabled, last) and ZERO categories in it', () async {
    final db = await _openLive(_path('fresh'));
    expect(await _uv(db), 8);
    final groups = await _groups(db);
    expect(groups.map((g) => g['code']).last, kCashUseGroupCode);
    final g = groups.last;
    expect(g['display_name'], 'Cash');
    expect(g['enabled'], 1);
    expect(await _count(db, 'SELECT COUNT(*) FROM classifications WHERE group_id = ?', [g['id']]), 0);
    expect(await _count(db, 'SELECT COUNT(*) FROM classifications'), 18, reason: 'still the 18 built-ins');
    // the locked Withdrawal group is a different group
    expect(groups.where((x) => x['code'] == 'AGENT_WITHDRAWAL'), hasLength(1));
    await db.close();
  });

  test('the 7-code CHECK holds: an unknown group code is refused', () async {
    final db = await _openLive(_path('check'));
    await expectLater(
      db.insert('classification_groups', {'code': 'NOPE', 'display_name': 'x', 'enabled': 1, 'created_at': 1}),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });

  test('upgrade from 0.2.0 (v5 file): group added, empty, old groups and rows untouched', () async {
    final path = _path('v5');
    await (await buildV2Database(path)).close();
    final v5 = await _openAt(path, 5);
    final before = await _groups(v5);
    final txBefore = await _count(v5, 'SELECT COUNT(*) FROM transactions');
    final classBefore = await _count(v5, 'SELECT COUNT(*) FROM classifications');
    await v5.close();

    final db = await _openLive(path);
    expect(await _uv(db), 8);
    final after = await _groups(db);
    expect(after.length, before.length + 1);
    expect(after.take(before.length).toList(), before, reason: 'ids, codes, names, flags kept');
    expect(after.last['code'], kCashUseGroupCode);
    expect(after.last['enabled'], 1);
    expect(await _count(db, 'SELECT COUNT(*) FROM classifications WHERE group_id = ?', [after.last['id']]), 0);
    expect(await _count(db, 'SELECT COUNT(*) FROM classifications'), classBefore);
    expect(await _count(db, 'SELECT COUNT(*) FROM transactions'), txBefore);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(firstIntOf(await db.rawQuery('PRAGMA foreign_keys')), 1);
    await db.close();
  });

  test('upgrade from a v6 file keeps a linked Cash entry whose category is in another group', () async {
    final path = await _v6File();
    final db = await _openLive(path);
    expect(await _uv(db), 8);
    final rows = await db.rawQuery("SELECT t.display_code AS code, t.parent_transaction_id AS p, g.code AS grp "
        'FROM transactions t JOIN classifications c ON c.id = t.classification_id '
        "JOIN classification_groups g ON g.id = c.group_id WHERE t.display_code IN ('WDR0000001', 'CASH-20260101-0199') ORDER BY t.id");
    expect(rows.map((r) => '${r['code']}|${r['grp']}|${r['p'] != null}').toList(), [
      'WDR0000001|AGENT_WITHDRAWAL|false',
      'CASH-20260101-0199|SEND_MONEY|true',
    ]);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
    await db.close();
  });

  test('upgrade from earlier versions (v1 and v2 files) ends with the group present and empty', () async {
    final p2 = _path('v2');
    await (await buildV2Database(p2)).close();
    final d2 = await _openLive(p2);
    expect(await _uv(d2), 8);
    expect((await _groups(d2)).map((g) => g['code']).last, kCashUseGroupCode);
    expect(await _count(d2, "SELECT COUNT(*) FROM classifications WHERE group_id = (SELECT id FROM classification_groups WHERE code = 'CASH_USE')"), 0);
    await d2.close();

    final p3 = _path('v3');
    await (await buildV2Database(p3)).close();
    final d3 = await _openAt(p3, 3);
    await d3.close();
    final d3b = await _openLive(p3);
    expect(await _uv(d3b), 8);
    expect(await _count(d3b, "SELECT COUNT(*) FROM classification_groups WHERE code = 'CASH_USE'"), 1);
    await d3b.close();
  });

  test('the migrated group table, triggers and indexes read the same as a fresh install', () async {
    final path = await _v6File();
    final migrated = await _openLive(path);
    final fresh = await _openLive(_path('fresh2'));
    final a = await _objects(migrated);
    final b = await _objects(fresh);
    for (final name in ['classification_groups', 'trg_transactions_classification_scope_ins', 'trg_transactions_classification_scope_upd']) {
      expect(a.where((s) => s.contains('|$name|')).toList(), b.where((s) => s.contains('|$name|')).toList(), reason: name);
    }
    await migrated.close();
    await fresh.close();
  });

  test('the two group-scope triggers still guard after the rebuild; a CASH row may sit in the Cash group', () async {
    final db = await _openLive(await _v6File());
    final cashGroup = (await _groups(db)).last['id']! as int;
    final fare = await db.insert('classifications', {'group_id': cashGroup, 'name': 'Fare', 'active': 1, 'created_at': 1});
    final rent = (await db.rawQuery("SELECT id FROM classifications WHERE seed_key = 'SEND_MONEY:rent'")).first['id']!;
    Map<String, Object?> row(String source, Object cls, String code) => {
          'display_code': code,
          'source_type': source,
          'amount_cents': 1000,
          'classification_id': cls,
          'raw_parse_source': source == 'CASH' ? 'MANUAL' : 'SMS_PARSE',
          'transaction_occurred_at': kFixtureNow,
          'created_at': kFixtureNow + 5,
        };
    await db.insert('transactions', row('CASH', fare, 'CASH-20260101-0102'));
    // a Send Money row may not use a Cash-group category (group must match the source type)
    await expectLater(db.insert('transactions', {...row('SEND_MONEY', fare, 'SMX0000001'), 'counterparty_label': 'T', 'counterparty_phone': '0700000001'}),
        throwsA(isA<DatabaseException>()));
    await expectLater(db.insert('transactions', row('CASH', 999999, 'CASH-20260101-0103')), throwsA(isA<DatabaseException>()));
    expect(rent, isNotNull);
    await db.close();
  });

  test('the AUTOINCREMENT counter of the groups is kept (next group id is after the Cash group)', () async {
    final db = await _openLive(await _v6File());
    final last = (await _groups(db)).last['id']! as int;
    await db.execute("DELETE FROM classification_groups WHERE code = 'CASH_USE'");
    final again = await db.insert('classification_groups', {'code': 'CASH_USE', 'display_name': 'Cash', 'enabled': 1, 'created_at': 1});
    expect(again, greaterThan(last), reason: 'sqlite_sequence survived the rebuild');
    await db.close();
  });

  group('migrateToV7 directly', () {
    Future<Database> raw(String path, {required bool fkOn}) => databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            singleInstance: false, onConfigure: (db) => db.execute('PRAGMA foreign_keys = ${fkOn ? 'ON' : 'OFF'}')));

    test('is idempotent: a second run changes nothing and adds no second group', () async {
      final path = _path('idem');
      await (await _openLive(path)).close();
      final db = await raw(path, fkOn: false);
      final before = await _groups(db);
      final objectsBefore = await _objects(db);
      await migrateToV7(db);
      expect(await _groups(db), before);
      expect(await _objects(db), objectsBefore);
      await db.close();
    });

    test('adds the group to a v6-shaped database with the 6-code table (the real shape of a 0.2.0 file)', () async {
      final path = await _v6File();
      final db = await raw(path, fkOn: false);
      expect(await _count(db, "SELECT COUNT(*) FROM sqlite_master WHERE name = 'classification_groups' AND sql LIKE '%CASH_USE%'"), 0);
      await migrateToV7(db);
      expect(await _count(db, "SELECT COUNT(*) FROM sqlite_master WHERE name = 'classification_groups' AND sql LIKE '%CASH_USE%'"), 1);
      expect(await _count(db, "SELECT COUNT(*) FROM classification_groups WHERE code = 'CASH_USE'"), 1);
      await db.close();
    });

    test('refuses to run with foreign keys ON (a table rebuild needs them OFF)', () async {
      final path = await _v6File();
      final db = await raw(path, fkOn: true);
      await expectLater(migrateToV7(db), throwsA(isA<StateError>()));
      await db.close();
    });
  });

  test('a failure in the step leaves the v6 file intact and the next open succeeds', () async {
    final path = await _v6File();
    final v6 = await _openAt(path, 6);
    final before = await _objects(v6);
    final groupsBefore = await _groups(v6);
    await v6.close();
    Object? error;
    try {
      final db = await openMmogoDatabase(databaseFactoryFfi, path,
          singleInstance: false,
          onUpgrade: (db, a, b) => AppMigrations.upgrade(db, a, b, steps: {
                7: (d) async {
                  await migrateToV7(d);
                  throw StateError('injected after v7');
                },
              }));
      await db.close();
    } catch (e) {
      error = e;
    }
    expect(error, isA<StateError>());
    final raw = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    expect(await _uv(raw), 6, reason: 'rolled back');
    expect(await _objects(raw), before);
    expect(await _groups(raw), groupsBefore);
    await raw.close();
    final ok = await _openLive(path);
    expect(await _uv(ok), 8);
    expect(await _count(ok, "SELECT COUNT(*) FROM classification_groups WHERE code = 'CASH_USE'"), 1);
    await ok.close();
  });

  test('createSchema + seed and the migration agree: the same group list and the Cash group empty', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            onCreate: (db, v) async {
              await AppSchema.createSchema(db);
              await AppSchema.seed(db);
            },
            version: 7));
    expect((await _groups(db)).map((g) => g['code']).toList(),
        ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME', 'CASH_USE']);
    expect(await _count(db, "SELECT COUNT(*) FROM classifications c JOIN classification_groups g ON g.id = c.group_id WHERE g.code = 'CASH_USE'"), 0);
    await db.close();
  });
}
