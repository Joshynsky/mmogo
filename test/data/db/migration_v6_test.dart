// 0.2.1: schema v6 = transactions.parent_transaction_id + cash_only_decided, an index and
// four guard triggers (additive). Real temp ffi files; invented rows only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v6.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/v2_fixture.dart';

late Directory _dir;
int _n = 0;
String _path(String name) => '${_dir.path}/${name}_${_n++}.db';

Future<Database> _openLive(String path) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);

Future<Database> _openAt(String path, int version) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false, version: version);

/// A real version-5 file (a v2 fixture climbed to 5) holding a withdrawal and its look-alikes.
Future<String> _v5File() async {
  final path = _path('v5');
  await (await buildV2Database(path)).close();
  final db = await _openAt(path, 5);
  final withdrawal = await db.rawQuery(
      "SELECT id FROM classifications WHERE seed_key = 'AGENT_WITHDRAWAL:cash_withdrawal'");
  await db.insert('transactions', {
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
  await db.close();
  return path;
}

Future<int> _uv(Database db) async => firstIntOf(await db.rawQuery('PRAGMA user_version'))!;

Future<int> _count(Database db, String sql) async => firstIntOf(await db.rawQuery(sql))!;

String _norm(Object? v) => '$v'.replaceAll('"', '').replaceAll(RegExp(r'\s+'), ' ').replaceAll('( ', '(').replaceAll(' )', ')').trim();

Future<List<String>> _objects(Database d) async => [
      for (final r in await d.rawQuery('SELECT type, name, tbl_name, sql FROM sqlite_master '
          "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"))
        _norm(r.values.join('|')),
    ];

Future<int> _firstWithdrawal(Database db) async =>
    firstIntOf(await db.rawQuery("SELECT id FROM transactions WHERE source_type = 'AGENT_WITHDRAWAL' LIMIT 1"))!;

Future<int> _cashClass(Database db) async =>
    firstIntOf(await db.rawQuery("SELECT id FROM classifications WHERE seed_key = 'SEND_MONEY:rent'"))!;

Map<String, Object?> _cash(int cls, {int? parent, int amount = 1000, String code = 'CASH-20260101-0101', int at = 1}) => {
      'display_code': code,
      'source_type': 'CASH',
      'amount_cents': amount,
      'classification_id': cls,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': kFixtureNow,
      'created_at': kFixtureNow + at,
      'parent_transaction_id': parent,
    };

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    _dir = Directory.systemTemp.createTempSync('mmogo_v6_');
  });
  tearDownAll(() {
    try {
      _dir.deleteSync(recursive: true);
    } on FileSystemException {
      // a handle still closing on Windows: the temp folder is cleaned by the OS later
    }
  });

  test('the live version is 8 and the ladder has step 6', () {
    expect(kDbVersion, 8);
    expect(AppMigrations.steps.keys, [2, 3, 4, 5, 6, 7, 8]);
  });

  test('v5 -> v6 with real rows: every old row keeps its values and reads parent NULL, decided 0', () async {
    final path = await _v5File();
    final v5 = await _openAt(path, 5);
    expect(await _uv(v5), 5);
    final before = [
      for (final r in await v5.rawQuery('SELECT * FROM transactions ORDER BY id')) {...r},
    ];
    expect(before.length, greaterThan(5));
    expect(before.any((r) => r['source_type'] == 'AGENT_WITHDRAWAL'), isTrue);
    await v5.close();

    final db = await _openLive(path);
    expect(await _uv(db), 8);
    final after = [for (final r in await db.rawQuery('SELECT * FROM transactions ORDER BY id')) {...r}];
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(after[i]['parent_transaction_id'], isNull);
      expect(after[i]['cash_only_decided'], 0);
      expect({...after[i]}..remove('parent_transaction_id')..remove('cash_only_decided')..remove('recorded_automatically'), before[i]);
    }
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
    expect(firstIntOf(await db.rawQuery('PRAGMA foreign_keys')), 1);
    await db.close();
  });

  test('a migrated file and a fresh file have the same schema objects (whitespace aside)', () async {
    final db = await _openLive(await _v5File());
    final fresh = await _openLive(_path('fresh'));
    final a = await _objects(db);
    expect(a, await _objects(fresh));
    expect(a.where((s) => s.contains('idx_transactions_parent')), hasLength(1));
    expect(a.where((s) => s.startsWith('trigger|trg_transactions_parent_link_')), hasLength(2));
    expect(a.where((s) => s.startsWith('trigger|trg_transactions_decided_')), hasLength(2));
    expect(a.where((s) => s.startsWith('trigger|trg_transactions_delete_pair')), hasLength(1));
    expect(a.where((s) => s.startsWith('trigger|trg_transactions_restore_')), hasLength(2));
    // negative control: a tampered file differs
    await db.execute('CREATE INDEX idx_extra ON transactions(amount_cents)');
    expect(await _objects(db), isNot(await _objects(fresh)));
    await db.close();
    await fresh.close();
  });

  test('the step is idempotent: a second run changes nothing and throws nothing', () async {
    final db = await _openLive(await _v5File());
    final before = await _objects(db);
    await migrateToV6(db);
    expect(await _objects(db), before);
    expect(await _count(db, 'SELECT COUNT(*) FROM transactions WHERE cash_only_decided != 0'), 0);
    await db.close();
  });

  test('a failure inside the step rolls the file back to a clean v5, the next open succeeds', () async {
    final path = await _v5File();
    Object? error;
    try {
      await openMmogoDatabase(databaseFactoryFfi, path,
          singleInstance: false,
          onUpgrade: (db, a, b) => AppMigrations.upgrade(db, a, b, steps: {
                6: (d) async {
                  await migrateToV6(d);
                  throw StateError('forced failure after the DDL ran');
                },
              }));
    } catch (e) {
      error = e;
    }
    expect(error, isA<StateError>());
    final raw = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    expect(await _uv(raw), 5);
    final cols = [for (final c in await raw.rawQuery('PRAGMA table_info(transactions)')) c['name']];
    expect(cols, isNot(contains('parent_transaction_id')));
    await raw.close();
    final db = await _openLive(path);
    expect(await _uv(db), 8);
    await db.close();
  });

  group('guard triggers and constraints (fresh file)', () {
    late Database db;
    late int withdrawal;
    late int cls;
    setUp(() async {
      db = await _openLive(_path('guards'));
      await db.insert('transactions', {
        'display_code': 'WDR0000001',
        'source_type': 'AGENT_WITHDRAWAL',
        'amount_cents': 500000,
        'transaction_cost_cents': 3500,
        'classification_id': firstIntOf(await db.rawQuery(
            "SELECT id FROM classifications WHERE seed_key = 'AGENT_WITHDRAWAL:cash_withdrawal'")),
        'raw_parse_source': 'SMS_PARSE',
        'transaction_occurred_at': kFixtureNow,
        'created_at': kFixtureNow,
      });
      withdrawal = await _firstWithdrawal(db);
      cls = await _cashClass(db);
    });
    tearDown(() => db.close());

    test('a Cash row may link to a withdrawal', () async {
      final id = await db.insert('transactions', _cash(cls, parent: withdrawal));
      expect(await _count(db, 'SELECT parent_transaction_id FROM transactions WHERE id = $id'), withdrawal);
    });

    test('a link on a non-Cash row is refused (insert and update)', () async {
      await expectLater(
        db.insert('transactions', {
          'display_code': 'SND0000001',
          'source_type': 'SEND_MONEY',
          'amount_cents': 100,
          'transaction_cost_cents': 0,
          'classification_id': cls,
          'raw_parse_source': 'SMS_PARSE',
          'transaction_occurred_at': kFixtureNow,
          'created_at': kFixtureNow,
          'parent_transaction_id': withdrawal,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.rawUpdate('UPDATE transactions SET parent_transaction_id = ? WHERE id = ?', [withdrawal, withdrawal]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('a link to a missing row or to a non-withdrawal row is refused', () async {
      await expectLater(db.insert('transactions', _cash(cls, parent: 99999)), throwsA(isA<DatabaseException>()));
      final plain = await db.insert('transactions', _cash(cls, code: 'CASH-20260101-0202', at: 2));
      await expectLater(
          db.insert('transactions', _cash(cls, parent: plain, code: 'CASH-20260101-0303', at: 3)),
          throwsA(isA<DatabaseException>()));
    });

    test('cash_only_decided: 0 or 1 only, and 1 only on a withdrawal', () async {
      await db.rawUpdate('UPDATE transactions SET cash_only_decided = 1 WHERE id = ?', [withdrawal]);
      await expectLater(
          db.rawUpdate('UPDATE transactions SET cash_only_decided = 2 WHERE id = ?', [withdrawal]),
          throwsA(isA<DatabaseException>()));
      final cash = await db.insert('transactions', _cash(cls));
      await expectLater(
          db.rawUpdate('UPDATE transactions SET cash_only_decided = 1 WHERE id = ?', [cash]),
          throwsA(isA<DatabaseException>()));
      await expectLater(
          db.insert('transactions', {..._cash(cls, code: 'CASH-20260101-0404', at: 4), 'cash_only_decided': 1}),
          throwsA(isA<DatabaseException>()));
    });

    test('a hard delete of the withdrawal leaves the entry as plain Cash (SET NULL)', () async {
      final id = await db.insert('transactions', _cash(cls, parent: withdrawal));
      await db.delete('transactions', where: 'id = ?', whereArgs: [withdrawal]);
      expect(await db.query('transactions', where: 'id = ? AND parent_transaction_id IS NULL', whereArgs: [id]),
          hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });
}
