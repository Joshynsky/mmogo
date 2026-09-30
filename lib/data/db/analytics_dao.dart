import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/counterparty/counterparty_key.dart';
import '../../domain/parsing/parsed_sms_fields.dart';

/// One itemized row for Analytics' dated transaction list — the minimal
/// projection of `transactions` (joined to `classifications` for the
/// display name) this screen needs to render a row, matching
/// the earlier prototype's row fields.
///
/// Deliberately joins `classifications` WITHOUT filtering on
/// `classifications.active` — Analytics'
/// `GROUP BY` query is NOT filtered on `active`: a soft-deleted
/// classification's past transactions remain fully counted in every
/// historical total. A transaction referencing a since-soft-deleted
/// classification must still render (with that classification's name) here,
/// same as any other row.
class AnalyticsTransactionRow {
  const AnalyticsTransactionRow({
    required this.id,
    required this.displayCode,
    required this.sourceType,
    required this.amountCents,
    required this.counterpartyLabel,
    required this.counterpartyPhone,
    required this.paybillAccountNumber,
    required this.classificationId,
    required this.classificationName,
    required this.occurredAt,
    required this.transactionCostCents,
  });

  final int id;
  final String displayCode;
  final String sourceType; // 'SEND_MONEY' | 'BUY_GOODS' | 'PAYBILL' | 'CASH'
  final int amountCents;
  final String? counterpartyLabel;
  final String? counterpartyPhone;
  final String? paybillAccountNumber;
  final int classificationId;
  final String classificationName;
  final DateTime occurredAt;

  /// -> `transactions.transaction_cost_cents`. Always `null` for CASH rows
  /// (schema CHECK); NOT NULL for every other `source_type`. T13 — added
  /// so Analytics' edit form (this row's own re-render target) can
  /// pre-fill the Transaction cost field without a second query; nothing
  /// prior to T13 needed this column on this class.
  final int? transactionCostCents;

  /// Row title: Cash rows show their classification (no counterparty exists
  /// for cash); every other row prefers its captured counterparty label,
  /// falling back to the classification name in the schema-disallowed edge
  /// case where a label is somehow missing — same rule
  /// `recent_transaction.dart` (T4) already established for Home's list.
  String get displayName {
    if (sourceType == 'CASH') return 'Cash — $classificationName';
    return (counterpartyLabel != null && counterpartyLabel!.isNotEmpty)
        ? counterpartyLabel!
        : classificationName;
  }
}

/// Analytics' query layer — follows the same raw-SQL-against-`AppDatabase`
/// idiom `home_dashboard_dao.dart` (T4) and `classification_dao.dart` (T3)
/// already established for this project (no repository/ORM abstraction).
///
/// Every query here:
///   - filters `deleted_at IS NULL` on `transactions` (a soft-deleted row is
///     excluded from every total/aggregate immediately, not just hidden).
///   - joins `classifications` WITHOUT an `active` filter (see
///     [AnalyticsTransactionRow]'s doc comment above) — deliberately different
///     from `classification_dao.dart`'s own active-filtered pickers, which
///     serve a different purpose (what's *selectable* now, not what
///     historically happened).
///   - supports an optional `[startMs, endMs]` window (`null` on either
///     means "all time" — party-filter mode's own requirement).
///   - supports a `types` filter (`source_type IN (...)`). T21's Analytics
///     passes [allTypes] and applies its single type filter in Dart, since
///     the chart and the By type tiles always show all four types.
///   - supports an optional party filter (`partyType`/`partyKey`) — see
///     [_partyWhereClause]'s own doc comment for the disclosed placeholder
///     contract this implements ahead of Parties/T15's real existence.
class AnalyticsDao {
  AnalyticsDao._();

  static const allTypes = {'SEND_MONEY', 'CASH', 'PAYBILL', 'BUY_GOODS'};

  /// Builds a `t.source_type IN (?,?,...)` fragment and appends its bind
  /// values to [args]. An empty [types] set means "no type is active" —
  /// matches the prototype's own bubble semantics (independently
  /// toggleable down to zero, at which point nothing matches) rather than
  /// silently falling back to "all types."
  static String _typeWhereClause(Set<String> types, List<Object?> args) {
    if (types.isEmpty) return '0'; // always-false: no active type -> no rows
    final placeholders = List.filled(types.length, '?').join(',');
    args.addAll(types);
    return 't.source_type IN ($placeholders)';
  }

