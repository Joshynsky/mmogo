// DB4 / DB5 (S3b): the v2 -> v3 migration (`migrateToV3`, lib/data/db/migration_v3.dart).
//
// CRITICAL slice: a bug here makes every 0.1.1 database unopenable or silently
// loses learned data. Every test uses INVENTED rows only and real database FILES
// opened through the one shared open function (`openMmogoDatabase`), so the
// foreign-key rule is the app's. Each group has a negative control (a case that
// must fail) next to the positive one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v3.dart';
import 'package:mmogo/data/db/migration_v3_ddl.dart';
import 'package:mmogo/data/db/migration_v3_rekey.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/schema_v1.dart';
import '../../fixtures/v2_fixture.dart';
import '../../support/db_dump.dart';

const _t = kFixtureNow;

late Directory _dir;
int _n = 0;
String _path([String name = 'db']) => '${_dir.path}${Platform.pathSeparator}${name}_${_n++}.db';

Future<Database> _openLive(String path, {bool single = false}) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: single);

/// Read-only snapshot of a file: `uv=<user_version>` then the full dump.
Future<List<String>> _readDump(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  final uv = firstIntOf(await db.rawQuery('PRAGMA user_version'));
  final d = await fullDump(db);
  await db.close();
  return ['uv=$uv', ...d];
}

Future<int> _count(DatabaseExecutor db, String sql, [List<Object?>? args]) async =>
    firstIntOf(await db.rawQuery(sql, args))!;

Future<int> _groupId(DatabaseExecutor db, String code) =>
    _count(db, 'SELECT id FROM classification_groups WHERE code = ?', [code]);

/// Learned-receiver rows with duplicate phone forms, different categories and
/// auto_apply flags (see the table in the test that asserts the report).
Future<void> _addDuplicatePhones(Database db) async {
  Future<void> m(String src, String key, int cls, int auto, int updated) =>
      db.insert('counterparty_classification_map', {
        'source_type': src,
        'counterparty_key': key,
        'classification_id': cls,
        'auto_apply': auto,
        'updated_at': updated,
      });
  await m('SEND_MONEY', '0711000001', 1, 1, _t + 10); // id 3  g1 loser (older than the winner)
  await m('SEND_MONEY', '+254711000001', 2, 0, _t + 20); // id 4  g1 WINNER (newest)
  await m('SEND_MONEY', '254711000001', 3, 1, _t + 15); // id 5  g1 loser
  await m('SEND_MONEY', '00254711000001', 1, 0, _t + 5); // id 6  g1 loser
  await m('SEND_MONEY', '0111000002', 1, 1, _t + 30); // id 7  g2 loser (same category)
  await m('SEND_MONEY', '+254111000002', 1, 0, _t + 31); // id 8  g2 WINNER
  await m('SEND_MONEY', '0711000003', 1, 0, _t + 1); // id 9  07 and 01 never merge ...
  await m('SEND_MONEY', '0111000003', 1, 0, _t + 1); // id 10 ... so both stay
  await m('SEND_MONEY', '0722000004', 2, 0, _t + 40); // id 11 g3 loser (tie on updated_at)
  await m('SEND_MONEY', '+254722000004', 2, 0, _t + 40); // id 12 g3 WINNER (higher id)
  await m('SEND_MONEY', '254733000005', 1, 1, _t + 2); // id 13 lone, key rewritten
  await m('SEND_MONEY', '0733 000 006', 1, 0, _t + 3); // id 14 lone, spaces removed
  await m('SEND_MONEY', 'not a phone', 1, 0, _t + 4); // id 15 left as is
  await m('PAYBILL', '+254700000009#ACC', 5, 0, _t + 5); // id 16 never touched
}

/// A populated v2 file (invented rows) with the duplicate-phone map rows.
Future<String> _populatedV2({bool hardDeletedTail = false}) async {
  final path = _path('v2');
  final db = await buildV2Database(path);
  await _addDuplicatePhones(db);
  if (hardDeletedTail) {
    // A purged soft-delete leaves AUTOINCREMENT ahead of MAX(id).
    final id = await db.insert('transactions', {
      'display_code': 'TST9999999', 'source_type': 'BUY_GOODS', 'amount_cents': 1,
      'transaction_cost_cents': 0, 'classification_id': 9, 'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': _t, 'created_at': _t,
    });
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }
  await db.close();
  return path;
}

