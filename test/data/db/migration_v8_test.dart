// 0.2.1: schema v8 = transactions.recorded_automatically (0/1), a partial index and two guard
// triggers (additive). Real temp ffi files; invented rows only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v8.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/domain/money/spent_amount.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/v2_fixture.dart';

late Directory _dir;
int _n = 0;
String _path(String name) => '${_dir.path}/${name}_${_n++}.db';

Future<Database> _openLive(String path) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);

Future<Database> _openAt(String path, int version) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false, version: version);

Future<int> _uv(Database db) async => firstIntOf(await db.rawQuery('PRAGMA user_version'))!;
Future<int> _count(Database db, String sql) async => firstIntOf(await db.rawQuery(sql))!;

String _norm(Object? v) =>
    '$v'.replaceAll('"', '').replaceAll(RegExp(r'\s+'), ' ').replaceAll('( ', '(').replaceAll(' )', ')').trim();

Future<List<String>> _objects(Database d) async => [
      for (final r in await d.rawQuery('SELECT type, name, tbl_name, sql FROM sqlite_master '
          "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"))
        _norm(r.values.join('|')),
    ];

Future<int> _seed(Database db, String key) async =>
    firstIntOf(await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [key]))!;

Map<String, Object?> _row(int cls, String code, String source, {int at = 0, String raw = 'SMS_PARSE'}) => {
      'display_code': code,
      'source_type': source,
      'amount_cents': 10000 + at,
      'transaction_cost_cents': source == 'CASH' ? null : 500,
      'classification_id': cls,
      'raw_parse_source': raw,
      'transaction_occurred_at': kFixtureNow + at,
      'created_at': kFixtureNow + at,
      if (source == 'SEND_MONEY') 'counterparty_label': 'TEST PERSON',
      if (source == 'SEND_MONEY') 'counterparty_phone': '0712345678',
      if (source == 'PAYBILL') 'counterparty_label': 'TEST CO',
    };

