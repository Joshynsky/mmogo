// 0.1.2 S9b-1: "Reset app" (Level 2) and its start-up resume, against a REAL
// SQLite file in a TEMP directory, mock prefs, a temp safety folder and fakes.
// Nothing here calls ResetResume.runIfPending, resetApp or AppDatabase with the
// real defaults: every call passes the env from test/support/data_op_env.dart
// (all paths asserted under Directory.systemTemp).
//
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/backup/safety_copy_store.dart';
import 'package:mmogo/data/db/app_database.dart';
import 'package:mmogo/data/maintenance/data_prefs_access.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/data/maintenance/device_keys.dart';
import 'package:mmogo/data/maintenance/reset_resume.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/data_op_env.dart';
import '../../support/fake_storage_bridge.dart';

class _ThrowingBridge extends FakeStorageBridge {
  @override
  Future<void> releaseGrant(String treeUri) async {
    calls.add('releaseGrant:$treeUri');
    throw const StorageException(StorageErrorCode.io);
  }
}

Future<List<String>> _dbFiles(DataOpEnv env) async => [
      for (final s in const ['', '-journal', '-wal', '-shm'])
        if (await File('${env.dbPath}$s').exists()) s.isEmpty ? 'db' : s,
    ];

Future<int> _safetyFiles(DataOpEnv env) async {
  final dir = Directory(p.join(env.safetyBase.path, 'safety'));
  return await dir.exists() ? dir.list().length : 0;
}

/// Closes the handle the way a killed process would (nothing is open after).
Future<void> _simulateKill(DataOpEnv env) async {
  env.db.failClose = false;
  await env.db.close();
  AppDatabase.resetInProgress = false;
}

