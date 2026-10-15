import '../counterparty/counterparty_key.dart';
import 'name_only_fields.dart';
import 'parsed_sms_fields.dart';

/// §DOMAIN.PARSING.NAME_ONLY_RESOLVER — 0.1.2 S8b (NO3). Pure: no storage, no
/// clock, no logging.

/// What the user told us earlier about a receiver name: the type, and when
/// (epoch ms). Stored by `RecipientMemory` (device only).
class RecipientRule {
  final SmsSourceType type;
  final int at;
  const RecipientRule({required this.type, required this.at});

  @override
  bool operator ==(Object other) => other is RecipientRule && other.type == type && other.at == at;

  @override
  int get hashCode => Object.hash(type, at);
}

/// The key a receiver NAME is remembered under: trim, collapse whitespace,
/// upper-case. It calls the one normaliser (`deriveCounterpartyKey`) with the
/// Buy Goods type and the name as the label; the Pochi case of that function
/// returns '' by design, so the label rule is reached through Buy Goods (the
/// same way Paid to does it). No copy of the rule lives here.
String deriveRecipientNameKey(String name) =>
    deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: name);

sealed class NameOnlyResolution {
  const NameOnlyResolution();
}

/// The name was remembered: typed fields, ready for the Add flow. [fromMemory]
/// is always true for a hit (kept so a caller can pass either shape on).
class Resolved extends NameOnlyResolution {
  final ParsedSmsFields fields;
  final bool fromMemory;
  const Resolved(this.fields, {this.fromMemory = true});
}

/// Not remembered: the Add flow (S8c) must ask the user for the type.
class NeedsType extends NameOnlyResolution {
  final NameOnlyFields fields;
  const NeedsType(this.fields);
}

/// A remembered Send Money is saved with phone NULL and label NULL (it shows
/// as "Unnamed"); a remembered Pochi keeps the name as its label. Any other
/// remembered type is not usable here and counts as a miss.
NameOnlyResolution resolveNameOnly(NameOnlyFields fields, RecipientRule? remembered) {
  if (remembered == null) return NeedsType(fields);
  final String? label;
  switch (remembered.type) {
    case SmsSourceType.sendMoney:
      label = null;
    case SmsSourceType.pochi:
      label = fields.name;
    default:
      return NeedsType(fields);
  }
  return Resolved(
    ParsedSmsFields(
      code: fields.code,
      sourceType: remembered.type,
      amountCents: fields.amountCents,
      transactionCostCents: fields.transactionCostCents,
      counterpartyLabel: label,
      counterpartyPhone: null,
      paybillAccountNumber: null,
      transactionOccurredAt: fields.transactionOccurredAt,
    ),
    fromMemory: true,
  );
}
