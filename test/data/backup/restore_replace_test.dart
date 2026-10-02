// B16: REPLACE mode, the safety copy, settings after commit, and Undo. Real
// in-memory database; fakes record call order. Plain test() only.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_writer.dart';
import 'package:mmogo/data/backup/safety_copy_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/backup_test_data.dart';
import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

/// SQL writes since [mark] as `sql:VERB` (from sqflite's own logger).
List<String> writesSince(List<Stmt> log, int mark) =>
    [for (final s in log.sublist(mark)) if (s.isWrite) 'sql:${s.verb}'];

RestoreService svc(
  Database db, {
  SafetyCopyStore? safety,
  BackupSettings? settings,
  RestoreWriter writer = const RestoreWriter(),
}) =>
    RestoreService(
      db: () async => db,
      backup: backupOf(db),
      safety: safety ?? FakeSafetyCopyStore([]),
      settings: settings ?? BackupSettings(prefs: SharedPreferences.getInstance),
      writer: writer,
      validateInIsolate: false,
    );

Uint8List replacementFile() => fileBytes(fileJson(
      classes: [
        ...seedRows(renamed: {'SEND_MONEY:rent': 'Nyumba'}),
        cls(20, 'BUY_GOODS', 'Kiosk'),
        cls(21, 'SEND_MONEY', 'Chama', active: 0),
      ],
      txs: [
        tx(1, 'NEW1111111', 'SEND_MONEY', 2, label: 'MAMA', phone: '0700000001'),
        tx(2, 'NEW2222222', 'BUY_GOODS', 20),
        tx(3, 'CASH-20260930-0800', 'CASH', 21, createdAt: f0 + 5),
      ],
      map: [mapRow('SEND_MONEY', '0700000001', 2)],
      prefs: {'palette_id': 'indigo', 'user_display_name': 'Wanjiru'},
    ));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('replace_never_writes_before_validation_completes', () async {
    final events = <String>[];
    final log = <Stmt>[];
    final db = await openTestDb(log: log);
    await populate(db);
    final before = await fullDump(db);
    final safety = FakeSafetyCopyStore(events);
    final mark = log.length;
    // Valid up to the LAST transaction row, which is bad: the whole file is
    // read before anything happens.
    final json = bigFileJson(300);
    (json['transactions']! as List<Map<String, Object?>>).last['amount_cents'] = 0;
    await expectLater(svc(db, safety: safety).restore(fileBytes(json), RestoreMode.replace),
        throwsA(isA<RestoreRejected>()));
    expect(events, isEmpty, reason: 'no safety copy for a bad file');
    expect(writesSince(log, mark), isEmpty);
    expect(await fullDump(db), before);
    await db.close();
  });

  test('replace_makes_safety_copy_before_transaction', () async {
    final events = <String>[];
    final log = <Stmt>[];
    final db = await openTestDb(log: log);
    await populate(db);
    final phoneBefore = await contentDump(db);
    final safety = _OrderedSafety(events, log)..markNow();
    final mark = log.length;
    final r = await svc(db, safety: safety).restore(replacementFile(), RestoreMode.replace);
    events.addAll(writesSince(log, mark));

    expect(events.first, 'safety.write');
    expect(safety.writesBeforeCopy, 0, reason: 'no SQL write before the copy is safe');
    expect(events.indexOf('sql:DELETE'), greaterThan(events.indexOf('safety.write')));
    expect(r.safetyCopyKept, isTrue);
    // The copy holds the phone's old data.
    final copyDb = await openTestDb();
    await svc(copyDb).restore(safety.bytes!, RestoreMode.replace);
    expect(await contentDump(copyDb), phoneBefore);
    await copyDb.close();
    await db.close();
  });

  test('replace_aborts_if_safety_copy_unreadable', () async {
    final log = <Stmt>[];
    final db = await openTestDb(log: log);
    await populate(db);
    final before = await fullDump(db);
    for (final safety in [
      FakeSafetyCopyStore([], unreadable: true),
      FakeSafetyCopyStore([], failWrite: true),
    ]) {
      final mark = log.length;
      await expectLater(
        svc(db, safety: safety).restore(replacementFile(), RestoreMode.replace),
        throwsA(isA<RestoreFailed>()
            .having((e) => e.reason, 'reason', RestoreFailReason.safetyCopyFailed)),
      );
      expect(writesSince(log, mark), isEmpty);
      expect(await fullDump(db), before);
    }
    await db.close();
  });

  test('replace_keeps_seed_classifications', () async {
    final db = await openTestDb();
    await populate(db);
    final seedIdsBefore = await db.rawQuery(
        'SELECT id, seed_key FROM classifications WHERE seed_key IS NOT NULL ORDER BY id');
    final r = await svc(db).restore(replacementFile(), RestoreMode.replace);

    expect(await db.rawQuery(
        'SELECT id, seed_key FROM classifications WHERE seed_key IS NOT NULL ORDER BY id'),
        seedIdsBefore, reason: 'same 12 built-in rows, same ids');
    expect(r.tally.builtInsUpdated, 12);
    expect(r.classifications, const TableCounts(added: 2, skipped: 12));
    expect(r.transactions, const TableCounts(added: 3));
    final c = await contentDump(db, withDeleted: true);
    expect(c['classifications']!.where((s) => !s.contains(':')), hasLength(2)); // Kiosk, Chama
    expect(c['classifications'], contains('SEND_MONEY|Nyumba|1|SEND_MONEY:rent|$f0'));
    expect(c['classifications'], contains('BUY_GOODS|Groceries|1|BUY_GOODS:groceries|$f0'),
        reason: 'the file\'s active flag and name win');
    expect(c['transactions'], hasLength(3), reason: 'old rows, recently deleted too, are gone');
    expect(c['counterparty_map'], hasLength(1));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test('replace_applies_seed_rename_and_swap', () async {
    final db = await openTestDb();
    final file = fileJson(classes: seedRows(renamed: {
      'PAYBILL:shopping': 'Transport',
      'PAYBILL:transport': 'Shopping',
    }));
    await svc(db).restore(fileBytes(file), RestoreMode.replace);
    final rows = await db.rawQuery(
        "SELECT seed_key, name FROM classifications WHERE seed_key IN ('PAYBILL:shopping','PAYBILL:transport') ORDER BY seed_key");
    expect(rows, [
      {'seed_key': 'PAYBILL:shopping', 'name': 'Transport'},
      {'seed_key': 'PAYBILL:transport', 'name': 'Shopping'},
    ]);
    await db.close();
  });

  test('settings_applied_only_after_commit', () async {
    final events = <String>[];
    final db = await openTestDb();
    await populate(db);
    int? liveAtApply;
    final settings = RecordingSettings(events, probe: () async {
      // A query OUTSIDE the transaction: it could not run (it would wait)
      // while the restore transaction were still open, and it sees the new
      // rows, so the commit has happened.
      liveAtApply = (await db.rawQuery(
              "SELECT COUNT(*) AS n FROM transactions WHERE display_code LIKE 'NEW%'"))
          .first['n'] as int;
    });
    await svc(db, safety: FakeSafetyCopyStore(events), settings: settings)
        .restore(replacementFile(), RestoreMode.replace);
    expect(events, ['safety.write', 'settings.apply']);
    expect(liveAtApply, 2);
    expect(settings.onlyIfUnsetCalls, [false], reason: 'replace overwrites');

    // Merge passes onlyIfUnset; a failed restore never applies settings.
    await svc(db, settings: settings).restore(bytesOf(validBackupJson()), RestoreMode.merge);
    expect(settings.onlyIfUnsetCalls, [false, true]);
    final writer = RestoreWriter(beforeRow: (t, i) => throw StateError('boom'));
    await expectLater(
        svc(db, settings: settings, writer: writer).restore(fileBytes(bigFileJson(3, prefix: 'Z')), RestoreMode.merge),
        throwsA(isA<RestoreFailed>()));
    expect(settings.onlyIfUnsetCalls, hasLength(2));
    await db.close();
  });

  test('replace_failure_rolls_back_and_keeps_old_data', () async {
    final db = await openTestDb();
    await populate(db);
    final before = await fullDump(db);
    final writer = RestoreWriter(beforeRow: (t, i) {
      if (t == 'counterparty_map') throw StateError('injected after deletes and inserts');
    });
    await expectLater(
      svc(db, writer: writer).restore(replacementFile(), RestoreMode.replace),
      throwsA(isA<RestoreFailed>()
          .having((e) => e.reason, 'reason', RestoreFailReason.databaseError)),
    );
    expect(await fullDump(db), before, reason: 'deletes, renames and inserts all undone');
    await db.close();
  });

  test('replace_refused_when_the_safety_copy_would_leave_rows_out', () async {
    final db = await openTestDb();
    await populate(db);
    // A legacy row the exporter must skip (amount over the file cap).
    await addTx(db, code: 'BIG1111111', source: 'BUY_GOODS',
        classId: await seedId(db, 'BUY_GOODS:shopping'), amount: 99999999999);
    final before = await fullDump(db);
    final events = <String>[];
    await expectLater(
      svc(db, safety: FakeSafetyCopyStore(events)).restore(replacementFile(), RestoreMode.replace),
      throwsA(isA<RestoreFailed>()
          .having((e) => e.reason, 'reason', RestoreFailReason.safetyCopyIncomplete)),
    );
    expect(events, isEmpty);
    expect(await fullDump(db), before);
    await db.close();
  });

  test('replace_refused_when_data_changed_after_the_safety_copy', () async {
    final db = await openTestDb();
    await populate(db);
    final safety = _SneakySafety(db);
    await expectLater(
      svc(db, safety: safety).restore(replacementFile(), RestoreMode.replace),
      throwsA(isA<RestoreFailed>()
          .having((e) => e.reason, 'reason', RestoreFailReason.dataChangedMeanwhile)),
    );
    expect((await db.rawQuery("SELECT COUNT(*) AS n FROM transactions WHERE display_code = 'LATE111111'"))
        .first['n'], 1);
    await db.close();
  });

  test('undo_last_replace_restores_previous_data', () async {
    SharedPreferences.setMockInitialValues({'palette_id': 'leaf'});
    final db = await openTestDb();
    await populate(db);
    final before = await contentDump(db);
    final safety = FakeSafetyCopyStore([]);
    final s = svc(db, safety: safety);
    await s.restore(replacementFile(), RestoreMode.replace);
    expect(await contentDump(db), isNot(before));
    expect((await SharedPreferences.getInstance()).getString('palette_id'), 'indigo');
    expect(await s.canUndo(), isTrue);

    final u = await s.undoLastReplace();
    expect(await contentDump(db), before, reason: 'content equal; ids may differ');
    expect((await SharedPreferences.getInstance()).getString('palette_id'), 'leaf');
    expect(u.transactions.added, 7);
    expect(await s.canUndo(), isFalse, reason: 'the copy is removed after a good undo');
    await expectLater(s.undoLastReplace(), throwsA(isA<RestoreFailed>()
        .having((e) => e.reason, 'reason', RestoreFailReason.noSafetyCopy)));
    await db.close();
  });

  test('merge_applies_only_unset_prefs_replace_overwrites (A5) and denied keys are never read (A4)', () async {
    SharedPreferences.setMockInitialValues({
      'palette_id': 'leaf',
      'update_check_enabled': true,
      'auto_backup_folder_uri': 'content://mine',
    });
    final json = validBackupJson();
    json['prefs'] = {
      'palette_id': 'ocean',
      'user_display_name': 'Amina',
      'update_check_enabled': false,
      'update_last_check_at': 1,
      'auto_backup_folder_uri': 'content://evil',
      'auto_backup_enabled': true,
      'last_seen_version': '99.0.0',
      'onboarding_complete': true,
    };
    final db = await openTestDb();
    final r = await svc(db).restore(bytesOf(json), RestoreMode.merge);
    final p1 = await SharedPreferences.getInstance();
    expect(r.settingsApplied, isTrue);
    expect(p1.getString('palette_id'), 'leaf');
    expect(p1.getString('user_display_name'), 'Amina');
    expect(p1.getBool('update_check_enabled'), isTrue);
    expect(p1.getString('auto_backup_folder_uri'), 'content://mine');
    for (final k in const ['update_last_check_at', 'auto_backup_enabled', 'last_seen_version', 'onboarding_complete']) {
      expect(p1.containsKey(k), isFalse, reason: k);
    }
    await svc(db).restore(bytesOf(json), RestoreMode.replace);
    final p2 = await SharedPreferences.getInstance();
    expect(p2.getString('palette_id'), 'ocean');
    expect(p2.getBool('update_check_enabled'), isTrue);
    expect(p2.getString('auto_backup_folder_uri'), 'content://mine');
    await db.close();
  });

  group('SafetyCopyStore (real files in a temp folder)', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('mmogo_safety_'));
    tearDown(() async => tmp.delete(recursive: true));

    test('keeps_only_the_newest_verified_copy', () async {
      var clock = DateTime(2026, 10, 2, 9, 0, 0);
      final store = SafetyCopyStore(baseDir: () async => tmp, now: () => clock);
      const expect3 = ExpectedRows(transactions: 3, classifications: 14, counterpartyMap: 1);
      final a = await store.write(replacementFile(), expect: expect3);
      clock = clock.add(const Duration(seconds: 1));
      final b = await store.write(replacementFile(), expect: expect3);
      expect(await a.exists(), isFalse);
      expect(await b.exists(), isTrue);
      expect(p.dirname(b.path), p.join(tmp.path, 'safety'));
      expect(SafetyCopyStore.namePattern.hasMatch(p.basename(b.path)), isTrue);
      expect(await store.readLatest(), replacementFile());
      await store.clear();
      expect(await store.exists(), isFalse);
    });

    test('a_bad_copy_is_refused_and_the_older_one_kept', () async {
      var clock = DateTime(2026, 10, 2, 9, 0, 0);
      final store = SafetyCopyStore(baseDir: () async => tmp, now: () => clock);
      const good = ExpectedRows(transactions: 3, classifications: 14, counterpartyMap: 1);
      final first = await store.write(replacementFile(), expect: good);
      clock = clock.add(const Duration(seconds: 1));
      await expectLater(
          store.write(replacementFile(),
              expect: const ExpectedRows(transactions: 4, classifications: 14, counterpartyMap: 1)),
          throwsA(isA<SafetyCopyError>()));
      clock = clock.add(const Duration(seconds: 1));
      await expectLater(store.write(Uint8List.fromList([1, 2, 3]), expect: good),
          throwsA(isA<SafetyCopyError>()));
      expect(await first.exists(), isTrue);
      expect((await store.latest())!.path, first.path);
      expect(tmp.listSync(recursive: true).whereType<File>(), hasLength(1));
    });
  });
}

