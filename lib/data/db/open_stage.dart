/// §DATA.DB.OPEN_STAGE — how far a database open got (0.1.2 S10c, E0).
///
/// `AppDatabase` sets it around `onUpgrade`; the open-failure classifier reads
/// it after a failed open. `inUpgrade` when the open threw = E0.
enum OpenStage { none, inUpgrade, afterUpgrade }
