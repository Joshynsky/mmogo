import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/home/recent_transaction.dart';
import '../../domain/money/spent_amount.dart';

/// One `source_type`'s totals within a period: the spent amount and the
/// M-Pesa transaction cost paid on top of it (`transaction_cost_cents`,
/// always NULL for CASH).
class SourceTypeTotal {
  const SourceTypeTotal({
    required this.totalCents,
    required this.costCents,
    this.withdrawnCents = 0,
    this.count = 0,
  });

  final int totalCents;
  final int costCents;

  /// Cash taken out at an agent in the period (S5): the amount of the
  /// withdrawals through the `withdrawnCents` rule, 0 for every other type.
  /// It is NOT spending and is never part of [totalCents].
  final int withdrawnCents;

  /// How many (not deleted) transactions of this type are in the period.
  final int count;
}

/// Minimal, ad hoc query layer against `AppDatabase`/`AppSchema` directly —
/// no repository/DAO abstraction existed before this slice (T1's own FLAGS
/// said building one was out of its scope). Raw SQL was chosen over
/// Dart-side aggregation (fetch-all-then-fold in memory) because every
/// query here is a straightforward `SUM`/`GROUP BY` sqlite already does
/// correctly and efficiently, and because the schema's own group-scope
/// triggers are already raw SQL against this same schema — staying in SQL
/// for read-side aggregation keeps one idiom instead of two. Flagged in
/// FLAGS as a precedent later slices (Parties/Analytics) may want to
/// follow, or to promote into a shared repository class once more than one
/// screen needs the same queries.
///
/// Every query here filters `deleted_at IS NULL`, by binding
/// rule: a soft-deleted transaction must be excluded from
/// every total/aggregate immediately, not just hidden from display.
class HomeDashboardDao {
  HomeDashboardDao._();

  static Future<int> sumAmountCents(
    Database db, {
    required int startMs,
    required int endMs,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM($kSpentCentsSql), 0) AS total
      FROM transactions
      WHERE deleted_at IS NULL
        AND transaction_occurred_at BETWEEN ? AND ?
      ''',
      [startMs, endMs],
    );
    return (rows.first['total'] as num).toInt();
  }

  /// Per-`source_type` totals (amount + transaction cost) within the given
  /// period. Only `source_type`s with at least one matching row appear in
  /// the returned map — callers should default missing keys to zero.
  static Future<Map<String, SourceTypeTotal>> sourceTypeTotals(
    Database db, {
    required int startMs,
    required int endMs,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT source_type,
             COALESCE(SUM($kSpentCentsSql), 0) AS total,
             COALESCE(SUM(transaction_cost_cents), 0) AS cost,
             COALESCE(SUM($kWithdrawnCentsSql), 0) AS withdrawn,
             COUNT(*) AS n
      FROM transactions
      WHERE deleted_at IS NULL
        AND transaction_occurred_at BETWEEN ? AND ?
      GROUP BY source_type
      ''',
      [startMs, endMs],
    );
    final result = <String, SourceTypeTotal>{};
    for (final row in rows) {
      result[row['source_type'] as String] = SourceTypeTotal(
        totalCents: (row['total'] as num).toInt(),
        costCents: (row['cost'] as num).toInt(),
        withdrawnCents: ((row['withdrawn'] ?? 0) as num).toInt(),
        count: ((row['n'] ?? 0) as num).toInt(),
      );
    }
    return result;
  }

  /// Most-recent-first, unfiltered by any period — Home's
  /// recent-transactions list is unfiltered by the period selector.
  static Future<List<RecentTransaction>> recentTransactions(
    Database db, {
    int limit = 5,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.id, t.display_code, t.source_type, t.amount_cents,
             t.counterparty_label, t.transaction_occurred_at,
             t.transaction_cost_cents, t.agent_number,
             c.name AS classification_name
      FROM transactions t
      JOIN classifications c ON c.id = t.classification_id
      WHERE t.deleted_at IS NULL
      ORDER BY t.transaction_occurred_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows
        .map(
          (row) => RecentTransaction(
            id: row['id'] as int,
            displayCode: row['display_code'] as String,
            sourceType: row['source_type'] as String,
            amountCents: (row['amount_cents'] as num).toInt(),
            counterpartyLabel: row['counterparty_label'] as String?,
            feeCents: ((row['transaction_cost_cents'] ?? 0) as num).toInt(),
            agentNumber: row['agent_number'] as String?,
            classificationName: row['classification_name'] as String,
            occurredAt: DateTime.fromMillisecondsSinceEpoch(
              row['transaction_occurred_at'] as int,
            ),
          ),
        )
        .toList();
  }
}
