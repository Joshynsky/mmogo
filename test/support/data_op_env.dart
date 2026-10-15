// Shared harness for the Delete data tests (0.1.2 S9b-1). THE DESTRUCTIVE
// CODE UNDER TEST MUST NEVER TOUCH THE REAL DATABASE, REAL PREFS OR THE REAL
// SAFETY FOLDER, so every test builds a [DataOpEnv]: a temp directory under
// Directory.systemTemp, a database file inside it, a safety base dir inside
// it, mock prefs and a fake PathProvider whose every answer is that temp
// directory. [assertUnderTemp] is called on every path the env hands out.
//
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/backup/safety_copy_store.dart';
import 'package:mmogo/data/db/app_database.dart';
import 'package:mmogo/data/maintenance/data_file_system.dart';
import 'package:mmogo/data/maintenance/data_op_gate.dart';
import 'package:mmogo/data/maintenance/data_prefs_access.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/data/maintenance/reset_resume.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_storage_bridge.dart';
import 'restore_test_db.dart' show populate;
import 'spent_test_data.dart' show insertSpentTx;

/// Fails the test when [path] is not inside the system temp directory.
void assertUnderTemp(String path) {
  final temp = p.normalize(Directory.systemTemp.absolute.path);
  final full = p.normalize(File(path).absolute.path);
  expect(p.isWithin(temp, full), isTrue, reason: 'a test path must be under Directory.systemTemp');
}

/// A PathProvider that answers every directory with the temp root.
class FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}

/// Prefs access wrapper that can fail or lie on chosen keys.
class FlakyPrefs implements DataPrefsAccess {
  FlakyPrefs(this.inner);
  final DataPrefsAccess inner;
  final Set<String> removeFails = {};
  final Set<String> removeLies = {}; // returns true but does nothing
  bool failSetInt = false;
  bool failKeys = false;
  final List<String> log = [];

  @override
  Future<Set<String>> keys() async {
    if (failKeys) throw StateError('keys failed');
    return inner.keys();
  }

  @override
  Future<bool> has(String key) => inner.has(key);
  @override
  Future<int?> readInt(String key) => inner.readInt(key);
  @override
  Future<String?> readString(String key) => inner.readString(key);

  @override
  Future<bool> setInt(String key, int value) async {
    log.add('setInt:$key');
    if (failSetInt) return false;
    return inner.setInt(key, value);
  }

  @override
  Future<bool> remove(String key) async {
    log.add('remove:$key');
    if (removeFails.contains(key)) return false;
    if (removeLies.contains(key)) return true;
    return inner.remove(key);
  }
}

/// File system that refuses to delete chosen paths ("locked file").
class LockedFs implements DataFileSystem {
  LockedFs([this.inner = const IoDataFileSystem()]);
  final DataFileSystem inner;
  final Set<String> locked = {};
  final List<String> deleted = [];

  /// Runs once, at the first delete call (a probe "in the middle of a reset").
  Future<void> Function()? onFirstDelete;

  /// A locked file stays: it still "exists" after a failed delete.
  @override
  Future<bool> exists(String path) async => locked.contains(path) || await inner.exists(path);

  @override
  Future<void> delete(String path) async {
    final hook = onFirstDelete;
    if (hook != null) {
      onFirstDelete = null;
      await hook();
    }
    if (locked.contains(path)) throw const FileSystemException('locked');
    deleted.add(path);
    await inner.delete(path);
  }
}

/// A safety store whose clearVerified can be made to fail.
class FlakySafety extends SafetyCopyStore {
  FlakySafety({required super.baseDir});
  bool failClear = false;
  bool existsThrows = false;
  int clearCalls = 0;

  @override
  Future<void> clearVerified() async {
    clearCalls++;
    if (failClear) throw const SafetyCopyError('not cleared');
    return super.clearVerified();
  }

  @override
  Future<bool> exists() async {
    if (existsThrows) throw StateError('exists failed');
    return super.exists();
  }
}

/// An AppDatabase whose close() can be made to fail.
class ClosableDb extends AppDatabase {
  ClosableDb(String path) : super.forPath(() async => path, factory: databaseFactoryFfi);
  bool failClose = false;
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    if (failClose) throw StateError('close failed');
    return super.close();
  }
}

class DataOpEnv {
  DataOpEnv._(this.root, this.dbPath, this.safetyBase, this.db, this.safety, this.prefs, this.fs, this.bridge) {
    assertUnderTemp(root.path);
    assertUnderTemp(dbPath);
    assertUnderTemp(safetyBase.path);
  }

  final Directory root;
  final String dbPath;
  final Directory safetyBase;
  final ClosableDb db;
  final FlakySafety safety;
  final FlakyPrefs prefs;
  final LockedFs fs;
  final FakeStorageBridge bridge;

  final DataOpGate gate = DataOpGate();
  int clockMs = 1790000000000;

  static Future<DataOpEnv> create({Map<String, Object> prefs = const {}}) async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('mmogo_s9b1_');
    PathProviderPlatform.instance = FakePathProvider(root.path);
    SharedPreferences.setMockInitialValues(prefs);
    AppDatabase.resetInProgress = false;
    final dbPath = p.join(root.path, 'db', 'mmogo.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    final safetyBase = Directory(p.join(root.path, 'support'));
    await safetyBase.create(recursive: true);
    return DataOpEnv._(
      root,
      dbPath,
      safetyBase,
      ClosableDb(dbPath),
      FlakySafety(baseDir: () async => safetyBase),
      FlakyPrefs(SharedDataPrefsAccess()),
      LockedFs(),
      FakeStorageBridge(),
    );
  }

