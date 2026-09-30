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
  });

  final int id;
  final String displayCode;
  final String sourceType; // 'SEND_MONEY' | 'BUY_GOODS' | 'PAYBILL' | 'CASH'
  final int amountCents;
  final String? counterpartyLabel;
  final String classificationName;
  final DateTime occurredAt;

  /// Matches the prototype's row-title logic exactly: Cash rows show their
  /// classification (no counterparty exists for cash); every other row
  /// prefers its captured counterparty label, falling back to the
  /// classification name only in the schema-disallowed edge case where a
  /// label is somehow missing.
  String get displayName {
    if (sourceType == 'CASH') return 'Cash — $classificationName';
    return (counterpartyLabel != null && counterpartyLabel!.isNotEmpty)
        ? counterpartyLabel!
        : classificationName;
  }
}
