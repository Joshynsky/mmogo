// 0.1.2 S9b-1: "Delete my transactions" (Level 1), DeleteDataServiceImpl against
// a REAL SQLite file in a TEMP directory, mock prefs, a temp safety folder and
// fakes (see test/support/data_op_env.dart; every path is asserted to be under
// Directory.systemTemp). Plain test(): a real Database hangs in testWidgets.
//
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/db/app_database.dart';
import 'package:mmogo/data/maintenance/data_op_gate.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/data/maintenance/device_keys.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/data_op_env.dart';
import '../../support/restore_test_db.dart' show fullDump, backupOf, exportOf;

class _ForgetLies extends RecipientMemory {
  @override
  Future<bool> forgetAll() async => true; // says yes, removes nothing
}

class _ForgetFalse extends RecipientMemory {
  @override
  Future<bool> forgetAll() async => false;
}

Future<Map<String, Object?>> _kept(DataOpEnv env) async {
  final m = await env.prefsMap();
  return {
    for (final e in m.entries)
      if (!const {
        'recipient_types_v1',
        'pending_entries_v1',
        'phone_merge_report_v1',
        'auto_backup_since_count',
      }.contains(e.key))
        e.key: e.value,
  };
}

Future<int> _safetyFiles(DataOpEnv env) async {
  final dir = Directory(p.join(env.safetyBase.path, 'safety'));
  if (!await dir.exists()) return 0;
  return dir.list().length;
}

RestoreService _restoreService(DataOpEnv env) => RestoreService(
      db: env.open,
      backup: BackupService(db: env.open),
      safety: env.safety,
      validateInIsolate: false,
      gate: env.gate,
    );