/// A real version-7 file (a v2 fixture climbed to 7) with mixed sources, a withdrawal with a
/// linked Cash entry, a Cash-group entry and soft-deleted rows.
Future<String> _v7File() async {
  final path = _path('v7');
  await (await buildV2Database(path)).close();
  final db = await _openAt(path, 7);
  final rent = await _seed(db, 'SEND_MONEY:rent');
  final pay = await _seed(db, 'PAYBILL:rent_payment');
  final goods = await _seed(db, 'BUY_GOODS:groceries');
  final wd = await _seed(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
  final air = await _seed(db, 'AIRTIME:airtime');
  final pochi = await _seed(db, 'POCHI_LA_BIASHARA:transport');
  final cashGroup = await db.insert('classifications', {
    'group_id': firstIntOf(await db.rawQuery("SELECT id FROM classification_groups WHERE code = 'CASH_USE'")),
    'name': 'Soap',
    'active': 1,
    'created_at': kFixtureNow,
  });
  await db.insert('transactions', _row(rent, 'SND0000001', 'SEND_MONEY', at: 1));
  await db.insert('transactions', {..._row(pay, 'PAY0000001', 'PAYBILL', at: 2), 'paybill_account_number': '123'});
  await db.insert('transactions', _row(goods, 'BUY0000001', 'BUY_GOODS', at: 3));
  await db.insert('transactions', _row(air, 'AIR0000001', 'AIRTIME', at: 4));
  await db.insert('transactions', _row(pochi, 'POC0000001', 'POCHI_LA_BIASHARA', at: 5));
  final w = await db.insert('transactions', {..._row(wd, 'WDR0000001', 'AGENT_WITHDRAWAL', at: 6), 'agent_number': '123456'});
  await db.insert('transactions',
      {..._row(rent, 'CASH-20260101-0101', 'CASH', at: 7, raw: 'MANUAL'), 'parent_transaction_id': w});
  await db.insert('transactions', _row(cashGroup, 'CASH-20260101-0102', 'CASH', at: 8, raw: 'MANUAL'));
  await db.insert('transactions', {..._row(rent, 'SND0000002', 'SEND_MONEY', at: 9), 'deleted_at': kFixtureNow + 99});
  await db.insert('transactions', _row(rent, 'MAN0000001', 'SEND_MONEY', at: 10, raw: 'MANUAL'));
  await db.close();
  return path;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    _dir = Directory.systemTemp.createTempSync('mmogo_v8_');
  });
  tearDownAll(() {
    try {
      _dir.deleteSync(recursive: true);
    } on FileSystemException {
      // a handle still closing on Windows: the OS cleans the temp folder later
    }
  });

  test('the live version is 8 and the ladder has step 8', () {
    expect(kDbVersion, 8);
    expect(AppMigrations.steps.keys, [2, 3, 4, 5, 6, 7, 8]);
  });

  test('v7 -> v8 with real rows: every old row keeps its values and reads flag 0 (not back-filled)', () async {
    final path = await _v7File();
    final v7 = await _openAt(path, 7);
    expect(await _uv(v7), 7);
    final before = [for (final r in await v7.rawQuery('SELECT * FROM transactions ORDER BY id')) {...r}];
    expect(before.length, 16); // 6 from the v2 fixture + 10 added here
    expect(before.any((r) => r['deleted_at'] != null), isTrue);
    expect(before.any((r) => r['parent_transaction_id'] != null), isTrue);
    await v7.close();

    final db = await _openLive(path);
    expect(await _uv(db), 8);
    final after = [for (final r in await db.rawQuery('SELECT * FROM transactions ORDER BY id')) {...r}];
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(after[i]['recorded_automatically'], 0);
      expect({...after[i]}..remove('recorded_automatically'), before[i]);
    }
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
    expect(firstIntOf(await db.rawQuery('PRAGMA foreign_keys')), 1);
    await db.close();
  });

  test('a migrated file and a fresh file have the same schema objects (whitespace aside)', () async {
    final db = await _openLive(await _v7File());
    final fresh = await _openLive(_path('fresh'));
    final a = await _objects(db);
    expect(a, await _objects(fresh));
    expect(a.where((s) => s.contains('idx_transactions_auto')), hasLength(1));
    expect(a.where((s) => s.startsWith('trigger|trg_transactions_auto_')), hasLength(2));
    await db.execute('CREATE INDEX idx_extra ON transactions(amount_cents)');
    expect(await _objects(db), isNot(await _objects(fresh))); // negative control
    await db.close();
    await fresh.close();
  });

  test('the step is idempotent, also from a half-applied file (column there, rest missing)', () async {
    final db = await _openLive(await _v7File());
    final before = await _objects(db);
    await migrateToV8(db);
    expect(await _objects(db), before);
    await db.execute('DROP TRIGGER trg_transactions_auto_ins');
    await db.execute('DROP INDEX idx_transactions_auto');
    await migrateToV8(db);
    expect(await _objects(db), before);
    expect(await _count(db, 'SELECT COUNT(*) FROM transactions WHERE recorded_automatically != 0'), 0);
    await db.close();
  });

  test('the step throws when a row is flagged afterwards (an old row must read 0)', () async {
    final db = await _openLive(await _v7File());
    await db.execute("UPDATE transactions SET recorded_automatically = 1 WHERE display_code = 'SND0000001'");
    await expectLater(migrateToV8(db), throwsA(isA<StateError>()));
    await db.close();
  });

  test('a failure inside the step rolls the file back to a clean v7, the next open succeeds', () async {
    final path = await _v7File();
    Object? error;
    try {
      await openMmogoDatabase(databaseFactoryFfi, path,
          singleInstance: false,
          onUpgrade: (db, a, b) => AppMigrations.upgrade(db, a, b, steps: {
                8: (d) async {
                  await migrateToV8(d);
                  throw StateError('forced failure after the DDL ran');
                },
              }));
    } catch (e) {
      error = e;
    }
    expect(error, isA<StateError>());
    final raw = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    expect(await _uv(raw), 7);
    final cols = [for (final c in await raw.rawQuery('PRAGMA table_info(transactions)')) c['name']];
    expect(cols, isNot(contains('recorded_automatically')));
    expect(await _count(raw, 'SELECT COUNT(*) FROM transactions'), 16);
    await raw.close();
    final db = await _openLive(path);
    expect(await _uv(db), 8);
    await db.close();
  });

  group('triggers and constraints (fresh file)', () {
    late Database db;
    late int rent;
    setUp(() async {
      db = await _openLive(_path('guards'));
      rent = await _seed(db, 'SEND_MONEY:rent');
    });
    tearDown(() => db.close());

    test('an automatic SMS-parse row for each non-Cash source is accepted', () async {
      for (final (src, key, extra) in [
        ('SEND_MONEY', 'SEND_MONEY:rent', <String, Object?>{}),
        ('PAYBILL', 'PAYBILL:rent_payment', <String, Object?>{'paybill_account_number': '123'}),
        ('BUY_GOODS', 'BUY_GOODS:groceries', <String, Object?>{}),
        ('AIRTIME', 'AIRTIME:airtime', <String, Object?>{}),
        ('POCHI_LA_BIASHARA', 'POCHI_LA_BIASHARA:transport', <String, Object?>{}),
      ]) {
        await db.insert('transactions',
            {..._row(await _seed(db, key), 'A$src', src), ...extra, 'recorded_automatically': 1});
      }
      expect(await _count(db, 'SELECT COUNT(*) FROM transactions WHERE recorded_automatically = 1'), 5);
    });

    test('flag 1 on a CASH row or a MANUAL row is refused (insert)', () async {
      await expectLater(
          db.insert('transactions',
              {..._row(rent, 'CASH-20260101-0101', 'CASH', raw: 'MANUAL'), 'recorded_automatically': 1}),
          throwsA(isA<DatabaseException>()));
      await expectLater(
          db.insert('transactions',
              {..._row(rent, 'SND0000009', 'SEND_MONEY', raw: 'MANUAL'), 'recorded_automatically': 1}),
          throwsA(isA<DatabaseException>()));
    });

    test('setting the flag, or changing source/raw on a flagged row, is refused (update)', () async {
      final manual = await db.insert('transactions', _row(rent, 'SND0000001', 'SEND_MONEY', raw: 'MANUAL'));
      await expectLater(db.rawUpdate('UPDATE transactions SET recorded_automatically = 1 WHERE id = ?', [manual]),
          throwsA(isA<DatabaseException>()));
      final auto =
          await db.insert('transactions', {..._row(rent, 'SND0000002', 'SEND_MONEY', at: 1), 'recorded_automatically': 1});
      await expectLater(db.rawUpdate("UPDATE transactions SET raw_parse_source = 'MANUAL' WHERE id = ?", [auto]),
          throwsA(isA<DatabaseException>()));
      expect(await _count(db, 'SELECT recorded_automatically FROM transactions WHERE id = $auto'), 1);
    });

    test('only 0 or 1; NULL is refused; the default is 0', () async {
      await expectLater(
          db.insert('transactions', {..._row(rent, 'SND0000003', 'SEND_MONEY'), 'recorded_automatically': 2}),
          throwsA(isA<DatabaseException>()));
      await expectLater(
          db.insert('transactions', {..._row(rent, 'SND0000004', 'SEND_MONEY'), 'recorded_automatically': null}),
          throwsA(isA<DatabaseException>()));
      final id = await db.insert('transactions', _row(rent, 'SND0000005', 'SEND_MONEY'));
      expect(await _count(db, 'SELECT recorded_automatically FROM transactions WHERE id = $id'), 0);
    });

    test('Undo (soft delete) and restore keep the flag at 1', () async {
      final id =
          await db.insert('transactions', {..._row(rent, 'SND0000006', 'SEND_MONEY'), 'recorded_automatically': 1});
      await db.rawUpdate('UPDATE transactions SET deleted_at = 5 WHERE id = ?', [id]);
      expect(await _count(db, 'SELECT recorded_automatically FROM transactions WHERE id = $id'), 1);
      await db.rawUpdate('UPDATE transactions SET deleted_at = NULL WHERE id = ?', [id]);
      expect(await _count(db, 'SELECT recorded_automatically FROM transactions WHERE id = $id'), 1);
    });
  });

  group('the history filter query and the read models', () {
    test('only live flagged rows, newest written first, id breaks ties, optional created_at window', () async {
      final db = await _openLive(_path('filter'));
      final rent = await _seed(db, 'SEND_MONEY:rent');
      Future<int> add(String code, int at, {int auto = 1, int? deleted}) => db.insert('transactions', {
            ..._row(rent, code, 'SEND_MONEY', at: at),
            'recorded_automatically': auto,
            'deleted_at': deleted,
          });
      await add('SND0000001', 10);
      await add('SND0000002', 30);
      final tieA = await add('SND0000003', 20);
      final tieB = await add('SND0000004', 20);
      await add('SND0000005', 40, auto: 0);
      await add('SND0000006', 50, deleted: 7);
      final all = await AnalyticsDao.recordedAutomatically(db);
      expect([for (final r in all) r.displayCode], ['SND0000002', 'SND0000004', 'SND0000003', 'SND0000001']);
      expect(tieB, greaterThan(tieA));
      expect(all.every((r) => r.recordedAutomatically), isTrue);
      final win = await AnalyticsDao.recordedAutomatically(db,
          sinceCreatedMs: kFixtureNow + 20, untilCreatedMs: kFixtureNow + 30);
      expect([for (final r in win) r.displayCode], ['SND0000004', 'SND0000003']);
      // The partial index is usable for this predicate (the planner may still pick another
      // index on a tiny table; INDEXED BY proves the index can serve the query).
      final viaIndex = await db.rawQuery('SELECT id FROM transactions INDEXED BY idx_transactions_auto '
          'WHERE recorded_automatically = 1 AND deleted_at IS NULL ORDER BY created_at DESC, id DESC');
      expect(viaIndex, hasLength(4));
      final listed = await AnalyticsDao.byCodes(db, {'SND0000005', 'SND0000001'});
      expect({for (final r in listed) r.displayCode: r.recordedAutomatically},
          {'SND0000005': false, 'SND0000001': true});
      await db.close();
    });

    test('the spend rule is unchanged: a flagged row spends exactly what an unflagged one does', () async {
      final db = await _openLive(_path('spend'));
      final rent = await _seed(db, 'SEND_MONEY:rent');
      final id = await db.insert('transactions', _row(rent, 'SND0000001', 'SEND_MONEY'));
      final plain = (await AnalyticsDao.byCodes(db, {'SND0000001'})).single;
      await db.rawUpdate('UPDATE transactions SET recorded_automatically = 1 WHERE id = ?', [id]);
      final flagged = (await AnalyticsDao.byCodes(db, {'SND0000001'})).single;
      expect(flagged.recordedAutomatically, isTrue);
      expect(flagged.spent, plain.spent);
      expect(flagged.spent, spentCents('SEND_MONEY', 10000, 500));
      await db.close();
    });
  });

  test('50,000 rows migrate v7 -> v8 inside the budget, untouched', () async {
    final path = _path('big');
    await (await buildV2Database(path)).close();
    final v7 = await _openAt(path, 7);
    final rent = await _seed(v7, 'SEND_MONEY:rent');
    final batch = v7.batch();
    for (var i = 0; i < 50000; i++) {
      batch.insert('transactions', _row(rent, 'B${i.toString().padLeft(9, '0')}', 'SEND_MONEY', at: i));
    }
    await batch.commit(noResult: true);
    final total = await _count(v7, 'SELECT COUNT(*) FROM transactions');
    expect(total, greaterThanOrEqualTo(50000));
    await v7.close();
    final sw = Stopwatch()..start();
    final db = await _openLive(path);
    sw.stop();
    // ignore: avoid_print
    print('v7 -> v8 on 50,000 rows: ${sw.elapsedMilliseconds} ms (incl. open)');
    expect(await _uv(db), 8);
    expect(await _count(db, 'SELECT COUNT(*) FROM transactions'), total);
    expect(await _count(db, 'SELECT COUNT(*) FROM transactions WHERE recorded_automatically != 0'), 0);
    expect(sw.elapsedMilliseconds, lessThan(15000));
    await db.close();
  });
}
