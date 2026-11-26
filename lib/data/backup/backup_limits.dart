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
///
/// 9 (0.2.2, item 2) adds the top-level `receiver_rules` section (each remembered person's level,
/// ceiling and category, by seed key or name) and its counts entry. It is a FILE schema only: the
/// database stays at version 8 (rules live in phone preferences), so this no longer mirrors
/// `kDbVersion`. A 0.2.1 or older app refuses a schema 9 file as made by a newer version (nothing is
/// written); a file of schema 8 or lower never carries the section and restores with no rules.
/// The rule row's `sc` key (chosen Suggest categories, 0.2.2 item 2 B-BK) was added WITHOUT a
/// schema bump: no released build ever wrote schema 9 (v0.2.1 writes 8; schema 9 first appears
/// after the v0.2.1 tag), so no schema 9 file without `sc` exists outside development builds.
/// 8 (0.2.1) adds one optional row key, `recorded_auto` (1 = recorded with no tap), written only
/// when 1. A 0.2.0 or older app refuses a schema 8 file as made by a newer version (nothing is
/// written); a file of schema 7 or lower restores with every flag 0. `format_version` stays 1.
/// 7 (0.2.1) adds the group code `CASH_USE` (a withdrawal's own category list, no seeds); a
/// file of schema 6 or lower never carries it and restores unchanged (the group stays empty).
/// 6 (0.2.1) adds two row keys, `parent_id` and `cash_only_decided`. A 0.2.1 backup
/// (schema 6) is refused by 0.2.0 as made by a newer version (its validator rejects
/// `schema_version` above 5); a 0.2.0 backup (schema 5) restores in 0.2.1 with every
/// entry unlinked (parent null, decided 0) and the same counts.
const int kBackupSchemaVersion = 9;

/// The lowest `schema_version` a file may carry (`seed_key` exists from v2).
const int kBackupMinSchemaVersion = 2;

/// First schema that may carry the two new group codes, the two new source
/// types, the five new seed keys and the `agent_number` row key (0.1.2).
const int kBackupFirstSchemaWithAgentAndAirtime = 3;

/// First schema that carries the `fuliza_events` section and its counts entry
/// (0.2.0). A schema 3 file with the section, or a schema 4 file without it,
/// is refused.
const int kBackupFirstSchemaWithFuliza = 4;

/// First schema whose transaction rows carry `parent_id` and `cash_only_decided`
/// (0.2.1, withdrawal with a linked Cash entry). An older file with either key is
/// refused (exact-key defence); a newer reader fills null / 0 for an older file.
const int kBackupFirstSchemaWithLinkedCash = 6;

/// First schema that may carry the group code `CASH_USE` (0.2.1, PM decision #33).
const int kBackupFirstSchemaWithCashGroup = 7;

/// First schema that carries the `receiver_rules` section and its counts entry (0.2.2). A schema 8
/// file WITH the section, or a schema 9 file WITHOUT it, is refused (exact-key defence).
const int kBackupFirstSchemaWithRules = 9;

/// Last top-level key of every file. Lets a reader (and the auto-backup
/// prune) see the file was written to the end.
const String kBackupEndMarker = 'mmogo-v1';

// --- size and row caps --------------------------------------------------------

/// 20 MB: the largest file the app will read (restore) or write (export).
const int kBackupMaxBytes = 20 * 1024 * 1024;

const int kBackupMaxTransactions = 50000;
const int kBackupMaxClassifications = 1000;
const int kBackupMaxMapRows = 20000;

/// Fuliza events: about 440 draws in three years, so this is ample.
const int kBackupMaxFulizaEvents = 20000;
const int kBackupMaxPrefsKeys = 32;

/// People with a rule: the same 300 as `kRuleCap` in the rule store (a test pins the two).
const int kBackupMaxRules = 300;

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

/// A Fuliza event code is an M-Pesa code (10 characters); 20 leaves room and
/// the text rules (no control characters, trimmed) still apply.
const int kBackupMaxFulizaCodeLength = 20;

