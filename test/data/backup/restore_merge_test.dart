// B15: restore writer, MERGE mode (Stage 2), on a REAL in-memory database
// with the real schema, triggers and unique indexes. Plain test() only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/schema_v1.dart';
import '../../support/backup_test_data.dart';
import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

RestoreService serviceFor(
  Database db, {
  RestoreWriter writer = const RestoreWriter(),
  List<String>? events,
  BackupSettings? settings,
  bool isolate = false,
}) =>
    RestoreService(
      db: () async => db,
      backup: backupOf(db),
      safety: FakeSafetyCopyStore(events ?? []),
      settings: settings ?? BackupSettings(prefs: SharedPreferences.getInstance),
      writer: writer,
      validateInIsolate: isolate,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('merge_restores_all_valid_rows', () async {
    final db = await openTestDb();
    final r = await serviceFor(db, isolate: true)
        .restore(bytesOf(validBackupJson()), RestoreMode.merge);

    expect(r.classifications, const TableCounts(added: 2, skipped: 3));
    expect(r.transactions, const TableCounts(added: 5));
    expect(r.counterpartyMap, const TableCounts(added: 2));
    expect(r.settingsApplied, isTrue);

    final c = await contentDump(db);
    expect(c['transactions'], hasLength(5));
    // QWE123RTY4 sits on the PAYBILL rent built-in; merge keeps the phone's
    // name ("Rent Payment"), it never renames.
    expect(c['transactions']!.where((s) => s.startsWith('QWE123RTY4|')).single,
        contains('|PAYBILL|Rent Payment|PAYBILL:rent_payment|'));
    // The second cash row points at the new user class "School fees".
    expect(c['transactions']!.where((s) => s.contains('|30000|')).single,
        contains('|SEND_MONEY|School fees|null|'));
    expect(c['classifications'], contains('SEND_MONEY|Old one|0|null|${tBase + 2000}'));
    expect(c['counterparty_map'], hasLength(2));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('palette_id'), 'leaf');
    await db.close();
  });

  test('merge_same_file_twice_issues_no_writes_second_pass', () async {
    final log = <Stmt>[];
    final db = await openTestDb(log: log);
    await populate(db);
    final file = bytesOf(validBackupJson());
    final s = serviceFor(db);
    await s.restore(file, RestoreMode.merge);

    final before = await fullDump(db);
    final changes = await totalChanges(db);
    final mark = log.length;
    final r2 = await s.restore(file, RestoreMode.merge);

    expect(log.sublist(mark).where((x) => x.isWrite), isEmpty,
        reason: 'pass 2 must not INSERT, UPDATE or DELETE');
    expect(await totalChanges(db), changes);
    expect(await fullDump(db), before);
    expect(r2.inserted, 0);
    expect(r2.settings.applied, isEmpty); // prefs were set by pass 1 (A5)
    await db.close();
  });

  test('merge_seed_matched_by_seed_key_even_if_renamed', () async {
    final db = await openTestDb();
    // Phone renamed the SEND_MONEY rent built-in; the file renamed it too, to
    // something else, and also has a user class literally called "Rent".
    await db.update('classifications', {'name': 'Landlord'},
        where: 'seed_key = ?', whereArgs: ['SEND_MONEY:rent']);
    final file = fileJson(
      classes: [
        ...seedRows(renamed: {'SEND_MONEY:rent': 'House'}),
        cls(40, 'SEND_MONEY', 'Rent'),
      ],
      txs: [
        tx(1, 'RRR1111111', 'SEND_MONEY', 2),
        tx(2, 'RRR2222222', 'SEND_MONEY', 40),
      ],
    );
    final r = await serviceFor(db).restore(fileBytes(file), RestoreMode.merge);

    expect(r.classifications, const TableCounts(added: 1, skipped: 12));
    final seeds = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NOT NULL');
    expect(seeds.first['n'], 12, reason: 'no built-in duplicated');
    final rentSeed = await seedId(db, 'SEND_MONEY:rent');
    final seedRow = await db.rawQuery('SELECT name FROM classifications WHERE id = ?', [rentSeed]);
    expect(seedRow.first['name'], 'Landlord', reason: 'merge never renames');
    final t1 = await db.rawQuery(
        "SELECT classification_id FROM transactions WHERE display_code = 'RRR1111111'");
    expect(t1.first['classification_id'], rentSeed);
    final t2 = await db.rawQuery(
        "SELECT c.name, c.seed_key FROM transactions t JOIN classifications c "
        "ON c.id = t.classification_id WHERE display_code = 'RRR2222222'");
    expect(t2.first, {'name': 'Rent', 'seed_key': null});
    await db.close();
  });

  test('merge_rolls_back_whole_restore_on_mid_transaction_failure', () async {
    final db = await openTestDb();
    await populate(db);
    final before = await fullDump(db);
    // 1,200 new rows: two 500-row batches have run when row 1,100 throws.
    final writer = RestoreWriter(beforeRow: (table, i) {
      if (table == 'transactions' && i == 1100) throw StateError('injected');
    });
    await expectLater(
      serviceFor(db, writer: writer).restore(fileBytes(bigFileJson(1200)), RestoreMode.merge),
      throwsA(isA<RestoreFailed>()
          .having((e) => e.reason, 'reason', RestoreFailReason.databaseError)),
    );
    expect(await fullDump(db), before, reason: 'zero partial rows, sqlite_sequence too');
    expect(RestoreFailed.userMessage, 'Could not restore. Nothing was changed.');
    await db.close();
  });

  test('merge_respects_group_scope_trigger', () async {
    final db = await openTestDb();
    await populate(db);
    final before = await fullDump(db);
    // Bypass the validator: a SEND_MONEY entry on a PAYBILL classification.
    final bad = fileJson(
      classes: [cls(1, 'PAYBILL', 'Bills'), cls(2, 'SEND_MONEY', 'Ok')],
      txs: [tx(1, 'GGG1111111', 'SEND_MONEY', 2), tx(2, 'GGG2222222', 'SEND_MONEY', 1)],
    );
    await expectLater(
      db.transaction((txn) => const RestoreWriter().merge(txn, unvalidated(bad))),
      throwsA(isA<DatabaseException>()),
    );
    expect(await fullDump(db), before);
    // Through the service the validator refuses the file first.
    await expectLater(
      serviceFor(db).restore(fileBytes(bad), RestoreMode.merge),
      throwsA(isA<RestoreRejected>()
          .having((e) => e.reason, 'reason', RestoreRejectReason.invalidRow)),
    );
    expect(await fullDump(db), before);
    await db.close();
  });

  test('merge_cash_dedupe_on_code_and_created_at', () async {
    final db = await openTestDb();
    final file = fileBytes(fileJson(classes: seedRows(), txs: [
      tx(1, 'CASH-20260921-1030', 'CASH', 1, amount: 500, createdAt: f0 + 1),
      tx(2, 'CASH-20260921-1030', 'CASH', 3, amount: 900, createdAt: f0 + 2),
    ]));
    final s = serviceFor(db);
    final r1 = await s.restore(file, RestoreMode.merge);
    expect(r1.transactions, const TableCounts(added: 2));

    // The user edits one cash entry's amount; display_code and created_at
    // never change on edit, so it still matches.
    await db.rawUpdate("UPDATE transactions SET amount_cents = 1 WHERE amount_cents = 500");
    final r2 = await s.restore(file, RestoreMode.merge);
    expect(r2.transactions, const TableCounts(skipped: 2));
    final n = await db.rawQuery("SELECT COUNT(*) AS n FROM transactions WHERE source_type = 'CASH'");
    expect(n.first['n'], 2);

    // Same code, a different created_at = a different cash entry.
    final other = fileBytes(fileJson(classes: seedRows(), txs: [
      tx(1, 'CASH-20260921-1030', 'CASH', 1, createdAt: f0 + 3),
    ]));
    expect((await s.restore(other, RestoreMode.merge)).transactions,
        const TableCounts(added: 1));
    await db.close();
  });

  test('merge_never_edits_or_deletes_existing_rows', () async {
    final log = <Stmt>[];
    final db = await openTestDb(log: log);
    await populate(db);
    final before = await fullDump(db);
    final mark = log.length;
    final file = fileJson(
      classes: [...seedRows(renamed: {'PAYBILL:shopping': 'Mall'}), cls(20, 'SEND_MONEY', 'Church', active: 0)],
      txs: [
        tx(1, 'AAA1111111', 'SEND_MONEY', 2, amount: 999999), // phone has it: amount stays
        tx(2, 'NEW1111111', 'BUY_GOODS', 10),
      ],
      map: [mapRow('SEND_MONEY', '0712345678', 1)], // phone's learned choice wins
    );
    final r = await serviceFor(db).restore(fileBytes(file), RestoreMode.merge);
    expect(r.transactions, const TableCounts(added: 1, skipped: 1));
    expect(r.counterpartyMap, const TableCounts(skipped: 1));

    final verbs = log.sublist(mark).where((x) => x.isWrite).map((x) => x.verb).toSet();
    expect(verbs, {'INSERT'});
    final after = await fullDump(db);
    for (final t in const ['classifications', 'transactions', 'counterparty_classification_map']) {
      final old = before[t]!;
      expect(after[t]!.sublist(0, old.length), old, reason: '$t rows unchanged');
    }
    await db.close();
  });

  test('restore_sql_uses_bound_parameters_only', () async {
    // 1. Static scan: no interpolation or concatenation in restore SQL; every
    // statement call takes a const `_...Sql` name.
    for (final path in const [
      'lib/data/backup/restore_writer.dart',
      'lib/data/backup/restore_plan.dart',
      'lib/data/backup/restore_service.dart',
    ]) {
      final lines = File(path).readAsLinesSync();
      final sqlWord = RegExp(r"'[^']*\b(SELECT|INSERT|UPDATE|DELETE|PRAGMA)\b[^']*'");
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (sqlWord.hasMatch(l)) {
          expect(l.contains(r'$'), isFalse, reason: '$path:${i + 1} interpolates into SQL');
        }
        expect(RegExp(r"\b(execute|rawQuery|rawInsert|rawUpdate|rawDelete)\((?!\s*('|_|sql\b|$))").hasMatch(l),
            isFalse, reason: '$path:${i + 1} passes a non-const SQL string');
      }
    }
    final writer = File('lib/data/backup/restore_writer.dart').readAsStringSync();
    expect(RegExp(r'txn\.(rawInsert|rawUpdate|rawDelete|rawQuery|execute|insert|update|delete)\((?!_)')
        .hasMatch(writer), isFalse);
    expect(RegExp(r'batch\.rawInsert\((?!_insert|sql)').hasMatch(writer), isFalse);

    // 2. Statement log of a real restore with hostile text.
    final log = <Stmt>[];
    final db = await openTestDb(log: log);
    const evil = "x'); DROP TABLE transactions;--";
    const evil2 = '" OR 1=1 --';
    final file = fileJson(
      classes: [...seedRows(), cls(30, 'PAYBILL', evil)],
      txs: [tx(1, 'SQL1111111', 'PAYBILL', 30, label: evil2, account: evil)],
      map: [mapRow('PAYBILL', '$evil2#$evil', 30)],
    );
    final mark = log.length;
    await serviceFor(db).restore(fileBytes(file), RestoreMode.merge);
    final writes = log.sublist(mark).where((x) => x.isWrite).toList();
    expect(writes, isNotEmpty);
    final allowed = {
      'INSERT INTO classifications (${kRestoreClassColumns.join(', ')})',
      'INSERT INTO transactions (${kRestoreTxColumns.join(', ')})',
      'INSERT INTO counterparty_classification_map (${kRestoreMapColumns.join(', ')})',
    };
    for (final w in writes) {
      expect(w.sql.contains(evil) || w.sql.contains(evil2), isFalse);
      expect(w.sql, contains('?'));
      expect(allowed.any(w.sql.startsWith), isTrue, reason: w.sql);
      expect(w.args, isA<List>());
    }
    // Stored verbatim as text; every table still there.
    final name = await db.rawQuery('SELECT name FROM classifications WHERE name = ?', [evil]);
    expect(name, hasLength(1));
    expect((await db.rawQuery('SELECT COUNT(*) AS n FROM transactions')).first['n'], 1);
    await db.close();
  });

  test('restore_never_reuses_file_ids', () async {
    final db = await openTestDb();
    await populate(db); // ids 13.. are taken by the phone's own rows
    final before = await fullDump(db);
    final churchId = await classId(db, 'SEND_MONEY', 'Church');
    final file = fileJson(
      classes: [
        cls(churchId, 'SEND_MONEY', 'Gym'), // same id as the phone's "Church"
        cls(999, 'BUY_GOODS', 'Kiosk'),
        cls(900, 'PAYBILL', 'Water', active: 0),
        ...seedRows().map((r) => {...r, 'id': (r['id']! as int) + 500}),
      ],
      txs: [
        tx(1, 'IDS1111111', 'SEND_MONEY', churchId), // tx id 1 exists on phone
        tx(950, 'IDS2222222', 'BUY_GOODS', 999),
        tx(2, 'IDS3333333', 'PAYBILL', 900),
      ],
    );
    await serviceFor(db).restore(fileBytes(file), RestoreMode.merge);

    final after = await fullDump(db);
    for (final t in const ['classifications', 'transactions']) {
      expect(after[t]!.sublist(0, before[t]!.length), before[t], reason: '$t untouched');
      expect(after[t]!.map((r) => r['id'] as int).every((id) => id < 900), isTrue);
    }
    final gym = await db.rawQuery(
        "SELECT c.id, c.name FROM transactions t JOIN classifications c "
        "ON c.id = t.classification_id WHERE t.display_code = 'IDS1111111'");
    expect(gym.first['name'], 'Gym');
    expect(gym.first['id'], isNot(churchId));
    await db.close();
  });

  test('merge_after_soft_delete_restores_live_row (A6)', () async {
    final db = await openTestDb();
    await populate(db); // EEE1111111 is recently deleted on the phone
    final file = fileJson(classes: seedRows(), txs: [tx(1, 'EEE1111111', 'SEND_MONEY', 1, amount: 4242)]);
    final r = await serviceFor(db).restore(fileBytes(file), RestoreMode.merge);
    expect(r.transactions, const TableCounts(added: 1));
    final rows = await db.rawQuery(
        "SELECT amount_cents, deleted_at FROM transactions WHERE display_code = 'EEE1111111' ORDER BY id");
    expect(rows, hasLength(2));
    expect(rows.last, {'amount_cents': 4242, 'deleted_at': null});
    expect(rows.first['deleted_at'], isNotNull, reason: 'the deleted one is left as it was');
    await db.close();
  });

  test('merge_skips_existing_mpesa_code', () async {
    final db = await openTestDb();
    final rent = await seedId(db, 'SEND_MONEY:rent');
    await addTx(db, code: 'XXX1111111', source: 'SEND_MONEY', classId: rent, amount: 100);
    final file = fileJson(classes: seedRows(), txs: [
      tx(1, 'XXX1111111', 'SEND_MONEY', 2, amount: 999),
      tx(2, 'YYY1111111', 'SEND_MONEY', 2),
    ]);
    final r = await serviceFor(db).restore(fileBytes(file), RestoreMode.merge);
    expect(r.transactions, const TableCounts(added: 1, skipped: 1));
    final x = await db.rawQuery("SELECT amount_cents FROM transactions WHERE display_code = 'XXX1111111'");
    expect(x.single['amount_cents'], 100);
    await db.close();
  });

  test('inspect_previews_counts_and_writes_nothing', () async {
    final log = <Stmt>[];
    final db = await openTestDb(log: log);
    await populate(db);
    final before = await fullDump(db);
    final mark = log.length;
    final p = await serviceFor(db, isolate: true).inspect(bytesOf(validBackupJson()));
    expect(log.sublist(mark).where((x) => x.isWrite), isEmpty);
    expect(await fullDump(db), before);
    expect(p.fileTransactions, 5);
    expect(p.newTransactions, 5);
    expect(p.duplicateTransactions, 0);
    expect(p.newClassifications, 2);
    expect(p.phoneTransactions, 7);
    expect(p.phoneUserClassifications, 3);
    expect(p.phoneCounterpartyMap, 2);
    expect(p.phoneRecentlyDeleted, 1);
    expect(p.fileSchemaVersion, 2);
    await expectLater(serviceFor(db).inspect(bytesOf({'app': 'other'})),
        throwsA(isA<RestoreRejected>()));
    await db.close();
  });

  test('restore_unavailable_below_v2', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onCreate: (db, v) async {
            await AppSchemaV1.createSchema(db);
            await AppSchemaV1.seed(db);
          },
        ));
    await expectLater(
      serviceFor(db).restore(bytesOf(validBackupJson()), RestoreMode.merge),
      throwsA(isA<RestoreFailed>()
          .having((e) => e.reason, 'reason', RestoreFailReason.schemaTooOld)),
    );
    await db.close();
  });
}
