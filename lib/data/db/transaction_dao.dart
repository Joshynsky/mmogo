import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T14 — Add confirmation step.
///
/// The exact set of already-resolved values needed to write one real row
/// into `transactions`, per the authoritative DDL
/// (`lib/data/db/schema.dart`'s `transactions` table).
/// Every field here maps 1:1 onto a NOT NULL / CHECK-constrained column —
/// this class does not invent an extra layer of validation on top of
/// SQLite's own CHECK constraints and group-scope guard triggers, which
/// remain the real enforcement mechanism (this dispatch's own instruction,
/// same discipline `classification_dao.dart` already established: surface
/// the real `DatabaseException`, don't pre-validate it away in Dart).
///
/// Deliberately holds a plain `String sourceType`/`rawParseSource`
/// (`'SEND_MONEY'|'BUY_GOODS'|'PAYBILL'|'CASH'` /
/// `'SMS_PARSE'|'MANUAL'`), matching `transactions.source_type`'s literal
/// DB values directly — same convention `recent_transaction.dart` (T4)
/// already uses, rather than introducing a new enum this dispatch has no
/// mandate to design (T5's `SmsSourceType` enum deliberately excludes
/// CASH, so it can't be reused here unmodified; T3/T6/T12 don't exist yet
/// to decide a shared vocabulary).
class NewTransactionInput {
  const NewTransactionInput({
    required this.displayCode,
    required this.sourceType,
    required this.amountCents,
    required this.transactionCostCents,
    required this.counterpartyLabel,
    required this.counterpartyPhone,
    required this.paybillAccountNumber,
    required this.classificationId,
    required this.rawParseSource,
    required this.transactionOccurredAt,
  });

  /// -> `transactions.display_code` (real M-Pesa code, or a
  /// `CASH-YYYYMMDD-HHMM` string — generation is the caller's job, T3/T6's
  /// scope, not this DAO's).
  final String displayCode;

  /// -> `transactions.source_type`. One of `'SEND_MONEY'`, `'BUY_GOODS'`,
  /// `'PAYBILL'`, `'CASH'`.
  final String sourceType;

  /// -> `transactions.amount_cents`. Must be > 0 (CHECK) — enforced by
  /// SQLite, not re-validated here.
  final int amountCents;

  /// -> `transactions.transaction_cost_cents`. Must be NULL iff
  /// [sourceType] is `'CASH'`, NOT NULL otherwise (CHECK) — enforced by
  /// SQLite.
  final int? transactionCostCents;

  /// -> `transactions.counterparty_label`. Required for BUY_GOODS; optional
  /// for SEND_MONEY/PAYBILL (opt-in identity capture) but then paired: for
  /// SEND_MONEY it is NULL iff [counterpartyPhone] is NULL, for PAYBILL iff
  /// [paybillAccountNumber] is NULL (paired CHECKs). Must be NULL for CASH.
  final String? counterpartyLabel;

  /// -> `transactions.counterparty_phone`. SEND_MONEY only (NULL otherwise);
  /// optional, but paired with [counterpartyLabel] (both set or both NULL).
  final String? counterpartyPhone;

  /// -> `transactions.paybill_account_number`. PAYBILL only (NULL
  /// otherwise); optional, but paired with [counterpartyLabel] (both set or
  /// both NULL).
  final String? paybillAccountNumber;

  /// -> `transactions.classification_id`. Already-chosen (auto-applied,
  /// pill-accepted, or manually picked) per this dispatch's brief — this
  /// DAO does not resolve a classification itself. Must belong to the
  /// group matching [sourceType] (non-cash) or any *enabled* group (cash)
  /// — enforced by `trg_transactions_classification_scope_ins`, not
  /// re-checked here.
  final int classificationId;

  /// -> `transactions.raw_parse_source`. One of `'SMS_PARSE'`, `'MANUAL'`.
  /// Must be `'MANUAL'` when [sourceType] is `'CASH'` (CHECK).
  final String rawParseSource;

  /// -> `transactions.transaction_occurred_at`. Epoch millis, matching
  /// every other epoch column's convention in `schema.dart`.
  final int transactionOccurredAt;
}

/// Minimal, ad hoc query layer against `AppDatabase`/`AppSchema` directly —
/// same idiom `classification_dao.dart`/`home_dashboard_dao.dart` already
/// established: raw `db.insert` calls, no repository/DAO base class, no
/// ORM. This is the first DAO to ever write a row into `transactions`
/// (T1-T13 only ever read it).
class TransactionDao {
  TransactionDao._();

