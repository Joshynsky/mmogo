// B7: the onUpgrade ladder (lib/data/db/migrations.dart).
//
// The upgrade tests build a REAL 0.1.0 (version 1) database FILE from the
// frozen shipped schema (test/fixtures/schema_v1.dart), fill it with user data
// (renamed, deactivated and user-created classifications, every source type,
// a soft-deleted row, cash, the map), then open it through the same
// openDatabase(version: kDbVersion, onUpgrade: AppMigrations.migrate) call
// shape AppDatabase uses.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fixtures/schema_v1.dart';

const _tables = [
  'classification_groups',
  'classifications',
  'transactions',
  'counterparty_classification_map',
];

Future<void> _onConfigure(Database db) => db.execute('PRAGMA foreign_keys = ON');

Future<Database> _openV1(String path) => databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: _onConfigure,
        onCreate: (db, v) async {
          await AppSchemaV1.createSchema(db);
          await AppSchemaV1.seed(db);
        },
      ),
    );

/// Opens exactly the way AppDatabase does.
Future<Database> _openLatest(String path) => databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kDbVersion,
        onConfigure: _onConfigure,
        onCreate: (db, v) async {
          await AppSchema.createSchema(db);
          await AppSchema.seed(db);
        },
        onUpgrade: AppMigrations.migrate,
      ),
    );

Future<int> _groupId(Database db, String code) async => (await db.rawQuery(
        'SELECT id FROM classification_groups WHERE code = ?', [code]))
    .first['id'] as int;

/// Fills a v1 database like a phone that has been used for a while.
Future<void> _fillV1(Database db) async {
  final send = await _groupId(db, 'SEND_MONEY');
  final buy = await _groupId(db, 'BUY_GOODS');
  const t = 1790000000000;

  // Renamed built-ins (id 2 SEND_MONEY Rent, id 6 PAYBILL Shopping), one
  // deactivated built-in (id 12 BUY_GOODS Groceries).
  await db.update('classifications', {'name': 'House rent'}, where: 'id = 2');
  await db.update('classifications', {'name': 'Supermarket'}, where: 'id = 6');
  await db.update('classifications', {'active': 0}, where: 'id = 12');
  // User-created rows, including one that reuses a built-in's old name.
  final mine = await db.insert('classifications',
      {'group_id': send, 'name': 'Church', 'active': 1, 'created_at': t});
  final dupName = await db.insert('classifications',
      {'group_id': send, 'name': 'Rent', 'active': 1, 'created_at': t});
  final inactiveMine = await db.insert('classifications',
      {'group_id': buy, 'name': 'Old shop', 'active': 0, 'created_at': t});

  Future<void> tx(Map<String, Object?> m) => db.insert('transactions', {
        'transaction_cost_cents': 0,
        'raw_parse_source': 'MANUAL',
        'transaction_occurred_at': t,
        'created_at': t,
        ...m,
      }).then((_) {});

  await tx({
    'display_code': 'AAA1', 'source_type': 'SEND_MONEY', 'amount_cents': 150000,
    'counterparty_label': 'Jane', 'counterparty_phone': '0712345678',
    'classification_id': 2, 'raw_parse_source': 'SMS_PARSE',
  });
  await tx({
    'display_code': 'AAA2', 'source_type': 'SEND_MONEY', 'amount_cents': 5000,
    'classification_id': mine, // identity NULL
  });
  await tx({
    'display_code': 'BBB1', 'source_type': 'PAYBILL', 'amount_cents': 99900,
    'counterparty_label': 'KPLC', 'paybill_account_number': '123456',
    'classification_id': 6, 'transaction_cost_cents': 33,
  });
  await tx({
    'display_code': 'CCC1', 'source_type': 'BUY_GOODS', 'amount_cents': 4500,
    'counterparty_label': 'Duka', 'classification_id': 11,
  });
  await tx({
    'display_code': 'CASH-20261001-0900', 'source_type': 'CASH',
    'amount_cents': 20000, 'transaction_cost_cents': null,
    'classification_id': 3,
  });
  // Soft-deleted row: its code may be reused by a live row.
  await tx({
    'display_code': 'AAA1', 'source_type': 'SEND_MONEY', 'amount_cents': 700,
    'classification_id': 1, 'deleted_at': t + 5,
  });
  await tx({
    'display_code': 'DDD1', 'source_type': 'BUY_GOODS', 'amount_cents': 100,
    'classification_id': inactiveMine,
  });

  await db.insert('counterparty_classification_map', {
    'source_type': 'SEND_MONEY', 'counterparty_key': '0712345678',
    'classification_id': 2, 'auto_apply': 1, 'updated_at': t,
  });
  await db.insert('counterparty_classification_map', {
    'source_type': 'PAYBILL', 'counterparty_key': 'KPLC|123456',
    'classification_id': 6, 'auto_apply': 0, 'updated_at': t + 1,
  });
  await db.insert('counterparty_classification_map', {
    'source_type': 'BUY_GOODS', 'counterparty_key': 'DUKA',
    'classification_id': dupName, 'auto_apply': 0, 'updated_at': t + 2,
  });
}

