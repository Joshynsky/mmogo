import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migrations.dart';

/// §DATA.DB.MIGRATION_V3_DDL — the FROZEN version-3 DDL, seeds and seed keys
/// (S3a, DB3: constants only).
///
/// NOTHING in the app reads this file yet: `AppSchema.createSchema`, `seed`,
/// `kDbVersion` (still 2) and the migration ladder are untouched. Slice S3b
/// makes `createSchema` and `_toV3` use these constants, so a fresh v3 file and
/// a migrated one come from the same text. Per the Judge (BINDING) the seed keys,
/// the DDL and the names below freeze here: change one and every released
/// backup or migrated database disagrees with it.
///
/// Only `classification_groups` (6-code CHECK) and `transactions` differ from
/// version 2; the rest is repeated so [createFreshV3ForTest] can build a whole
/// database. Statements are positional-`?` free DDL: no parameters at all.

/// `classification_groups` — the 6-code CHECK (adds AGENT_WITHDRAWAL, AIRTIME).
const String kV3GroupsDdl = '''
CREATE TABLE classification_groups (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  code          TEXT NOT NULL UNIQUE
                CHECK (code IN ('SEND_MONEY','PAYBILL','BUY_GOODS','POCHI_LA_BIASHARA','AGENT_WITHDRAWAL','AIRTIME')),
  display_name  TEXT NOT NULL,
  enabled       INTEGER NOT NULL DEFAULT 1,
  created_at    INTEGER NOT NULL
)''';

/// `classifications` — unchanged from version 2.
const String kV3ClassificationsDdl = '''
CREATE TABLE classifications (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id      INTEGER NOT NULL REFERENCES classification_groups(id) ON DELETE RESTRICT,
  name          TEXT NOT NULL,
  active        INTEGER NOT NULL DEFAULT 1,
  created_at    INTEGER NOT NULL,
  seed_key      TEXT NULL
)''';

/// The three `classifications` indexes — unchanged from version 2.
const List<String> kV3ClassificationIndexes = [
  'CREATE UNIQUE INDEX idx_classifications_active_name ON classifications(group_id, name) WHERE active = 1',
  'CREATE INDEX idx_classifications_group ON classifications(group_id)',
  'CREATE UNIQUE INDEX idx_classifications_seed_key ON classifications(seed_key) WHERE seed_key IS NOT NULL',
];

/// The agent-number CHECK on its own (DBE T2.2): NULL, or a Withdrawal row with
/// 1..20 ASCII digits. Kept as a named constant so a test can strip exactly this
/// clause from [kV3TransactionsDdl] and prove the clause is what rejects.
const String kV3AgentNumberCheck =
    "CHECK ( agent_number IS NULL OR ( source_type = 'AGENT_WITHDRAWAL' "
    "AND length(agent_number) BETWEEN 1 AND 20 AND agent_number NOT GLOB '*[^0-9]*' ) )";

/// The label CHECK on its own (widened to the two new identity-carrying types).
const String kV3LabelCheck =
    "CHECK ( source_type IN ('SEND_MONEY','BUY_GOODS','PAYBILL','POCHI_LA_BIASHARA','AGENT_WITHDRAWAL') "
    'OR counterparty_label IS NULL )';

