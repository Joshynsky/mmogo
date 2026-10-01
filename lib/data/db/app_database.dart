import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema.dart';

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
  AppDatabase._internal();

  static final AppDatabase instance = AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // Desktop targets (Windows/Linux) have no first-party sqflite plugin —
    // route through sqflite_common_ffi's sqlite3-backed factory instead.
    // Mobile (Android/iOS) keeps the default plugin-backed factory.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String dbDirPath;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      // getDatabasesPath() is unsupported by databaseFactoryFfi on some
      // platforms; use the app's documents directory instead.
      final dir = await getApplicationDocumentsDirectory();
      dbDirPath = dir.path;
    } else {
      dbDirPath = await getDatabasesPath();
    }
    final dbPath = p.join(dbDirPath, 'mmogo.db');
    debugPrint('AppDatabase: opening $dbPath');

    return openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        // Triggers + FK enforcement both require this ON per-connection.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await AppSchema.createSchema(db);
        await AppSchema.seed(db);
      },
    );
  }

  /// Test/dev-only: closes and clears the cached instance so a fresh
  /// database can be opened (e.g. an in-memory DB per test case).
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
