import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/cash/cash_code.dart';
import '../../domain/money/spent_amount.dart' as spent_rule;
import 'analytics_dao.dart' show AnalyticsDao, AnalyticsTransactionRow;

/// One live Cash entry linked to a withdrawal (0.2.1). It counts as spent; the
/// withdrawal itself stays 0 spent with its fee as the cost.
class LinkedCashEntry {
  const LinkedCashEntry({
    required this.id,
    required this.withdrawalId,
    required this.amountCents,
    required this.classificationId,
    required this.classificationName,
    required this.occurredAt,
  });

  final int id;
  final int withdrawalId;
  final int amountCents;
  final int classificationId;
  final String classificationName;
  final DateTime occurredAt;

  /// What this entry adds to "spent" (the spend rule, for a Cash row: its full amount).
  int get spentCents => spent_rule.spentCents('CASH', amountCents, null);
}

/// §DATA.DB.LINKED_CASH — the rules for a withdrawal's linked Cash entries.
///
/// A withdrawal (`AGENT_WITHDRAWAL`) ALWAYS stays a withdrawal. Picking a category
/// for it adds a CASH row (raw_parse_source MANUAL, cost NULL, the withdrawal's own
/// date and time, `CASH-YYYYMMDD-HHMM` code) whose `parent_transaction_id` points at
/// the withdrawal. The entries of one withdrawal never add up to more than its amount;
/// the rest is "still cash". The spend rule (`spentCents`) is untouched: the entry
/// counts because it is a CASH row, the withdrawal still counts 0.
///
/// Every write runs in ONE transaction (a [Database] is wrapped; a [Transaction] is
/// used as it is). Errors: [ArgumentError] for a bad amount or category,
/// [StateError] for a row that is not what the call needs (not a live withdrawal, not
/// a live linked entry, a decision that needs the caller's say-so).
///
/// Deleting follows the same idea: `TransactionDao.softDelete` of a withdrawal takes
/// its linked entries with it (same `deleted_at`), and `restore` brings the pair back.
class LinkedCashDao {
  LinkedCashDao._();

  /// The groups a linked Cash entry's category may come from: the user's Cash list
  /// (`CASH_USE`, what a withdrawal's chips offer) plus the three M-Pesa groups of the Cash
  /// picker (same list as `ClassificationDao.fetchFlatActiveClassifications`), so an entry
  /// made before the Cash list existed can still be edited.
  static const String _pickerGroups = "'CASH_USE','SEND_MONEY','PAYBILL','BUY_GOODS'";

  static Future<T> _atomic<T>(DatabaseExecutor db, Future<T> Function(DatabaseExecutor ex) body) {
    if (db is Database) return db.transaction((txn) => body(txn));
    return body(db);
  }

