/// Shared constants for the backup file: the exporter (`BackupService`) and
/// the restore validator (`BackupValidator`) both import this file, so a file
/// the app writes can never exceed what the app will read back.
///
/// Created by B9; imported by B10. No imports here (pure constants), so it can
/// be used from an isolate.
library;

// --- envelope ---------------------------------------------------------------

const String kBackupAppMarker = 'mmogo';
const int kBackupFormatVersion = 1;

/// The `schema_version` the exporter writes (the database version it exports).
/// Mirrors `kDbVersion` in `migrations.dart` (a test pins the two together);
/// kept as a literal here so this file stays import-free.
const int kBackupSchemaVersion = 3;

/// The lowest `schema_version` a file may carry (`seed_key` exists from v2).
const int kBackupMinSchemaVersion = 2;

/// First schema that may carry the two new group codes, the two new source
/// types, the five new seed keys and the `agent_number` row key (0.1.2).
const int kBackupFirstSchemaWithAgentAndAirtime = 3;

/// Last top-level key of every file. Lets a reader (and the auto-backup
/// prune) see the file was written to the end.
const String kBackupEndMarker = 'mmogo-v1';

// --- size and row caps --------------------------------------------------------

/// 20 MB: the largest file the app will read (restore) or write (export).
const int kBackupMaxBytes = 20 * 1024 * 1024;

const int kBackupMaxTransactions = 50000;
const int kBackupMaxClassifications = 1000;
const int kBackupMaxMapRows = 20000;
const int kBackupMaxPrefsKeys = 32;

/// Deepest JSON nesting a valid file has is 3 (root, array, row object). The
/// validator's pre-scan refuses anything deeper than this before `jsonDecode`.
const int kBackupMaxJsonDepth = 8;

// --- string lengths -------------------------------------------------------------

/// Classification names (B3 limit on the Add and Manage screens).
const int kBackupMaxClassificationNameLength = 100;

/// Receiver / business label (B3 limit).
const int kBackupMaxLabelLength = 200;

const int kBackupMaxPaybillAccountLength = 100;

/// Agent number: 1 to 20 ASCII digits (mirrors the DB CHECK).
const int kBackupMaxAgentNumberLength = 20;

/// A PAYBILL key is `LABEL#ACCOUNT`: 200 + 1 + 100 = 301, so 310 leaves room.
const int kBackupMaxCounterpartyKeyLength = 310;
const int kBackupMaxDisplayNameLength = 30;

// --- value ranges ---------------------------------------------------------------

/// Epoch ms, [2007-01-01T00:00Z, 2100-01-01T00:00Z).
const int kBackupMinEpochMs = 1167609600000;
const int kBackupMaxEpochMs = 4102444800000;

const int kBackupMaxClassificationFileId = 2147483647;
const int kBackupMaxAmountCents = 10000000000; // KSh 100 million
const int kBackupMaxCostCents = 10000000;

// --- enums ----------------------------------------------------------------------

/// Group codes of a schema >= 3 file (six).
const List<String> kBackupGroupCodes = [
  'SEND_MONEY',
  'PAYBILL',
  'BUY_GOODS',
  'POCHI_LA_BIASHARA',
  'AGENT_WITHDRAWAL',
  'AIRTIME',
];

/// Group codes a schema 2 file may carry (the original four, literal).
const List<String> kBackupGroupCodesV2 = [
  'SEND_MONEY',
  'PAYBILL',
  'BUY_GOODS',
  'POCHI_LA_BIASHARA',
];

/// Source types of a schema >= 3 file (seven). POCHI_LA_BIASHARA is a
/// stored group code AND a source type since 0.1.2; a garbage type is not.
const List<String> kBackupSourceTypes = [
  'SEND_MONEY',
  'BUY_GOODS',
  'PAYBILL',
  'CASH',
  'POCHI_LA_BIASHARA',
  'AGENT_WITHDRAWAL',
  'AIRTIME',
];

/// Source types a schema 2 file may carry (the original four, literal).
const List<String> kBackupSourceTypesV2 = [
  'SEND_MONEY',
  'BUY_GOODS',
  'PAYBILL',
  'CASH',
];

/// Source types whose `counterparty_label` may be set (mirrors the v3 label
/// CHECK of `transactions`): every identity-carrying type. CASH and AIRTIME
/// never carry a label.
const List<String> kBackupLabelSourceTypes = [
  'SEND_MONEY',
  'BUY_GOODS',
  'PAYBILL',
  'POCHI_LA_BIASHARA',
  'AGENT_WITHDRAWAL',
];

/// Source types a counterparty-map row may carry (never CASH).
const List<String> kBackupMapSourceTypes = [
  'SEND_MONEY',
  'BUY_GOODS',
  'PAYBILL',
];

const List<String> kBackupRawParseSources = ['SMS_PARSE', 'MANUAL'];

/// The 12 built-in keys a schema 2 file may carry (literal, frozen).
const List<String> kBackupSeedKeysV2 = [
  'SEND_MONEY:family_friends',
  'SEND_MONEY:rent',
  'SEND_MONEY:transport',
  'SEND_MONEY:groceries',
  'PAYBILL:rent_payment',
  'PAYBILL:shopping',
  'PAYBILL:transport',
  'PAYBILL:groceries',
  'BUY_GOODS:rent_payment',
  'BUY_GOODS:shopping',
  'BUY_GOODS:transport',
  'BUY_GOODS:groceries',
];