/// `transactions` — DBE T2.3: 7 source types, `agent_number TEXT NULL` after
/// `paybill_account_number`, the widened label CHECK and the agent-number CHECK.
const String kV3TransactionsDdl = '''
CREATE TABLE transactions (
  id                      INTEGER PRIMARY KEY AUTOINCREMENT,
  display_code            TEXT NOT NULL,
  source_type             TEXT NOT NULL
    CHECK (source_type IN ('SEND_MONEY','BUY_GOODS','PAYBILL','CASH','POCHI_LA_BIASHARA','AGENT_WITHDRAWAL','AIRTIME')),
  amount_cents            INTEGER NOT NULL CHECK (amount_cents > 0),
  transaction_cost_cents  INTEGER NULL,
  counterparty_label      TEXT NULL,
  counterparty_phone      TEXT NULL,
  paybill_account_number  TEXT NULL,
  agent_number            TEXT NULL,
  classification_id       INTEGER NOT NULL REFERENCES classifications(id) ON DELETE RESTRICT,
  raw_parse_source        TEXT NOT NULL CHECK (raw_parse_source IN ('SMS_PARSE','MANUAL')),
  transaction_occurred_at INTEGER NOT NULL,
  created_at              INTEGER NOT NULL,
  deleted_at              INTEGER NULL,
  CHECK ( (source_type = 'CASH' AND transaction_cost_cents IS NULL)
       OR (source_type != 'CASH' AND transaction_cost_cents IS NOT NULL) ),
  $kV3LabelCheck,
  CHECK ( source_type = 'SEND_MONEY' OR counterparty_phone IS NULL ),
  CHECK ( source_type = 'PAYBILL' OR paybill_account_number IS NULL ),
  $kV3AgentNumberCheck,
  CHECK ( source_type != 'SEND_MONEY' OR (counterparty_label IS NULL) = (counterparty_phone IS NULL) ),
  CHECK ( source_type != 'PAYBILL' OR (counterparty_label IS NULL) = (paybill_account_number IS NULL) ),
  CHECK ( source_type != 'CASH' OR raw_parse_source = 'MANUAL' )
)''';

/// The five `transactions` indexes, verbatim from version 2.
const List<String> kV3TransactionIndexes = [
  'CREATE INDEX idx_transactions_classification ON transactions(classification_id)',
  'CREATE INDEX idx_transactions_occurred ON transactions(transaction_occurred_at)',
  'CREATE INDEX idx_transactions_source ON transactions(source_type)',
  'CREATE INDEX idx_transactions_deleted_at ON transactions(deleted_at)',
  "CREATE UNIQUE INDEX idx_transactions_mpesa_code ON transactions(display_code) "
      "WHERE source_type != 'CASH' AND deleted_at IS NULL",
];

/// The two group-scope guard triggers, verbatim from version 2.
const List<String> kV3Triggers = [
  '''
CREATE TRIGGER trg_transactions_classification_scope_ins
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
  SELECT RAISE(ABORT, 'classification_id does not belong to the group matching source_type')
  WHERE NEW.source_type != 'CASH'
    AND (SELECT g.code FROM classifications c
         JOIN classification_groups g ON g.id = c.group_id
         WHERE c.id = NEW.classification_id) != NEW.source_type;

  SELECT RAISE(ABORT, 'classification_id belongs to a disabled group')
  WHERE NEW.source_type = 'CASH'
    AND (SELECT g.enabled FROM classifications c
         JOIN classification_groups g ON g.id = c.group_id
         WHERE c.id = NEW.classification_id) != 1;
END''',
  '''
CREATE TRIGGER trg_transactions_classification_scope_upd
BEFORE UPDATE OF classification_id, source_type ON transactions
FOR EACH ROW
BEGIN
  SELECT RAISE(ABORT, 'classification_id does not belong to the group matching source_type')
  WHERE NEW.source_type != 'CASH'
    AND (SELECT g.code FROM classifications c
         JOIN classification_groups g ON g.id = c.group_id
         WHERE c.id = NEW.classification_id) != NEW.source_type;

  SELECT RAISE(ABORT, 'classification_id belongs to a disabled group')
  WHERE NEW.source_type = 'CASH'
    AND (SELECT g.enabled FROM classifications c
         JOIN classification_groups g ON g.id = c.group_id
         WHERE c.id = NEW.classification_id) != 1;
END''',
];

/// `counterparty_classification_map` and its two indexes — unchanged in shape.
const String kV3MapDdl = '''
CREATE TABLE counterparty_classification_map (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  source_type       TEXT NOT NULL CHECK (source_type IN ('SEND_MONEY','BUY_GOODS','PAYBILL')),
  counterparty_key  TEXT NOT NULL,
  classification_id INTEGER NOT NULL REFERENCES classifications(id) ON DELETE CASCADE,
  auto_apply        INTEGER NOT NULL DEFAULT 0,
  updated_at        INTEGER NOT NULL,
  UNIQUE (source_type, counterparty_key)
)''';

const List<String> kV3MapIndexes = [
  'CREATE INDEX idx_counterparty_map_classification ON counterparty_classification_map(classification_id)',
  'CREATE INDEX idx_counterparty_map_recency ON counterparty_classification_map(updated_at DESC)',
];