Future<String> _plainV1() async {
  final path = _path('v1');
  final db = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) async {
            await AppSchemaV1.createSchema(db);
            await AppSchemaV1.seed(db);
          }));
  await db.close();
  return path;
}

/// A v2 file with no transactions and the given user rows planted in the Pochi
/// group (groups: ids 1..4; Pochi is disabled in 0.1.1).
Future<String> _v2WithPlanted(
    List<({String name, int active, String group})> rows) async {
  final path = _path('plant');
  final db = await buildV2Database(path, populate: false);
  for (final r in rows) {
    await db.insert('classifications', {
      'group_id': await _groupId(db, r.group),
      'name': r.name,
      'active': r.active,
      'created_at': _t,
    });
  }
  await db.close();
  return path;
}

Future<Object?> _failAt(String path, String label, {bool single = true}) async {
  migrateToV3Hook = (l) async {
    if (l == label) throw StateError('injected at $l');
  };
  try {
    final db = await _openLive(path, single: single);
    await db.close();
    return null;
  } catch (e) {
    return e;
  } finally {
    migrateToV3Hook = null;
  }
}

const _expectedLabels = [
  'pre', 'drop_triggers', 'groups_create', 'groups_copy', 'groups_drop', 'groups_rename',
  'tx_rename_old', 'tx_create', 'tx_copy', 'tx_drop', 'seq_restore',
  'index_1', 'index_2', 'index_3', 'index_4', 'index_5', 'trigger_1', 'trigger_2',
  'rekey_read', 'rekey_delete', 'rekey_update',
  'group_ins_agent', 'group_ins_airtime', 'pochi_enable', 'pochi_rename',
  'seed_1_adopt', 'seed_1_insert', 'seed_2_adopt', 'seed_2_insert', 'seed_3_adopt',
  'seed_3_insert', 'seed_4_adopt', 'seed_4_insert', 'seed_5_adopt', 'seed_5_insert',
  'fk_check', 'invariants',
];

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() => _dir = Directory.systemTemp.createTempSync('mmogo_v3_'));
  tearDown(() {
    migrateToV3Hook = null;
    try {
      _dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('v2 -> v3 on a populated invented fixture', () {
    test('the ladder is registered and the live version is 3', () {
      expect(kDbVersion, 3);
      expect(AppMigrations.steps.keys, [2, 3]);
    });

    test('transactions are identical, agent_number is NULL, 14 columns, integrity ok, FK check empty',
        () async {
      final path = await _populatedV2();
      final v2 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final cols = kV2TxColumns.join(', ');
      final before = await v2.rawQuery('SELECT $cols FROM transactions ORDER BY id');
      expect(before, hasLength(6));
      await v2.close();

      final db = await _openLive(path);
      expect(firstIntOf(await db.rawQuery('PRAGMA user_version')), 3);
      expect(await db.rawQuery('SELECT $cols FROM transactions ORDER BY id'), before);
      expect(await _count(db, 'SELECT COUNT(*) FROM transactions WHERE agent_number IS NOT NULL'), 0);
      final info = await db.rawQuery('PRAGMA table_info(transactions)');
      expect(info, hasLength(14));
      expect(info.firstWhere((c) => c['name'] == 'agent_number')['notnull'], 0);
      expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(firstIntOf(await db.rawQuery('PRAGMA foreign_keys')), 1);
      await db.close();
    });

    test('the re-key report counts are exactly the hand-counted ones', () async {
      final path = await _populatedV2();
      lastPhoneRekeyReport = null;
      final db = await _openLive(path);
      expect(lastPhoneRekeyReport, isNotNull);
      expect(
          lastPhoneRekeyReport,
          const PhoneRekeyReport(
            mapBefore: 16,
            mapAfter: 11,
            keysRewritten: 5,
            groupsMerged: 3,
            losersDeleted: 5,
            losersWithDifferentCategory: 3,
            losersWithAutoApply: 3,
          ));
      await db.close();
    });

    test('the surviving map rows: winners kept with their own category, 07 and 01 apart, '
        'PAYBILL and BUY_GOODS untouched', () async {
      final path = await _populatedV2();
      final db = await _openLive(path);
      expect(await mapRows(db), [
        'SEND_MONEY|0700000001|1|1|${_t + 1}', // id 1, was already canonical
        'BUY_GOODS|test shop|9|0|${_t + 2}', // id 2
        'SEND_MONEY|0711000001|2|0|${_t + 20}', // id 4: winner of 4 forms, its OWN class/auto
        'SEND_MONEY|0111000002|1|0|${_t + 31}', // id 8
        'SEND_MONEY|0711000003|1|0|${_t + 1}', // id 9
        'SEND_MONEY|0111000003|1|0|${_t + 1}', // id 10
        'SEND_MONEY|0722000004|2|0|${_t + 40}', // id 12: tie on updated_at, higher id wins
        'SEND_MONEY|0733000005|1|1|${_t + 2}', // id 13
        'SEND_MONEY|0733000006|1|0|${_t + 3}', // id 14
        'SEND_MONEY|not a phone|1|0|${_t + 4}', // id 15
        'PAYBILL|+254700000009#ACC|5|0|${_t + 5}', // id 16: a phone-shaped PAYBILL key stays
      ]);
      expect(await _count(db, 'SELECT COUNT(*) FROM counterparty_classification_map'), 11);
      await db.close();
    });

    test('stored phones and labels are never touched by the re-key', () async {
      final path = await _populatedV2();
      final db0 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final before = await db0.rawQuery(
          'SELECT id, counterparty_phone, counterparty_label FROM transactions ORDER BY id');
      await db0.close();
      final db = await _openLive(path);
      expect(
          await db.rawQuery(
              'SELECT id, counterparty_phone, counterparty_label FROM transactions ORDER BY id'),
          before);
      await db.close();
    });

    test('AUTOINCREMENT counters never go backwards (a purged tail row keeps its number)', () async {
      final path = await _populatedV2(hardDeletedTail: true);
      final db0 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final seqBefore = await db0.rawQuery('SELECT name, seq FROM sqlite_sequence ORDER BY name');
      final maxId = await _count(db0, 'SELECT MAX(id) FROM transactions');
      await db0.close();
      final txSeq = seqBefore.firstWhere((r) => r['name'] == 'transactions')['seq'] as int;
      expect(txSeq, greaterThan(maxId), reason: 'the fixture really has a purged tail');

      final db = await _openLive(path);
      final seqAfter = await db.rawQuery('SELECT name, seq FROM sqlite_sequence ORDER BY name');
      expect(seqAfter.firstWhere((r) => r['name'] == 'transactions')['seq'], txSeq);
      final next = await db.insert('transactions', {
        'display_code': 'TSTNEXT001', 'source_type': 'BUY_GOODS', 'amount_cents': 5,
        'transaction_cost_cents': 0, 'classification_id': 9, 'raw_parse_source': 'MANUAL',
        'transaction_occurred_at': _t, 'created_at': _t,
      });
      expect(next, txSeq + 1, reason: 'the purged number is not reused');
      await db.close();
    });

    test('the guard triggers, the unique M-Pesa code index and the new CHECKs all fire after the upgrade',
        () async {
      final path = await _populatedV2();
      final db = await _openLive(path);
      Map<String, Object?> row(String code, String src, int cls, {String? agent, int cost = 0}) => {
            'display_code': code, 'source_type': src, 'amount_cents': 100,
            'transaction_cost_cents': src == 'CASH' ? null : cost, 'classification_id': cls,
            'raw_parse_source': 'MANUAL', 'transaction_occurred_at': _t, 'created_at': _t,
            'agent_number': ?agent,
          };
      final withdrawal = await _count(
          db, "SELECT id FROM classifications WHERE seed_key = 'AGENT_WITHDRAWAL:cash_withdrawal'");
      // trigger: PAYBILL with a SEND_MONEY class
      await expectLater(db.insert('transactions', row('ZZ1', 'PAYBILL', 1)), throwsA(anything));
      // new type + new column work
      await db.insert('transactions', row('ZZ2', 'AGENT_WITHDRAWAL', withdrawal, agent: '123456'));
      // CHECK: agent number on another type, non-digits, 21 digits
      await expectLater(db.insert('transactions', row('ZZ3', 'SEND_MONEY', 1, agent: '123')),
          throwsA(anything));
      await expectLater(
          db.insert('transactions', row('ZZ4', 'AGENT_WITHDRAWAL', withdrawal, agent: '12a')),
          throwsA(anything));
      await expectLater(
          db.insert('transactions', row('ZZ5', 'AGENT_WITHDRAWAL', withdrawal, agent: '1' * 21)),
          throwsA(anything));
      // unique live M-Pesa code
      await expectLater(db.insert('transactions', row('ZZ2', 'AGENT_WITHDRAWAL', withdrawal)),
          throwsA(anything));
      await db.close();
    });

    test('the migrated schema equals a fresh v3 schema for every object (whitespace aside)', () async {
      final path = await _populatedV2();
      final db = await _openLive(path);
      final fresh = await _openLive(_path('fresh'));
      String norm(Object? v) => '$v'
          .replaceAll('"classification_groups"', 'classification_groups')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('( ', '(')
          .replaceAll(' )', ')')
          .trim();
      Future<List<String>> objects(Database d) async => [
            for (final r in await d.rawQuery("SELECT type, name, tbl_name, sql FROM sqlite_master "
                "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"))
              norm(r.values.join('|'))
          ];
      final a = await objects(db);
      expect(a, await objects(fresh));
      expect(a, hasLength(16), reason: '4 tables + 10 indexes + 2 triggers');
      // negative control: a tampered migrated file differs
      await db.execute('CREATE INDEX idx_extra ON transactions(amount_cents)');
      expect(await objects(db), isNot(await objects(fresh)));
      await db.close();
      await fresh.close();
    });
  });

  group('v1 -> v3 chain over the frozen 12 only', () {
    test('a 0.1.0 file runs _toV2 then _toV3; ids 1..12 carry the frozen keys, 13..17 the new five',
        () async {
      final path = await _plainV1();
      final db = await _openLive(path);
      expect(firstIntOf(await db.rawQuery('PRAGMA user_version')), 3);
      final rows = await db.rawQuery('SELECT id, seed_key FROM classifications ORDER BY id');
      expect(rows.map((r) => r['seed_key']).toList(), v3SeedKeys());
      for (var i = 0; i < 12; i++) {
        expect(rows[i]['seed_key'], AppMigrations.v2SeedClassifications[i].seedKey);
      }
      // a v1 -> v3 file equals a fresh v3 file row for row (only created_at differs)
      final fresh = await _openLive(_path('fresh'));
      Future<List<String>> noClock(Database d) async => [
            for (final r in await d.rawQuery(
                'SELECT id, group_id, name, active, seed_key FROM classifications ORDER BY id'))
              r.values.join('|')
          ];
      expect(await noClock(db), await noClock(fresh));
      expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
      await fresh.close();
    });

    test('NEGATIVE CONTROL: looping the LIVE 17-entry list over a v1 file would key a USER row as a '
        'built-in; looping the frozen 12 does not', () async {
      Future<int> keyedBy(List<({String group, String name, String seedKey})> list) async {
        final path = await _plainV1();
        final db = await databaseFactoryFfi.openDatabase(path,
            options: OpenDatabaseOptions(singleInstance: false));
        await db.execute('ALTER TABLE classifications ADD COLUMN seed_key TEXT NULL');
        // three user rows in a 0.1.0 file: ids 13, 14, 15 (the last one in the Pochi group)
        final send = await _groupId(db, 'SEND_MONEY');
        final pochi = await _groupId(db, 'POCHI_LA_BIASHARA');
        for (final (g, n) in [(send, 'Mine A'), (send, 'Mine B'), (pochi, 'Mine C')]) {
          await db.insert('classifications',
              {'group_id': g, 'name': n, 'active': 1, 'created_at': _t});
        }
        var keyed = 0;
        for (var i = 0; i < list.length; i++) {
          keyed += await db.rawUpdate(
            'UPDATE classifications SET seed_key = ? WHERE id = ? AND seed_key IS NULL '
            'AND group_id = (SELECT id FROM classification_groups WHERE code = ?)',
            [list[i].seedKey, i + 1, list[i].group],
          );
        }
        await db.close();
        return keyed;
      }

      expect(await keyedBy(AppMigrations.v2SeedClassifications), 12);
      expect(await keyedBy([...AppMigrations.v2SeedClassifications, ...kV3NewSeeds]), 13,
          reason: 'user row id 15 (Pochi) would be keyed as POCHI_LA_BIASHARA:transport');
    });
  });

  group('seeds: adopt-before-insert for all five (positional ? placeholders)', () {
    Future<Database> migrated(String path) => _openLive(path);

    Future<List<Map<String, Object?>>> pochi(Database db) => db.rawQuery(
        'SELECT c.id, c.name, c.active, c.seed_key FROM classifications c '
        "JOIN classification_groups g ON g.id = c.group_id WHERE g.code = 'POCHI_LA_BIASHARA' "
        'ORDER BY c.id');

    for (final name in ['Transport', 'Groceries', 'Shopping']) {
      test('an ACTIVE user "$name" in the Pochi group is adopted: id kept, seed_key set, map row follows',
          () async {
        final path = await _v2WithPlanted([(name: name, active: 1, group: 'POCHI_LA_BIASHARA')]);
        final p = await databaseFactoryFfi.openDatabase(path,
            options: OpenDatabaseOptions(singleInstance: false));
        final plantedId = await _count(p, 'SELECT id FROM classifications WHERE seed_key IS NULL');
        await p.insert('counterparty_classification_map', {
          'source_type': 'SEND_MONEY', 'counterparty_key': '0700000077',
          'classification_id': plantedId, 'auto_apply': 1, 'updated_at': _t,
        });
        await p.close();

        final db = await migrated(path);
        final rows = await pochi(db);
        expect(rows, hasLength(3), reason: 'two inserted, one adopted');
        final adopted = rows.singleWhere((r) => r['name'] == name);
        expect(adopted['id'], plantedId);
        expect(adopted['seed_key'], 'POCHI_LA_BIASHARA:${name.toLowerCase()}');
        expect(await _count(db, 'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'), 17);
        expect(await _count(db, 'SELECT COUNT(*) FROM classifications'), 12 + 1 + 4,
            reason: '12 old + the planted row + 4 inserted');
        expect(
            await _count(db,
                "SELECT classification_id FROM counterparty_classification_map WHERE counterparty_key = '0700000077'"),
            plantedId);
        await db.close();
      });
    }

    test('all three planted together are adopted; Withdrawal and Airtime are inserted', () async {
      final path = await _v2WithPlanted([
        (name: 'Transport', active: 1, group: 'POCHI_LA_BIASHARA'),
        (name: 'Groceries', active: 1, group: 'POCHI_LA_BIASHARA'),
        (name: 'Shopping', active: 1, group: 'POCHI_LA_BIASHARA'),
      ]);
      final db = await migrated(path);
      expect(await _count(db, 'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'), 17);
      expect(await _count(db, 'SELECT COUNT(*) FROM classifications'), 12 + 3 + 2);
      expect((await pochi(db)).every((r) => r['seed_key'] != null), isTrue);
      await db.close();
    });

    test('NEGATIVE CONTROL: without the adopt statement the insert would hit the unique name index',
        () async {
      final path = await _v2WithPlanted([(name: 'Transport', active: 1, group: 'POCHI_LA_BIASHARA')]);
      final db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      final seed = kV3NewSeeds[2]; // Pochi Transport
      await expectLater(
          db.rawInsert(kV3InsertSeedSql,
              [seed.name, _t, seed.seedKey, seed.group, seed.seedKey]),
          throwsA(isA<DatabaseException>()),
          reason: 'insert alone collides with the planted active row (index is on group_id, name)');
      await db.close();
    });

    test('an INACTIVE same-name row is untouched and the seed is inserted beside it', () async {
      final path = await _v2WithPlanted([(name: 'Transport', active: 0, group: 'POCHI_LA_BIASHARA')]);
      final db = await migrated(path);
      final rows = await pochi(db);
      expect(rows.where((r) => r['name'] == 'Transport'), hasLength(2));
      final inactive = rows.firstWhere((r) => r['active'] == 0);
      expect(inactive['seed_key'], isNull);
      expect(rows.where((r) => r['seed_key'] == 'POCHI_LA_BIASHARA:transport'), hasLength(1));
      expect(await _count(db, 'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'), 17);
      await db.close();
    });

    test('a case variant ("transport") is untouched and the seed is inserted', () async {
      final path = await _v2WithPlanted([(name: 'transport', active: 1, group: 'POCHI_LA_BIASHARA')]);
      final db = await migrated(path);
      final rows = await pochi(db);
      expect(rows.singleWhere((r) => r['name'] == 'transport')['seed_key'], isNull);
      expect(rows.singleWhere((r) => r['name'] == 'Transport')['seed_key'],
          'POCHI_LA_BIASHARA:transport');
      await db.close();
    });

    test('the same name in ANOTHER group is untouched (a user "Shopping" in Send Money)', () async {
      final path = await _v2WithPlanted([(name: 'Shopping', active: 1, group: 'SEND_MONEY')]);
      final db = await migrated(path);
      final planted = await db.rawQuery(
          "SELECT seed_key FROM classifications WHERE name = 'Shopping' AND group_id = ? AND id > 12",
          [await _groupId(db, 'SEND_MONEY')]);
      expect(planted.single['seed_key'], isNull);
      expect((await pochi(db)).where((r) => r['name'] == 'Shopping'), hasLength(1));
      await db.close();
    });

    test('the Pochi group is enabled and renamed; a hand-changed display name is left alone', () async {
      final path = await _v2WithPlanted([]);
      var db = await migrated(path);
      final g = (await db.rawQuery(
              "SELECT display_name, enabled FROM classification_groups WHERE code = 'POCHI_LA_BIASHARA'"))
          .single;
      expect(g, {'display_name': 'Pochi', 'enabled': 1});
      await db.close();

      // guard: a name changed by anything else is never overwritten
      final plain = await buildV2Database(_path('guard'), populate: false);
      await plain.update('classification_groups', {'display_name': 'My Pochi'},
          where: "code = 'POCHI_LA_BIASHARA'");
      final guardPath = plain.path;
      await plain.close();
      db = await migrated(guardPath);
      final g2 = (await db.rawQuery(
              "SELECT display_name, enabled FROM classification_groups WHERE code = 'POCHI_LA_BIASHARA'"))
          .single;
      expect(g2, {'display_name': 'My Pochi', 'enabled': 1});
      await db.close();
    });

    test('Withdrawal / Airtime adopt SQL: a planted active user row in the (pre-existing) group is adopted',
        () async {
      // v2 forbids these group codes, so plant them in a v3-shaped database that
      // holds the 12 old seeds only, then run the real adopt/insert statements.
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false, version: 3, onCreate: (db, v) async {
        await createFreshV3ForTest(db);
        await db.delete('classifications', where: 'id > 12');
        await db.update('sqlite_sequence', {'seq': 12}, where: "name = 'classifications'");
        final aw = await _groupId(db, 'AGENT_WITHDRAWAL');
        final at = await _groupId(db, 'AIRTIME');
        for (final (g, n) in [(aw, 'Withdrawal'), (at, 'Airtime')]) {
          await db.insert('classifications',
              {'group_id': g, 'name': n, 'active': 1, 'created_at': _t});
        }
      }));
      for (final s in kV3NewSeeds.take(2)) {
        final changed = await db.rawUpdate(kV3AdoptSeedSql, [s.seedKey, s.name, s.group, s.seedKey]);
        expect(changed, 1, reason: s.seedKey);
        final inserted = await db.rawInsert(kV3InsertSeedSql, [s.name, _t, s.seedKey, s.group, s.seedKey]);
        expect(inserted, 0, reason: 'nothing left to insert for ${s.seedKey}');
      }
      expect(await _count(db, 'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'), 14);
      expect(await _count(db, 'SELECT COUNT(*) FROM classifications'), 14);
      await db.close();
    });

    test('second run of the adopt/insert/group statements changes nothing', () async {
      final path = await _v2WithPlanted([(name: 'Transport', active: 1, group: 'POCHI_LA_BIASHARA')]);
      final db = await migrated(path);
      final before = await fullDump(db);
      for (final s in kV3NewSeeds) {
        expect(await db.rawUpdate(kV3AdoptSeedSql, [s.seedKey, s.name, s.group, s.seedKey]), 0);
        expect(await db.rawInsert(kV3InsertSeedSql, [s.name, _t, s.seedKey, s.group, s.seedKey]), 0);
      }
      for (final g in kV3GroupSeeds) {
        expect(await db.rawInsert(kV3InsertGroupSql, [g.code, g.displayName, g.enabled, _t, g.code]), 0);
      }
      expect(await db.rawUpdate(kV3PochiRenameSql), 0);
      expect(await fullDump(db), before);
      // the re-key is idempotent too
      final report = await db.transaction((txn) => rekeySendMoneyKeys(txn));
      expect(report.losersDeleted, 0);
      expect(report.keysRewritten, 0);
      expect(await fullDump(db), before);
      await db.close();
    });

    test('re-running the WHOLE step on a v3 file refuses (it would drop agent_number) and changes nothing',
        () async {
      final db = await _openLive(_path('fresh'));
      await db.insert('transactions', {
        'display_code': 'TSTAGENT01', 'source_type': 'AGENT_WITHDRAWAL', 'amount_cents': 100,
        'transaction_cost_cents': 0, 'agent_number': '987654', 'raw_parse_source': 'MANUAL',
        'classification_id': await _count(db, "SELECT id FROM classifications WHERE seed_key = 'AGENT_WITHDRAWAL:cash_withdrawal'"),
        'transaction_occurred_at': _t, 'created_at': _t,
      });
      final before = await fullDump(db);
      await db.execute('PRAGMA foreign_keys = OFF');
      await expectLater(db.transaction((txn) => migrateToV3(txn)), throwsStateError);
      await db.execute('PRAGMA foreign_keys = ON');
      expect(await fullDump(db), before);
      expect(await db.rawQuery("SELECT agent_number FROM transactions"), [
        {'agent_number': '987654'}
      ]);
      await db.close();
    });

    test('statements use positional ? only: no named parameters, ? count equals the argument count',
        () async {
      final named = RegExp(r"(?<![A-Za-z0-9_'])[:@\$][A-Za-z_]");
      const stmts = {
        'adopt': (kV3AdoptSeedSql, 4),
        'insert seed': (kV3InsertSeedSql, 5),
        'insert group': (kV3InsertGroupSql, 5),
      };
      stmts.forEach((k, v) {
        expect(named.hasMatch(v.$1), isFalse, reason: k);
        expect('?'.allMatches(v.$1).length, v.$2, reason: k);
      });
      // NEGATIVE CONTROL: the DBE's named form is flagged by the same scan
      expect(named.hasMatch('UPDATE classifications SET seed_key = :K WHERE name = :N'), isTrue);
    });
  });

  group('frozen _v2TxColumns (kV2TxColumns)', () {
    test('it is exactly the 13 columns of the real v2 table, in order, and has no agent_number',
        () async {
      final db = await buildV2Database(_path('v2'), populate: false);
      final names = (await db.rawQuery('PRAGMA table_info(transactions)'))
          .map((c) => c['name'])
          .toList();
      expect(kV2TxColumns, hasLength(13));
      expect(names, kV2TxColumns);
      expect(kV2TxColumns, isNot(contains('agent_number')));
      await db.close();
    });

    test('it is NOT the live column list (the live v3 table has 14)', () async {
      final fresh = await _openLive(_path('fresh'));
      final live = (await fresh.rawQuery('PRAGMA table_info(transactions)'))
          .map((c) => c['name'] as String)
          .toList();
      expect(live, hasLength(14));
      expect(live, isNot(kV2TxColumns));
      expect(live, contains('agent_number'));
      await fresh.close();
    });

    test('NEGATIVE CONTROL: copying with the LIVE list fails ("no such column") and rolls back to v2',
        () async {
      final path = await _populatedV2();
      final pre = await _readDump(path);
      final fresh = await _openLive(_path('fresh'));
      final live = (await fresh.rawQuery('PRAGMA table_info(transactions)'))
          .map((c) => c['name'] as String)
          .toList();
      await fresh.close();

      Object? error;
      try {
        final db = await openMmogoDatabase(databaseFactoryFfi, path,
            singleInstance: false,
            onUpgrade: (db, a, b) => AppMigrations.upgrade(db, a, b, steps: {
                  3: (d) => migrateToV3(d, txColumns: live),
                }));
        await db.close();
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect('$error', contains('agent_number'));
      expect(await _readDump(path), pre, reason: 'rolled back: still v2, identical rows');
    });
  });

  group('failing-step injection at EVERY position of _toV3', () {
    test('the dry run lists exactly the expected labels, in order', () async {
      final path = await _populatedV2();
      final labels = <String>[];
      migrateToV3Hook = (l) async => labels.add(l);
      final db = await _openLive(path);
      await db.close();
      expect(labels, _expectedLabels);
    });

    for (final fixture in ['v2 populated', 'v1 chain']) {
      test('$fixture: a throw at each label leaves the file v${fixture == 'v1 chain' ? 1 : 2} with '
          'identical rows and sqlite_master, FK ON on the next open, no cached handle', () async {
        for (final label in _expectedLabels) {
          final path = fixture == 'v1 chain' ? await _plainV1() : await _populatedV2();
          final pre = await _readDump(path);
          final error = await _failAt(path, label);
          expect(error, isNotNull, reason: 'the open must throw at $label');
          expect('$error', contains('injected at $label'));
          expect(await _readDump(path), pre, reason: 'rolled back after a throw at $label');

          // the same path (singleInstance: true, as in the app) opens normally next time
          final db = await _openLive(path, single: true);
          expect(firstIntOf(await db.rawQuery('PRAGMA user_version')), 3, reason: label);
          expect(firstIntOf(await db.rawQuery('PRAGMA foreign_keys')), 1, reason: label);
          expect((await db.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
          expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
          expect(await _count(db, 'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'), 17);
          await db.close();
        }
      });
    }

    test('NEGATIVE CONTROL: a migration run WITHOUT the upgrade transaction leaves a half-migrated '
        'file, and the comparison used above notices', () async {
      final path = await _populatedV2();
      final pre = await _readDump(path);
      final db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.execute('PRAGMA foreign_keys = OFF');
      migrateToV3Hook = (l) async {
        if (l == 'seed_1_adopt') throw StateError('injected');
      };
      await expectLater(migrateToV3(db), throwsStateError); // autocommit: nothing rolls back
      migrateToV3Hook = null;
      await db.close();
      expect(await _readDump(path), isNot(pre));
    });

    test('NEGATIVE CONTROL: the comparison notices a row tampered with after a failure', () async {
      final path = await _populatedV2();
      final pre = await _readDump(path);
      await _failAt(path, 'tx_copy');
      final db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.update('counterparty_classification_map', {'auto_apply': 0}, where: 'id = 1');
      await db.close();
      expect(await _readDump(path), isNot(pre));
    });

    test('a broken invariant rolls the whole step back (planted foreign-key violation)', () async {
      final path = await _populatedV2();
      final pre = await _readDump(path);
      final db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.insert('counterparty_classification_map', {
        'source_type': 'BUY_GOODS', 'counterparty_key': 'ORPHAN', 'classification_id': 9999,
        'auto_apply': 0, 'updated_at': _t,
      });
      await db.close();
      final planted = await _readDump(path);
      Object? error;
      try {
        await (await _openLive(path)).close();
      } catch (e) {
        error = e;
      }
      expect('$error', contains('foreign_key_check'));
      expect(await _readDump(path), planted, reason: 'still v2 with the planted row, nothing else changed');
      expect(planted, isNot(pre));
    });
  });

  group('50,000-row timing', () {
    test('50,000 transactions and a 15,000-row map migrate, with the digest and re-key counts intact',
        () async {
      final path = _path('big');
      final db = await buildV2Database(path, populate: false);
      await db.transaction((txn) async {
        final b = txn.batch();
        for (var i = 0; i < 50000; i++) {
          b.insert('transactions', {
            'display_code': 'BIG${i.toString().padLeft(8, '0')}',
            'source_type': 'SEND_MONEY', 'amount_cents': 100 + i,
            'transaction_cost_cents': i % 7, 'counterparty_label': 'Test $i',
            'counterparty_phone': '07${(10000000 + i).toString()}',
            'classification_id': 1 + i % 4, 'raw_parse_source': 'MANUAL',
            'transaction_occurred_at': _t + i, 'created_at': _t + i,
          });
        }
        for (var i = 0; i < 10000; i++) {
          final d = (10000000 + i).toString();
          b.insert('counterparty_classification_map', {
            'source_type': 'SEND_MONEY', 'counterparty_key': '07$d', 'classification_id': 1,
            'auto_apply': 0, 'updated_at': _t + i,
          });
          if (i < 5000) {
            b.insert('counterparty_classification_map', {
              'source_type': 'SEND_MONEY', 'counterparty_key': '+2547$d',
              'classification_id': 2, 'auto_apply': 1, 'updated_at': _t + 50000 + i,
            });
          }
        }
        await b.commit(noResult: true);
      });
      expect(await _count(db, 'SELECT COUNT(*) FROM transactions'), 50000);
      await db.close();

      final sw = Stopwatch()..start();
      final up = await _openLive(path);
      sw.stop();
      // ignore: avoid_print
      print('S3B_TIMING_50K upgrade of 50000 transactions + 15000 map rows: ${sw.elapsedMilliseconds} ms');
      expect(await _count(up, 'SELECT COUNT(*) FROM transactions'), 50000);
      final r = lastPhoneRekeyReport!;
      expect(r.mapBefore, 15000);
      expect(r.mapAfter, 10000);
      expect(r.losersDeleted, 5000, reason: 'each +254 form is newer than its 07 form: 5,000 merges');
      expect(r.keysRewritten, 5000);
      expect(r.groupsMerged, 5000);
      expect(r.losersWithDifferentCategory, 5000);
      expect(r.losersWithAutoApply, 0);
      expect((await up.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
      expect(await up.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await up.close();
      expect(sw.elapsedMilliseconds, lessThan(120000));
    }, timeout: const Timeout(Duration(minutes: 8)));
  });
}