void main() {
  late DataOpEnv env;

  setUp(() async {
    env = await DataOpEnv.create();
    await env.populateAll();
  });
  tearDown(() => env.dispose());

  test('harness: every path is under the system temp directory', () {
    assertUnderTemp(env.dbPath);
    assertUnderTemp(env.safetyBase.path);
    assertUnderTemp(env.root.path);
  });

  group('1. the database part', () {
    test('rows gone (live and soft-deleted), map gone, categories and sequence untouched, next id is higher', () async {
      final db = await env.open();
      final before = await fullDump(db);
      final maxId = await env.count('SELECT MAX(id) FROM transactions');
      final live = await env.count('SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL');
      final soft = await env.count('SELECT COUNT(*) FROM transactions WHERE deleted_at IS NOT NULL');
      final learned = await env.count('SELECT COUNT(*) FROM counterparty_classification_map');
      expect(live, greaterThan(8));
      expect(soft, greaterThan(0));
      expect(learned, greaterThan(0));

      final r = await env.service().deleteMyTransactions();

      expect(r.outcome, DeleteDataOutcome.done);
      expect(r.transactionsDeleted, live);
      expect(r.softDeletedIncluded, soft);
      expect(r.learnedReceiversDeleted, learned);
      expect(r.safetyCopyCleared, isTrue);
      expect(r.failedStep, isNull);
      expect(await env.count('SELECT COUNT(*) FROM transactions'), 0);
      expect(await env.count('SELECT COUNT(*) FROM counterparty_classification_map'), 0);
      final after = await fullDump(db);
      expect(after['classification_groups'], before['classification_groups']);
      expect(after['classifications'], before['classifications']);
      expect(after['sqlite_sequence'], before['sqlite_sequence']);
      final cats = await db.rawQuery('SELECT name FROM classifications WHERE seed_key IS NULL ORDER BY name');
      expect(cats.map((e) => e['name']), containsAll(['Church', 'Old shop', 'School fees']));

      // A stale id never aliases a new row (AUTOINCREMENT keeps counting).
      final cls = await env.count('SELECT id FROM classifications WHERE seed_key IS NOT NULL ORDER BY id LIMIT 1');
      final group = await env.count('SELECT g.id FROM classification_groups g JOIN classifications c ON c.group_id = g.id WHERE c.id = $cls');
      expect(group, greaterThan(0));
      final newId = await db.insert('transactions', {
        'display_code': 'NEWCODE001',
        'source_type': 'CASH',
        'amount_cents': 100,
        'transaction_cost_cents': null,
        'classification_id': await env.count(
            "SELECT c.id FROM classifications c JOIN classification_groups g ON g.id = c.group_id WHERE g.code = 'SEND_MONEY' LIMIT 1"),
        'raw_parse_source': 'MANUAL',
        'transaction_occurred_at': 1,
        'created_at': 1,
      });
      expect(newId, greaterThan(maxId));
    });

    test('foreign_key_check is empty and the file still has the 17 seeded built-ins', () async {
      await env.service().deleteMyTransactions();
      final db = await env.open();
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(await env.count('SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL'), 17);
    });
  });

  test('2. kept prefs are unchanged; removed prefs are gone; the counter is 0', () async {
    final keptBefore = await _kept(env);
    expect(keptBefore.keys, containsAll(['user_display_name', 'palette_id', 'auto_backup_written_uris', 'auto_backup_folder_uri']));
    final r = await env.service().deleteMyTransactions();
    expect(r.outcome, DeleteDataOutcome.done);
    expect(await _kept(env), keptBefore);
    final after = await env.prefsMap();
    expect(after.containsKey('recipient_types_v1'), isFalse);
    expect(after.containsKey('pending_entries_v1'), isFalse);
    expect(after.containsKey('phone_merge_report_v1'), isFalse);
    expect(after['auto_backup_since_count'], 0);
  });

  test('3. the safety folder is empty (copy and .partial) and Undo of Replace is not offered', () async {
    expect(await _safetyFiles(env), 2);
    expect(await env.safety.exists(), isTrue);
    await env.service().deleteMyTransactions();
    expect(await _safetyFiles(env), 0);
    expect(await env.safety.exists(), isFalse);
    expect(await _restoreService(env).canUndo(), isFalse);
  });

  test('4. the result carries counts only: no name, code or amount anywhere in it', () async {
    final r = await env.service().deleteMyTransactions();
    final text = r.toString();
    for (final secret in ['INVENTED', 'JANE', '0712', 'AAA1', 'SCHOOL', 'DUKA', '123456', 'Invented']) {
      expect(text.contains(secret), isFalse, reason: secret);
    }
    final peek = await env.service().peek();
    expect(peek.rememberedRecipientsCount, 0);
  });

  group('5. the verify guard', () {
    test('a non-zero count after the delete rolls everything back and runs none of b-e', () async {
      final db = await env.open();
      final before = await fullDump(db);
      final prefsBefore = await env.prefsMap();
      final r = await env.service(countRows: (_, table) async => table == 'transactions' ? 3 : 0).deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.nothingWasDeleted);
      expect(r.transactionsDeleted, 0);
      expect(await fullDump(db), before, reason: 'rolled back whole');
      expect(await env.prefsMap(), prefsBefore, reason: 'steps c-e not run');
      expect(await _safetyFiles(env), 2, reason: 'step b not run');
      expect(env.gate.isHeld, isFalse);
    });
  });

  group('6. failure injection: notFinished with the step, DB part committed, retry ends clean', () {
    Future<void> expectClean() async {
      expect(await env.count('SELECT COUNT(*) FROM transactions'), 0);
      expect(await env.count('SELECT COUNT(*) FROM counterparty_classification_map'), 0);
      expect(await _safetyFiles(env), 0);
      final m = await env.prefsMap();
      expect(m.containsKey('recipient_types_v1'), isFalse);
      expect(m.containsKey('pending_entries_v1'), isFalse);
      expect(m['auto_backup_since_count'], 0);
    }

    test('map delete fails (trigger): rolled back, retry ends clean', () async {
      final db = await env.open();
      await db.execute(
          "CREATE TRIGGER t_map BEFORE DELETE ON counterparty_classification_map BEGIN SELECT RAISE(ABORT, 'no'); END");
      final before = await env.count('SELECT COUNT(*) FROM transactions');
      final r = await env.service().deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(r.failedStep, DeleteDataStep.database);
      expect(await env.count('SELECT COUNT(*) FROM transactions'), before);
      expect(await _safetyFiles(env), 2);
      await db.execute('DROP TRIGGER t_map');
      expect((await env.service().deleteMyTransactions()).outcome, DeleteDataOutcome.done);
      await expectClean();
    });

    test('transaction delete fails (trigger): the map delete is rolled back too', () async {
      final db = await env.open();
      await db.execute("CREATE TRIGGER t_tx BEFORE DELETE ON transactions BEGIN SELECT RAISE(ABORT, 'no'); END");
      final mapBefore = await env.count('SELECT COUNT(*) FROM counterparty_classification_map');
      final r = await env.service().deleteMyTransactions();
      expect(r.failedStep, DeleteDataStep.database);
      expect(await env.count('SELECT COUNT(*) FROM counterparty_classification_map'), mapBefore);
      await db.execute('DROP TRIGGER t_tx');
      expect((await env.service().deleteMyTransactions()).outcome, DeleteDataOutcome.done);
      await expectClean();
    });

    test('VACUUM throws: still a success, vacuumRan false', () async {
      final r = await env.service(vacuum: (_) async => throw StateError('vacuum')).deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(r.vacuumRan, isFalse);
      await expectClean();
    });

    test('VACUUM works: vacuumRan true (real VACUUM on the temp file)', () async {
      final r = await env.service().deleteMyTransactions();
      expect(r.vacuumRan, isTrue);
    });

    test('clearVerified fails: notFinished at safetyCopy, rows already gone, retry clean', () async {
      env.safety.failClear = true;
      final r = await env.service().deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(r.failedStep, DeleteDataStep.safetyCopy);
      expect(r.transactionsDeleted, greaterThan(0), reason: 'the database part stays committed');
      expect(await env.count('SELECT COUNT(*) FROM transactions'), 0);
      expect(await env.prefsMap().then((m) => m.containsKey('recipient_types_v1')), isTrue, reason: 'c not run');
      env.safety.failClear = false;
      final again = await env.service().deleteMyTransactions();
      expect(again.outcome, DeleteDataOutcome.done);
      expect(again.transactionsDeleted, 0);
      await expectClean();
    });

    test('exists() throwing after the clear counts as a failure of step safetyCopy', () async {
      env.safety.existsThrows = true;
      final r = await env.service().deleteMyTransactions();
      expect(r.failedStep, DeleteDataStep.safetyCopy);
    });

    test('forgetAll returns false: notFinished at recipientMemory; retry clean', () async {
      final r = await env.service(memory: _ForgetFalse()).deleteMyTransactions();
      expect(r.failedStep, DeleteDataStep.recipientMemory);
      expect(r.safetyCopyCleared, isTrue);
      expect((await env.service().deleteMyTransactions()).outcome, DeleteDataOutcome.done);
      await expectClean();
    });

    test('forgetAll says true but the key is still stored on a fresh read: recipientMemory', () async {
      final r = await env.service(memory: _ForgetLies()).deleteMyTransactions();
      expect(r.failedStep, DeleteDataStep.recipientMemory);
    });

    test('pref remove fails for the queue key: notFinished at queue; retry clean', () async {
      env.prefs.removeFails.add('pending_entries_v1');
      final r = await env.service().deleteMyTransactions();
      expect(r.failedStep, DeleteDataStep.queue);
      expect(await env.prefsMap().then((m) => m.containsKey('recipient_types_v1')), isFalse, reason: 'c ran');
      env.prefs.removeFails.clear();
      expect((await env.service().deleteMyTransactions()).outcome, DeleteDataOutcome.done);
      await expectClean();
    });

    test('a remove that lies (true, key stays) is caught by the read-back', () async {
      env.prefs.removeLies.add('pending_entries_v1');
      final r = await env.service().deleteMyTransactions();
      expect(r.failedStep, DeleteDataStep.queue);
    });

    test('writeSinceCount false: notFinished at sinceCount; retry clean', () async {
      final r = await env.service(writeSinceCount: (_) async => false).deleteMyTransactions();
      expect(r.failedStep, DeleteDataStep.sinceCount);
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect((await env.service().deleteMyTransactions()).outcome, DeleteDataOutcome.done);
      await expectClean();
    });

    test('the data-changed refresh (step f) runs once on success and not on a failure', () async {
      var n = 0;
      await env.service(onDataChanged: () => n++).deleteMyTransactions();
      expect(n, 1);
      env.safety.failClear = true;
      await env.service(onDataChanged: () => n++).deleteMyTransactions();
      expect(n, 1, reason: 'a failed run does not refresh');
    });
  });

  group('7. retry and empty states', () {
    test('a second run on an empty database succeeds with zero counts', () async {
      final svc = env.service();
      await svc.deleteMyTransactions();
      final r = await svc.deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(r.transactionsDeleted + r.softDeletedIncluded + r.learnedReceiversDeleted, 0);
    });

    test('an empty database with a leftover safety copy and prefs still runs b-e', () async {
      final svc = env.service();
      await svc.deleteMyTransactions();
      // Leftovers arrive again.
      final dir = Directory(p.join(env.safetyBase.path, 'safety'));
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'mmogo-safety-20260922-100000-001.json')).writeAsString('{}');
      final sp = await SharedPreferences.getInstance();
      await sp.setString('pending_entries_v1', '[]');
      await sp.setInt('auto_backup_since_count', 4);
      final r = await svc.deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(await _safetyFiles(env), 0);
      final m = await env.prefsMap();
      expect(m.containsKey('pending_entries_v1'), isFalse);
      expect(m['auto_backup_since_count'], 0);
    });
  });

  group('9. auto-backup', () {
    Future<(AutoBackupService, Completer<void>, List<int>)> seeded() async {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt('auto_backup_every_n', 1);
      await sp.setInt('auto_backup_since_count', 0);
      final gate = Completer<void>();
      final exports = <int>[];
      final auto = AutoBackupService(
        bridge: () => env.bridge,
        export: () async {
          exports.add(exports.length);
          await gate.future;
          return Uint8List.fromList(utf8.encode('{"app":"mmogo"}'));
        },
        notify: (_) {},
      );
      env.bridge.folders['content://tree/invented'] = {};
      return (auto, gate, exports);
    }

    test('quiesce waits for the run in flight; nothing new is written after the commit; written list intact', () async {
      final (auto, gate, exports) = await seeded();
      final run = auto.onEntrySaved();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(exports.length, 1);
      var finished = false;
      final del = env.service(auto: auto, quiesceBound: const Duration(seconds: 5)).deleteMyTransactions().then((r) {
        finished = true;
        return r;
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(finished, isFalse, reason: 'waits for the run in flight');
      gate.complete();
      await run;
      final r = await del;
      expect(r.outcome, DeleteDataOutcome.done);
      final filesAfterDelete = env.bridge.folders['content://tree/invented']!.length;
      expect(filesAfterDelete, 1, reason: 'the run that was in flight finished BEFORE the delete started');
      final m = await env.prefsMap();
      expect(m['auto_backup_since_count'], 0);
      expect((m['auto_backup_written_uris']! as List).length, 1, reason: 'written list kept');
      expect(auto.isBlocked, isFalse, reason: 'resumed in finally');
    });

    test('onEntrySaved is inert while blocked: no export, no counting, no queue', () async {
      final (auto, gate, exports) = await seeded();
      gate.complete();
      var hookRan = false;
      final r = await env.service(auto: auto, vacuum: (_) async {
        hookRan = true;
        await auto.onEntrySaved();
        await auto.onEntrySaved();
      }).deleteMyTransactions();
      expect(hookRan, isTrue);
      expect(r.outcome, DeleteDataOutcome.done);
      expect(exports, isEmpty);
      expect((await env.prefsMap())['auto_backup_since_count'], 0);
      // After resume it works again.
      await auto.onEntrySaved();
      expect(exports.length, 1);
    });

    test('A2: a run that outlasts the bound makes Level 1 busy and touches nothing; auto-backup resumes', () async {
      final (auto, gate, exports) = await seeded();
      final run = auto.onEntrySaved();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final before = await fullDump(await env.open());
      final prefsBefore = await env.prefsMap();
      final r = await env.service(auto: auto, quiesceBound: const Duration(milliseconds: 100)).deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.busy);
      expect(await fullDump(await env.open()), before);
      expect(await env.prefsMap(), prefsBefore);
      expect(await _safetyFiles(env), 2);
      expect(auto.isBlocked, isFalse);
      expect(env.gate.isHeld, isFalse);
      gate.complete();
      await run;
      expect(exports.length, 1);
    });
  });

  group('10. Replace then Level 1', () {
    test('after a Replace the safety copy exists; after Level 1 Undo is not offered and undo says noSafetyCopy', () async {
      // Start from a clean safety folder; a real Replace writes the copy.
      await env.safety.clearVerified();
      final db = await env.open();
      final bytes = await exportOf(db);
      final svc = _restoreService(env);
      await svc.restore(bytes, RestoreMode.replace);
      expect(await env.safety.exists(), isTrue, reason: 'Replace kept a safety copy');
      await env.service().deleteMyTransactions();
      expect(await env.safety.exists(), isFalse, reason: 'checked with exists() itself (canUndo swallows errors)');
      expect(await svc.canUndo(), isFalse);
      await expectLater(
        svc.undoLastReplace(),
        throwsA(isA<RestoreFailed>().having((e) => e.reason, 'reason', RestoreFailReason.noSafetyCopy)),
      );
    });
  });

  group('11. a restore file cannot carry the device-only keys', () {
    for (final mode in RestoreMode.values) {
      test('${mode.name}: recipient_types_v1, pending_entries_v1, reset_pending_v1 in a file change nothing', () async {
        final db = await env.open();
        final json = jsonDecode(utf8.decode(await exportOf(db))) as Map<String, Object?>;
        (json['prefs'] as Map<String, Object?>)
          ..['recipient_types_v1'] = '{"FILE NAME":{"t":"SEND_MONEY","at":1}}'
          ..['pending_entries_v1'] = '[{"from":"file"}]'
          ..['reset_pending_v1'] = 1;
        final before = await env.prefsMap();
        await _restoreService(env).restore(Uint8List.fromList(utf8.encode(jsonEncode(json))), mode);
        final after = await env.prefsMap();
        for (final k in ['recipient_types_v1', 'pending_entries_v1', 'reset_pending_v1']) {
          expect(after[k], before[k], reason: k);
        }
        expect(after.containsKey('reset_pending_v1'), isFalse);
      });
    }
  });

  group('12. an export of an empty database', () {
    test('restores in Merge and in Replace after Level 1', () async {
      await env.service().deleteMyTransactions();
      final db = await env.open();
      final bytes = await backupOf(db).exportToBytes();
      final svc = _restoreService(env);
      final merge = await svc.restore(bytes, RestoreMode.merge);
      expect(merge.mode, RestoreMode.merge);
      final replace = await svc.restore(bytes, RestoreMode.replace);
      expect(replace.mode, RestoreMode.replace);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });

  group('peek (A10) and the gate (A4, A7)', () {
    test('peek counts what is there; nothingLeftToDeleteAtLevel1 false; Level 2 flag false', () async {
      final peek = await env.service().peek();
      expect(peek.liveTransactions, greaterThan(0));
      expect(peek.softDeletedTransactions, greaterThan(0));
      expect(peek.learnedReceivers, greaterThan(0));
      expect(peek.safetyCopyPresent, isTrue);
      expect(peek.rememberedRecipientsPresent, isTrue);
      expect(peek.rememberedRecipientsCount, 1);
      expect(peek.queuePresent, isTrue);
      expect(peek.nothingLeftToDeleteAtLevel1, isFalse);
      expect(peek.nothingLeftAtLevel2, isFalse);
    });

    test('after Level 1: Level 1 has nothing left, Level 2 still has (categories, settings)', () async {
      await env.service().deleteMyTransactions();
      final peek = await env.service().peek();
      expect(peek.nothingLeftToDeleteAtLevel1, isTrue);
      expect(peek.nothingLeftAtLevel2, isFalse);
    });

    test('nothingLeftAtLevel2: empty DB, no user categories, only whatsnew_seen_version stored', () async {
      final fresh = await DataOpEnv.create(prefs: {'whatsnew_seen_version': '0.1.2'});
      addTearDown(fresh.dispose);
      await fresh.open();
      final peek = await fresh.service().peek();
      expect(peek.nothingLeftAtLevel2, isTrue);
      expect(peek.nothingLeftToDeleteAtLevel1, isTrue);
      // One more pref key and it is no longer "nothing".
      await (await SharedPreferences.getInstance()).setString('palette_id', 'leaf');
      expect((await fresh.service().peek()).nothingLeftAtLevel2, isFalse);
    });

    test('a peek that cannot read is incomplete and never claims "nothing left"', () async {
      env.prefs.failKeys = true;
      final peek = await env.service().peek();
      expect(peek.incomplete, isTrue);
      expect(peek.nothingLeftToDeleteAtLevel1, isFalse);
      expect(peek.nothingLeftAtLevel2, isFalse);
    });

    test('a held gate makes Level 1 busy without touching anything; the gate stays as it was', () async {
      env.gate.tryAcquire();
      final before = await fullDump(await env.open());
      final r = await env.service().deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.busy);
      expect(await fullDump(await env.open()), before);
      expect(await _safetyFiles(env), 2);
      expect(env.gate.isHeld, isTrue, reason: 'not released by the loser');
      env.gate.release();
    });

    test('the gate is released after done, after notFinished and after an unexpected error', () async {
      await env.service().deleteMyTransactions();
      expect(env.gate.isHeld, isFalse);
      env.safety.failClear = true;
      await env.service().deleteMyTransactions();
      expect(env.gate.isHeld, isFalse);
      // An unexpected error: the database getter itself throws.
      final svc = env.service();
      AppDatabase.resetInProgress = true;
      final r = await svc.deleteMyTransactions();
      AppDatabase.resetInProgress = false;
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(env.gate.isHeld, isFalse);
    });

    test('A7: a held gate makes restore and undoLastReplace refuse (busy) without touching data', () async {
      final db = await env.open();
      final bytes = await exportOf(db);
      final before = await fullDump(db);
      final svc = _restoreService(env);
      env.gate.tryAcquire();
      await expectLater(
        svc.restore(bytes, RestoreMode.replace),
        throwsA(isA<RestoreFailed>().having((e) => e.reason, 'reason', RestoreFailReason.busy)),
      );
      await expectLater(
        svc.undoLastReplace(),
        throwsA(isA<RestoreFailed>().having((e) => e.reason, 'reason', RestoreFailReason.busy)),
      );
      expect(await fullDump(db), before);
      expect(await _safetyFiles(env), 2, reason: 'no safety copy written by a refused Replace');
      expect(env.gate.isHeld, isTrue);
      env.gate.release();
      // And the gate is released after a restore.
      await svc.restore(bytes, RestoreMode.merge);
      expect(env.gate.isHeld, isFalse);
    });
  });

  test('queueKeys is exactly [pending_entries_v1] and never holds the reset flag or the merge report', () {
    expect(queueKeys, ['pending_entries_v1']);
    expect(queueKeys.contains(kResetPendingKey), isFalse);
    expect(kPendingEntriesKey, 'pending_entries_v1');
    expect(kResetPendingKey, 'reset_pending_v1');
    expect(kPhoneMergeReportKey, 'phone_merge_report_v1');
  });

  test('DataOpGate: second acquire fails until release', () {
    final g = DataOpGate();
    expect(g.tryAcquire(), isTrue);
    expect(g.tryAcquire(), isFalse);
    g.release();
    expect(g.tryAcquire(), isTrue);
  });

  test('BackupPrefs counter helper sanity (the service uses the real BackupPrefs by default)', () async {
    expect(await BackupPrefs.readSinceCount(), 7);
  });
}
