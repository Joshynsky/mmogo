import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pure schema/seed logic, factored out of [AppDatabase] so it can be
/// exercised directly against an in-memory database in unit tests without
/// needing `path_provider`'s platform channel (unavailable outside a real
/// app run). This is the single source of truth for the DDL described in
/// the app's data model (current schema only) — `AppDatabase` and the test suite both call into this file
/// rather than each keeping their own copy of the schema.
class AppSchema {
  AppSchema._();

  static Future<void> createSchema(Database db) async {
    // --- classification_groups ---------------------------------------
    await db.execute('''
      CREATE TABLE classification_groups (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        code          TEXT NOT NULL UNIQUE
                      CHECK (code IN ('SEND_MONEY','PAYBILL','BUY_GOODS','POCHI_LA_BIASHARA')),
        display_name  TEXT NOT NULL,
        enabled       INTEGER NOT NULL DEFAULT 1,
        created_at    INTEGER NOT NULL
      )
    ''');

    // --- classifications ------------------------------------------------
    await db.execute('''
      CREATE TABLE classifications (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id      INTEGER NOT NULL REFERENCES classification_groups(id) ON DELETE RESTRICT,
        name          TEXT NOT NULL,
        active        INTEGER NOT NULL DEFAULT 1,
        created_at    INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_classifications_active_name
        ON classifications(group_id, name) WHERE active = 1
    ''');
    await db.execute('''
      CREATE INDEX idx_classifications_group ON classifications(group_id)
    ''');

    // --- transactions (revised DDL — current authoritative) -------------
    await db.execute('''
      CREATE TABLE transactions (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        display_code            TEXT NOT NULL,
        source_type             TEXT NOT NULL
                                 CHECK (source_type IN ('SEND_MONEY','BUY_GOODS','PAYBILL','CASH')),
        amount_cents            INTEGER NOT NULL CHECK (amount_cents > 0),
        transaction_cost_cents  INTEGER NULL,
        counterparty_label      TEXT NULL,
        counterparty_phone      TEXT NULL,
        paybill_account_number  TEXT NULL,
        classification_id       INTEGER NOT NULL REFERENCES classifications(id) ON DELETE RESTRICT,
        raw_parse_source        TEXT NOT NULL CHECK (raw_parse_source IN ('SMS_PARSE','MANUAL')),
        transaction_occurred_at INTEGER NOT NULL,
        created_at              INTEGER NOT NULL,
        deleted_at               INTEGER NULL,
        CHECK ( (source_type = 'CASH' AND transaction_cost_cents IS NULL)
             OR (source_type != 'CASH' AND transaction_cost_cents IS NOT NULL) ),
        -- T6 schema amendment (2026-09-19, PM decision, cited directly per
        -- this dispatch's own instruction — same citable-decision
        -- discipline as classification_dao.dart's dedup-rule comment):
        -- Add's M-Pesa tab gets a real manual-entry path back (PM direct
        -- decision, 2026-09-17), which requires
        -- Send Money/Paybill identity capture to be genuinely opt-in — an
        -- unchecked "also record receiver/business identity" checkbox
        -- must leave counterparty_label/counterparty_phone/
        -- paybill_account_number truly NULL. The three CHECKs below
        -- originally in this file (T1) made counterparty_label/
        -- counterparty_phone/paybill_account_number mandatory for ALL of
        -- SEND_MONEY/BUY_GOODS/PAYBILL, directly contradicting that later
        -- decision (T1 predates it and was never updated). Loosened here:
        -- counterparty_label stays mandatory ONLY for BUY_GOODS (no
        -- toggle exists for it — merchant identity is the entire point of
        -- a Buy Goods entry, hence the Buy Goods exemption);
        -- counterparty_phone (SEND_MONEY) and
        -- paybill_account_number (PAYBILL) become genuinely optional —
        -- their "must be NOT NULL" CHECKs are dropped entirely below.
        -- T6 return-pass-2 amendment (2026-09-19 PM decision, "M-Pesa entry
        -- rules settled by the PM during the T6 guided device check", D3):
        -- Buy Goods gets the same opt-in capture checkbox as Send Money/
        -- Paybill now (superseding the 2026-09-17 "always captures the
        -- merchant" rule) — counterparty_label is no longer mandatory for
        -- BUY_GOODS either. The line below (`CHECK (source_type !=
        -- 'BUY_GOODS' OR counterparty_label IS NOT NULL)`) is DELETED per
        -- that decision; every source_type's identity field(s) are now
        -- uniformly optional.
        CHECK ( source_type IN ('SEND_MONEY','BUY_GOODS','PAYBILL') OR counterparty_label IS NULL ),
        CHECK ( source_type = 'SEND_MONEY' OR counterparty_phone IS NULL ),
        CHECK ( source_type = 'PAYBILL' OR paybill_account_number IS NULL ),
        -- Paired-optionality safety net (T6, disclosed judgment call, not
        -- explicit spec text): the Add — M-Pesa tab's single opt-in
        -- checkbox controls both fields of each pair together, so a state
        -- where one half is captured and the other silently isn't would
        -- always be a bug, never a legitimate partial entry.
        CHECK ( source_type != 'SEND_MONEY' OR (counterparty_label IS NULL) = (counterparty_phone IS NULL) ),
        CHECK ( source_type != 'PAYBILL' OR (counterparty_label IS NULL) = (paybill_account_number IS NULL) ),
        CHECK ( source_type != 'CASH' OR raw_parse_source = 'MANUAL' )
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_transactions_classification ON transactions(classification_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_transactions_occurred ON transactions(transaction_occurred_at)
    ''');
    await db.execute('''
      CREATE INDEX idx_transactions_source ON transactions(source_type)
    ''');
    await db.execute('''
      CREATE INDEX idx_transactions_deleted_at ON transactions(deleted_at)
    ''');
    // D5 (2026-09-19 PM decision, T6 return-pass-2): an M-Pesa code must not
    // exist twice. display_code stays non-unique in general on purpose
    // (Cash codes, CASH-YYYYMMDD-HHMM, can legitimately collide within the
    // same minute — hence the id/display_code split) so the
    // uniqueness is scoped to non-Cash, non-soft-deleted rows only. A
    // soft-deleted row frees its code for reuse (the WHERE clause excludes
    // it). Enforced by SQLite, not re-validated in Dart — the form/DAO
    // still perform an inline "already recorded" pre-check
    // (TransactionDao.mpesaCodeExists) for a fast, friendly message, but
    // this index is the real backstop, same discipline as every other
    // constraint in this file.
    await db.execute('''
      CREATE UNIQUE INDEX idx_transactions_mpesa_code
        ON transactions(display_code) WHERE source_type != 'CASH' AND deleted_at IS NULL
    ''');

    // --- group-scope guard triggers (INSERT / UPDATE) --------------------
    await db.execute('''
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
      END
    ''');
    await db.execute('''
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
      END
    ''');

    // --- counterparty_classification_map (empty at seed) -----------------
    await db.execute('''
      CREATE TABLE counterparty_classification_map (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        source_type       TEXT NOT NULL CHECK (source_type IN ('SEND_MONEY','BUY_GOODS','PAYBILL')),
        counterparty_key  TEXT NOT NULL,
        classification_id INTEGER NOT NULL REFERENCES classifications(id) ON DELETE CASCADE,
        auto_apply        INTEGER NOT NULL DEFAULT 0,
        updated_at        INTEGER NOT NULL,
        UNIQUE (source_type, counterparty_key)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_counterparty_map_classification
        ON counterparty_classification_map(classification_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_counterparty_map_recency
        ON counterparty_classification_map(updated_at DESC)
    ''');
  }