  /// **Reconciliation (this dispatch, T15):** this file used to reimplement
  /// `counterparty_key` derivation a *third* time, inline in SQL
  /// (`TRIM(UPPER(t.counterparty_label))`, no internal-whitespace
  /// collapse) — a real, live divergence from
  /// `deriveCounterpartyKey` (`lib/domain/counterparty/counterparty_key.dart`),
  /// the single authoritative implementation, which DOES collapse
  /// internal whitespace. A label like `'LOOP   BIZ'` (irregular internal
  /// spacing) would have grouped correctly on Parties (T15, which calls
  /// `deriveCounterpartyKey` directly) but silently matched ZERO rows here
  /// — a real user-visible bug, not a theoretical one.
  ///
  /// Fixed by dropping the party-match out of SQL entirely (option (b) from
  /// this dispatch's brief): [_matchesParty] below re-derives each
  /// candidate row's key via the one authoritative `deriveCounterpartyKey`
  /// function in Dart, after the (still SQL-side) type/date/deleted-at
  /// filtering has already narrowed the candidate set. This guarantees
  /// Parties' own grouping query and Analytics' party filter agree by
  /// construction — there is only one normalization implementation left to
  /// keep in sync, not two. This project's data volumes are personal-
  /// finance-app scale, so filtering an already-narrowed candidate set in
  /// Dart is not a real performance concern.
  static SmsSourceType? _smsSourceTypeOf(String dbValue) => switch (dbValue) {
        'SEND_MONEY' => SmsSourceType.sendMoney,
        'PAYBILL' => SmsSourceType.payBill,
        'BUY_GOODS' => SmsSourceType.buyGoods,
        _ => null, // CASH (or anything unrecognized): no counterparty identity at all.
      };

  static bool _matchesParty({
    required String rowSourceType,
    required String? rowLabel,
    required String? rowPhone,
    required String? rowAccount,
    required String partyType,
    required String partyKey,
  }) {
    if (rowSourceType != partyType) return false;
    final sms = _smsSourceTypeOf(rowSourceType);
    if (sms == null) return false;
    final key = deriveCounterpartyKey(
      sourceType: sms,
      counterpartyLabel: rowLabel,
      counterpartyPhone: rowPhone,
      paybillAccountNumber: rowAccount,
    );
    return key == partyKey;
  }

  static String _buildWhere({
    required int? startMs,
    required int? endMs,
    required Set<String> types,
    required List<Object?> args,
  }) {
    final clauses = <String>['t.deleted_at IS NULL'];
    if (startMs != null && endMs != null) {
      clauses.add('t.transaction_occurred_at BETWEEN ? AND ?');
      args.addAll([startMs, endMs]);
    }
    clauses.add(_typeWhereClause(types, args));
    return clauses.join(' AND ');
  }

  /// T9 handoff fix: the `transaction_occurred_at` of a live (not
  /// soft-deleted) transaction, so Analytics can open on a period that
  /// contains the row Home's recent list handed it. `null` when [id] no
  /// longer exists or was soft-deleted in the meantime — the caller then
  /// falls back to its default period.
  static Future<DateTime?> occurredAtOf(Database db, {required int id}) async {
    final rows = await db.rawQuery(
      'SELECT transaction_occurred_at FROM transactions WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(rows.first['transaction_occurred_at'] as int);
  }

  /// T21: the day of the first live (not soft-deleted) transaction — where
  /// Analytics' "All time" starts and how far back its Year menu goes.
  /// `null` when there are no transactions.
  static Future<DateTime?> firstOccurredAt(Database db) async {
    final rows = await db.rawQuery(
      'SELECT MIN(transaction_occurred_at) AS first_at FROM transactions WHERE deleted_at IS NULL',
    );
    final value = rows.isEmpty ? null : rows.first['first_at'];
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch((value as num).toInt());
  }

  /// Period-scoped (or all-time, if [startMs]/[endMs] are both `null` —
  /// party-filter mode) itemized transaction list, most-recent-first,
  /// filtered by the active [types] set and optionally by party.
  static Future<List<AnalyticsTransactionRow>> itemizedTransactions(
    Database db, {
    int? startMs,
    int? endMs,
    required Set<String> types,
    String? partyType,
    String? partyKey,
  }) async {
    final args = <Object?>[];
    final where = _buildWhere(startMs: startMs, endMs: endMs, types: types, args: args);
    final rows = await db.rawQuery(
      '''
      SELECT t.id, t.display_code, t.source_type, t.amount_cents,
             t.counterparty_label, t.counterparty_phone, t.paybill_account_number,
             t.classification_id, c.name AS classification_name,
             t.transaction_occurred_at, t.transaction_cost_cents
      FROM transactions t
      JOIN classifications c ON c.id = t.classification_id
      WHERE $where
      ORDER BY t.transaction_occurred_at DESC
      ''',
      args,
    );
    var items = rows
        .map(
          (row) => AnalyticsTransactionRow(
            id: row['id'] as int,
            displayCode: row['display_code'] as String,
            sourceType: row['source_type'] as String,
            amountCents: (row['amount_cents'] as num).toInt(),
            counterpartyLabel: row['counterparty_label'] as String?,
            counterpartyPhone: row['counterparty_phone'] as String?,
            paybillAccountNumber: row['paybill_account_number'] as String?,
            classificationId: row['classification_id'] as int,
            classificationName: row['classification_name'] as String,
            occurredAt: DateTime.fromMillisecondsSinceEpoch(
              row['transaction_occurred_at'] as int,
            ),
            transactionCostCents: (row['transaction_cost_cents'] as num?)?.toInt(),
          ),
        )
        .toList();
    if (partyType != null && partyKey != null) {
      items = items
          .where(
            (r) => _matchesParty(
              rowSourceType: r.sourceType,
              rowLabel: r.counterpartyLabel,
              rowPhone: r.counterpartyPhone,
              rowAccount: r.paybillAccountNumber,
              partyType: partyType,
              partyKey: partyKey,
            ),
          )
          .toList();
    }
    return items;
  }
}