/// Records whether any SQL write happened before the copy was made.
class _OrderedSafety extends FakeSafetyCopyStore {
  _OrderedSafety(super.events, this.log);
  final List<Stmt> log;
  int? writesBeforeCopy;
  int _mark = 0;

  @override
  Future<File> write(Uint8List data,
      {required ExpectedRows expect,
      Set<String> enabledGroupCodes = BackupValidator.defaultEnabledGroups}) {
    writesBeforeCopy = log.sublist(_mark).where((s) => s.isWrite).length;
    return super.write(data, expect: expect, enabledGroupCodes: enabledGroupCodes);
  }

  void markNow() => _mark = log.length;
}

/// Adds an entry right after the copy is made (another write sneaking in).
class _SneakySafety extends FakeSafetyCopyStore {
  _SneakySafety(this.db) : super([]);
  final Database db;

  @override
  Future<File> write(Uint8List data,
      {required ExpectedRows expect,
      Set<String> enabledGroupCodes = BackupValidator.defaultEnabledGroups}) async {
    final f = await super.write(data, expect: expect, enabledGroupCodes: enabledGroupCodes);
    await addTx(db, code: 'LATE111111', source: 'SEND_MONEY',
        classId: await seedId(db, 'SEND_MONEY:rent'));
    return f;
  }
}