void main() {
  late DataOpEnv env;

  setUp(() async {
    env = await DataOpEnv.create();
    await env.populateAll();
    await plantSidecars(env.dbPath);
  });
  tearDown(() => env.dispose());

  group('1. the resume (flag planted)', () {
    test('deletes the four files, wipes every pref, removes the flag LAST; the DB reopens fresh', () async {
      await env.db.close();
      await plantSidecars(env.dbPath);
      await (await SharedPreferences.getInstance()).setInt(kResetPendingKey, 123);
      expect(await _dbFiles(env), ['db', '-journal', '-wal', '-shm']);

      final done = await ResetResume.runIfPending(env: env.resetEnv());

      expect(done, isTrue);
      expect(ResetResume.lastOutcome, ResetResumeOutcome.completed);
      expect(await _dbFiles(env), isEmpty);
      expect(await _safetyFiles(env), 0);
      expect(await env.prefsMap(), isEmpty, reason: 'every key, flag included');
      final removes = env.prefs.log.where((l) => l.startsWith('remove:')).toList();
      expect(removes.last, 'remove:$kResetPendingKey', reason: 'the flag goes last');
      expect(removes.where((l) => l == 'remove:$kResetPendingKey').length, 1);
      expect(AppDatabase.resetInProgress, isFalse);

      // Fresh install: 17 built-ins, no transactions.
      expect(await env.count('SELECT COUNT(*) FROM classifications'), 17);
      expect(await env.count('SELECT COUNT(*) FROM transactions'), 0);
      expect(await env.count('SELECT COUNT(*) FROM counterparty_classification_map'), 0);
    });

    test('with no flag it returns at once and touches nothing', () async {
      final prefsBefore = await env.prefsMap();
      final done = await ResetResume.runIfPending(env: env.resetEnv());
      expect(done, isFalse);
      expect(ResetResume.lastOutcome, ResetResumeOutcome.nothingPending);
      expect(await _dbFiles(env), contains('db'));
      expect(await env.prefsMap(), prefsBefore);
      expect(await _safetyFiles(env), 2);
    });

    test('a flag that cannot be read in time starts the app normally and touches nothing', () async {
      final stuck = ResetEnv(
        db: env.db,
        dbFactory: () => databaseFactoryFfi,
        safety: env.safety,
        prefs: _StuckPrefs(),
        fs: env.fs,
        flagReadTimeout: const Duration(milliseconds: 50),
      );
      final done = await ResetResume.runIfPending(env: stuck);
      expect(done, isFalse);
      expect(ResetResume.lastOutcome, ResetResumeOutcome.flagUnreadable);
      expect(await _dbFiles(env), contains('db'));
      expect(AppDatabase.resetInProgress, isFalse);
    });
  });

  group('A1: the reset guard', () {
    test('while set, the database getter does not open or create the file', () async {
      final fresh = await DataOpEnv.create();
      addTearDown(fresh.dispose);
      AppDatabase.resetInProgress = true;
      await expectLater(fresh.db.database, throwsStateError);
      expect(await fresh.dbFileExists(), isFalse);
      AppDatabase.resetInProgress = false;
    });

    test('a query that arrives in the middle of a reset (after the file is deleted) creates no mmogo.db', () async {
      var probed = false;
      env.fs.onFirstDelete = () async {
        probed = true;
        expect(AppDatabase.resetInProgress, isTrue);
        await expectLater(env.db.database, throwsStateError);
      };
      final r = await env.service().resetApp();
      expect(probed, isTrue);
      expect(r.outcome, DeleteDataOutcome.done);
      expect(await _dbFiles(env), isEmpty, reason: 'nothing brought the file back');
      expect(AppDatabase.resetInProgress, isFalse, reason: 'cleared once the flag is gone');
    });

    test('a failed reset clears the guard again', () async {
      env.fs.locked.add(env.dbPath);
      final r = await env.service().resetApp();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(AppDatabase.resetInProgress, isFalse);
    });
  });

  group('3. crash injection: stop after each step, then the resume ends clean', () {
    Future<void> expectFresh() async {
      expect(await _dbFiles(env), isEmpty);
      expect(await _safetyFiles(env), 0);
      expect(await env.prefsMap(), isEmpty);
      expect(ResetResume.lastOutcome, ResetResumeOutcome.completed);
      expect(AppDatabase.resetInProgress, isFalse);
    }

    test('after step 2 (flag written, the handle will not close)', () async {
      env.db.failClose = true;
      final r = await env.service().resetApp();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(r.failedStep, DeleteDataStep.database);
      expect((await env.prefsMap()).containsKey(kResetPendingKey), isTrue);
      await _simulateKill(env);
      expect(await ResetResume.runIfPending(env: env.resetEnv()), isTrue);
      await expectFresh();
    });

    test('after step 3 (closed; the files are locked)', () async {
      env.fs.locked.add(env.dbPath);
      final r = await env.service().resetApp();
      expect(r.failedStep, DeleteDataStep.files);
      expect((await env.prefsMap()).containsKey(kResetPendingKey), isTrue);
      env.fs.locked.clear();
      expect(await ResetResume.runIfPending(env: env.resetEnv()), isTrue);
      await expectFresh();
    });

    test('after step 4 (files deleted; the safety copy will not clear)', () async {
      env.safety.failClear = true;
      final r = await env.service().resetApp();
      expect(r.failedStep, DeleteDataStep.safetyCopy);
      expect(await _dbFiles(env), isEmpty, reason: 'step 4 was done');
      env.safety.failClear = false;
      expect(await ResetResume.runIfPending(env: env.resetEnv()), isTrue);
      await expectFresh();
    });

    test('after step 5 (safety cleared; one pref will not go)', () async {
      env.prefs.removeFails.add('palette_id');
      final r = await env.service().resetApp();
      expect(r.failedStep, DeleteDataStep.prefs);
      expect((await env.prefsMap()).containsKey(kResetPendingKey), isTrue);
      env.prefs.removeFails.clear();
      expect(await ResetResume.runIfPending(env: env.resetEnv()), isTrue);
      await expectFresh();
    });

    test('after step 6 (prefs wiped, the flag will not go): only the flag remains, resume removes it', () async {
      env.prefs.removeFails.add(kResetPendingKey);
      final r = await env.service().resetApp();
      expect(r.failedStep, DeleteDataStep.resetFlag);
      expect((await env.prefsMap()).keys.toList(), [kResetPendingKey]);
      env.prefs.removeFails.clear();
      expect(await ResetResume.runIfPending(env: env.resetEnv()), isTrue);
      await expectFresh();
    });

    test('the flag remove lies (true, still stored): caught by the read-back', () async {
      env.prefs.removeLies.add(kResetPendingKey);
      final r = await env.service().resetApp();
      expect(r.failedStep, DeleteDataStep.resetFlag);
      env.prefs.removeLies.clear();
    });
  });

  group('4. step 2 failure touches nothing', () {
    test('the flag cannot be written: notFinished at resetFlag, nothing deleted, handle still open', () async {
      final prefsBefore = await env.prefsMap();
      env.prefs.failSetInt = true;
      final r = await env.service().resetApp();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(r.failedStep, DeleteDataStep.resetFlag);
      expect(await _dbFiles(env), contains('db'));
      expect(await env.prefsMap(), prefsBefore);
      expect(await _safetyFiles(env), 2);
      expect(env.db.closeCalls, 0);
      expect(env.db.isOpen, isTrue);
      expect(AppDatabase.resetInProgress, isFalse);
      expect(env.gate.isHeld, isFalse);
    });
  });

  group('5. a locked file', () {
    test('the flag stays, the result is notFinished, a retry works, the start-up resume never throws', () async {
      env.fs.locked.add('${env.dbPath}-wal');
      final r = await env.service().resetApp();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(r.failedStep, DeleteDataStep.files);
      expect((await env.prefsMap()).containsKey(kResetPendingKey), isTrue);

      // Next launch: still locked -> no crash, no loop, flag kept.
      final again = await ResetResume.runIfPending(env: env.resetEnv());
      expect(again, isFalse);
      expect(ResetResume.lastOutcome, ResetResumeOutcome.notFinished);
      expect(ResetResume.lastFailedStep, DeleteDataStep.files);
      expect((await env.prefsMap()).containsKey(kResetPendingKey), isTrue);

      env.fs.locked.clear();
      final retry = await env.service().resetApp();
      expect(retry.outcome, DeleteDataOutcome.done);
      expect(await env.prefsMap(), isEmpty);
    });
  });

  group('7. backup folder and the old permission', () {
    test('files in the backup folder and the written list are untouched; releaseGrant gets the old uri', () async {
      final b = env.bridge;
      final doc = b.seed('content://tree/invented', 'mmogo-auto-20260920-100000.json', Uint8List.fromList([1, 2, 3]));
      final r = await env.service().resetApp();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(b.calls, contains('releaseGrant:content://tree/invented'));
      expect(b.contents.containsKey(doc), isTrue, reason: 'the backup files stay');
      expect(b.calls.where((c) => c.startsWith('deleteFile')), isEmpty);
      expect(b.calls.where((c) => c.startsWith('createFile')), isEmpty);
    });

    test('a bridge that throws does not stop the reset', () async {
      final bridge = _ThrowingBridge();
      final r = await DeleteDataServiceImpl(
        env: ResetEnv(
          db: env.db,
          dbFactory: () => databaseFactoryFfi,
          safety: env.safety,
          prefs: env.prefs,
          bridge: () => bridge,
          fs: env.fs,
          nowMs: () => env.clockMs,
          grantTimeout: const Duration(milliseconds: 200),
        ),
        autoBackup: () => AutoBackupService(bridge: () => bridge),
        gate: env.gate,
      ).resetApp();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(bridge.calls, contains('releaseGrant:content://tree/invented'));
      expect(await env.prefsMap(), isEmpty);
    });

    test('the grant is released BEFORE the prefs that hold its address are wiped', () async {
      final order = <String>[];
      env.bridge.calls.clear();
      final bridge = _OrderBridge(order, env);
      await DeleteDataServiceImpl(
        env: ResetEnv(
          db: env.db,
          dbFactory: () => databaseFactoryFfi,
          safety: env.safety,
          prefs: env.prefs,
          bridge: () => bridge,
          fs: env.fs,
        ),
        autoBackup: () => AutoBackupService(bridge: () => bridge),
        gate: env.gate,
      ).resetApp();
      expect(order, ['release:uri-still-stored']);
    });

    test('A9: the resume also releases the grant when the uri is still present', () async {
      await env.db.close();
      await (await SharedPreferences.getInstance()).setInt(kResetPendingKey, 1);
      await ResetResume.runIfPending(env: env.resetEnv());
      expect(env.bridge.calls, contains('releaseGrant:content://tree/invented'));
    });
  });

  group('8. combinations', () {
    test('Level 1 then Level 2', () async {
      final svc = env.service();
      expect((await svc.deleteMyTransactions()).outcome, DeleteDataOutcome.done);
      expect((await svc.resetApp()).outcome, DeleteDataOutcome.done);
      expect(await _dbFiles(env), isEmpty);
      expect(await env.prefsMap(), isEmpty);
    });

    test('Level 2 straight on a fresh install (no database file, no prefs) is a clean success and creates nothing', () async {
      final fresh = await DataOpEnv.create();
      addTearDown(fresh.dispose);
      final r = await fresh.service().resetApp();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(await fresh.dbFileExists(), isFalse);
      expect(await fresh.prefsMap(), isEmpty);
    });

    test('the result carries counts only', () async {
      final r = await env.service().resetApp();
      expect(r.transactionsDeleted, greaterThan(0));
      final text = r.toString();
      for (final secret in ['INVENTED', 'Invented', '0712', 'JANE', '123456']) {
        expect(text.contains(secret), isFalse, reason: secret);
      }
    });
  });

  group('9. auto-backup during a reset', () {
    test('a run in flight is waited for; a run that outlasts the bound is notFinished at database and touches nothing', () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt('auto_backup_every_n', 1);
      await sp.setInt('auto_backup_since_count', 0);
      final gate = Completer<void>();
      final auto = AutoBackupService(
        bridge: () => env.bridge,
        export: () async {
          await gate.future;
          return Uint8List.fromList([1]);
        },
        notify: (_) {},
      );
      env.bridge.folders['content://tree/invented'] = {};
      final run = auto.onEntrySaved();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefsBefore = await env.prefsMap();
      final r = await env.service(auto: auto, quiesceBound: const Duration(milliseconds: 100)).resetApp();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(r.failedStep, DeleteDataStep.database);
      expect(await _dbFiles(env), contains('db'));
      expect(await env.prefsMap(), prefsBefore);
      expect(auto.isBlocked, isFalse);
      gate.complete();
      await run;
    });

    test('onEntrySaved is inert while the reset holds auto-backup still', () async {
      var exports = 0;
      final auto = AutoBackupService(
        bridge: () => env.bridge,
        export: () async {
          exports++;
          return Uint8List.fromList([1]);
        },
        notify: (_) {},
      );
      env.fs.onFirstDelete = () async {
        expect(auto.isBlocked, isTrue);
        await auto.onEntrySaved();
      };
      await env.service(auto: auto).resetApp();
      expect(exports, 0);
      expect(auto.isBlocked, isFalse);
    });
  });

  group('A4: clearVerified', () {
    test('removes copies and .json.partial and proves it; an absent folder is clean and is not created', () async {
      await env.safety.clearVerified();
      expect(await _safetyFiles(env), 0);
      final fresh = await DataOpEnv.create();
      addTearDown(fresh.dispose);
      await fresh.safety.clearVerified();
      expect(await Directory(p.join(fresh.safetyBase.path, 'safety')).exists(), isFalse);
    });

    test('an unrelated file in the folder is left alone', () async {
      final other = File(p.join(env.safetyBase.path, 'safety', 'notes.txt'))..writeAsStringSync('x');
      await env.safety.clearVerified();
      expect(other.existsSync(), isTrue);
    });

    test('an exists() failure is a SafetyCopyError', () async {
      env.safety.existsThrows = true;
      // FlakySafety.clearVerified calls super, which calls this.exists().
      await expectLater(env.safety.clearVerified(), throwsA(isA<SafetyCopyError>()));
    });
  });

  test('10. start-up cleanup never removes the flag: the constant and the queue list keep it out', () {
    expect(kResetPendingKey, 'reset_pending_v1');
    expect(queueKeys, isNot(contains(kResetPendingKey)));
    expect(kBaselinePrefKey, 'whatsnew_seen_version');
  });

  test('no file in lib/ outside data/maintenance and the UI copy names the flag key', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll('\\', '/');
      if (path.contains('data/maintenance/')) continue;
      if (f.readAsStringSync().contains('reset_pending_v1')) offenders.add(path);
    }
    expect(offenders, isEmpty, reason: 'only device_keys.dart may spell the flag key');
  });

  test('DeleteDataService constructed with an env never uses the real database path', () async {
    final path = await env.db.databasePath();
    assertUnderTemp(path);
    expect(path, env.dbPath);
  });
}

class _StuckPrefs implements DataPrefsAccess {
  @override
  Future<bool> has(String key) => Completer<bool>().future; // never answers

  @override
  Future<Set<String>> keys() => Completer<Set<String>>().future;
  @override
  Future<int?> readInt(String key) => Completer<int?>().future;
  @override
  Future<String?> readString(String key) => Completer<String?>().future;
  @override
  Future<bool> setInt(String key, int value) async => false;
  @override
  Future<bool> remove(String key) async => false;
}

class _OrderBridge extends FakeStorageBridge {
  _OrderBridge(this.order, this.env);
  final List<String> order;
  final DataOpEnv env;

  @override
  Future<void> releaseGrant(String treeUri) async {
    final stored = await env.prefs.readString('auto_backup_folder_uri');
    order.add(stored == treeUri ? 'release:uri-still-stored' : 'release:uri-already-wiped');
    await super.releaseGrant(treeUri);
  }
}
