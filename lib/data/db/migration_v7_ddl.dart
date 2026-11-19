import 'migration_v3_ddl.dart';

/// §DATA.DB.MIGRATION_V7_DDL (0.2.1, PM decision #33) - the "Cash" category group.
///
/// A withdrawal's own list of categories ("What was this money for?"). It starts EMPTY for every
/// user (no seeds), is not locked (Manage categories lets the user rename and delete), and is a
/// real `classification_groups` row so backups, restore and Manage carry it by code like the
/// other groups. The locked `AGENT_WITHDRAWAL` group is NOT reused: it holds the one built-in
/// 'Withdrawal' category the withdrawal rows themselves use.
const String kCashUseGroupCode = 'CASH_USE';

/// The group's display name (the Manage categories tab).
const String kCashUseGroupName = 'Cash';

/// `classification_groups` with the 7-code CHECK (adds [kCashUseGroupCode]). SQLite cannot
/// alter a CHECK, so the version 7 step rebuilds the table from this text and a fresh
/// install creates it from this text, so the two cannot drift.
const String kV7GroupsDdl = '''
CREATE TABLE classification_groups (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  code          TEXT NOT NULL UNIQUE
                CHECK (code IN ('SEND_MONEY','PAYBILL','BUY_GOODS','POCHI_LA_BIASHARA','AGENT_WITHDRAWAL','AIRTIME','CASH_USE')),
  display_name  TEXT NOT NULL,
  enabled       INTEGER NOT NULL DEFAULT 1,
  created_at    INTEGER NOT NULL
)''';

/// The v3 schema statements with the group table swapped for [kV7GroupsDdl].
List<String> v7SchemaStatements() => [
      for (final s in v3SchemaStatements()) s == kV3GroupsDdl ? kV7GroupsDdl : s,
    ];