/// The 17 built-in classification keys (`classifications.seed_key`) of a
/// schema >= 3 file: the 12 above, then the five 0.1.2 seeds. A file may carry
/// each at most once, on a row of the matching group. A test pins this list to
/// `AppSchema.seedClassifications`.
const List<String> kBackupSeedKeys = [
  'SEND_MONEY:family_friends',
  'SEND_MONEY:rent',
  'SEND_MONEY:transport',
  'SEND_MONEY:groceries',
  'PAYBILL:rent_payment',
  'PAYBILL:shopping',
  'PAYBILL:transport',
  'PAYBILL:groceries',
  'BUY_GOODS:rent_payment',
  'BUY_GOODS:shopping',
  'BUY_GOODS:transport',
  'BUY_GOODS:groceries',
  'AGENT_WITHDRAWAL:cash_withdrawal',
  'AIRTIME:airtime',
  'POCHI_LA_BIASHARA:transport',
  'POCHI_LA_BIASHARA:groceries',
  'POCHI_LA_BIASHARA:shopping',
];

/// C-A10: the two built-ins a restore never writes (Withdrawal and Airtime):
/// they stay active with their own names whatever a file says. Taken from
/// [kBackupSeedKeys] by group prefix so the strings are not typed twice; a test
/// pins the two values.
final Set<String> kBackupLockedSeedKeys = {
  for (final k in kBackupSeedKeys)
    if (k.startsWith('AGENT_WITHDRAWAL:') || k.startsWith('AIRTIME:')) k,
};

// --- exact key sets (const; the file's keys are never used as column names) -----

const List<String> kBackupTopLevelKeys = [
  'app',
  'format_version',
  'schema_version',
  'created_at',
  'counts',
  'classifications',
  'transactions',
  'counterparty_map',
  'prefs',
  'end',
];

const List<String> kBackupCountsKeys = [
  'classifications',
  'transactions',
  'counterparty_map',
];

const List<String> kBackupClassificationKeys = [
  'id',
  'group',
  'name',
  'active',
  'seed_key',
  'created_at',
];

/// Row keys of a schema >= 3 file (13): `agent_number` is always present
/// (null allowed). The exporter writes these.
const List<String> kBackupTransactionKeys = [
  'id',
  'display_code',
  'source_type',
  'amount_cents',
  'transaction_cost_cents',
  'counterparty_label',
  'counterparty_phone',
  'paybill_account_number',
  'agent_number',
  'classification',
  'raw_parse_source',
  'transaction_occurred_at',
  'created_at',
];

/// Row keys of a schema 2 file (12, literal): no `agent_number`. A schema 2
/// file that carries the key is refused (exact-key defence).
const List<String> kBackupTransactionKeysV2 = [
  'id',
  'display_code',
  'source_type',
  'amount_cents',
  'transaction_cost_cents',
  'counterparty_label',
  'counterparty_phone',
  'paybill_account_number',
  'classification',
  'raw_parse_source',
  'transaction_occurred_at',
  'created_at',
];

const List<String> kBackupMapKeys = [
  'source_type',
  'counterparty_key',
  'classification',
  'auto_apply',
  'updated_at',
];

// --- patterns -------------------------------------------------------------------

/// Non-CASH display code: an M-Pesa code.
final RegExp kBackupMpesaCodePattern = RegExp(r'^[A-Z0-9]{10}$');

/// CASH display code, `CASH-YYYYMMDD-HHMM`.
final RegExp kBackupCashCodePattern = RegExp(r'^CASH-\d{8}-\d{4}$');

final RegExp kBackupPhonePattern = RegExp(r'^[0-9+ ]{7,20}$');

/// Agent number: 1 to 20 ASCII digits. Dart `$` matches only at the end of
/// input, so `12\n` fails here exactly as the DB's GLOB rejects it.
final RegExp kBackupAgentNumberPattern = RegExp(r'^[0-9]{1,20}$');

/// Manual backup file name (`mmogo-backup-YYYYMMDD-HHMMSS.json`).
final RegExp kBackupManualFileNamePattern =
    RegExp(r'^mmogo-backup-\d{8}-\d{6}\.json$');

// --- text safety ----------------------------------------------------------------

/// False when [s] holds a C0 or C1 control character (U+0000-001F,
/// U+007F-009F) or a bidi / format control (U+061C, U+200E, U+200F,
/// U+202A-202E, U+2066-2069). Every string in a backup file must pass; the
/// validator rejects the file rather than edit the text.
bool backupTextIsClean(String s) {
  for (final c in s.codeUnits) {
    if (c <= 0x1F) return false;
    if (c >= 0x7F && c <= 0x9F) return false;
    if (c == 0x061C || c == 0x200E || c == 0x200F) return false;
    if (c >= 0x202A && c <= 0x202E) return false;
    if (c >= 0x2066 && c <= 0x2069) return false;
  }
  return true;
}
