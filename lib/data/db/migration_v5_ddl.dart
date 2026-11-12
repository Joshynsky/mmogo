/// §DATA.DB.MIGRATION_V5_DDL — the FROZEN version-5 trigger text (WBS row 17).
///
/// ONE constant, used by both `AppSchema.createSchema` (fresh install) and the
/// `_toV5` step (upgrade), so a fresh and a migrated file carry identical text.
/// It blocks moving an Airtime entry between its two categories (the kind of an
/// entry is its category). Inserts are not affected; only an update that
/// changes `classification_id` of an AIRTIME row.
library;

const String kAirtimeKindTriggerName = 'trg_airtime_kind_locked';

const String kAirtimeKindTriggerDdl =
    'CREATE TRIGGER IF NOT EXISTS trg_airtime_kind_locked '
    'BEFORE UPDATE OF classification_id ON transactions '
    "WHEN NEW.source_type='AIRTIME' AND OLD.classification_id IS NOT NEW.classification_id "
    "BEGIN SELECT RAISE(ABORT,'airtime kind is locked'); END";
