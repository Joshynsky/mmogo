// what clears the 24 h "Recorded automatically" list in the phone's
// preferences (`autoread_airtime_trail_v1`, row numbers and times only), and
// what must not. Standard flavor (these code paths compile in both builds).
// Real SQLite in a temp folder, mock prefs, invented data only.
//
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_writer.dart';
import 'package:mmogo/data/backup/restore_trail_hook.dart';
import 'package:mmogo/data/backup/safety_copy_store.dart';
import 'package:mmogo/data/maintenance/data_op_gate.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/data/maintenance/device_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/data_op_env.dart';
import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

const _trail = '[[11,1790000000000],[12,1790000100000]]';

Future<void> _plant() async => (await SharedPreferences.getInstance())
    .setString(kAirtimeTrailPrefsKey, _trail);

Future<String?> _stored() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  return p.getString(kAirtimeTrailPrefsKey);
}

RestoreService _svc(Database db) => RestoreService(
  db: () async => db,
  backup: backupOf(db),
  safety: FakeSafetyCopyStore([]),
  settings: BackupSettings(prefs: SharedPreferences.getInstance),
  validateInIsolate: false,
  gate: DataOpGate(),
);

Uint8List _file({Map<String, Object?> prefs = const {}}) => fileBytes(
  fileJson(
    classes: seedRowsV5(),
    txs: [
      tx(1, 'NEW1111111', 'SEND_MONEY', 2, label: 'MAMA', phone: '0700000001'),
    ],
    prefs: prefs,
    schemaVersion: 5,
  ),
);

