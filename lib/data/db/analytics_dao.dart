import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/counterparty/counterparty_key.dart';
import '../../domain/format/source_types.dart';
import '../../domain/money/spent_amount.dart';
import '../../domain/paid_to/paid_to.dart' show paidToPartyKeyOf, paidToPochi, paidToWithdrawal;
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
    this.agentNumber,
    this.fromMessage = false,
    this.parentTransactionId,
    this.cashOnlyDecided = false,
    this.linkedCategoryNames = const [],
    this.linkedCents = 0,
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

  /// What this row adds to "spent" (the one rule, `spentCents`): a
  /// withdrawal adds 0, every other type its amount. Every spent total
  /// sums this, never [amountCents].
  int get spent => spentCents(sourceType, amountCents, transactionCostCents);

  /// The cash this row took out at an agent (the amount of a withdrawal, 0
  /// for every other type). Tracked, never spending; only the Withdrawal tile
  /// reads it.
  int get withdrawn => withdrawnCents(sourceType, amountCents);

  /// -> `transactions.transaction_cost_cents`. Always `null` for CASH rows
  /// (schema CHECK); NOT NULL for every other `source_type`. T13 — added
  /// so Analytics' edit form (this row's own re-render target) can
  /// pre-fill the Transaction cost field without a second query; nothing
  /// prior to T13 needed this column on this class.
  final int? transactionCostCents;

  /// -> `transactions.agent_number` (v3). Withdrawal rows only, else null.
  final String? agentNumber;

  /// 0.2.0 S9: the row was read from an M-Pesa message (`raw_parse_source` = SMS_PARSE), not typed by hand.
  /// The edit sheet locks the message's own figures for such a row (flavor-gated there). Existing column, no schema change.
  final bool fromMessage;

  /// 0.2.1: the withdrawal this Cash entry is linked to (`parent_transaction_id`), else null.
  final int? parentTransactionId;

  /// 0.2.1: true for a Cash entry added from a withdrawal (shows "from withdrawal").
  bool get fromWithdrawal => parentTransactionId != null;

  /// 0.2.1: a withdrawal the user marked "Cash only" (`cash_only_decided`).
  final bool cashOnlyDecided;

  /// 0.2.1: on a withdrawal row, the category names of its live linked entries, oldest
  /// first, each name once (for the "-> Rent" line). Empty on every other row.
  final List<String> linkedCategoryNames;

  /// 0.2.1: on a withdrawal row, the total of its live linked entries in cents (what is
  /// no longer "still cash"); 0 otherwise. Display only, never a spent total.
  final int linkedCents;

  /// Row title: Cash rows show their classification (no counterparty exists
  /// for cash); every other row prefers its captured counterparty label,
  /// falling back to the classification name in the schema-disallowed edge
  /// case where a label is somehow missing — same rule
  /// `recent_transaction.dart` (T4) already established for Home's list.
  String get displayName {
    if (sourceType == 'CASH') return 'Cash — $classificationName';
    // Airtime has no payee: its title is always the type name (S6a, mock).
    if (sourceType == 'AIRTIME') return 'Airtime';
    return (counterpartyLabel != null && counterpartyLabel!.isNotEmpty)
        ? counterpartyLabel!
        : classificationName;
  }
}

/// 0.1.2 S6c: the cash taken out at agents inside each window, in cents
/// (one per `(startMs, endMs)`, both ends inclusive). Feeds only the chart's
/// hatched segment and its legend; never a spent total.
List<int> withdrawnPerWindow(List<(int, int)> windows, Iterable<AnalyticsTransactionRow> rows) {
  final out = List<int>.filled(windows.length, 0);
  for (final r in rows) {
    final w = r.withdrawn;
    if (w == 0) continue;
    final ms = r.occurredAt.millisecondsSinceEpoch;
    for (var i = 0; i < windows.length; i++) {
      if (ms >= windows[i].$1 && ms <= windows[i].$2) out[i] += w;
    }
  }
  return out;
}

