/// §DATA.MAINTENANCE.KEYS — device-only preference keys used by "Delete data"
/// (0.1.2 S9b-1). All of them live in the STANDARD build (no autoread flag
/// needed to compile them) and NONE of them is in the backup allowlist
/// (`kBackupSettingSpecs` stays at eleven keys): a restore file cannot carry
/// or set any of them.
library;

/// The queue of entries waiting for the user (written by the autoread build
/// only). Level 1 removes it by this exact string.
const String kPendingEntriesKey = 'pending_entries_v1';

/// The "a reset is under way" flag (epoch ms). Written first, removed LAST.
/// Standard start-up cleanup must never remove it.
const String kResetPendingKey = 'reset_pending_v1';

/// The report of the phone-number merge (S3b/CA4), device only.
const String kPhoneMergeReportKey = 'phone_merge_report_v1';

/// Every key of the same family as [kPendingEntriesKey]. Pinned by a test:
/// no prefix removal and no guessed names; a new queue key is added here by
/// name when the autoread feature defines it (AR1/AR4A).
const List<String> queueKeys = [kPendingEntriesKey];

/// Prefix of one stored auto-read waiting item (one pref per item, the prefix
/// plus a 32-hex id). The same string as `kPendingItemPrefix` in
/// `lib/autoread/data/pending_items_store.dart`, repeated here because the
/// standard build drops `lib/autoread/`; a test pins the two together. These are
/// the only keys removed by prefix, and only this prefix.
const String kPendingItemKeyPrefix = 'autoread_pending_v1.';

/// The auto-read generation counter (see `kPendingGenerationKey`). Delete data
/// BUMPS it (never removes it) so a parse that started earlier cannot write
/// afterwards. It holds no user data.
const String kPendingGenerationPrefsKey = 'autoread_generation_v1';

/// Every prefix whose keys the queue step removes.
const List<String> queueKeyPrefixes = [kPendingItemKeyPrefix];

/// The only pref that exists on a device that was never used or was just
/// reset (Welcome re-marks it). Used by `nothingLeftAtLevel2`.
const String kBaselinePrefKey = 'whatsnew_seen_version';