  static Future<void> seed(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // classification_groups — 4 seed rows, POCHI_LA_BIASHARA disabled.
    final groupIds = <String, int>{};
    for (final row in const [
      ('SEND_MONEY', 'Send Money', 1),
      ('PAYBILL', 'Paybill', 1),
      ('BUY_GOODS', 'Buy Goods', 1),
      ('POCHI_LA_BIASHARA', 'Pochi La Biashara', 0),
    ]) {
      final id = await db.insert('classification_groups', {
        'code': row.$1,
        'display_name': row.$2,
        'enabled': row.$3,
        'created_at': now,
      });
      groupIds[row.$1] = id;
    }

    // classifications — 12 seed rows, group-scoped.
    const seedClassifications = [
      ('SEND_MONEY', 'Family/Friends'),
      ('SEND_MONEY', 'Rent'),
      ('SEND_MONEY', 'Transport'),
      ('SEND_MONEY', 'Groceries'),
      ('PAYBILL', 'Rent Payment'),
      ('PAYBILL', 'Shopping'),
      ('PAYBILL', 'Transport'),
      ('PAYBILL', 'Groceries'),
      ('BUY_GOODS', 'Rent Payment'),
      ('BUY_GOODS', 'Shopping'),
      ('BUY_GOODS', 'Transport'),
      ('BUY_GOODS', 'Groceries'),
    ];
    for (final row in seedClassifications) {
      await db.insert('classifications', {
        'group_id': groupIds[row.$1],
        'name': row.$2,
        'active': 1,
        'created_at': now,
      });
    }

    // counterparty_classification_map — intentionally empty at seed.
  }
}
