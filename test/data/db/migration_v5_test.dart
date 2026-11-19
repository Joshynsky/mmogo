// WBS row 17 (J-row17 v2): schema v5 = two built-in Airtime categories and the
// kind-lock trigger, data only. Real temp ffi files; invented rows only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v5.dart';
import 'package:mmogo/data/db/migration_v5_ddl.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/open_classifier.dart';
import 'package:mmogo/data/db/open_evidence_file.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/domain/airtime/airtime_kind.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/schema_v1.dart';
import '../../fixtures/v2_fixture.dart';

late Directory _dir;
int _n = 0;
String _path(String name) => '${_dir.path}/${name}_${_n++}.db';

Future<Database> _openLive(String path) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);

Future<Database> _openAt(String path, int version) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false, version: version);

/// A real version-3 file with invented rows (a v2 fixture upgraded by the live v3 step only).
Future<String> _v3File() async {
  final path = _path('v3');
  await (await buildV2Database(path)).close();
  await (await _openAt(path, 3)).close();
  return path;
}

/// The Oppo shape: a v4 file, the Airtime category id 14 named 'Airtime' holding
/// [airtimeRows] invented airtime entries, plus a user category.
Future<String> _v4File({int airtimeRows = 11}) async {
  final path = await _v3File();
  final v3 = await _openAt(path, 3);
  await _addAirtime(v3, airtimeRows);
  await v3.close();
  await (await _openAt(path, 4)).close();
  return path;
}

Future<void> _addAirtime(Database db, int rows, {int? classification}) async {
  final cls = classification ?? await _id(db, kAirtimeSeedMyself);
  for (var i = 0; i < rows; i++) {
    await db.insert('transactions', {
      'display_code': 'AIR${(_n++).toString().padLeft(7, '0')}',
      'source_type': 'AIRTIME',
      'amount_cents': 500 + i * 100,
      'transaction_cost_cents': 0,
      'classification_id': cls,
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': kFixtureNow + i,
      'created_at': kFixtureNow + i,
    });
  }
}

Future<int> _id(DatabaseExecutor db, String seedKey) async =>
    firstIntOf(await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [seedKey]))!;

Future<int> _uv(Database db) async => firstIntOf(await db.rawQuery('PRAGMA user_version'))!;

Future<List<Map<String, Object?>>> _all(DatabaseExecutor db, String table) async =>
    [for (final r in await db.rawQuery('SELECT * FROM $table ORDER BY id')) {...r}];

Future<String> _txFingerprint(DatabaseExecutor db) async {
  final cols = await db.rawQuery('PRAGMA table_info(transactions)');
  final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n, SUM(amount_cents) AS s, GROUP_CONCAT(display_code) AS c FROM '
      '(SELECT * FROM transactions ORDER BY id)');
  return '${cols.map((c) => c.values.join('|')).join(';')}#${rows.first.values.join('#')}';
}

Future<List<String>> _classNames(DatabaseExecutor db) async => [
      for (final r in await db.rawQuery(
          'SELECT c.name, c.seed_key, c.active, g.code FROM classifications c '
          'JOIN classification_groups g ON g.id = c.group_id ORDER BY c.seed_key IS NULL, c.seed_key, c.name'))
        r.values.join('|')
    ];

String _norm(Object? v) => '$v'.replaceAll(RegExp(r'\s+'), ' ').trim();

