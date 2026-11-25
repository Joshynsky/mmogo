import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One row of Recently Deleted's own list — soft-deleted transactions still
/// within the 1-hour restore grace window, most-recently-deleted first.
/// Mirrors `AnalyticsTransactionRow`'s `displayName` logic (Cash rows show
/// their classification, everything else prefers its counterparty label)
/// rather than importing that class directly — this row carries a smaller,
/// purpose-built field set (`deletedAt` in place of `occurredAt`/cost/etc.,
/// none of which the Recently Deleted UI renders) per this dispatch's own
/// "your call whether this lives in `transaction_dao.dart` or a new file"
/// instruction: one DAO file per screen's own real read needs, matching
/// `analytics_dao.dart`/`home_dashboard_dao.dart`'s
/// existing precedent.
class DeletedTransactionRow {
  const DeletedTransactionRow({
    required this.id,
    required this.displayCode,
    required this.sourceType,
    required this.amountCents,
    required this.counterpartyLabel,
    required this.classificationName,
    required this.deletedAt,
    this.parentTransactionId,
    this.recordedAutomatically = false,
    this.linkedCategoryNames = const [],
  });

  final int id;
  final String displayCode;
  final String sourceType; // 'SEND_MONEY' | 'BUY_GOODS' | 'PAYBILL' | 'CASH'
  final int amountCents;
  final String? counterpartyLabel;
  final String classificationName;
  final DateTime deletedAt;

  /// 0.2.1: the withdrawal this Cash entry was linked to, else null.
  final int? parentTransactionId;

  /// 0.2.1: true when the row had been written with no tap (stays 1 through Undo).
  final bool recordedAutomatically;

  /// 0.2.1: true for a Cash entry that came from a withdrawal.
  bool get fromWithdrawal => parentTransactionId != null;

  /// 0.2.1: on a withdrawal, the category names of the linked entries deleted with it
  /// (same `deleted_at`), oldest first, each once. Empty otherwise.
  final List<String> linkedCategoryNames;

  /// Same rule `AnalyticsTransactionRow.displayName`/`recent_transaction
  /// .dart` already establish: Cash rows show their classification (no
  /// counterparty exists for cash); every other row prefers its captured
  /// counterparty label, falling back to the classification name.
  String get displayName {
    if (sourceType == 'CASH') return 'Cash — $classificationName';
    return (counterpartyLabel != null && counterpartyLabel!.isNotEmpty)
        ? counterpartyLabel!
        : classificationName;
  }
}

List<String> _names(String? joined) =>
    joined == null || joined.isEmpty ? const [] : {...joined.split('\u001f')}.toList();

/// Recently Deleted's own query layer — same raw-SQL-against-`AppDatabase`
/// idiom every other screen-scoped DAO in this codebase already follows.
class RecentlyDeletedDao {
  RecentlyDeletedDao._();

  /// Soft-deleted (`deleted_at IS NOT NULL`) rows only, ordered by
  /// `deleted_at DESC` (most-recently-deleted first) — the
  /// explicit ordering for Recently Deleted Transactions.
  /// Deliberately joins `classifications` WITHOUT an `active` filter, same
  /// reasoning as `AnalyticsTransactionRow`'s query: a row referencing a
  /// since-soft-deleted classification still must render with that
  /// classification's name.
  static Future<List<DeletedTransactionRow>> deletedTransactions(Database db) async {
    final rows = await db.rawQuery('''
      SELECT t.id, t.display_code, t.source_type, t.amount_cents,
             t.counterparty_label, c.name AS classification_name, t.deleted_at,
             t.parent_transaction_id, t.recorded_automatically,
             (SELECT group_concat(lname, char(31)) FROM
                (SELECT lc.name AS lname FROM transactions ch
                 JOIN classifications lc ON lc.id = ch.classification_id
                 WHERE ch.parent_transaction_id = t.id AND ch.deleted_at = t.deleted_at
                 ORDER BY ch.id)) AS linked_names
      FROM transactions t
      JOIN classifications c ON c.id = t.classification_id
      WHERE t.deleted_at IS NOT NULL
      ORDER BY t.deleted_at DESC, t.id DESC
    ''');
    return rows
        .map(
          (row) => DeletedTransactionRow(
            id: row['id'] as int,
            displayCode: row['display_code'] as String,
            sourceType: row['source_type'] as String,
            amountCents: (row['amount_cents'] as num).toInt(),
            counterpartyLabel: row['counterparty_label'] as String?,
            classificationName: row['classification_name'] as String,
            deletedAt: DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int),
            parentTransactionId: row['parent_transaction_id'] as int?,
            recordedAutomatically: row['recorded_automatically'] == 1,
            linkedCategoryNames: _names(row['linked_names'] as String?),
          ),
        )
        .toList();
  }
}
