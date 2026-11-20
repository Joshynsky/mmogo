/// §DATA.DB.MIGRATION_V8_DDL — the FROZEN version-8 statements (0.2.1, auto-record marker).
///
/// ONE list, used by both `AppSchema.createSchema` (fresh install) and `migrateToV8`
/// (upgrade), so a fresh and a migrated file carry identical text. Additive only: one
/// column, one partial index, two triggers. No table is rebuilt, no row is touched
/// (every old row reads 0, including 0.2.0 auto-recorded airtime: NOT back-filled).
///
/// `recorded_automatically`: 1 = the row was written with no tap (the Auto-record level
/// only); a row the user confirmed with Yes or Parse stays 0. The rule "a flagged row is
/// not CASH and came from an SMS parse" reads other columns of the same row, and a column
/// added by ALTER cannot carry a table-level CHECK, so it is two triggers (insert, update).
/// The history filter `recorded_automatically = 1 AND deleted_at IS NULL` uses the partial
/// index. Undo is the existing soft delete; the flag stays 1.
library;

const String kRecordedAutoColumnName = 'recorded_automatically';

const String kV8AddRecordedColumn =
    'ALTER TABLE transactions ADD COLUMN recorded_automatically INTEGER NOT NULL DEFAULT 0 '
    'CHECK (recorded_automatically IN (0,1))';

/// Index, then triggers. `IF NOT EXISTS`, so a second run changes nothing.
const List<String> kV8IndexAndTriggers = [
  'CREATE INDEX IF NOT EXISTS idx_transactions_auto ON transactions(created_at) '
      'WHERE recorded_automatically = 1',
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_auto_ins
BEFORE INSERT ON transactions
FOR EACH ROW WHEN NEW.recorded_automatically = 1
BEGIN
  SELECT RAISE(ABORT, 'recorded_automatically needs a non-Cash row from an SMS parse')
  WHERE NEW.source_type = 'CASH' OR NEW.raw_parse_source IS NOT 'SMS_PARSE';
END''',
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_auto_upd
BEFORE UPDATE OF recorded_automatically, source_type, raw_parse_source ON transactions
FOR EACH ROW WHEN NEW.recorded_automatically = 1
BEGIN
  SELECT RAISE(ABORT, 'recorded_automatically needs a non-Cash row from an SMS parse')
  WHERE NEW.source_type = 'CASH' OR NEW.raw_parse_source IS NOT 'SMS_PARSE';
END''',
];

/// The whole v8 addition, in creation order (fresh install runs exactly this).
const List<String> kV8Statements = [
  kV8AddRecordedColumn,
  ...kV8IndexAndTriggers,
];
