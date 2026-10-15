import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_open.dart';

/// Owns the single sqflite [Database] instance for the whole app.
///
/// Built against the CURRENT DDL only — see [AppSchema] for the actual DDL, which
/// this class just opens a real on-device database against:
///   - `classification_groups` (seed: 4 rows, POCHI_LA_BIASHARA disabled)
///   - `classifications` (seed: 12 rows, group-scoped uniqueness)
///   - `transactions` (revised DDL — counterparty_phone,
///     classification_id, deleted_at) + the two group-scope guard triggers
///   - `counterparty_classification_map` (no seed rows)
///
/// Desktop note: sqflite's native implementation targets mobile only.
/// `sqflite_common_ffi` supplies the desktop FFI backend; this file
/// initializes it for Windows/Linux so a desktop launch gets a real,
/// working database, not just Android/iOS.
class AppDatabase {
  AppDatabase._internal()
      : _pathOverride = null,
        _factoryOverride = null;

  /// Test seam: a database at [path] (a temp path) opened through [factory].
  /// The real app never uses this; tests use it so no test can reach the
  /// real database file.
  AppDatabase.forPath(Future<String> Function() path, {DatabaseFactory? factory})
      : _pathOverride = path,
        _factoryOverride = factory;

  static final AppDatabase instance = AppDatabase._internal();

  final Future<String> Function()? _pathOverride;
  final DatabaseFactory? _factoryOverride;

  /// How long [close] may take before it gives up (a timeout is a failure of
  /// the reset at step "database").
  Duration closeTimeout = const Duration(seconds: 10);

  /// Set by "Reset app" BEFORE the handle is closed, cleared only when the
  /// reset flag is removed or the reset stops with a failure. While it is set
  /// the [database] getter refuses to open (or create) the file, so a query
  /// from a screen cannot bring `mmogo.db` back in the middle of a reset.
  static bool resetInProgress = false;

  Database? _db;

  bool get isOpen => _db != null;

  Future<Database> get database async {
    if (resetInProgress) {
      throw StateError('A data operation is in progress');
    }
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  /// The full path of the database file (without opening it).
  Future<String> databasePath() async {
    final override = _pathOverride;
    if (override != null) return override();
    final String dbDirPath;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      // getDatabasesPath() is unsupported by databaseFactoryFfi on some
      // platforms; use the app's documents directory instead.
      final dir = await getApplicationDocumentsDirectory();
      dbDirPath = dir.path;
    } else {
      dbDirPath = await getDatabasesPath();
    }
    return p.join(dbDirPath, 'mmogo.db');
  }

  Future<Database> _open() async {
    // Desktop targets (Windows/Linux) have no first-party sqflite plugin —
    // route through sqflite_common_ffi's sqlite3-backed factory instead.
    // Mobile (Android/iOS) keeps the default plugin-backed factory.
    if (_factoryOverride == null && !kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await databasePath();
    debugPrint('AppDatabase: opening $dbPath');

    // DB1: the one shared open function (foreign-key rule lives there).
    return openMmogoDatabase(_factoryOverride ?? databaseFactory, dbPath);
  }

  /// Closes and clears the cached instance. Bounded by [closeTimeout]: a
  /// handle that will not close throws a [TimeoutException] and stays cached.
  Future<void> close() async {
    final db = _db;
    if (db == null) return;
    await db.close().timeout(closeTimeout);
    _db = null;
  }
}
