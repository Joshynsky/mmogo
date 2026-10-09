import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migrations.dart';
import 'schema.dart';

/// §DATA.DB.OPEN — the ONE place a mmogo database is opened (S3a, DB1).
///
/// `AppDatabase`, the migration tests and the frozen-fixture builders all call
/// [openMmogoDatabase], so the foreign-key behaviour below cannot drift between
/// the app and its tests.
///
/// Foreign-key rule (a table-rebuild upgrade needs it, see [kFkOffUpgradeFromTarget]):
///  - a fresh file, or a file already at the target version: `foreign_keys` ON;
///  - an upgrade whose TARGET version is `>= kFkOffUpgradeFromTarget` (the v3
///    rebuild): OFF while `onUpgrade` runs (`PRAGMA foreign_keys` is a no-op
///    inside a transaction, so it must be set in `onConfigure`, before sqflite
///    opens the upgrade transaction); the migration itself runs
///    `PRAGMA foreign_key_check` before it commits;
///  - after the open completes (`onOpen`, which runs after any upgrade has
///    committed): always ON, read back, and a StateError if it is not.
///  - an upgrade to a target BELOW [kFkOffUpgradeFromTarget] (today's v1 -> v2)
///    keeps the 0.1.1 behaviour: ON throughout.
///
/// With `kDbVersion = 2` (this slice) no live path reaches the OFF branch, so
/// the shipped behaviour is the 0.1.1 one: ON for every open.

/// The first target version whose upgrade rebuilds tables (needs FK OFF).
const int kFkOffUpgradeFromTarget = 3;

/// Opens (creating or upgrading) the mmogo database at [path] through [factory].
///
/// [version], [onCreate] and [onUpgrade] default to the live ones; a test passes
/// its own to exercise a future version or a failing step. [onOpen] is for tests
/// that want to observe the state right after open.
Future<Database> openMmogoDatabase(
  DatabaseFactory factory,
  String path, {
  int version = kDbVersion,
  bool singleInstance = true,
  FutureOr<void> Function(Database db, int version)? onCreate,
  FutureOr<void> Function(Database db, int oldVersion, int newVersion)? onUpgrade,
}) {
  return factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      singleInstance: singleInstance,
      onConfigure: (db) async {
        final uv = firstIntOf(await db.rawQuery('PRAGMA user_version')) ?? 0;
        final upgrading = uv > 0 && uv < version;
        final off = upgrading && version >= kFkOffUpgradeFromTarget;
        await db.execute('PRAGMA foreign_keys = ${off ? 'OFF' : 'ON'}');
      },
      onCreate: onCreate ??
          (db, v) async {
            await AppSchema.createSchema(db);
            await AppSchema.seed(db);
          },
      onUpgrade: onUpgrade ?? AppMigrations.migrate,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        final on = firstIntOf(await db.rawQuery('PRAGMA foreign_keys'));
        if (on != 1) {
          throw StateError('PRAGMA foreign_keys is not ON after open');
        }
      },
    ),
  );
}

/// The first column of the first row as an int (sqflite's own helper is not
/// exported by sqflite_common_ffi), or null for no rows / a non-int.
int? firstIntOf(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return null;
  final v = rows.first.values.first;
  return v is int ? v : null;
}
