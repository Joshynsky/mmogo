import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/airtime/airtime_kind.dart';
import 'migration_v3_ddl.dart';
import 'migration_v5_ddl.dart';
import 'migration_v6_ddl.dart';
import 'migration_v7_ddl.dart';

/// Pure schema/seed logic, factored out of [AppDatabase] so it can be
/// exercised directly against an in-memory database in unit tests without
/// needing `path_provider`'s platform channel (unavailable outside a real
/// app run). This is the single source of truth for the DDL described in
/// the app's data model (current schema only) — `AppDatabase` and the test suite both call into this file
/// rather than each keeping their own copy of the schema.
/// Version 4 (0.2.0 S12): the Fuliza ledger's stored events. ONE definition, used by
/// [AppSchema.createSchema] (fresh install) and by `AppMigrations` step 4 (upgrade), so
/// the two cannot drift. `kind` holds the `FulizaEventKind` enum NAMES (a test pins
/// them). `occurred_at` is epoch milliseconds, like `transactions.transaction_occurred_at`.
/// The message text is never stored.
const List<String> kFulizaEventsStatements = [
  '''CREATE TABLE IF NOT EXISTS fuliza_events (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  kind                 TEXT    NOT NULL CHECK (kind IN ('draw','repayFull','repayPartial')),
  code                 TEXT    NOT NULL CHECK (length(code) > 0),
  occurred_at          INTEGER NOT NULL,
  amount_cents         INTEGER NOT NULL CHECK (amount_cents > 0),
  fee_cents            INTEGER NOT NULL DEFAULT 0 CHECK (fee_cents >= 0),
  printed_total_cents  INTEGER NULL CHECK (printed_total_cents IS NULL OR printed_total_cents >= 0)
)''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_fuliza_events_kind_code ON fuliza_events(kind, code)',
];

class AppSchema {
  AppSchema._();

  /// The 18 built-in classifications, in insertion order (ids 1..18 on a fresh
  /// install). The first 12 are the 0.1.1 list (`AppMigrations.v2SeedClassifications`
  /// is its frozen copy: `_toV2` relies on ids 1..12 to backfill `seed_key`);
  /// the next 5 are `kV3NewSeeds` (version 5 renames the Airtime one to 'For myself'
  /// and appends 'For another number' as id 18). Append only: never reorder or insert in the middle.
  static const List<({String group, String name, String seedKey})>
      seedClassifications = [
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
    // Added in version 3 (0.1.2); frozen as `kV3NewSeeds`. Ids 13..17 on a fresh install.
    (group: 'AGENT_WITHDRAWAL', name: 'Withdrawal', seedKey: 'AGENT_WITHDRAWAL:cash_withdrawal'),
    (group: 'AIRTIME', name: kAirtimeNameMyself, seedKey: kAirtimeSeedMyself),
    (group: 'POCHI_LA_BIASHARA', name: 'Transport', seedKey: 'POCHI_LA_BIASHARA:transport'),
    (group: 'POCHI_LA_BIASHARA', name: 'Groceries', seedKey: 'POCHI_LA_BIASHARA:groceries'),
    (group: 'POCHI_LA_BIASHARA', name: 'Shopping', seedKey: 'POCHI_LA_BIASHARA:shopping'),
    // Added in version 5 (0.2.0 row 17): the second Airtime category. Id 18 on a
    // fresh install; a migrated file gets the next free id.
    (group: 'AIRTIME', name: kAirtimeNameOther, seedKey: kAirtimeSeedOther),
  ];

  /// Creates the CURRENT (version 7) schema: the v3 tables plus `fuliza_events`, the Airtime kind-lock trigger and the v6 link columns/triggers from the frozen constants in
  /// `migration_v3_ddl.dart`, so a fresh install and a migrated 0.1.1 database
  /// come from the same text. (The long design history of the `transactions`
  /// CHECKs lives with the frozen 0.1.1 copy, `test/fixtures/schema_v2.dart`.)
  static Future<void> createSchema(Database db) async {
    for (final sql in v7SchemaStatements()) {
      await db.execute(sql);
    }
    for (final sql in kFulizaEventsStatements) {
      await db.execute(sql);
    }
    await db.execute(kAirtimeKindTriggerDdl);
    for (final sql in kV6Statements) {
      await db.execute(sql);
    }
  }

  static Future<void> seed(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // classification_groups — 6 seed rows (ids 1..6), all enabled; Pochi is
    // named 'Pochi' (renamed from 'Pochi La Biashara' in 0.1.2).
    final groupIds = <String, int>{};
    for (final g in kV3GroupSeeds) {
      groupIds[g.code] = await db.insert('classification_groups', {
        'code': g.code,
        'display_name': g.displayName,
        'enabled': g.enabled,
        'created_at': now,
      });
    }

    // Version 7: the withdrawal "Cash" group (id 7). It has NO seed categories; the user makes them.
    groupIds[kCashUseGroupCode] = await db.insert('classification_groups', {
      'code': kCashUseGroupCode,
      'display_name': kCashUseGroupName,
      'enabled': 1,
      'created_at': now,
    });

    // classifications — 18 seed rows, group-scoped, each with its seed_key.
    for (final row in seedClassifications) {
      await db.insert('classifications', {
        'group_id': groupIds[row.group],
        'name': row.name,
        'active': 1,
        'created_at': now,
        'seed_key': row.seedKey,
      });
    }

    // counterparty_classification_map — intentionally empty at seed.
  }
}