Future<Map<String, List<Map<String, Object?>>>> _dump(Database db,
    {bool dropSeedKey = false}) async {
  final out = <String, List<Map<String, Object?>>>{};
  for (final t in _tables) {
    final rows = await db.rawQuery('SELECT * FROM $t ORDER BY id');
    out[t] = [
      for (final r in rows)
        {
          for (final e in r.entries)
            if (!(dropSeedKey && t == 'classifications' && e.key == 'seed_key'))
              e.key: e.value
        }
    ];
  }
  return out;
}

/// Shape of the schema independent of how it was created (ALTER TABLE rewrites
/// the stored CREATE text, so compare columns, indexes and triggers).
Future<Map<String, Object?>> _shape(Database db) async {
  final shape = <String, Object?>{};
  for (final t in _tables) {
    final cols = await db.rawQuery('PRAGMA table_info($t)');
    shape['cols:$t'] = {
      for (final c in cols)
        c['name'] as String:
            '${c['type']}|${c['notnull']}|${c['dflt_value']}|${c['pk']}'
    };
  }
  final master = await db.rawQuery(
      "SELECT type, name, tbl_name, sql FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' AND type IN ('index','trigger') "
      "ORDER BY name");
  shape['objects'] = {
    for (final m in master)
      '${m['type']}:${m['name']}':
          '${m['tbl_name']}|${(m['sql'] as String).replaceAll(RegExp(r'\s+'), ' ').trim()}'
  };
  return shape;
}

Future<int> _userVersion(Database db) async =>
    (await db.rawQuery('PRAGMA user_version')).first.values.first as int;

