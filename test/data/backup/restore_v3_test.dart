// S3c (mmogo 0.1.2): restore of OLDER files into a schema 3 database.
//  - CA5 / C-A5: SEND_MONEY map keys are put through the phone key rule before
//    the dedupe (tests R1 to R9), and the Replace map-count assertion compares
//    with what the plan wrote, not the file's row count.
//  - BK3: a Replace of a v2 file into a 17-built-in database succeeds, and the
//    five 0.1.2 built-ins are not touched.
// Real in-memory database with the real v3 schema, triggers and indexes.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_writer.dart';
import 'package:mmogo/data/db/migration_v3_ddl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

RestoreService svc(Database db, {FakeSafetyCopyStore? safety}) => RestoreService(
      db: () async => db,
      backup: backupOf(db),
      safety: safety ?? FakeSafetyCopyStore([]),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      validateInIsolate: false,
    );

/// `key|class seed_key|auto_apply|updated_at` of every SEND_MONEY map row.
Future<List<String>> sendMap(DatabaseExecutor db) async => [
      for (final r in await db.rawQuery(
          'SELECT m.counterparty_key, c.seed_key, m.auto_apply, m.updated_at '
          'FROM counterparty_classification_map m JOIN classifications c '
          "ON c.id = m.classification_id WHERE m.source_type = 'SEND_MONEY' ORDER BY m.id"))
        r.values.join('|'),
    ];

Future<int> mapCount(DatabaseExecutor db) async => (await db.rawQuery(
        'SELECT COUNT(*) AS n FROM counterparty_classification_map'))
    .first['n']! as int;

/// A schema 2 file with the given SEND_MONEY map rows over the 12 built-ins.
Uint8List v2File(List<Map<String, Object?>> map) =>
    fileBytes(fileJson(classes: seedRows(), map: map));

