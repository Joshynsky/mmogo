/// §DATA.DB.MIGRATION_V6_DDL — the FROZEN version-6 statements (0.2.1, withdrawal
/// with a linked Cash entry).
///
/// ONE list, used by both `AppSchema.createSchema` (fresh install) and the `_toV6`
/// step (upgrade), so a fresh and a migrated file carry identical text. Additive
/// only: two columns on `transactions`, one index, seven triggers. No table is
/// rebuilt, no existing row is touched (old rows read NULL / 0).
///
/// `parent_transaction_id`: a general parent/child link (today only a linked Cash
/// entry -> its Agent withdrawal; category linking may reuse it later). `ON DELETE
/// SET NULL`: a hard delete of the parent (the 1-hour purge, Replace) leaves the
/// child as plain Cash instead of failing. The column is added with a NULL default,
/// which SQLite allows together with REFERENCES.
///
/// `cash_only_decided`: 1 = the user chose "Cash only" for this withdrawal, so the
/// To do check skips it. Meaningful on a withdrawal row only.
///
/// The two rules are triggers (not CHECKs) because they read another row (the
/// parent's type) and a column added by ALTER cannot carry a table-level CHECK.
///
/// Three more triggers make a withdrawal and its entries ONE pair for the soft delete (the DAO
/// stays a single UPDATE of the row asked for, so every caller and test double keeps working):
///  - `trg_transactions_delete_pair`: deleting a withdrawal gives its live entries the SAME
///    `deleted_at` in the same statement;
///  - `trg_transactions_restore_entry_guard`: restoring an entry is ignored (0 rows changed,
///    no error) when its withdrawal was deleted on its own, or when the entry no longer fits in
///    what the withdrawal has left (the other live entries plus this one above its amount);
///  - `trg_transactions_restore_pair`: restoring either member brings back the partners deleted
///    with it (same `deleted_at`), so the pair returns together.
/// The fit check adds amounts with TOTAL(): it is a bookkeeping check on a withdrawal's
/// entries, not a spent total (the spend rule stays `spentCents`).
library;

const String kParentColumnName = 'parent_transaction_id';
const String kCashOnlyDecidedColumnName = 'cash_only_decided';

const String kV6AddParentColumn =
    'ALTER TABLE transactions ADD COLUMN parent_transaction_id INTEGER NULL '
    'REFERENCES transactions(id) ON DELETE SET NULL';

const String kV6AddDecidedColumn =
    'ALTER TABLE transactions ADD COLUMN cash_only_decided INTEGER NOT NULL DEFAULT 0 '
    'CHECK (cash_only_decided IN (0,1))';

/// Index, then triggers. `IF NOT EXISTS`, so a second run changes nothing.
const List<String> kV6IndexAndTriggers = [
  'CREATE INDEX IF NOT EXISTS idx_transactions_parent ON transactions(parent_transaction_id) '
      'WHERE parent_transaction_id IS NOT NULL',
  // A parent link only on a CASH row, and only to an AGENT_WITHDRAWAL row.
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_parent_link_ins
BEFORE INSERT ON transactions
FOR EACH ROW WHEN NEW.parent_transaction_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'a parent link needs a Cash row pointing at a withdrawal')
  WHERE NEW.source_type != 'CASH'
     OR (SELECT source_type FROM transactions WHERE id = NEW.parent_transaction_id)
        IS NOT 'AGENT_WITHDRAWAL';
END''',
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_parent_link_upd
BEFORE UPDATE OF parent_transaction_id, source_type ON transactions
FOR EACH ROW WHEN NEW.parent_transaction_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'a parent link needs a Cash row pointing at a withdrawal')
  WHERE NEW.source_type != 'CASH'
     OR (SELECT source_type FROM transactions WHERE id = NEW.parent_transaction_id)
        IS NOT 'AGENT_WITHDRAWAL';
END''',
  // The pair rules for the soft delete (see the library comment).
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_delete_pair
AFTER UPDATE OF deleted_at ON transactions
FOR EACH ROW WHEN OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL
  AND NEW.source_type = 'AGENT_WITHDRAWAL'
BEGIN
  UPDATE transactions SET deleted_at = NEW.deleted_at
  WHERE parent_transaction_id = NEW.id AND deleted_at IS NULL;
END''',
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_restore_entry_guard
BEFORE UPDATE OF deleted_at ON transactions
FOR EACH ROW WHEN OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL
  AND NEW.parent_transaction_id IS NOT NULL
BEGIN
  SELECT RAISE(IGNORE) WHERE
    EXISTS (SELECT 1 FROM transactions p WHERE p.id = NEW.parent_transaction_id
            AND p.deleted_at IS NOT NULL AND p.deleted_at != OLD.deleted_at)
    OR EXISTS (SELECT 1 FROM transactions p WHERE p.id = NEW.parent_transaction_id
            AND p.deleted_at IS NULL
            AND NEW.amount_cents + (SELECT TOTAL(c.amount_cents) FROM transactions c
                  WHERE c.parent_transaction_id = p.id AND c.deleted_at IS NULL AND c.id != NEW.id)
                > p.amount_cents);
END''',
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_restore_pair
AFTER UPDATE OF deleted_at ON transactions
FOR EACH ROW WHEN OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL
BEGIN
  UPDATE transactions SET deleted_at = NULL
  WHERE parent_transaction_id = NEW.id AND deleted_at = OLD.deleted_at;
  UPDATE transactions SET deleted_at = NULL
  WHERE id = NEW.parent_transaction_id AND deleted_at = OLD.deleted_at;
  UPDATE transactions SET deleted_at = NULL
  WHERE parent_transaction_id = NEW.parent_transaction_id AND deleted_at = OLD.deleted_at;
END''',
  // The decided flag only on a withdrawal.
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_decided_ins
BEFORE INSERT ON transactions
FOR EACH ROW WHEN NEW.cash_only_decided != 0 AND NEW.source_type != 'AGENT_WITHDRAWAL'
BEGIN
  SELECT RAISE(ABORT, 'cash_only_decided is only for a withdrawal row');
END''',
  '''CREATE TRIGGER IF NOT EXISTS trg_transactions_decided_upd
BEFORE UPDATE OF cash_only_decided, source_type ON transactions
FOR EACH ROW WHEN NEW.cash_only_decided != 0 AND NEW.source_type != 'AGENT_WITHDRAWAL'
BEGIN
  SELECT RAISE(ABORT, 'cash_only_decided is only for a withdrawal row');
END''',
];

/// The whole v6 addition, in creation order (fresh install runs exactly this).
const List<String> kV6Statements = [
  kV6AddParentColumn,
  kV6AddDecidedColumn,
  ...kV6IndexAndTriggers,
];