/// 0.1.2 S7c: the cash taken out at agents across [rows], in cents (the same figure the Paid to
/// row and recipient sheet show for a Withdrawal agent). Never a spent total.
int cashOutTotal(Iterable<AnalyticsTransactionRow> rows) => rows.fold(0, (s, r) => s + r.withdrawn);

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

  /// Every stored source type, derived from [sourceTypeOrder] so a type
  /// added there can never be left out of an Analytics query.
  /// The SELECT list every row query here shares (alias `t` = transactions, `c` =
  /// classifications). `linked_names` / `linked_amounts` are the 0.2.1 read of a withdrawal's
  /// live linked entries; both are NULL on a row with none.
  static const String rowColumns = '''
t.id, t.display_code, t.source_type, t.amount_cents,
             t.counterparty_label, t.counterparty_phone, t.paybill_account_number,
             t.classification_id, c.name AS classification_name,
             t.transaction_occurred_at, t.transaction_cost_cents, t.agent_number, t.raw_parse_source,
             t.parent_transaction_id, t.cash_only_decided,
             (SELECT group_concat(lname, char(31)) FROM
                (SELECT lc.name AS lname FROM transactions ch
                 JOIN classifications lc ON lc.id = ch.classification_id
                 WHERE ch.parent_transaction_id = t.id AND ch.deleted_at IS NULL
                 ORDER BY ch.id)) AS linked_names,
             (SELECT group_concat(ch.amount_cents, char(31)) FROM transactions ch
              WHERE ch.parent_transaction_id = t.id AND ch.deleted_at IS NULL) AS linked_amounts''';

  /// Builds one row from a query that selected [rowColumns].
  static AnalyticsTransactionRow rowFrom(Map<String, Object?> row) {
    final names = row['linked_names'] as String?;
    // Summed here, not in SQL: the spend guard test allows no raw sum of the amount column under lib/.
    final amounts = row['linked_amounts'] as String?;
    final linked = amounts == null || amounts.isEmpty
        ? 0
        : amounts.split('\u001f').fold<int>(0, (s, a) => s + int.parse(a));
    return AnalyticsTransactionRow(
      id: row['id'] as int,
      displayCode: row['display_code'] as String,
      sourceType: row['source_type'] as String,
      amountCents: (row['amount_cents'] as num).toInt(),
      counterpartyLabel: row['counterparty_label'] as String?,
      counterpartyPhone: row['counterparty_phone'] as String?,
      paybillAccountNumber: row['paybill_account_number'] as String?,
      classificationId: row['classification_id'] as int,
      classificationName: row['classification_name'] as String,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(row['transaction_occurred_at'] as int),
      transactionCostCents: (row['transaction_cost_cents'] as num?)?.toInt(),
      agentNumber: row['agent_number'] as String?,
      fromMessage: row['raw_parse_source'] == 'SMS_PARSE',
      parentTransactionId: row['parent_transaction_id'] as int?,
      cashOnlyDecided: row['cash_only_decided'] == 1,
      linkedCategoryNames:
          names == null || names.isEmpty ? const [] : {...names.split('\u001f')}.toList(),
      linkedCents: linked,
    );
  }

  static final Set<String> allTypes = {for (final (code, _) in sourceTypeOrder) code};

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
        // Pochi and Withdrawal have no map key: [_matchesParty] matches them
        // through Paid to's own key (S7b). Airtime has no receiver and CASH no
        // counterparty identity at all: no party match.
        _ => null,
      };

  static bool _matchesParty({
    required String rowSourceType,
    required String? rowLabel,
    required String? rowPhone,
    required String? rowAccount,
    required String? rowAgentNumber,
    required String partyType,
    required String partyKey,
  }) {
    if (rowSourceType != partyType) return false;
    // S7b (PT1): Pochi (`tel|<phone key>` else `name|<LABEL>`) and Withdrawal
    // (`no|<agent number>` else `name|<LABEL>`) use the SAME key Paid to groups
    // by, so the recipient view holds exactly the rows of the Paid to row.
    if (rowSourceType == paidToPochi || rowSourceType == paidToWithdrawal) {
      return paidToPartyKeyOf(
            sourceType: rowSourceType,
            label: rowLabel,
            phone: rowPhone,
            account: rowAccount,
            agentNumber: rowAgentNumber,
          ) ==
          partyKey;
    }
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
      SELECT $rowColumns
      FROM transactions t
      JOIN classifications c ON c.id = t.classification_id
      WHERE $where
      ORDER BY t.transaction_occurred_at DESC
      ''',
      args,
    );
    var items = rows.map(rowFrom).toList();
    if (partyType != null && partyKey != null) {
      items = items
          .where(
            (r) => _matchesParty(
              rowSourceType: r.sourceType,
              rowLabel: r.counterpartyLabel,
              rowPhone: r.counterpartyPhone,
              rowAccount: r.paybillAccountNumber,
              rowAgentNumber: r.agentNumber,
              partyType: partyType,
              partyKey: partyKey,
            ),
          )
          .toList();
    }
    return items;
  }

  /// 0.2.0 S9: the live (not soft-deleted) rows whose code is in [codes], newest first. The Fuliza page uses
  /// it to pair a borrowing with the payment it funded, by code (read time, nothing stored).
  static Future<List<AnalyticsTransactionRow>> byCodes(Database db, Set<String> codes) async {
    if (codes.isEmpty) return const [];
    final marks = List.filled(codes.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT $rowColumns
      FROM transactions t
      JOIN classifications c ON c.id = t.classification_id
      WHERE t.deleted_at IS NULL AND t.display_code IN ($marks)
      ORDER BY t.transaction_occurred_at DESC
      ''',
      codes.toList(),
    );
    return rows.map(rowFrom).toList();
  }
}
