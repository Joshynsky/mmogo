/// Read-model for one row in Home's recent-transactions list — the
/// minimal projection of `transactions` (joined to `classifications` for
/// the name) that the list actually needs to render, per
/// Home's recent list: unfiltered by the period selector,
/// excludes soft-deleted rows, most-recent-first.
class RecentTransaction {
  const RecentTransaction({
    required this.id,
    required this.displayCode,
    required this.sourceType,
    required this.amountCents,
    required this.counterpartyLabel,
    required this.classificationName,
    required this.occurredAt,
    this.feeCents = 0,
    this.agentNumber,
  });

  final int id;
  final String displayCode;
  final String sourceType; // 'SEND_MONEY' | 'BUY_GOODS' | 'PAYBILL' | 'CASH'
  final int amountCents;
  final String? counterpartyLabel;
  final String classificationName;
  final DateTime occurredAt;

  /// The M-Pesa transaction cost of this row (0 when none; NULL for Cash).
  final int feeCents;

  /// The agent number of a withdrawal (null for every other row).
  final String? agentNumber;

  bool get isWithdrawalRow => sourceType == 'AGENT_WITHDRAWAL';

  /// Matches the prototype's row-title logic exactly: Cash rows show their
  /// classification (no counterparty exists for cash); every other row
  /// prefers its captured counterparty label, falling back to the
  /// classification name only in the schema-disallowed edge case where a
  /// label is somehow missing.
  String get displayName {
    // Withdrawal and Airtime rows have no payee: the title is the type name.
    if (sourceType == 'AGENT_WITHDRAWAL') return 'Withdrawal';
    if (sourceType == 'AIRTIME') return 'Airtime';
    if (sourceType == 'CASH') return 'Cash — $classificationName';
    return (counterpartyLabel != null && counterpartyLabel!.isNotEmpty)
        ? counterpartyLabel!
        : classificationName;
  }
}