/// The six group rows of a FRESH version-3 install, in id order (1..6).
/// Display names: 'Pochi' (enabled, renamed from 'Pochi La Biashara'),
/// 'Withdrawal', 'Airtime' (names fixed 08-10-2026).
const List<({String code, String displayName, int enabled})> kV3GroupSeeds = [
  (code: 'SEND_MONEY', displayName: 'Send Money', enabled: 1),
  (code: 'PAYBILL', displayName: 'Paybill', enabled: 1),
  (code: 'BUY_GOODS', displayName: 'Buy Goods', enabled: 1),
  (code: 'POCHI_LA_BIASHARA', displayName: 'Pochi', enabled: 1),
  (code: 'AGENT_WITHDRAWAL', displayName: 'Withdrawal', enabled: 1),
  (code: 'AIRTIME', displayName: 'Airtime', enabled: 1),
];

/// FROZEN `_v3NewSeeds`: the five built-ins version 3 adds, in insertion order
/// (ids 13..17 on a fresh install). The seed key never changes. Note the
/// AGENT_WITHDRAWAL key keeps the older `cash_withdrawal` spelling on purpose.
const List<({String group, String name, String seedKey})> kV3NewSeeds = [
  (group: 'AGENT_WITHDRAWAL', name: 'Withdrawal', seedKey: 'AGENT_WITHDRAWAL:cash_withdrawal'),
  (group: 'AIRTIME', name: 'Airtime', seedKey: 'AIRTIME:airtime'),
  (group: 'POCHI_LA_BIASHARA', name: 'Transport', seedKey: 'POCHI_LA_BIASHARA:transport'),
  (group: 'POCHI_LA_BIASHARA', name: 'Groceries', seedKey: 'POCHI_LA_BIASHARA:groceries'),
  (group: 'POCHI_LA_BIASHARA', name: 'Shopping', seedKey: 'POCHI_LA_BIASHARA:shopping'),
];

/// The five new seed keys (what a schema >= 3 backup may name beyond the 12).
const List<String> kV3NewSeedKeys = [
  'AGENT_WITHDRAWAL:cash_withdrawal',
  'AIRTIME:airtime',
  'POCHI_LA_BIASHARA:transport',
  'POCHI_LA_BIASHARA:groceries',
  'POCHI_LA_BIASHARA:shopping',
];

/// All 17 seed keys of version 3 in fresh-install order: the frozen 12, then
/// [kV3NewSeeds].
List<String> v3SeedKeys() => [
      ...AppMigrations.v2SeedClassifications.map((s) => s.seedKey),
      ...kV3NewSeeds.map((s) => s.seedKey),
    ];

/// Every DDL statement of a whole version-3 schema, in creation order.
List<String> v3SchemaStatements() => [
      kV3GroupsDdl,
      kV3ClassificationsDdl,
      ...kV3ClassificationIndexes,
      kV3TransactionsDdl,
      ...kV3TransactionIndexes,
      ...kV3Triggers,
      kV3MapDdl,
      ...kV3MapIndexes,
    ];

/// Builds a FRESH version-3 database (schema + 6 groups + 17 seeds) from the
/// constants above. Test-only: the app's `createSchema` is not switched yet (S3b).
/// [ddl] lets a negative-control test hand in a deliberately altered statement
/// list; the default is the frozen one.
@visibleForTesting
Future<void> createFreshV3ForTest(Database db, {List<String>? ddl, int? nowMs}) async {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  for (final sql in ddl ?? v3SchemaStatements()) {
    await db.execute(sql);
  }
  final groupIds = <String, int>{};
  for (final g in kV3GroupSeeds) {
    groupIds[g.code] = await db.insert('classification_groups', {
      'code': g.code,
      'display_name': g.displayName,
      'enabled': g.enabled,
      'created_at': now,
    });
  }
  for (final s in [...AppMigrations.v2SeedClassifications, ...kV3NewSeeds]) {
    await db.insert('classifications', {
      'group_id': groupIds[s.group],
      'name': s.name,
      'active': 1,
      'created_at': now,
      'seed_key': s.seedKey,
    });
  }
}