/// Rule key (the normalised receiver key), as the rule codec: 1..200.
const int kBackupMaxRuleKeyLength = 200;

// --- value ranges ---------------------------------------------------------------

/// Epoch ms, [2007-01-01T00:00Z, 2100-01-01T00:00Z).
const int kBackupMinEpochMs = 1167609600000;
const int kBackupMaxEpochMs = 4102444800000;

const int kBackupMaxClassificationFileId = 2147483647;
const int kBackupMaxAmountCents = 10000000000; // KSh 100 million
const int kBackupMaxCostCents = 10000000;

/// A rule's ceiling in cents, 1..Ksh 1,000,000 (mirrors `kCeilingMinCents` / `kCeilingMaxCents`).
const int kBackupMinCeilingCents = 1;
const int kBackupMaxCeilingCents = 100000000;

/// Fuliza amounts, fees and printed totals share the transaction amount cap.
const int kBackupMaxFulizaCents = kBackupMaxAmountCents;

// --- enums ----------------------------------------------------------------------

/// Group codes of a schema 3..6 file (six).
const List<String> kBackupGroupCodes = [
  'SEND_MONEY',
  'PAYBILL',
  'BUY_GOODS',
  'POCHI_LA_BIASHARA',
  'AGENT_WITHDRAWAL',
  'AIRTIME',
];