void main() {
  late Directory dir;
  late String path;

  setUpAll(sqfliteFfiInit);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('mmogo_mig_');
    path = p.join(dir.path, 'mmogo.db');
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('fresh install: version 2 with all 12 seed keys', () async {
    expect(kDbVersion, 2);
    final db = await _openLatest(path);
    expect(await _userVersion(db), 2);
    final rows = await db
        .rawQuery('SELECT id, name, seed_key FROM classifications ORDER BY id');
    expect(rows.length, 12);
    for (var i = 0; i < 12; i++) {
      expect(rows[i]['id'], i + 1);
      expect(rows[i]['seed_key'], AppSchema.seedClassifications[i].seedKey);
      expect(rows[i]['name'], AppSchema.seedClassifications[i].name);
    }
    expect(rows.map((r) => r['seed_key']).toSet().length, 12);
    await db.close();
  });

  test('v1 fixture really is the 0.1.0 shape (no seed_key, version 1)', () async {
    final db = await _openV1(path);
    expect(await _userVersion(db), 1);
    final cols = await db.rawQuery('PRAGMA table_info(classifications)');
    expect(cols.any((c) => c['name'] == 'seed_key'), isFalse);
    await db.close();
  });

  test('upgrade_v1_to_v2_keeps_every_row (real 0.1.0 database file)', () async {
    final v1 = await _openV1(path);
    await _fillV1(v1);
    final before = await _dump(v1);
    expect((before['transactions'] as List).length, 7);
    await v1.close();

    final db = await _openLatest(path);
    expect(await _userVersion(db), 2);

    // Data intact, row for row; seed_key is the only new column.
    expect(await _dump(db, dropSeedKey: true), before);

    // seed_key set on exactly the 12 built-ins (even renamed/deactivated ones).
    final rows = await db.rawQuery(
        'SELECT id, name, active, seed_key FROM classifications ORDER BY id');
    expect(rows.length, 15);
    for (var i = 0; i < 12; i++) {
      expect(rows[i]['seed_key'], AppSchema.seedClassifications[i].seedKey,
          reason: 'id ${i + 1}');
    }
    for (var i = 12; i < rows.length; i++) {
      expect(rows[i]['seed_key'], isNull, reason: 'user row id ${i + 1}');
    }
    // Renamed built-ins kept the user's names and their keys.
    expect(rows[1]['name'], 'House rent');
    expect(rows[1]['seed_key'], 'SEND_MONEY:rent');
    expect(rows[5]['name'], 'Supermarket');
    expect(rows[5]['seed_key'], 'PAYBILL:shopping');
    expect(rows[11]['active'], 0);
    expect(rows[11]['seed_key'], 'BUY_GOODS:groceries');

    expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test('upgraded schema equals a fresh v2 schema (columns, indexes, triggers)',
      () async {
    final v1 = await _openV1(path);
    await v1.close();
    final upgraded = await _openLatest(path);
    final upgradedShape = await _shape(upgraded);
    await upgraded.close();

    final fresh = await _openLatest(p.join(dir.path, 'fresh.db'));
    final freshShape = await _shape(fresh);
    await fresh.close();

    expect(upgradedShape, freshShape);
    final objects = (upgradedShape['objects'] as Map).keys;
    expect(
        objects,
        containsAll([
          'trigger:trg_transactions_classification_scope_ins',
          'trigger:trg_transactions_classification_scope_upd',
          'index:idx_transactions_mpesa_code',
          'index:idx_classifications_active_name',
          'index:idx_classifications_seed_key',
        ]));
  });

  test('after upgrade the triggers and unique indexes still fire', () async {
    final v1 = await _openV1(path);
    await _fillV1(v1);
    await v1.close();
    final db = await _openLatest(path);
    const t = 1790000001000;
    Map<String, Object?> row(String code, String src, int cls) => {
          'display_code': code,
          'source_type': src,
          'amount_cents': 100,
          'transaction_cost_cents': src == 'CASH' ? null : 0,
          'classification_id': cls,
          'raw_parse_source': 'MANUAL',
          'transaction_occurred_at': t,
          'created_at': t,
        };
    // group-scope trigger (insert): PAYBILL source with a SEND_MONEY class.
    await expectLater(
        db.insert('transactions', row('ZZZ1', 'PAYBILL', 1)), throwsA(anything));
    // group-scope trigger (update).
    final ok = await db.insert('transactions', row('ZZZ2', 'SEND_MONEY', 1));
    await expectLater(
        db.update('transactions', {'classification_id': 5},
            where: 'id = ?', whereArgs: [ok]),
        throwsA(anything));
    // M-Pesa code unique index (live rows).
    await expectLater(db.insert('transactions', row('ZZZ2', 'SEND_MONEY', 1)),
        throwsA(anything));
    // active-name unique index.
    await expectLater(
        db.insert('classifications', {
          'group_id': await _groupId(db, 'SEND_MONEY'),
          'name': 'Church',
          'active': 1,
          'created_at': t,
        }),
        throwsA(anything));
    // map UNIQUE(source_type, counterparty_key).
    await expectLater(
        db.insert('counterparty_classification_map', {
          'source_type': 'SEND_MONEY',
          'counterparty_key': '0712345678',
          'classification_id': 1,
          'auto_apply': 0,
          'updated_at': t,
        }),
        throwsA(anything));
    // seed_key unique index: a user row cannot claim a built-in's key.
    await expectLater(
        db.update('classifications', {'seed_key': 'SEND_MONEY:rent'},
            where: 'id = 13'),
        throwsA(anything));
    await db.close();
  });

  test('opening an already-upgraded database again is a no-op', () async {
    final v1 = await _openV1(path);
    await _fillV1(v1);
    await v1.close();
    var db = await _openLatest(path);
    final first = await _dump(db);
    final firstShape = await _shape(db);
    await db.close();

    db = await _openLatest(path);
    expect(await _userVersion(db), 2);
    expect(await _dump(db), first);
    expect(await _shape(db), firstShape);
    await db.close();
  });

  test('running the v2 step a second time changes nothing (idempotent)',
      () async {
    final v1 = await _openV1(path);
    await _fillV1(v1);
    await v1.close();
    final db = await _openLatest(path);
    final before = await _dump(db);
    final shapeBefore = await _shape(db);
    await db.transaction((txn) => AppMigrations.upgrade(txn, 1, 2));
    expect(await _dump(db), before);
    expect(await _shape(db), shapeBefore);
    await db.close();
  });

  test('a failing step rolls the upgrade back: file stays v1, content identical',
      () async {
    final v1 = await _openV1(path);
    await _fillV1(v1);
    final before = await _dump(v1);
    await v1.close();

    final failing = <int, Future<void> Function(DatabaseExecutor)>{
      2: (db) async {
        await AppMigrations.steps[2]!(db); // the real step runs, then...
        throw StateError('boom after the real step');
      },
    };
    await expectLater(
      databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: _onConfigure,
          onUpgrade: (db, o, n) =>
              AppMigrations.upgrade(db, o, n, steps: failing),
        ),
      ),
      throwsA(anything),
    );

    final db = await _openV1(path);
    expect(await _userVersion(db), 1);
    final cols = await db.rawQuery('PRAGMA table_info(classifications)');
    expect(cols.any((c) => c['name'] == 'seed_key'), isFalse);
    expect(await _dump(db), before);
    await db.close();
  });

  test('a missing step is an error, not a silent skip', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await expectLater(
        AppMigrations.upgrade(db, 1, 2, steps: {}), throwsStateError);
    await db.close();
  });
}