void main() {
  group('Delete data and Reset app', () {
    late DataOpEnv env;
    setUp(() async {
      env = await DataOpEnv.create();
      await env.populateAll();
      await _plant();
    });
    tearDown(() => env.dispose());

    test(
      'delete_data_removes_trail_key_and_in_memory_list (stored half: key absent after Level 1)',
      () async {
        expect(await _stored(), _trail);
        final r = await env.service().deleteMyTransactions();
        expect(r.outcome, DeleteDataOutcome.done);
        expect(
          (await env.prefsMap()).containsKey(kAirtimeTrailPrefsKey),
          isFalse,
        );
      },
    );

    test(
      'delete_data_trail_key_remove_failure_is_notFinished_at_prefs_and_retry_succeeds',
      () async {
        env.prefs.removeFails.add(kAirtimeTrailPrefsKey);
        final r = await env.service().deleteMyTransactions();
        expect(r.outcome, DeleteDataOutcome.notFinished);
        expect(r.failedStep, DeleteDataStep.prefs);
        expect(await _stored(), _trail, reason: 'nothing pretends it is gone');
        env.prefs.removeFails.clear();
        final again = await env.service().deleteMyTransactions();
        expect(again.outcome, DeleteDataOutcome.done);
        expect(
          (await env.prefsMap()).containsKey(kAirtimeTrailPrefsKey),
          isFalse,
        );
      },
    );

    test('a remove that lies is caught by the read-back (same step)', () async {
      env.prefs.removeLies.add(kAirtimeTrailPrefsKey);
      final r = await env.service().deleteMyTransactions();
      expect(r.failedStep, DeleteDataStep.prefs);
    });

    test('reset_app_wipes_trail_key', () async {
      final r = await env.service().resetApp();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(
        (await env.prefsMap()).containsKey(kAirtimeTrailPrefsKey),
        isFalse,
      );
    });
  });

  group('Restore', () {
    late Database db;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await openTestDb();
      await populate(db);
      await _plant();
    });
    tearDown(() async {
      AirtimeTrailRestoreHook.clearMemory = null;
      await db.close();
    });

    test(
      'restore_replace_clears_trail (stored key and the list in memory), after the commit',
      () async {
        var cleared = 0;
        AirtimeTrailRestoreHook.clearMemory = () => cleared++;
        await _svc(db).restore(_file(), RestoreMode.replace);
        expect(await _stored(), isNull);
        expect(cleared, 1);
      },
    );

    test(
      'restore_replace_clears_trail: a failed restore (file refused, nothing written) does not',
      () async {
        var cleared = 0;
        AirtimeTrailRestoreHook.clearMemory = () => cleared++;
        await expectLater(
          _svc(db).restore(
            Uint8List.fromList(utf8.encode('not a backup')),
            RestoreMode.replace,
          ),
          throwsA(isA<RestoreRejected>()),
        );
        expect(await _stored(), _trail);
        expect(cleared, 0);
      },
    );

    test(
      'restore_replace_clears_trail: a rolled-back Replace (a write fails midway) does not',
      () async {
        var cleared = 0;
        AirtimeTrailRestoreHook.clearMemory = () => cleared++;
        final svc = RestoreService(
          db: () async => db,
          backup: backupOf(db),
          safety: FakeSafetyCopyStore([]),
          settings: BackupSettings(prefs: SharedPreferences.getInstance),
          validateInIsolate: false,
          gate: DataOpGate(),
          writer: RestoreWriter(
            beforeRow: (table, index) => throw StateError('forced failure'),
          ),
        );
        await expectLater(
          svc.restore(_file(), RestoreMode.replace),
          throwsA(isA<RestoreFailed>()),
        );
        expect(await _stored(), _trail);
        expect(cleared, 0);
      },
    );

    test('restore_merge_keeps_trail', () async {
      var cleared = 0;
      AirtimeTrailRestoreHook.clearMemory = () => cleared++;
      await _svc(db).restore(_file(), RestoreMode.merge);
      expect(await _stored(), _trail);
      expect(cleared, 0);
    });

    test(
      'restore_file_with_trail_like_pref_is_never_read: Merge and Replace never write a file value',
      () async {
        const planted = '[[99,1790000999999]]';
        await _svc(db).restore(
          _file(prefs: {kAirtimeTrailPrefsKey: planted}),
          RestoreMode.merge,
        );
        expect(
          await _stored(),
          _trail,
          reason: 'Merge keeps ours, never the file\'s',
        );
        await _svc(db).restore(
          _file(prefs: {kAirtimeTrailPrefsKey: planted}),
          RestoreMode.replace,
        );
        expect(
          await _stored(),
          isNull,
          reason: 'Replace clears, never takes the file\'s value',
        );
        expect(
          kBackupSettingSpecs.any(
            (s) =>
                s.prefsKey == kAirtimeTrailPrefsKey ||
                s.fileKey == kAirtimeTrailPrefsKey,
          ),
          isFalse,
        );
      },
    );

    test(
      'the Undo of a Replace also clears it (the rows were replaced again)',
      () async {
        final tmp = await Directory.systemTemp.createTemp('mmogo_r18_undo_');
        addTearDown(() => tmp.delete(recursive: true));
        final svc = RestoreService(
          db: () async => db,
          backup: backupOf(db),
          safety: SafetyCopyStore(baseDir: () async => tmp),
          settings: BackupSettings(prefs: SharedPreferences.getInstance),
          validateInIsolate: false,
          gate: DataOpGate(),
        );
        await svc.restore(_file(), RestoreMode.replace);
        await _plant(); // an entry recorded after the Replace
        var cleared = 0;
        AirtimeTrailRestoreHook.clearMemory = () => cleared++;
        await svc.undoLastReplace();
        expect(await _stored(), isNull);
        expect(cleared, 1);
      },
    );
  });

  group('Backup file and schema', () {
    test(
      'backup_file_has_no_trail_field_and_schema_5_13_keys_unchanged',
      () async {
        SharedPreferences.setMockInitialValues({});
        await _plant();
        final db = await openTestDb();
        await populate(db);
        final json =
            jsonDecode(utf8.decode(await backupOf(db).exportToBytes()))
                as Map<String, dynamic>;
        expect(json['schema_version'], 5);
        expect(
          utf8.decode(await backupOf(db).exportToBytes()),
          isNot(contains('autoread_airtime_trail')),
        );
        expect(
          (json['prefs'] as Map).keys,
          isNot(contains(kAirtimeTrailPrefsKey)),
        );
        final tx = (json['transactions'] as List).cast<Map<String, dynamic>>();
        expect(tx.first.keys.toSet(), kBackupTransactionKeys.toSet());
        expect(kBackupTransactionKeys, hasLength(13));
        expect(kBackupSchemaVersion, 5);
        await db.close();
      },
    );

    test(
      'db_version_still_5_fresh_and_migrated_equal (no schema drift: no new column; the equality test is migration_v5_test)',
      () async {
        expect(kDbVersion, 5);
        final db = await openTestDb();
        final cols = [
          for (final r in await db.rawQuery('PRAGMA table_info(transactions)'))
            r['name'] as String,
        ];
        expect(
          cols.where((c) => c.contains('auto') || c.contains('trail')),
          isEmpty,
        );
        await db.close();
      },
    );

    test(
      'the Delete data service source names the trail key through device_keys only',
      () {
        final src = File(
          'lib/data/maintenance/delete_data_service.dart',
        ).readAsStringSync();
        expect(src.contains('autoread_airtime_trail'), isFalse);
        expect(kAirtimeTrailPrefsKey, 'autoread_airtime_trail_v1');
      },
    );
  });
}