/// Group codes of a schema >= 7 file (seven): the six plus `CASH_USE`.
const List<String> kBackupGroupCodesV7 = [
  ...kBackupGroupCodes,
  'CASH_USE',
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

/// Fuliza event kinds: the `FulizaEventKind` enum NAMES (a test pins them).
const List<String> kBackupFulizaKinds = ['draw', 'repayFull', 'repayPartial'];

/// Rule kinds in a file: the storage codes of `ReceiverType` (a test pins them). A rule row's
/// `lv` is 0 Suggested, 1 Ask first, 2 Auto-record.
const List<String> kBackupRuleTypes = ['SM', 'PB', 'BG', 'PO'];
const int kBackupMaxRuleLevel = 2;

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

/// The 17 built-in classification keys of a schema 3 or 4 file: the 12 above,
/// then the five 0.1.2 seeds. FROZEN literal: schema 5 added a key (below), and
/// a schema 3/4 file naming it is refused.
const List<String> kBackupSeedKeysV3V4 = [
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

/// The 18 built-in classification keys of a schema >= 5 file: the 17 above, then
/// `AIRTIME:for_another_number` LAST. A file may carry each at most once, on a row
/// of the matching group. A test pins this list to `AppSchema.seedClassifications`.
const List<String> kBackupSeedKeys = [
  ...kBackupSeedKeysV3V4,
  'AIRTIME:for_another_number',
];

/// The first backup schema that may name the 18th seed key.
const int kBackupFirstSchemaWithAirtimeKinds = 5;

/// C-A10: the two built-ins a restore never writes (Withdrawal and Airtime):
/// they stay active with their own names whatever a file says. Taken from
/// [kBackupSeedKeys] by group prefix so the strings are not typed twice; a test
/// pins the two values.
final Set<String> kBackupLockedSeedKeys = {
  for (final k in kBackupSeedKeys)
    if (k.startsWith('AGENT_WITHDRAWAL:') || k.startsWith('AIRTIME:')) k,
};

// --- exact key sets (const; the file's keys are never used as column names) -----

/// Top-level keys of a schema 9 file (what the exporter writes, in order): `receiver_rules` sits
/// between `fuliza_events` and `prefs`.
const List<String> kBackupTopLevelKeys = [
  'app',
  'format_version',
  'schema_version',
  'created_at',
  'counts',
  'classifications',
  'transactions',
  'counterparty_map',
  'fuliza_events',
  'receiver_rules',
  'prefs',
  'end',
];

/// Top-level keys of a schema 4..8 file (literal, frozen): no `receiver_rules`.
const List<String> kBackupTopLevelKeysV8 = [
  'app',
  'format_version',
  'schema_version',
  'created_at',
  'counts',
  'classifications',
  'transactions',
  'counterparty_map',
  'fuliza_events',
  'prefs',
  'end',
];

/// Top-level keys of a schema 2 or 3 file (literal, frozen): no `fuliza_events`.
const List<String> kBackupTopLevelKeysV3 = [
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

/// Counts keys of a schema 9 file.
const List<String> kBackupCountsKeys = [
  'classifications',
  'transactions',
  'counterparty_map',
  'fuliza_events',
  'receiver_rules',
];

/// Counts keys of a schema 4..8 file (literal, frozen).
const List<String> kBackupCountsKeysV8 = [
  'classifications',
  'transactions',
  'counterparty_map',
  'fuliza_events',
];

/// Counts keys of a schema 2 or 3 file (literal, frozen).
const List<String> kBackupCountsKeysV3 = [
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

/// The two OPTIONAL row keys of a schema >= 6 file (0.2.1): `parent_id` (the file-local
/// `id` of the withdrawal a Cash entry is linked to) and `cash_only_decided` (1 = the
/// user chose Cash only). The exporter writes a key ONLY when it is not the default
/// (null / 0), so a file without links is byte-for-byte as small as before (the 20 MB cap
/// still holds 50,000 ordinary rows); a reader fills the defaults. A file of schema 5 or
/// older that carries either key is refused. Rule for a bad link: `backup_links.dart`.
const List<String> kBackupTransactionLinkKeys = [
  'parent_id',
  'cash_only_decided',
];

/// First schema whose transaction rows may carry `recorded_auto` (0.2.1, auto-record marker).
const int kBackupFirstSchemaWithAutoMarker = 8;

/// The ONE optional row key of a schema >= 8 file: `recorded_auto`, int 0 or 1, written only
/// when 1 (so a file without auto-recorded rows keeps its size). 1 on a CASH or MANUAL row is
/// refused by the validator. A file of schema 7 or older that carries it is refused.
const String kBackupRecordedAutoKey = 'recorded_auto';

/// Row keys of a schema >= 3 file (13): `agent_number` is always present
/// (null allowed). The exporter writes these (plus the optional link keys above).
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

/// Row keys of a `fuliza_events` row (schema >= 4). `kind` is an enum name,
/// `occurred_at` epoch ms, money in integer cents.
const List<String> kBackupFulizaKeys = [
  'kind',
  'code',
  'occurred_at',
  'amount_cents',
  'fee_cents',
  'printed_total_cents',
];

/// Row keys of a `receiver_rules` row (schema >= 9), ALL present (null allowed where noted):
/// `t` kind code, `k` normalised key, `name` label, `lv` 0..2, `cat_seed` built-in category key OR
/// `cat_name` the person's own category name (never both; both null = no category), `ceil` cents or
/// null, `ap` 0/1 (restored from Auto-record, awaiting a review). Category DATABASE ids never travel:
/// a restore gives categories new ids, so the rule names its category and restore maps it back.
/// `sc` (0.2.2 item 2, B-BK): the person's chosen Suggest categories ("Categories I choose"), a
/// list of 0..[kBackupMaxChosenCategories] entries in the order chosen, each a map with exactly
/// one of `cat_seed` / `cat_name` (the same naming as the rule's own category). Always present
/// (the exporter writes `[]` when none and for every level above Suggested). Restore maps each
/// entry back to the phone's id, drops entries that are not ACTIVE categories after the restore,
/// clamps to [kBackupMaxChosenCategories] and keeps the list only at Suggested (`restore_rules.dart`).
/// A missing, null or unreadable `sc` (not a list, too many entries, or an entry that is not exactly
/// one valid `cat_seed` / `cat_name`) REFUSES the file (`backup_validator.dart`, field `sc`).
const List<String> kBackupRuleKeys = [
  't',
  'k',
  'name',
  'lv',
  'cat_seed',
  'cat_name',
  'ceil',
  'ap',
  'sc',
];

/// Most chosen Suggest categories a rule row's `sc` may carry: the same 2 as
/// `kMaxChosenCategories` in the rule model (a test pins the two; `lib/data` may not import it).
const int kBackupMaxChosenCategories = 2;

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