Uint8List v3File(List<Map<String, Object?>> map) =>
    fileBytes(fileJson(classes: seedRowsV3(), map: map, schemaVersion: 3));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('C-A5 restore normalises SEND_MONEY map keys (R1 to R9)', () {
    // File ids: 1 = SEND_MONEY:family_friends ("A"), 2 = SEND_MONEY:rent ("B"),
    // 3 = SEND_MONEY:transport ("C").
    test('R1: 0712345678 (A, updated 100) + +254712345678 (B, updated 200) give ONE row, key 0712345678, class B, added 1 skipped 1',
        () async {
      final db = await openTestDb();
      final r = await svc(db).restore(
          v2File([
            mapRow('SEND_MONEY', '0712345678', 1, updatedAt: f0 + 100),
            mapRow('SEND_MONEY', '+254712345678', 2, updatedAt: f0 + 200),
          ]),
          RestoreMode.merge);
      expect(r.counterpartyMap, const TableCounts(added: 1, skipped: 1));
      expect(await sendMap(db), ['0712345678|SEND_MONEY:rent|1|${f0 + 200}']);
      await db.close();
    });

    test('R1b: the winner is the NEWEST row, not the last one (newer first in the file)', () async {
      final db = await openTestDb();
      final r = await svc(db).restore(
          v2File([
            mapRow('SEND_MONEY', '+254712345678', 2, updatedAt: f0 + 200),
            mapRow('SEND_MONEY', '0712345678', 1, updatedAt: f0 + 100),
          ]),
          RestoreMode.merge);
      expect(r.counterpartyMap, const TableCounts(added: 1, skipped: 1));
      expect(await sendMap(db), ['0712345678|SEND_MONEY:rent|1|${f0 + 200}']);
      await db.close();
    });

    test('R2: equal updated_at, the later array index wins', () async {
      final db = await openTestDb();
      await svc(db).restore(
          v2File([
            mapRow('SEND_MONEY', '0712345678', 1, autoApply: 1),
            mapRow('SEND_MONEY', '254712345678', 2, autoApply: 0),
          ]),
          RestoreMode.merge);
      expect(await sendMap(db), ['0712345678|SEND_MONEY:rent|0|$f0']);
      await db.close();
    });

    test('R3: the phone already holds 0712345678 (class C): both file rows are skipped, the phone row is untouched',
        () async {
      final db = await openTestDb();
      await addMap(db, 'SEND_MONEY', '0712345678', await seedId(db, 'SEND_MONEY:transport'), autoApply: 0);
      final before = await sendMap(db);
      final r = await svc(db).restore(
          v2File([
            mapRow('SEND_MONEY', '0712345678', 1, updatedAt: f0 + 100),
            mapRow('SEND_MONEY', '+254712345678', 2, updatedAt: f0 + 200),
          ]),
          RestoreMode.merge);
      expect(r.counterpartyMap, const TableCounts(added: 0, skipped: 2));
      expect(await sendMap(db), before);
      await db.close();
    });

    test('R4: 0112345678 and 0712345678 are different people and are inserted separately', () async {
      final db = await openTestDb();
      final r = await svc(db).restore(
          v2File([
            mapRow('SEND_MONEY', '0112345678', 1),
            mapRow('SEND_MONEY', '0712345678', 2),
          ]),
          RestoreMode.merge);
      expect(r.counterpartyMap, const TableCounts(added: 2, skipped: 0));
      expect(await sendMap(db), hasLength(2));
      await db.close();
    });

    test('R5: R1 file as a REPLACE succeeds and the map holds 1 row (red with the old file-count assertion)',
        () async {
      final db = await openTestDb();
      await populate(db);
      final bytes = v2File([
        mapRow('SEND_MONEY', '0712345678', 1, updatedAt: f0 + 100),
        mapRow('SEND_MONEY', '+254712345678', 2, updatedAt: f0 + 200),
      ]);
      final fileRows = BackupValidator.validate(bytes).counterpartyMap.length;
      final r = await svc(db).restore(bytes, RestoreMode.replace);
      expect(r.counterpartyMap, const TableCounts(added: 1, skipped: 1));
      final n = await mapCount(db);
      expect(n, 1);
      // The pre-fix assertion compared COUNT(map) with the file's row count:
      // 1 != 2, which threw and rolled back a legitimate Replace.
      expect(fileRows, 2);
      expect(n, isNot(fileRows), reason: 'the old assertion would have rolled this Replace back');
      await db.close();
    });

    test('R6: a SCHEMA 3 file with a non-canonical key is normalised too', () async {
      final db = await openTestDb();
      final r = await svc(db).restore(
          v3File([mapRow('SEND_MONEY', '254712345678', 1)]), RestoreMode.merge);
      expect(r.counterpartyMap, const TableCounts(added: 1, skipped: 0));
      expect(await sendMap(db), ['0712345678|SEND_MONEY:family_friends|1|$f0']);
      await db.close();
    });

    test('R7: a BUY_GOODS or PAYBILL key shaped like a phone is not touched', () async {
      final db = await openTestDb();
      await svc(db).restore(
          v3File([
            mapRow('BUY_GOODS', '+254712345678', 9),
            mapRow('PAYBILL', '+254712345678#254712345678', 5),
          ]),
          RestoreMode.merge);
      final keys = [
        for (final r in await db.rawQuery(
            'SELECT source_type, counterparty_key FROM counterparty_classification_map ORDER BY id'))
          '${r['source_type']}|${r['counterparty_key']}',
      ];
      expect(keys, ['BUY_GOODS|+254712345678', 'PAYBILL|+254712345678#254712345678']);
      await db.close();
    });

    test('R8: export, validate, restore keeps the learned receivers equal', () async {
      final a = await openTestDb();
      final rent = await seedId(a, 'SEND_MONEY:rent');
      await addMap(a, 'SEND_MONEY', '0712345678', rent);
      await addMap(a, 'SEND_MONEY', '0112345678', rent, autoApply: 0);
      await addMap(a, 'BUY_GOODS', 'DUKA', await seedId(a, 'BUY_GOODS:shopping'));
      final file = await exportOf(a);
      for (final mode in RestoreMode.values) {
        final b = await openTestDb();
        await svc(b).restore(file, mode);
        expect((await contentDump(b))['counterparty_map'], (await contentDump(a))['counterparty_map'],
            reason: mode.name);
        await b.close();
      }
      await a.close();
    });

    test('R9: 0712 345 678 normalises to 0712345678', () async {
      final db = await openTestDb();
      await svc(db).restore(v2File([mapRow('SEND_MONEY', '0712 345 678', 1)]), RestoreMode.merge);
      expect(await sendMap(db), ['0712345678|SEND_MONEY:family_friends|1|$f0']);
      await db.close();
    });

    test('the preview counts the combined row once (inspect shows 1 new, not 2)', () async {
      final db = await openTestDb();
      final p = await svc(db).inspect(v2File([
        mapRow('SEND_MONEY', '0712345678', 1, updatedAt: f0 + 100),
        mapRow('SEND_MONEY', '+254712345678', 2, updatedAt: f0 + 200),
      ]));
      expect(p.fileCounterpartyMap, 2);
      expect(p.newCounterpartyMap, 1);
      await db.close();
    });

    test('a SCHEMA 2 pre-restore safety copy (written by 0.1.1) is still undoable on a schema 3 database',
        () async {
      final db = await openTestDb();
      await populate(db);
      final events = <String>[];
      final safety = FakeSafetyCopyStore(events);
      // The copy 0.1.1 would have left: a schema 2 file with 12 built-ins.
      safety.bytes = fileBytes(fileJson(
        classes: [...seedRows(), cls(20, 'SEND_MONEY', 'Old one')],
        txs: [tx(1, 'OLD1111111', 'SEND_MONEY', 1, label: 'MAMA', phone: '0700000001')],
        map: [mapRow('SEND_MONEY', '0700000001', 1)],
      ));
      final s = svc(db, safety: safety);
      expect(await s.canUndo(), isTrue);
      final u = await s.undoLastReplace();
      expect(u.transactions.added, 1);
      final codes = [for (final r in await db.rawQuery('SELECT display_code FROM transactions')) r['display_code']];
      expect(codes, ['OLD1111111']);
      expect(await sendMap(db), ['0700000001|SEND_MONEY:family_friends|1|$f0']);
      // All 17 built-ins are still there (the v2 copy named 12 of them).
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NOT NULL')).first['n'],
          17);
      expect(await s.canUndo(), isFalse);
      await db.close();
    });
  });

  group('BK3 Replace of a v2 file into a 17-built-in database', () {
    final fixture = File('test/fixtures/backup_v2_anonymised.json').readAsBytesSync();

    Future<List<String>> newSeedRows(DatabaseExecutor db) async => [
          for (final r in await db.rawQuery(
              'SELECT c.id, g.code, c.name, c.active, c.created_at, c.seed_key FROM classifications c '
              'JOIN classification_groups g ON g.id = c.group_id '
              'WHERE c.seed_key IN (${List.filled(5, '?').join(',')}) ORDER BY c.id',
              kV3NewSeedKeys))
            r.values.join('|'),
        ];

    Future<int> classCount(DatabaseExecutor db) async =>
        (await db.rawQuery('SELECT COUNT(*) AS n FROM classifications')).first['n']! as int;

    test('replace_of_a_v2_file_into_a_17_seed_database_succeeds_and_leaves_the_five_new_seeds_untouched', () async {
      final db = await openTestDb();
      await populate(db);
      final fiveBefore = await newSeedRows(db);
      expect(fiveBefore, hasLength(5));
      final file = BackupValidator.validate(fixture);
      expect(file.classifications, hasLength(14));

      final r = await svc(db).restore(fixture, RestoreMode.replace);
      expect(r.classifications, const TableCounts(added: 2, skipped: 12));

      // 17 built-ins stay, plus the file's 2 user classifications; NOT the
      // file's count of 14 (that check would have rolled every v2 Replace back).
      final n = await classCount(db);
      expect(n, 19);
      expect(n, isNot(file.classifications.length));
      expect(n,
          RestoreWriter.expectedReplaceClassCount(
              fileClassifications: 14, dbSeedRows: 17, fileSeedRows: 12, mergedIntoExisting: 0));
      expect(await newSeedRows(db), fiveBefore, reason: 'the five new built-ins are untouched');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      // The file's rows arrived: 8 transactions; the 5 map rows combined to 4.
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM transactions')).first['n'], 8);
      expect(await mapCount(db), 4);
      await db.close();
    });

    test('a file user class that lands on an existing built-in name (Pochi "Transport") still restores', () async {
      final db = await openTestDb();
      final bytes = fileBytes(fileJson(
        classes: [...seedRows(), cls(20, 'POCHI_LA_BIASHARA', 'Transport'), cls(21, 'SEND_MONEY', 'Chama')],
        // A v2 file has no Pochi transaction type, but Cash may sit on any enabled group.
        txs: [tx(1, 'CASH-20260101-0101', 'CASH', 20)],
      ));
      final fiveBefore = await newSeedRows(db);
      final r = await svc(db).restore(bytes, RestoreMode.replace);
      // 12 built-ins + "Transport"(Pochi) matched onto the Pochi built-in = 13
      // skipped; only "Chama" is inserted.
      expect(r.classifications, const TableCounts(added: 1, skipped: 13));
      expect(await classCount(db), 18);
      expect(await newSeedRows(db), fiveBefore);
      final onSeed = await db.rawQuery(
          "SELECT c.seed_key FROM transactions t JOIN classifications c ON c.id = t.classification_id "
          "WHERE t.source_type = 'CASH'");
      expect(onSeed.single['seed_key'], 'POCHI_LA_BIASHARA:transport');
      await db.close();
    });

    test('Merge AND Replace of a v2 file with active user Transport / Groceries / Shopping in the Pochi group: no abort, remapped onto the built-ins (T1.6, C6)',
        () async {
      for (final mode in RestoreMode.values) {
        final db = await openTestDb();
        final fiveBefore = await newSeedRows(db);
        final bytes = fileBytes(fileJson(
          classes: [
            ...seedRows(),
            cls(20, 'POCHI_LA_BIASHARA', 'Transport'),
            cls(21, 'POCHI_LA_BIASHARA', 'Groceries'),
            cls(22, 'POCHI_LA_BIASHARA', 'Shopping'),
          ],
          // A v2 file has no Pochi transaction type; Cash may sit on the group.
          txs: [
            tx(1, 'CASH-20260101-0101', 'CASH', 20, createdAt: f0 + 1),
            tx(2, 'CASH-20260101-0102', 'CASH', 21, createdAt: f0 + 2),
            tx(3, 'CASH-20260101-0103', 'CASH', 22, createdAt: f0 + 3),
          ],
        ));
        final r = await svc(db).restore(bytes, mode);
        expect(r.classifications, const TableCounts(added: 0, skipped: 15), reason: mode.name);
        expect(await classCount(db), 17, reason: '${mode.name}: nothing inserted, nothing lost');
        expect(await newSeedRows(db), fiveBefore, reason: mode.name);
        final seeds = [
          for (final x in await db.rawQuery(
              'SELECT c.seed_key FROM transactions t JOIN classifications c ON c.id = t.classification_id '
              'ORDER BY t.id'))
            x['seed_key'],
        ];
        expect(seeds, [
          'POCHI_LA_BIASHARA:transport', 'POCHI_LA_BIASHARA:groceries', 'POCHI_LA_BIASHARA:shopping',
        ], reason: mode.name);
        await db.close();
      }
    });

    test('expectedReplaceClassCount: the formula, and each wrong shortcut gives a different number', () {
      int f({int file = 14, int db = 17, int seeds = 12, int merged = 0}) =>
          RestoreWriter.expectedReplaceClassCount(
              fileClassifications: file, dbSeedRows: db, fileSeedRows: seeds, mergedIntoExisting: merged);
      // v2 file, 17-built-in database, two user rows: 14 + (17 - 12) = 19.
      expect(f(), 19);
      // A v3 file names all 17: nothing extra.
      expect(f(file: 19, seeds: 17), 19);
      // A user row merged onto an existing name is not inserted.
      expect(f(file: 15, merged: 1), 19);
      // NEGATIVE CONTROLS: the shortcuts are wrong.
      expect(f(), isNot(14), reason: 'the file count alone (the unfixed check)');
      expect(f(file: 15, merged: 1), isNot(f(file: 15, merged: 0)), reason: 'forgetting the merged rows');
      expect(f(), isNot(f(db: 12)), reason: 'forgetting the built-ins the file does not name');
    });
  });

  group('Replace failure inside the map insert still rolls back whole', () {
    test('NEGATIVE CONTROL: a writer that hits a real count mismatch still rolls back', () async {
      // Plan says one thing, the table another: the assertion must still fire.
      final db = await openTestDb();
      await populate(db);
      final before = await fullDump(db);
      final bytes = v2File([mapRow('SEND_MONEY', '0712345678', 1)]);
      var calls = 0;
      final writer = RestoreWriter(beforeRow: (table, i) {
        calls++;
        if (table == 'counterparty_map') throw StateError('injected');
      });
      final s = RestoreService(
        db: () async => db,
        backup: backupOf(db),
        safety: FakeSafetyCopyStore([]),
        settings: BackupSettings(prefs: SharedPreferences.getInstance),
        writer: writer,
        validateInIsolate: false,
      );
      await expectLater(s.restore(bytes, RestoreMode.replace), throwsA(isA<RestoreFailed>()));
      expect(calls, greaterThan(0));
      expect(await fullDump(db), before, reason: 'rolled back whole');
      await db.close();
    });
  });
}