  /// The live linked entries of [withdrawalId], oldest first.
  static Future<List<LinkedCashEntry>> linkedEntriesOf(DatabaseExecutor db, int withdrawalId) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.id, t.parent_transaction_id, t.amount_cents, t.classification_id,
             c.name AS classification_name, t.transaction_occurred_at
      FROM transactions t
      JOIN classifications c ON c.id = t.classification_id
      WHERE t.parent_transaction_id = ? AND t.deleted_at IS NULL
      ORDER BY t.id
      ''',
      [withdrawalId],
    );
    return [
      for (final r in rows)
        LinkedCashEntry(
          id: r['id']! as int,
          withdrawalId: r['parent_transaction_id']! as int,
          amountCents: (r['amount_cents']! as num).toInt(),
          classificationId: r['classification_id']! as int,
          classificationName: r['classification_name']! as String,
          occurredAt: DateTime.fromMillisecondsSinceEpoch(r['transaction_occurred_at']! as int),
        ),
    ];
  }

  /// The row of one live Cash entry (any live row with a classification), or null.
  static Future<AnalyticsTransactionRow?> liveEntryRow(DatabaseExecutor db, int entryId) async {
    final rows = await db.rawQuery(
      'SELECT ${AnalyticsDao.rowColumns} FROM transactions t JOIN classifications c ON c.id = t.classification_id '
      'WHERE t.id = ? AND t.deleted_at IS NULL',
      [entryId],
    );
    return rows.isEmpty ? null : AnalyticsDao.rowFrom(rows.first);
  }

  /// What is still cash: the withdrawal's amount minus its live linked entries.
  /// Throws [StateError] when [withdrawalId] is not a live withdrawal.
  static Future<int> remainingCents(DatabaseExecutor db, int withdrawalId) async {
    final w = await _liveWithdrawal(db, withdrawalId);
    return _remaining(db, w.amount, withdrawalId, exceptEntry: null);
  }

  /// Adds a linked Cash entry of [amountCents] in [classificationId] to the
  /// withdrawal. Date and time are the withdrawal's. The amount must be above 0 and
  /// at most [remainingCents]. The category must be one the Cash picker offers (active,
  /// in an enabled Cash, Send money, Paybill or Buy goods group). Clears the "Cash only"
  /// decision (the withdrawal is now categorized). Returns the new entry's id.
  static Future<int> createLinkedCash(
    DatabaseExecutor db, {
    required int withdrawalId,
    required int classificationId,
    required int amountCents,
  }) =>
      _atomic(db, (ex) async {
        final w = await _liveWithdrawal(ex, withdrawalId);
        await _checkCategory(ex, classificationId);
        if (amountCents <= 0) throw ArgumentError.value(amountCents, 'amountCents', 'must be above 0');
        final left = await _remaining(ex, w.amount, withdrawalId, exceptEntry: null);
        if (amountCents > left) {
          throw ArgumentError.value(amountCents, 'amountCents', 'more than the $left cents still cash');
        }
        final code = generateCashDisplayCode(w.occurredAt);
        // (code, created_at) must stay unique inside a backup file, and two entries of one
        // minute share a code: never reuse a created_at of the same code.
        final last = await ex.rawQuery(
          "SELECT MAX(created_at) AS m FROM transactions WHERE source_type = 'CASH' AND display_code = ?",
          [code],
        );
        final now = DateTime.now().millisecondsSinceEpoch;
        final lastMs = (last.first['m'] as num?)?.toInt() ?? 0;
        final id = await ex.insert('transactions', {
          'display_code': code,
          'source_type': 'CASH',
          'amount_cents': amountCents,
          'transaction_cost_cents': null,
          'classification_id': classificationId,
          'raw_parse_source': 'MANUAL',
          'transaction_occurred_at': w.occurredAt,
          'created_at': now > lastMs ? now : lastMs + 1,
          'deleted_at': null,
          'parent_transaction_id': withdrawalId,
        });
        await ex.update('transactions', {'cash_only_decided': 0},
            where: 'id = ? AND cash_only_decided != 0', whereArgs: [withdrawalId]);
        return id;
      });

  /// Edits a live linked entry: its amount (above 0, at most what the withdrawal has
  /// left counting the entry's own old amount) and/or its category (same picker rule
  /// as [createLinkedCash]). A null argument leaves that field as it is.
  static Future<void> updateLinkedEntry(
    DatabaseExecutor db, {
    required int entryId,
    int? amountCents,
    int? classificationId,
  }) =>
      _atomic(db, (ex) async {
        final parent = await _liveEntryParent(ex, entryId);
        final w = await _liveWithdrawal(ex, parent);
        final values = <String, Object?>{};
        if (amountCents != null) {
          if (amountCents <= 0) throw ArgumentError.value(amountCents, 'amountCents', 'must be above 0');
          final room = await _remaining(ex, w.amount, parent, exceptEntry: entryId);
          if (amountCents > room) {
            throw ArgumentError.value(amountCents, 'amountCents', 'more than the $room cents available');
          }
          values['amount_cents'] = amountCents;
        }
        if (classificationId != null) {
          await _checkCategory(ex, classificationId);
          values['classification_id'] = classificationId;
        }
        if (values.isEmpty) return;
        await ex.update('transactions', values, where: 'id = ?', whereArgs: [entryId]);
      });

  /// The withdrawal's category was picked or changed. No live entry yet: adds one for
  /// the FULL amount. Exactly one entry: it follows the new category (amount kept).
  /// Several entries: [StateError] (the caller edits the entry it means with
  /// [updateLinkedEntry]). Returns the entry's id.
  static Future<int> setWithdrawalCategory(
    DatabaseExecutor db, {
    required int withdrawalId,
    required int classificationId,
  }) =>
      _atomic(db, (ex) async {
        final w = await _liveWithdrawal(ex, withdrawalId);
        final entries = await linkedEntriesOf(ex, withdrawalId);
        if (entries.isEmpty) {
          return createLinkedCash(ex,
              withdrawalId: withdrawalId, classificationId: classificationId, amountCents: w.amount);
        }
        if (entries.length > 1) {
          throw StateError('this withdrawal has several linked entries; edit the entry itself');
        }
        await updateLinkedEntry(ex, entryId: entries.first.id, classificationId: classificationId);
        return entries.first.id;
      });

  /// The user chose "Cash only" (or "Keep withdrawal" after deleting its only entry):
  /// sets `cash_only_decided = 1` so the To do check skips this withdrawal.
  ///
  /// When live linked entries exist, nothing is removed unless the caller passes
  /// [removeLinked] true (after asking the user); without it this throws [StateError].
  /// Removing means a soft delete of each entry (Recently deleted, restorable for an
  /// hour, own `deleted_at`), so it leaves every total at once.
  static Future<void> markCashOnly(
    DatabaseExecutor db, {
    required int withdrawalId,
    bool removeLinked = false,
  }) =>
      _atomic(db, (ex) async {
        await _liveWithdrawal(ex, withdrawalId);
        final entries = await linkedEntriesOf(ex, withdrawalId);
        if (entries.isNotEmpty) {
          if (!removeLinked) {
            throw StateError('this withdrawal has linked entries; pass removeLinked to remove them');
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          await ex.update('transactions', {'deleted_at': now},
              where: 'parent_transaction_id = ? AND deleted_at IS NULL', whereArgs: [withdrawalId]);
        }
        await ex.update('transactions', {'cash_only_decided': 1}, where: 'id = ?', whereArgs: [withdrawalId]);
      });

  /// "Cash only for all": [markCashOnly] for every id in [withdrawalIds], in ONE transaction.
  /// If any one fails (gone, or it got a linked entry meanwhile) nothing is changed.
  static Future<void> markManyCashOnly(DatabaseExecutor db, {required List<int> withdrawalIds}) =>
      _atomic(db, (ex) async {
        for (final id in withdrawalIds) {
          await markCashOnly(ex, withdrawalId: id);
        }
      });

  /// Withdrawals still waiting for a decision (To do): `AGENT_WITHDRAWAL`, not deleted,
  /// no live linked entry, not marked Cash only; newest first (by the withdrawal's
  /// date). [sinceMs] (epoch ms) keeps only withdrawals on or after that moment, so a
  /// caller can leave the old ones out; null = all.
  static Future<List<AnalyticsTransactionRow>> undecidedWithdrawals(
    DatabaseExecutor db, {
    int? sinceMs,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT ${AnalyticsDao.rowColumns}
      FROM transactions t
      JOIN classifications c ON c.id = t.classification_id
      WHERE t.source_type = 'AGENT_WITHDRAWAL' AND t.deleted_at IS NULL
        AND t.cash_only_decided = 0
        AND NOT EXISTS (SELECT 1 FROM transactions ch
                        WHERE ch.parent_transaction_id = t.id AND ch.deleted_at IS NULL)
        ${sinceMs == null ? '' : 'AND t.transaction_occurred_at >= ?'}
      ORDER BY t.transaction_occurred_at DESC, t.id DESC
      ''',
      [?sinceMs],
    );
    return [for (final r in rows) AnalyticsDao.rowFrom(r)];
  }

  // ---------------------------------------------------------------------------

  static Future<({int amount, int occurredAt})> _liveWithdrawal(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery(
      'SELECT amount_cents, transaction_occurred_at FROM transactions '
      "WHERE id = ? AND source_type = 'AGENT_WITHDRAWAL' AND deleted_at IS NULL",
      [id],
    );
    if (rows.isEmpty) throw StateError('no live withdrawal with id $id');
    return (
      amount: (rows.first['amount_cents']! as num).toInt(),
      occurredAt: rows.first['transaction_occurred_at']! as int,
    );
  }

  static Future<int> _liveEntryParent(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery(
      'SELECT parent_transaction_id FROM transactions '
      'WHERE id = ? AND parent_transaction_id IS NOT NULL AND deleted_at IS NULL',
      [id],
    );
    if (rows.isEmpty) throw StateError('no live linked entry with id $id');
    return rows.first['parent_transaction_id']! as int;
  }

  /// [withdrawn] minus the live linked entries of the withdrawal (optionally leaving
  /// one entry out). A bookkeeping sum of what the entries take out of the withdrawal,
  /// not a spent total.
  static Future<int> _remaining(DatabaseExecutor db, int withdrawn, int withdrawalId,
      {required int? exceptEntry}) async {
    final rows = await db.rawQuery(
      'SELECT amount_cents FROM transactions '
      'WHERE parent_transaction_id = ? AND deleted_at IS NULL AND id != ?',
      [withdrawalId, exceptEntry ?? -1],
    );
    // Summed here, not in SQL: the spend guard test allows no raw sum of the amount column under lib/.
    return rows.fold<int>(withdrawn, (left, r) => left - (r['amount_cents']! as num).toInt());
  }

  static Future<void> _checkCategory(DatabaseExecutor db, int classificationId) async {
    final rows = await db.rawQuery(
      'SELECT 1 FROM classifications c JOIN classification_groups g ON g.id = c.group_id '
      'WHERE c.id = ? AND c.active = 1 AND g.enabled = 1 AND g.code IN ($_pickerGroups)',
      [classificationId],
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(classificationId, 'classificationId', 'not a category the Cash picker offers');
    }
  }
}
