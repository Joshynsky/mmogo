// T5 — SMS parsing engine (WBS row T5).
//
// The transaction-type vocabulary a successfully-parsed M-Pesa SMS can
// resolve to. Deliberately excludes CASH — no parser path ever produces a
// cash transaction (the `transactions.source_type` CHECK and
// `classification_groups` reflect this: CASH has no matching group/parser).
enum SmsSourceType { sendMoney, payBill, buyGoods }

/// Maps each [SmsSourceType] to the exact string stored in
/// `transactions.source_type` / `classification_groups.code`
/// (`lib/data/db/schema.dart`), for T6 to use unmodified when it writes a
/// row from a successful parse.
extension SmsSourceTypeDb on SmsSourceType {
  String get dbValue => switch (this) {
        SmsSourceType.sendMoney => 'SEND_MONEY',
        SmsSourceType.payBill => 'PAYBILL',
        SmsSourceType.buyGoods => 'BUY_GOODS',
      };
}

/// The four values plus the M-Pesa code that a successful parse must
/// extract, one field per column T6 will eventually write:
///   - [code]                    -> `transactions.display_code`
///   - [sourceType]              -> `transactions.source_type`
///   - [amountCents]             -> `transactions.amount_cents`
///   - [transactionCostCents]    -> `transactions.transaction_cost_cents`
///   - [counterpartyLabel]       -> `transactions.counterparty_label`
///     (receiver name for Send Money, business/merchant name for
///     Paybill/Buy Goods)
///   - [counterpartyPhone]       -> `transactions.counterparty_phone`
///     (Send Money only, verbatim as the SMS carries it, no reformatting)
///   - [paybillAccountNumber]    -> `transactions.paybill_account_number`
///     (Paybill only)
///   - [transactionOccurredAt]   -> `transactions.transaction_occurred_at`
///     (epoch millis, local device time, matching the column's INTEGER
///     epoch-millis convention used elsewhere in schema.dart)
///
/// This class is a pure data holder — T5 does not write to the database
/// (that's T6's job; T5 has no dependency on T1's schema at
/// all, only on producing values shaped to fit it later).
class ParsedSmsFields {
  final String code;
  final SmsSourceType sourceType;
  final int amountCents;
  final int transactionCostCents;
  final String? counterpartyLabel;
  final String? counterpartyPhone;
  final String? paybillAccountNumber;
  final int transactionOccurredAt;

  const ParsedSmsFields({
    required this.code,
    required this.sourceType,
    required this.amountCents,
    required this.transactionCostCents,
    required this.counterpartyLabel,
    required this.counterpartyPhone,
    required this.paybillAccountNumber,
    required this.transactionOccurredAt,
  });

  @override
  String toString() =>
      'ParsedSmsFields(code: $code, sourceType: $sourceType, '
      'amountCents: $amountCents, transactionCostCents: $transactionCostCents, '
      'counterpartyLabel: $counterpartyLabel, counterpartyPhone: $counterpartyPhone, '
      'paybillAccountNumber: $paybillAccountNumber, '
      'transactionOccurredAt: $transactionOccurredAt)';

  @override
  bool operator ==(Object other) =>
      other is ParsedSmsFields &&
      other.code == code &&
      other.sourceType == sourceType &&
      other.amountCents == amountCents &&
      other.transactionCostCents == transactionCostCents &&
      other.counterpartyLabel == counterpartyLabel &&
      other.counterpartyPhone == counterpartyPhone &&
      other.paybillAccountNumber == paybillAccountNumber &&
      other.transactionOccurredAt == transactionOccurredAt;

  @override
  int get hashCode => Object.hash(
        code,
        sourceType,
        amountCents,
        transactionCostCents,
        counterpartyLabel,
        counterpartyPhone,
        paybillAccountNumber,
        transactionOccurredAt,
      );
}
