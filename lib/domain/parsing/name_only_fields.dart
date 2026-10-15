/// §DOMAIN.PARSING.NAME_ONLY_FIELDS — the fields of a `sent to <NAME>` message
/// that carries no phone and no account (0.1.2 S8a, NO1).
///
/// It has NO source type on purpose: the message could be a Pochi la Biashara
/// payment or a person-to-person send with the number missing, and only the
/// user (S8c Add flow, with the S8b resolver) can say which. Never saved by
/// itself.
class NameOnlyFields {
  final String code;
  final int amountCents;
  final int transactionCostCents;
  final String name;
  final int transactionOccurredAt;

  const NameOnlyFields({
    required this.code,
    required this.amountCents,
    required this.transactionCostCents,
    required this.name,
    required this.transactionOccurredAt,
  });

  @override
  String toString() => 'NameOnlyFields(code: $code, amountCents: $amountCents, '
      'transactionCostCents: $transactionCostCents, name: $name, '
      'transactionOccurredAt: $transactionOccurredAt)';

  @override
  bool operator ==(Object other) =>
      other is NameOnlyFields &&
      other.code == code &&
      other.amountCents == amountCents &&
      other.transactionCostCents == transactionCostCents &&
      other.name == name &&
      other.transactionOccurredAt == transactionOccurredAt;

  @override
  int get hashCode => Object.hash(
      code, amountCents, transactionCostCents, name, transactionOccurredAt);
}