  ResetEnv resetEnv({int Function()? nowMs}) => ResetEnv(
        db: db,
        dbFactory: () => databaseFactoryFfi,
        safety: safety,
        prefs: prefs,
        bridge: () => bridge,
        fs: fs,
        nowMs: nowMs ?? () => clockMs,
        grantTimeout: const Duration(milliseconds: 300),
        flagReadTimeout: const Duration(milliseconds: 500),
      );

  RecipientMemory memory() => RecipientMemory(nowMs: () => clockMs);

  DeleteDataServiceImpl service({
    AutoBackupService? auto,
    Future<void> Function(Database db)? vacuum,
    Future<int> Function(DatabaseExecutor db, String table)? countRows,
    Future<bool> Function(int value)? writeSinceCount,
    RecipientMemory? memory,
    void Function()? onDataChanged,
    Duration quiesceBound = const Duration(milliseconds: 400),
  }) =>
      DeleteDataServiceImpl(
        env: resetEnv(),
        memory: memory ?? this.memory(),
        autoBackup: () => auto ?? AutoBackupService(bridge: () => bridge),
        gate: gate,
        onDataChanged: onDataChanged,
        vacuumTimeout: const Duration(seconds: 5),
        quiesceBound: quiesceBound,
        vacuum: vacuum,
        countRows: countRows,
        writeSinceCount: writeSinceCount,
      );

  Future<Database> open() => db.database;

  Future<void> dispose() async {
    AppDatabase.resetInProgress = false;
    try {
      await db.close();
    } catch (_) {}
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  }

  /// A populated phone: live and recently deleted rows of all 7 source types
  /// (a Withdrawal with an agent number), 3 user categories, a renamed and a
  /// hidden built-in, learned receivers, prefs of every family, a safety copy
  /// file plus a .partial, remembered recipients, a queue and a counter.
  Future<void> populateAll() async {
    final d = await open();
    await populate(d); // user classes, renamed/hidden built-ins, 8 rows, 2 map rows
    final t0 = DateTime(2026, 9, 21, 10).millisecondsSinceEpoch;
    for (final (i, type) in const ['POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME', 'CASH'].indexed) {
      await insertSpentTx(d,
          code: type == 'CASH' ? 'CASH-20260921-2000' : 'PXQ${i}ZZZ00$i',
          sourceType: type,
          amountCents: 5000 + i,
          feeCents: 100,
          occurredAtMs: t0 + i);
    }
    // Withdrawal with an agent number, one soft-deleted AIRTIME.
    await d.update('transactions', {'agent_number': '123456'},
        where: "source_type = 'AGENT_WITHDRAWAL'");
    await insertSpentTx(d,
        code: 'AIRDEL0001', sourceType: 'AIRTIME', amountCents: 2000, feeCents: 0, occurredAtMs: t0 + 9, deletedAtMs: t0 + 99);

    SharedPreferences.setMockInitialValues({
      'user_display_name': 'Invented User',
      'palette_id': 'leaf',
      'appearance_mode': 'dark',
      'onboarding_complete': true,
      'first_day_of_week': 3,
      'tour_seen_home': true,
      'update_check_enabled': false,
      'whatsnew_seen_version': '0.1.1',
      'updates_inbox_v1': '[]',
      'auto_backup_enabled': true,
      'auto_backup_folder_uri': 'content://tree/invented',
      'auto_backup_folder_name': 'Invented folder',
      'auto_backup_every_n': 12,
      'auto_backup_keep_k': 4,
      'auto_backup_since_count': 7,
      'auto_backup_written_uris': <String>['content://tree/invented/doc/1'],
      'auto_backup_last_at': '2026-09-20T10:00:00.000',
      'backup_last_manual_at': 1790000000000,
      'recipient_types_v1': '{"INVENTED NAME":{"t":"POCHI_LA_BIASHARA","at":1790000000000}}',
      'pending_entries_v1': '[{"x":1}]',
      'phone_merge_report_v1': '{"merged":2}',
    });
    final dir = Directory(p.join(safetyBase.path, 'safety'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'mmogo-safety-20260921-100000-001.json')).writeAsString('{}');
    await File(p.join(dir.path, 'mmogo-safety-20260921-100000-002.json.partial')).writeAsString('{');
  }

  Future<int> count(String sql) async => firstIntOf(await (await open()).rawQuery(sql)) ?? -1;

  static int? firstIntOf(List<Map<String, Object?>> rows) => rows.isEmpty ? null : rows.first.values.first as int?;

  Future<Map<String, Object?>> prefsMap() async {
    final sp = await SharedPreferences.getInstance();
    await sp.reload();
    return {for (final k in sp.getKeys()) k: sp.get(k)};
  }

  Future<bool> dbFileExists() => File(dbPath).exists();
}

/// Creates the four database sidecar files next to the database.
Future<void> plantSidecars(String dbPath) async {
  for (final s in const ['-journal', '-wal', '-shm']) {
    await File('$dbPath$s').writeAsString('x');
  }
}