Future<String> _triggerText(DatabaseExecutor db) async => _norm((await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='trigger' AND name = ?", [kAirtimeKindTriggerName]))
    .single['sql']);

Future<int> _count(DatabaseExecutor db, String sql, [List<Object?>? a]) async =>
    firstIntOf(await db.rawQuery(sql, a))!;

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() => _dir = Directory.systemTemp.createTempSync('mmogo_v5_'));
  tearDown(() {
    try {
      _dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the live version is 5, the ladder has step 5, the backup schema equals it', () {
    expect(kDbVersion, 7);
    expect(AppMigrations.steps.keys, [2, 3, 4, 5, 6, 7]);
    expect(kBackupSchemaVersion, kDbVersion); // backup_schema_version_equals_db_version_5
  });

  test('migrate_v3_to_v5_airtime_renamed_other_added_rows_intact', () async {
    final path = await _v3File();
    final v3 = await _openAt(path, 3);
    await _addAirtime(v3, 3);
    final myselfId = await _id(v3, kAirtimeSeedMyself);
    final txBefore = await _all(v3, 'transactions');
    final classesBefore = await _all(v3, 'classifications');
    expect(await _count(v3, "SELECT COUNT(*) FROM classifications WHERE name = 'Airtime'"), 1);
    await v3.close();

    final db = await _openAt(path, 5); // the v5 step on its own (v6 adds columns, see migration_v6_test)
    expect(await _uv(db), 5);
    expect(await _all(db, 'transactions'), txBefore);
    // Every old classification row is unchanged except the renamed Airtime one; one row is new.
    final after = await _all(db, 'classifications');
    expect(after.length, classesBefore.length + 1);
    for (final r in classesBefore) {
      final now = after.firstWhere((a) => a['id'] == r['id']);
      if (r['id'] == myselfId) {
        expect(now['name'], kAirtimeNameMyself);
        expect({...now}..remove('name'), {...r}..remove('name'));
      } else {
        expect(now, r);
      }
    }
    final other = after.firstWhere((a) => a['seed_key'] == kAirtimeSeedOther);
    expect(other['name'], kAirtimeNameOther);
    expect(other['active'], 1);
    expect(other['group_id'], after.firstWhere((a) => a['id'] == myselfId)['group_id']);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test('migrate_v4_oppo_shape_id14_renamed_11_rows_stay_myself_user_classes_kept', () async {
    final path = await _v4File(airtimeRows: 11);
    final v4 = await _openAt(path, 4);
    final oppoId = await _id(v4, kAirtimeSeedMyself); // 14 on the real file; the fixture has extra user rows
    final airtimeGroup = firstIntOf(await v4.rawQuery("SELECT id FROM classification_groups WHERE code = 'AIRTIME'"))!;
    await v4.insert('classifications',
        {'group_id': 1, 'name': 'Invented user class', 'active': 1, 'created_at': kFixtureNow});
    final classesBefore = await _all(v4, 'classifications');
    final fulizaBefore = await _all(v4, 'fuliza_events');
    expect(await _count(v4, "SELECT COUNT(*) FROM transactions WHERE source_type='AIRTIME'"), 11);
    await v4.close();

    final db = await _openLive(path);
    expect(await _uv(db), 7);
    expect(await _id(db, kAirtimeSeedMyself), oppoId, reason: 'the id does not change');
    expect(await _count(db, 'SELECT COUNT(*) FROM transactions WHERE classification_id = ?', [oppoId]), 11);
    expect((await db.rawQuery('SELECT name FROM classifications WHERE id = ?', [oppoId])).single['name'], 'For myself');
    expect(await _all(db, 'fuliza_events'), fulizaBefore);
    final user = await db.rawQuery("SELECT * FROM classifications WHERE name = 'Invented user class'");
    expect(user, hasLength(1));
    expect(user.single, classesBefore.firstWhere((r) => r['name'] == 'Invented user class'));
    final other = (await db.rawQuery('SELECT * FROM classifications WHERE seed_key = ?', [kAirtimeSeedOther])).single;
    expect(other['group_id'], airtimeGroup);
    await db.close();
  });

  test('migrate_v5_transactions_table_info_unchanged', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    final before = await v4.rawQuery('PRAGMA table_info(transactions)');
    final ddl = (await v4.rawQuery("SELECT sql FROM sqlite_master WHERE name='transactions'")).single['sql'];
    await v4.close();
    final db = await _openAt(path, 5);
    expect(await db.rawQuery('PRAGMA table_info(transactions)'), before);
    expect((await db.rawQuery("SELECT sql FROM sqlite_master WHERE name='transactions'")).single['sql'], ddl);
    await db.close();
  });

  test('migrate_v5_row_count_sum_codes_unchanged', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    final before = await _txFingerprint(v4);
    await v4.close();
    final db = await _openAt(path, 5);
    expect(await _txFingerprint(db), before);
    await db.close();
  });

  test('migrate_v5_no_airtime_row_lands_in_other_category', () async {
    final path = await _v4File();
    final db = await _openLive(path);
    expect(
        await _count(db,
            "SELECT COUNT(*) FROM transactions t JOIN classifications c ON c.id = t.classification_id "
            "WHERE t.source_type='AIRTIME' AND c.seed_key = ?", [kAirtimeSeedOther]),
        0);
    expect(
        await _count(db,
            "SELECT COUNT(*) FROM transactions t JOIN classifications c ON c.id = t.classification_id "
            "WHERE t.source_type='AIRTIME' AND c.seed_key = ?", [kAirtimeSeedMyself]),
        11);
    await db.close();
  });

  test('migrate_v5_new_row_gets_next_free_id', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    final maxId = await _count(v4, 'SELECT MAX(id) FROM classifications');
    await v4.close();
    final db = await _openLive(path);
    expect(await _id(db, kAirtimeSeedOther), greaterThan(maxId));
    await db.close();
  });

  test('migrate_v4_new_row_already_present_no_duplicate', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    final airtimeGroup = firstIntOf(await v4.rawQuery("SELECT id FROM classification_groups WHERE code = 'AIRTIME'"))!;
    await v4.insert('classifications', {
      'group_id': airtimeGroup,
      'name': 'Something else',
      'active': 0,
      'created_at': kFixtureNow,
      'seed_key': kAirtimeSeedOther,
    });
    await v4.close();
    final db = await _openLive(path);
    expect(await _count(db, 'SELECT COUNT(*) FROM classifications WHERE seed_key = ?', [kAirtimeSeedOther]), 1);
    final row = (await db.rawQuery('SELECT name, active FROM classifications WHERE seed_key = ?', [kAirtimeSeedOther])).single;
    expect(row['name'], kAirtimeNameOther);
    expect(row['active'], 1);
    await db.close();
  });

  test('migrate_v4_new_key_in_wrong_group_throws_file_unchanged', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    await v4.insert('classifications',
        {'group_id': 1, 'name': 'Misplaced', 'active': 1, 'created_at': kFixtureNow, 'seed_key': kAirtimeSeedOther});
    final before = await _all(v4, 'classifications');
    final tx = await _txFingerprint(v4);
    await v4.close();
    await expectLater(_openLive(path), throwsA(anything));
    final after = await _openAt(path, 4);
    expect(await _uv(after), 4);
    expect(await _all(after, 'classifications'), before);
    expect(await _txFingerprint(after), tx);
    await after.close();
  });

  test('migrate_v4_user_row_named_for_myself_renamed_kept', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    final airtimeGroup = firstIntOf(await v4.rawQuery("SELECT id FROM classification_groups WHERE code = 'AIRTIME'"))!;
    final a = await v4.insert('classifications',
        {'group_id': airtimeGroup, 'name': kAirtimeNameMyself, 'active': 1, 'created_at': kFixtureNow});
    final b = await v4.insert('classifications',
        {'group_id': airtimeGroup, 'name': kAirtimeNameOther, 'active': 1, 'created_at': kFixtureNow});
    await v4.close();
    final db = await _openLive(path);
    expect((await db.rawQuery('SELECT name, active, seed_key FROM classifications WHERE id = ?', [a])).single,
        {'name': 'For myself (2)', 'active': 1, 'seed_key': null});
    expect((await db.rawQuery('SELECT name, active, seed_key FROM classifications WHERE id = ?', [b])).single,
        {'name': 'For another number (2)', 'active': 1, 'seed_key': null});
    expect((await db.rawQuery('SELECT name FROM classifications WHERE seed_key = ?', [kAirtimeSeedMyself])).single['name'],
        'For myself');
    await db.close();
  });

  test('migrate_v4_airtime_inactive_row_is_set_active', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    await v4.update('classifications', {'active': 0}, where: 'seed_key = ?', whereArgs: [kAirtimeSeedMyself]);
    await v4.close();
    final db = await _openLive(path);
    expect((await db.rawQuery('SELECT active FROM classifications WHERE seed_key = ?', [kAirtimeSeedMyself])).single['active'], 1);
    await db.close();
  });

  test('migrate_v4_airtime_row_missing_throws_file_unchanged', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    await v4.update('classifications', {'seed_key': null}, where: 'seed_key = ?', whereArgs: [kAirtimeSeedMyself]);
    final before = await _all(v4, 'classifications');
    await v4.close();
    await expectLater(_openLive(path), throwsA(anything));
    final after = await _openAt(path, 4);
    expect(await _uv(after), 4);
    expect(await _all(after, 'classifications'), before);
    await after.close();
  });

  test('migrate_v5_failure_after_insert_rolls_back_to_v4_name_airtime', () async {
    final path = await _v4File();
    final v4 = await _openAt(path, 4);
    final before = await _all(v4, 'classifications');
    await v4.close();
    await expectLater(
      openMmogoDatabase(databaseFactoryFfi, path,
          singleInstance: false,
          onUpgrade: (db, a, b) => AppMigrations.upgrade(db, a, b, steps: {
                5: (d) => migrateToV5(d, afterInsert: (_) async => throw StateError('injected')),
              })),
      throwsA(anything),
    );
    final after = await _openAt(path, 4);
    expect(await _uv(after), 4);
    expect(await _all(after, 'classifications'), before);
    expect((await after.rawQuery('SELECT name FROM classifications WHERE seed_key = ?', [kAirtimeSeedMyself])).single['name'],
        'Airtime');
    expect(await _count(after, "SELECT COUNT(*) FROM sqlite_master WHERE name = ?", [kAirtimeKindTriggerName]), 0);
    await after.close();
  });

  test('open_v5_file_missing_airtime_seed_fails_clean', () async {
    final path = _path('fresh');
    final fresh = await _openLive(path);
    await fresh.delete('classifications', where: 'seed_key = ?', whereArgs: [kAirtimeSeedOther]);
    await fresh.close();
    await expectLater(_openLive(path), throwsA(isA<StateError>()));
  });

  test('open_newer_than_7_refused_unchanged', () async {
    final path = _path('fresh');
    final fresh = await _openLive(path);
    await fresh.execute('PRAGMA user_version = 8');
    final before = await _all(fresh, 'classifications');
    await fresh.close();
    await expectLater(_openLive(path), throwsA(isA<StateError>()));
    final raw = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    expect(await _uv(raw), 8);
    expect(await _all(raw, 'classifications'), before);
    await raw.close();
  });

  test('migrate_v2_v1_ladder_reaches_v5', () async {
    final p2 = _path('v2');
    await (await buildV2Database(p2)).close();
    final d2 = await _openLive(p2);
    expect(await _uv(d2), 7);
    expect(await _count(d2, 'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'), 18);
    expect(await _id(d2, kAirtimeSeedOther), isPositive);
    expect(await _triggerText(d2), _norm(kAirtimeKindTriggerDdl.replaceFirst(' IF NOT EXISTS', '')));
    await d2.close();

    final p1 = _path('v1');
    final v1 = await databaseFactoryFfi.openDatabase(p1,
        options: OpenDatabaseOptions(
            version: 1,
            singleInstance: false,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, v) async {
              await AppSchemaV1.createSchema(db);
              await AppSchemaV1.seed(db);
            }));
    await v1.close();
    final d1 = await _openLive(p1);
    expect(await _uv(d1), 7);
    expect(await _count(d1, 'SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'), 18);
    expect((await d1.rawQuery('SELECT name FROM classifications WHERE seed_key = ?', [kAirtimeSeedMyself])).single['name'],
        'For myself');
    await d1.close();
  });

  test('open_snapshot_taken_for_header_4', () async {
    final path = await _v4File();
    final evidence = FileOpenEvidence(path: path, factory: databaseFactoryFfi);
    expect(await evidence.headerUserVersion(), 4);
    final snap = await prepareOpenSnapshot(evidence, proofOnRecord: true);
    expect(snap, isNotNull);
    expect(snap!.userVersion, 4);
    // A v5 file needs no snapshot.
    final db = await _openLive(path);
    await db.close();
    expect(await evidence.headerUserVersion(), 7);
    expect(await prepareOpenSnapshot(evidence, proofOnRecord: true), isNull);
  });

  test('migrate_idempotent_second_open_no_change', () async {
    final path = await _v4File();
    final first = await _openLive(path);
    final classes = await _all(first, 'classifications');
    final tx = await _all(first, 'transactions');
    // The step itself run a second time changes nothing.
    await first.transaction((t) => migrateToV5(t));
    expect(await _all(first, 'classifications'), classes);
    expect(await _all(first, 'transactions'), tx);
    await first.close();
    final second = await _openLive(path);
    expect(await _all(second, 'classifications'), classes);
    expect(await _all(second, 'transactions'), tx);
    await second.close();
  });

  test('idempotent step with an entry already in the other category changes nothing', () async {
    final path = await _v4File(airtimeRows: 2);
    final db = await _openLive(path);
    await _addAirtime(db, 2, classification: await _id(db, kAirtimeSeedOther));
    final tx = await _all(db, 'transactions');
    await db.transaction((t) => migrateToV5(t));
    expect(await _all(db, 'transactions'), tx);
    await db.close();
  });

  test('fresh_v5_and_migrated_names_seedkeys_trigger_equal', () async {
    final fresh = await _openLive(_path('fresh'));
    final fromV3Path = await _v3File();
    final fromV3 = await _openLive(fromV3Path);
    final fromV4 = await _openLive(await _v4File());

    final freshNames = await _classNames(fresh);
    final freshTrigger = await _triggerText(fresh);
    for (final migrated in [fromV3, fromV4]) {
      // The v2 fixture carries renamed / hidden built-ins and user categories:
      // compare the seed rows only (seed_key NOT NULL) by key and group.
      Future<List<String>> seeds(DatabaseExecutor d) async => [
            for (final r in await d.rawQuery(
                'SELECT c.seed_key, g.code FROM classifications c JOIN classification_groups g ON g.id = c.group_id '
                'WHERE c.seed_key IS NOT NULL ORDER BY c.seed_key'))
              r.values.join('|')
          ];
      expect(await seeds(migrated), await seeds(fresh));
      expect(await _triggerText(migrated), freshTrigger);
      expect(
          (await migrated.rawQuery('SELECT name FROM classifications WHERE seed_key IN (?, ?) ORDER BY seed_key',
                  [kAirtimeSeedMyself, kAirtimeSeedOther]))
              .map((r) => r['name']),
          ['For myself', 'For another number']);
    }
    expect(freshNames.where((n) => n.contains('AIRTIME')).toList(), [
      'For myself|AIRTIME:airtime|1|AIRTIME',
      'For another number|AIRTIME:for_another_number|1|AIRTIME',
    ]);
    await fresh.close();
    await fromV3.close();
    await fromV4.close();
  });

  test('fresh_v5_seeds_18_classifications_both_airtime_active', () async {
    final db = await _openLive(_path('fresh'));
    expect(await _uv(db), 7);
    expect(await _count(db, 'SELECT COUNT(*) FROM classifications'), 18);
    final rows = await db.rawQuery('SELECT id, name, active, seed_key FROM classifications WHERE id IN (14, 18) ORDER BY id');
    expect(rows.map((r) => r.values.join('|')), ['14|For myself|1|AIRTIME:airtime', '18|For another number|1|AIRTIME:for_another_number']);
    expect(await _count(db, "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name = ?", [kAirtimeKindTriggerName]), 1);
    await db.close();
  });

  test('app_schema_seeds_equal_backup_seed_keys_18', () {
    final seeds = [for (final s in AppSchema.seedClassifications) s.seedKey];
    expect(seeds.length, 18);
    expect(seeds, kBackupSeedKeys);
    expect(kBackupSeedKeysV3V4.length, 17);
    expect(kBackupSeedKeysV3V4, isNot(contains(kAirtimeSeedOther)));
    expect(kBackupSeedKeys.last, kAirtimeSeedOther);
  });

  test('frozen v3 seeds are not edited: the v3 ladder still names the category Airtime', () async {
    final path = await _v3File();
    final v3 = await _openAt(path, 3);
    expect((await v3.rawQuery('SELECT name FROM classifications WHERE seed_key = ?', [kAirtimeSeedMyself])).single['name'], 'Airtime');
    await v3.close();
  });
}
