import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The database version this build creates and expects.
///
/// 1 = the 0.1.0 schema. 2 = adds `classifications.seed_key` (0.1.1).
/// Adding v3 later means: add `_toV3`, register it in [AppMigrations.steps],
/// bump this constant, and update `AppSchema.createSchema` to the latest
/// shape in the same change.
const int kDbVersion = 2;

/// The `onUpgrade` ladder.
///
/// Rules every step follows:
///  - one function per step; step N only knows how to go from N-1 to N;
///  - runs inside sqflite's single `onUpgrade` transaction (which restores the
///    previous `user_version` if anything throws), so a step uses the
///    [DatabaseExecutor] it is given and never opens a nested transaction or
///    touches `AppDatabase.instance`;
///  - idempotent, and additive only (no table rebuilds, so the guard triggers
///    and unique indexes are never at risk).
class AppMigrations {
  AppMigrations._();

  /// DB2: the FROZEN 12 built-ins as 0.1.1 shipped them (ids 1..12, in this
  /// order). `_toV2` backfills `seed_key` from THIS list, never from the live
  /// `AppSchema.seedClassifications`, which grows to 17 entries at version 3
  /// (reading it would index ids 13..17 into a 0.1.0 file). A test pins the
  /// length at 12 and fails if `_toV2` mentions the live list. Never edit.
  static const List<({String group, String name, String seedKey})>
      v2SeedClassifications = _v2SeedClassifications;

  /// Key = the version the step upgrades TO.
  static final Map<int, Future<void> Function(DatabaseExecutor db)> steps = {
    2: _toV2,
  };

  /// Wired as `openDatabase(onUpgrade: AppMigrations.migrate)`.
  static Future<void> migrate(Database db, int oldVersion, int newVersion) =>
      upgrade(db, oldVersion, newVersion, steps: steps);

  /// Runs every step from `from + 1` up to and including `to`. [steps] is
  /// injectable so a test can supply a failing step.
  static Future<void> upgrade(
    DatabaseExecutor db,
    int from,
    int to, {
    Map<int, Future<void> Function(DatabaseExecutor db)>? steps,
  }) async {
    final ladder = steps ?? AppMigrations.steps;
    for (var v = from + 1; v <= to; v++) {
      final step = ladder[v];
      if (step == null) throw StateError('No migration step for version $v');
      await step(db);
    }
  }

  /// v1 -> v2: a stable key for the 12 built-in classifications, so a built-in
  /// the user renamed is still recognised as that built-in (a backup restore
  /// would otherwise bring it back as a duplicate). User-created rows keep
  /// `seed_key = NULL`.
  static Future<void> _toV2(DatabaseExecutor db) async {
    final cols = await db.rawQuery('PRAGMA table_info(classifications)');
    final hasColumn = cols.any((c) => c['name'] == 'seed_key');
    if (!hasColumn) {
      await db.execute('ALTER TABLE classifications ADD COLUMN seed_key TEXT NULL');
    }
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_classifications_seed_key
        ON classifications(seed_key) WHERE seed_key IS NOT NULL
    ''');

    // Seed ids in any 0.1.0 database are exactly 1..12, in seed order (fresh
    // AUTOINCREMENT, rows are never hard-deleted), so the backfill is exact
    // even if the user renamed or deactivated a built-in. The group check is
    // a belt-and-braces guard.
    for (var i = 0; i < _v2SeedClassifications.length; i++) {
      final seed = _v2SeedClassifications[i];
      await db.rawUpdate(
        'UPDATE classifications SET seed_key = ? '
        'WHERE id = ? AND seed_key IS NULL '
        'AND group_id = (SELECT id FROM classification_groups WHERE code = ?)',
        [seed.seedKey, i + 1, seed.group],
      );
    }
  }
}

/// See [AppMigrations.v2SeedClassifications]. FROZEN: 12 entries, never edited.
const List<({String group, String name, String seedKey})> _v2SeedClassifications = [
  (group: 'SEND_MONEY', name: 'Family/Friends', seedKey: 'SEND_MONEY:family_friends'),
  (group: 'SEND_MONEY', name: 'Rent', seedKey: 'SEND_MONEY:rent'),
  (group: 'SEND_MONEY', name: 'Transport', seedKey: 'SEND_MONEY:transport'),
  (group: 'SEND_MONEY', name: 'Groceries', seedKey: 'SEND_MONEY:groceries'),
  (group: 'PAYBILL', name: 'Rent Payment', seedKey: 'PAYBILL:rent_payment'),
  (group: 'PAYBILL', name: 'Shopping', seedKey: 'PAYBILL:shopping'),
  (group: 'PAYBILL', name: 'Transport', seedKey: 'PAYBILL:transport'),
  (group: 'PAYBILL', name: 'Groceries', seedKey: 'PAYBILL:groceries'),
  (group: 'BUY_GOODS', name: 'Rent Payment', seedKey: 'BUY_GOODS:rent_payment'),
  (group: 'BUY_GOODS', name: 'Shopping', seedKey: 'BUY_GOODS:shopping'),
  (group: 'BUY_GOODS', name: 'Transport', seedKey: 'BUY_GOODS:transport'),
  (group: 'BUY_GOODS', name: 'Groceries', seedKey: 'BUY_GOODS:groceries'),
];
