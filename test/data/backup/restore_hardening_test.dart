// B18 (folded into B15/B16 by PM decision): restore hardening. End to end on
// a REAL in-memory database (and a real v1 database FILE for the upgrade
// case), real exporter, real validator, real safety-copy store in a temp
// folder. Plain test() only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_writer.dart';
import 'package:mmogo/data/backup/safety_copy_store.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/schema_v1.dart';
import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

RestoreService svc(Database db, {SafetyCopyStore? safety, bool isolate = false}) => RestoreService(
      db: () async => db,
      backup: backupOf(db),
      safety: safety ?? FakeSafetyCopyStore([]),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      validateInIsolate: isolate,
    );

Future<void> wipe(Database db) async {
  await db.delete('counterparty_classification_map');
  await db.delete('transactions');
  await db.delete('classifications', where: 'seed_key IS NULL');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round_trip_export_wipe_restore_equals_original', () async {
    for (final mode in RestoreMode.values) {
      final db = await openTestDb();
      await populate(db);
      final original = await contentDump(db);
      final file = await exportOf(db);

      // Same phone, wiped (entries, learned receivers, own classifications).
      await wipe(db);
      await svc(db, isolate: true).restore(file, mode);
      expect(await contentDump(db), original, reason: mode.name);

      // A fresh install restored with Replace is the old phone, exactly.
      final fresh = await openTestDb();
      await svc(fresh).restore(file, RestoreMode.replace);
      expect(await contentDump(fresh), original);
      // And exporting it again gives an equivalent file.
      final again = await exportOf(fresh);
      final a = jsonDecode(utf8.decode(file)) as Map;
      final b = jsonDecode(utf8.decode(again)) as Map;
      expect(b['counts'], a['counts']);
      await fresh.close();
      await db.close();
    }
  });

  test('double_restore_is_idempotent_and_restoring_own_export_changes_nothing', () async {
    final db = await openTestDb();
    await populate(db);
    final file = await exportOf(db);
    final before = await fullDump(db);
    final r = await svc(db).restore(file, RestoreMode.merge);
    expect(r.inserted, 0);
    expect(await fullDump(db), before);

    final fresh = await openTestDb();
    await svc(fresh).restore(file, RestoreMode.merge);
    final once = await fullDump(fresh);
    final changes = await totalChanges(fresh);
    await svc(fresh).restore(file, RestoreMode.merge);
    expect(await fullDump(fresh), once);
    expect(await totalChanges(fresh), changes);
    await fresh.close();
    await db.close();
  });

  test('clashing_codes_keep_the_phone_copy_and_add_the_rest', () async {
    final a = await openTestDb();
    await populate(a);
    final file = await exportOf(a);
    final b = await openTestDb();
    final rent = await seedId(b, 'SEND_MONEY:rent');
    // Phone B already has two of A's codes, with different amounts.
    await addTx(b, code: 'AAA1111111', source: 'SEND_MONEY', classId: rent, amount: 1);
    await addTx(b, code: 'CCC1111111', source: 'BUY_GOODS',
        classId: await seedId(b, 'BUY_GOODS:shopping'), amount: 2);
    final r = await svc(b).restore(file, RestoreMode.merge);
    expect(r.transactions, const TableCounts(added: 5, skipped: 2));
    final amounts = await b.rawQuery(
        "SELECT amount_cents FROM transactions WHERE display_code IN ('AAA1111111','CCC1111111') ORDER BY display_code");
    expect(amounts.map((e) => e['amount_cents']), [1, 2]);
    await a.close();
    await b.close();
  });

  test('soft_deleted_code_reuse: a deleted entry comes back from an older backup as a new entry (A6)', () async {
    final db = await openTestDb();
    await populate(db);
    final file = await exportOf(db);
    // Delete AAA1111111 after the backup (it moves to Recently deleted).
    await db.rawUpdate("UPDATE transactions SET deleted_at = ? WHERE display_code = 'AAA1111111'", [t0 + 500]);
    final r = await svc(db).restore(file, RestoreMode.merge);
    expect(r.transactions, const TableCounts(added: 1, skipped: 6));
    final rows = await db.rawQuery(
        "SELECT deleted_at FROM transactions WHERE display_code = 'AAA1111111' ORDER BY id");
    expect(rows.map((e) => e['deleted_at']), [t0 + 500, null]);
    // The backup never carried the recently deleted EEE1111111 (A1).
    expect(utf8.decode(file).contains('EEE1111111'), isFalse);
    await db.close();
  });

  test('rename_round_trips_via_seed_key', () async {
    final a = await openTestDb();
    await renamePhone(a);
    final file = await exportOf(a);

    final viaReplace = await openTestDb();
    await svc(viaReplace).restore(file, RestoreMode.replace);
    expect(await contentDump(viaReplace), await contentDump(a));

    final viaMerge = await openTestDb();
    await svc(viaMerge).restore(file, RestoreMode.merge);
    final seeds = await viaMerge.rawQuery(
        'SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NOT NULL');
    expect(seeds.first['n'], 12);
    // REN1111111 is on the built-in (matched by seed_key, B keeps its own name
    // "Rent"). A's user class "Rent" meets B's ACTIVE built-in "Rent" by
    // (group, name) and merges into it (data-model D, merge step 2; a second
    // active "Rent" cannot exist in one group).
    final rent = await viaMerge.rawQuery(
        "SELECT c.name, c.seed_key FROM transactions t JOIN classifications c ON c.id = t.classification_id "
        "WHERE t.display_code IN ('REN1111111','REN2222222') ORDER BY t.display_code");
    expect(rent, [
      {'name': 'Rent', 'seed_key': 'SEND_MONEY:rent'},
      {'name': 'Rent', 'seed_key': 'SEND_MONEY:rent'},
    ]);
    for (final d in [a, viaReplace, viaMerge]) {
      await d.close();
    }
  });

  test('a_real_constraint_failure_mid_restore_rolls_everything_back', () async {
    final db = await openTestDb();
    await populate(db);
    final before = await fullDump(db);
    // Bypassing the validator: row 800 is a PAYBILL entry on a SEND_MONEY
    // classification, so SQLite's own guard trigger aborts inside the 2nd
    // 500-row batch, after 800 rows were already inserted.
    final json = bigFileJson(1000);
    (json['transactions']! as List<Map<String, Object?>>)[800]['source_type'] = 'PAYBILL';
    await expectLater(
      db.transaction((txn) => const RestoreWriter().merge(txn, unvalidated(json))),
      throwsA(isA<DatabaseException>()),
    );
    expect(await fullDump(db), before);
    await db.close();
  });

  test('replace_then_undo_restores_the_exact_prior_state (real safety copy on disk)', () async {
    final tmp = await Directory.systemTemp.createTemp('mmogo_undo_');
    SharedPreferences.setMockInitialValues({'palette_id': 'leaf', 'user_display_name': 'Otieno'});
    final db = await openTestDb();
    await populate(db);
    // Without recently deleted rows the prior state comes back exactly.
    await db.delete('transactions', where: 'deleted_at IS NOT NULL');
    final before = await contentDump(db, withDeleted: true);
    final store = SafetyCopyStore(baseDir: () async => tmp);
    final s = svc(db, safety: store);
    await s.restore(fileBytes(fileJson(classes: seedRows(), txs: [tx(1, 'ZZZ1111111', 'SEND_MONEY', 1)],
        prefs: {'palette_id': 'ocean', 'user_display_name': 'Kamau'})), RestoreMode.replace);
    final copy = await store.latest();
    expect(copy, isNotNull);
    expect(p.isWithin(tmp.path, copy!.path), isTrue);

    await s.undoLastReplace();
    expect(await contentDump(db, withDeleted: true), before);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('palette_id'), 'leaf');
    expect(prefs.getString('user_display_name'), 'Otieno');
    expect(await store.exists(), isFalse);
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('replace_removes_recently_deleted_rows_for_good (known limit of Undo)', () async {
    final db = await openTestDb();
    await populate(db); // one recently deleted row
    final s = svc(db);
    await s.restore(fileBytes(fileJson(classes: seedRows())), RestoreMode.replace);
    await s.undoLastReplace();
    final n = await db.rawQuery('SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NOT NULL');
    expect(n.first['n'], 0, reason: 'backups and safety copies never hold recently deleted rows (A1)');
    await db.close();
  });

  group('hostile_files_are_refused_and_change_nothing', () {
    final valid = utf8.encode(jsonEncode(bigFileJson(3)));
    Map<String, Object?> j() => bigFileJson(3);
    final cases = <String, Uint8List>{
      'truncated': Uint8List.fromList(valid.sublist(0, valid.length - 20)),
      'empty': Uint8List(0),
      'not utf-8': Uint8List.fromList([0x7B, 0xFF, 0xFE, 0x7D]),
      'json array root': Uint8List.fromList(utf8.encode('[1,2]')),
      'deep nesting': Uint8List.fromList(utf8.encode('[' * 100000 + ']' * 100000)),
      'foreign app': fileBytes(j()..['app'] = 'other'),
      'newer schema': fileBytes(j()..['schema_version'] = kDbVersion + 1),
      'extra top-level key': fileBytes(j()..['auto_backup_folder_uri'] = 'content://evil'),
      'counts do not match': fileBytes(j()..['counts'] = {'classifications': 12, 'transactions': 4, 'counterparty_map': 0}),
      'extra row key': fileBytes(j()..['transactions'] = [
            {...tx(1, 'K000000001', 'SEND_MONEY', 1), 'deleted_at': null},
          ]),
      'wrong-group classification (hand edit)': fileBytes(j()..['transactions'] = [tx(1, 'W000000001', 'PAYBILL', 1)]),
      'duplicate codes': fileBytes(j()..['transactions'] = [
            tx(1, 'D000000001', 'SEND_MONEY', 1),
            tx(2, 'D000000001', 'SEND_MONEY', 1),
          ]),
      'cash on Pochi (disabled group)': fileBytes(j()
        ..['classifications'] = [...seedRows(), cls(50, 'POCHI_LA_BIASHARA', 'Pochi')]
        ..['transactions'] = [tx(1, 'CASH-20260101-0101', 'CASH', 50)]),
      'over 20 MB': Uint8List(20 * 1024 * 1024 + 1),
    };
    for (final e in cases.entries) {
      test(e.key, () async {
        final bytes = e.value;
        final json = e.key.startsWith('counts') || e.key.startsWith('extra row') ||
                e.key.startsWith('wrong') || e.key.startsWith('duplicate') || e.key.startsWith('cash')
            ? _fixedCounts(bytes, keepCounts: e.key.startsWith('counts'))
            : bytes;
        final db = await openTestDb();
        await populate(db);
        final before = await fullDump(db);
        for (final mode in RestoreMode.values) {
          await expectLater(svc(db).restore(json, mode), throwsA(isA<RestoreRejected>()));
          await expectLater(svc(db).inspect(json), throwsA(isA<RestoreRejected>()));
        }
        expect(await fullDump(db), before);
        await db.close();
      });
    }
  });

  test('text_that_looks_like_urls_paths_or_sql_is_stored_as_plain_text', () async {
    final db = await openTestDb();
    const odd = ['file:///etc/passwd', 'https://evil.example/x?y=1', r'C:\Windows\system32', 'rm -rf / ; echo', "'); DROP TABLE classifications;--"];
    final file = fileJson(classes: [
      ...seedRows(),
      for (var i = 0; i < odd.length; i++) cls(100 + i, 'SEND_MONEY', odd[i]),
    ]);
    await svc(db).restore(fileBytes(file), RestoreMode.merge);
    final names = (await db.rawQuery('SELECT name FROM classifications WHERE seed_key IS NULL ORDER BY id'))
        .map((r) => r['name']);
    expect(names, odd);
    await db.close();
  });

  test('inactive_name_collision_maps_instead_of_duplicating', () async {
    final db = await openTestDb();
    await addClass(db, 'SEND_MONEY', 'Gym'); // active on the phone
    final file = fileJson(classes: [
      ...seedRows(),
      cls(60, 'SEND_MONEY', 'Gym', active: 0),
      cls(61, 'BUY_GOODS', 'Stall', active: 0),
      cls(62, 'BUY_GOODS', 'Stall'),
    ], txs: [
      tx(1, 'GYM1111111', 'SEND_MONEY', 60),
      tx(2, 'STA1111111', 'BUY_GOODS', 61),
      tx(3, 'STA2222222', 'BUY_GOODS', 62),
    ]);
    final r = await svc(db).restore(fileBytes(file), RestoreMode.merge);
    expect(r.classifications, const TableCounts(added: 2, skipped: 13));
    final gym = await db.rawQuery("SELECT COUNT(*) AS n FROM classifications WHERE name = 'Gym'");
    expect(gym.first['n'], 1);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test('trigger_and_reference_backstops_on_the_restore_path (validator bypassed)', () async {
    final db = await openTestDb();
    await populate(db);
    final before = await fullDump(db);
    Future<void> bypass(Map<String, Object?> json, Matcher m) => expectLater(
        db.transaction((txn) => const RestoreWriter().merge(txn, unvalidated(json))),
        throwsA(m));
    // CASH on the disabled Pochi group: the trigger aborts.
    await bypass(
        fileJson(classes: [...seedRows(), cls(70, 'POCHI_LA_BIASHARA', 'Pochi')],
            txs: [tx(1, 'CASH-20260101-0101', 'CASH', 70)]),
        isA<DatabaseException>());
    // Wrong group for the source type: the trigger aborts.
    await bypass(fileJson(classes: seedRows(), txs: [tx(1, 'WRG1111111', 'PAYBILL', 1)]),
        isA<DatabaseException>());
    // Map row or entry pointing at a classification the file lacks.
    await bypass(fileJson(classes: seedRows(), map: [mapRow('SEND_MONEY', 'k', 77)]), isA<StateError>());
    await bypass(fileJson(classes: seedRows(), txs: [tx(1, 'DNG1111111', 'SEND_MONEY', 77)]), isA<StateError>());
    expect(await fullDump(db), before);

    // In-file duplicates the validator would refuse are, on this path, folded
    // by the plan (skipped), never written twice.
    final dupes = fileJson(classes: [...seedRows(), cls(80, 'PAYBILL', 'Twice'), cls(81, 'PAYBILL', 'Twice')],
        map: [mapRow('SEND_MONEY', 'dup', 1), mapRow('SEND_MONEY', 'dup', 1)]);
    final d = await db.transaction((txn) => const RestoreWriter().merge(txn, unvalidated(dupes)));
    expect(d.classifications, const TableCounts(added: 1, skipped: 13));
    expect(d.counterpartyMap, const TableCounts(added: 1, skipped: 1));

    // Two cash rows with the same code (different created_at) are fine.
    final ok = fileJson(classes: seedRows(), txs: [
      tx(1, 'CASH-20260101-0101', 'CASH', 1, createdAt: f0 + 1),
      tx(2, 'CASH-20260101-0101', 'CASH', 1, createdAt: f0 + 2),
    ]);
    final t = await db.transaction((txn) => const RestoreWriter().merge(txn, unvalidated(ok)));
    expect(t.transactions.added, 2);
    await db.close();
  });

  test('upgrade_case: a 0.1.0 database migrated to v2, exported, restored on a fresh install', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('mmogo_upgrade_');
    final path = p.join(dir.path, 'mmogo.db');
    final v1 = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await AppSchemaV1.createSchema(db);
        await AppSchemaV1.seed(db);
      },
    ));
    await v1.update('classifications', {'name': 'House rent'}, where: 'id = 2');
    await v1.update('classifications', {'active': 0}, where: 'id = 12');
    final church = await addClass(v1, 'SEND_MONEY', 'Church');
    final rentAgain = await addClass(v1, 'SEND_MONEY', 'Rent');
    await addTx(v1, code: 'UPG1111111', source: 'SEND_MONEY', classId: 2, label: 'JANE', phone: '0712345678');
    await addTx(v1, code: 'UPG2222222', source: 'SEND_MONEY', classId: rentAgain);
    await addTx(v1, code: 'UPG3333333', source: 'PAYBILL', classId: 6, label: 'KPLC', account: '123');
    await addTx(v1, code: 'CASH-20261001-0900', source: 'CASH', classId: church);
    await addTx(v1, code: 'UPG4444444', source: 'BUY_GOODS', classId: 12, deletedAt: t0 + 9);
    await addMap(v1, 'SEND_MONEY', '0712345678', 2);
    await v1.close();

    final upgraded = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
      version: kDbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: AppMigrations.migrate,
    ));
    final source = await contentDump(upgraded);
    final export = await backupOf(upgraded).export();
    expect(export.skippedCount, 0);
    expect(export.excludedSoftDeleted, 1);

    final fresh = await openTestDb();
    await svc(fresh).restore(export.bytes, RestoreMode.replace);
    expect(await contentDump(fresh), source);
    final merged = await openTestDb();
    final r = await svc(merged).restore(export.bytes, RestoreMode.merge);
    expect(r.transactions.added, 4);
    expect((await merged.rawQuery('SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NOT NULL'))
        .first['n'], 12);
    await upgraded.close();
    await fresh.close();
    await merged.close();
    await dir.delete(recursive: true);
  });

  test('extreme_history_50000_rows_restores_within_the_caps (timing note)', () async {
    final json = bigFileJson(50000);
    final bytes = fileBytes(json);
    expect(bytes.length, lessThan(20 * 1024 * 1024));
    final db = await openTestDb();
    final sw = Stopwatch()..start();
    final r = await svc(db, isolate: true).restore(bytes, RestoreMode.merge);
    sw.stop();
    expect(r.transactions.added, 50000);
    // ignore: avoid_print
    print('TIMING: 50,000-row merge restore (${bytes.length} bytes) took ${sw.elapsedMilliseconds} ms on the desktop test VM');
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// A phone with a renamed built-in and a user class reusing its old name.
Future<void> renamePhone(Database db) async {
  await db.update('classifications', {'name': 'Landlord'},
      where: 'seed_key = ?', whereArgs: ['SEND_MONEY:rent']);
  final mine = await addClass(db, 'SEND_MONEY', 'Rent');
  await addTx(db, code: 'REN1111111', source: 'SEND_MONEY', classId: await seedId(db, 'SEND_MONEY:rent'));
  await addTx(db, code: 'REN2222222', source: 'SEND_MONEY', classId: mine);
}

/// Re-encodes [bytes] with `counts` fixed to the array lengths (unless the
/// case is about wrong counts), so each case fails for its own reason.
Uint8List _fixedCounts(Uint8List bytes, {required bool keepCounts}) {
  if (keepCounts) return bytes;
  final m = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
  m['counts'] = {
    'classifications': (m['classifications']! as List).length,
    'transactions': (m['transactions']! as List).length,
    'counterparty_map': (m['counterparty_map']! as List).length,
  };
  return fileBytes(m);
}