  /// Inserts one real row into `transactions`. `created_at` is stamped
  /// here (now, epoch millis) — it is not part of [NewTransactionInput]
  /// since it is never a caller-supplied/user-visible value, same
  /// treatment `classification_dao.dart`'s `createClassification` gives
  /// its own `created_at`. `deleted_at` is always written as `NULL` — a
  /// freshly-confirmed transaction is never born soft-deleted.
  ///
  /// Deliberately does NOT catch/wrap the real `DatabaseException` the
  /// group-scope guard triggers (or any CHECK constraint) may throw — the
  /// caller (the confirmation UI) surfaces that real exception directly,
  /// same discipline as every other DAO in this codebase.
  /// D5 (T6 return-pass-2, 2026-09-19 PM decision) — whether a non-deleted,
  /// non-Cash row already carries this exact [code]. Backs the Add — M-Pesa
  /// form's inline "This code is already recorded" message, for both a
  /// typed code and a parsed one (the code field shows the error
  /// either way). This
  /// is a friendly pre-check only, not the real enforcement mechanism —
  /// `idx_transactions_mpesa_code` (`schema.dart`) is; [insert] deliberately
  /// does not catch/swallow that index's violation either, so a race
  /// between this check and the actual save still surfaces as [insert]'s
  /// real `DatabaseException`, same discipline as every other constraint in
  /// this codebase.
  static Future<bool> mpesaCodeExists(Database db, {required String code}) async {
    final rows = await db.query(
      'transactions',
      columns: ['id'],
      where: "display_code = ? AND source_type != 'CASH' AND deleted_at IS NULL",
      whereArgs: [code],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<int> insert(Database db, NewTransactionInput input) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('transactions', {
      'display_code': input.displayCode,
      'source_type': input.sourceType,
      'amount_cents': input.amountCents,
      'transaction_cost_cents': input.transactionCostCents,
      'counterparty_label': input.counterpartyLabel,
      'counterparty_phone': input.counterpartyPhone,
      'paybill_account_number': input.paybillAccountNumber,
      'classification_id': input.classificationId,
      'raw_parse_source': input.rawParseSource,
      'transaction_occurred_at': input.transactionOccurredAt,
      'created_at': now,
      'deleted_at': null,
    });
  }

  /// T13 — Analytics' edit-form save. Updates an existing row's Amount,
  /// occurred-at and classification for EVERY `source_type`, plus (non-Cash
  /// only) `counterparty_label` + the type-specific phone/account +
  /// `transaction_cost_cents` — exactly the field set
  /// the earlier prototype's edit-save wrote, no
  /// more. `display_code`, `source_type` and `raw_parse_source` are never
  /// touched here (not editable).
  ///
  /// Looks up the target row's own `source_type` first (a plain read-then-
  /// write, same "cheap pre-read, the real constraint stays the backstop"
  /// idiom [mpesaCodeExists] already uses in this file) purely to decide
  /// WHICH of the optional non-Cash columns belong in the `SET` clause —
  /// never to pre-validate the edit's own correctness. A Cash row's
  /// `counterparty_label`/`counterparty_phone`/`paybill_account_number`/
  /// `transaction_cost_cents` are therefore never written by this method at
  /// all (left exactly as they already are — always NULL for Cash) rather
  /// than being explicitly re-set to NULL: there is no edit-form field for
  /// them on a Cash row, so this method never touches a column it has no
  /// caller-supplied value for.
  ///
  /// Deliberately does NOT catch/wrap any real `DatabaseException` a CHECK
  /// constraint (e.g. the paired-optionality CHECKs, if the caller passes
  /// a non-null [counterpartyLabel] alongside a null [counterpartyPhone]/
  /// [paybillAccountNumber] for a SEND_MONEY/PAYBILL row) or the
  /// group-scope guard trigger (`trg_transactions_classification_scope_upd`
  /// — a re-pick into a classification belonging to a mismatched group) may
  /// throw — same undisguised-surfacing discipline as every other DAO in
  /// this codebase.
  static Future<void> update(
    Database db, {
    required int id,
    required int amountCents,
    required int transactionOccurredAt,
    required int classificationId,
    String? counterpartyLabel,
    String? counterpartyPhone,
    String? paybillAccountNumber,
    int? transactionCostCents,
  }) async {
    final rows = await db.query(
      'transactions',
      columns: ['source_type'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('TransactionDao.update: no transaction with id $id');
    }
    final sourceType = rows.first['source_type'] as String;

    final values = <String, Object?>{
      'amount_cents': amountCents,
      'transaction_occurred_at': transactionOccurredAt,
      'classification_id': classificationId,
    };

    if (sourceType != 'CASH') {
      values['counterparty_label'] = counterpartyLabel;
      values['transaction_cost_cents'] = transactionCostCents;
      if (sourceType == 'SEND_MONEY') {
        values['counterparty_phone'] = counterpartyPhone;
      } else if (sourceType == 'PAYBILL') {
        values['paybill_account_number'] = paybillAccountNumber;
      }
      // BUY_GOODS: neither counterparty_phone nor paybill_account_number is
      // touched — both are already NULL for BUY_GOODS and stay that way,
      // matching the prototype's edit form (no phone/account field renders
      // for Buy Goods either).
    }

    await db.update('transactions', values, where: 'id = ?', whereArgs: [id]);
  }

  /// T13 — Delete swipe/edge-button action. `SET deleted_at = <now>` — a
  /// soft-delete, not a hard delete (with a 1-hour restore grace
  /// window). Every existing read in this codebase already filters
  /// `deleted_at IS NULL`, so the row disappears from every total/list the
  /// instant this commits — no other query needs to change.
  static Future<void> softDelete(Database db, {required int id}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'transactions',
      {'deleted_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// T13 — Recently Deleted's Restore action. `SET deleted_at = NULL` —
  /// returns the row to normal Analytics/Home visibility, as
  /// long as it is still within the restore window.
  static Future<void> restore(Database db, {required int id}) async {
    await db.update(
      'transactions',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// T13 — the app-launch purge sweep. A real hard `DELETE`, not another
  /// soft-delete layer — once the 1-hour grace window passes, the row is
  /// genuinely gone
  /// (`WHERE deleted_at IS NOT NULL AND deleted_at < now - 1h`).
  /// Returns the number of rows purged — not consumed by any UI behavior
  /// (the sweep is silent per spec), but useful for a test assertion.
  static Future<int> purgeExpiredSoftDeletes(Database db) async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - 3600000;
    return db.delete(
      'transactions',
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    );
  }
}
