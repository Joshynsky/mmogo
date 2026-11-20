/// AUTOREAD RULES key function: the one key a rule is stored under.
library;

import '../../data/prefs/recipient_memory.dart';
import '../../domain/counterparty/counterparty_key.dart';
import '../../domain/parsing/name_only_resolver.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import 'rule_model.dart';

/// Longest key kept (same as the recipient memory).
const int kRuleKeyMaxLength = 200;

/// The one key a rule is stored under, or null when there is none (empty,
/// over 200 chars, Pochi not remembered as Pochi, or details recording off).
/// Send Money = normalised phone (07xx, 01xx, +254 are one key); Paybill =
/// BUSINESS#account (business UPPERCASE, account case kept); Buy Goods = shop
/// name UPPERCASE; Pochi = the recipient-memory name key (the same key
/// RecipientMemory stores it under).
String? receiverKey(
  ReceiverType type, {
  String? phone,
  String? business,
  String? account,
  String? shopName,
  String? name,
  bool pochiRemembered = false,
  bool recordReceiverDetails = true,
}) {
  if (!recordReceiverDetails) return null;
  final String key;
  switch (type) {
    case ReceiverType.sendMoney:
      // The one phone rule lives behind deriveCounterpartyKey (a guard test lists who may call it).
      key = deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: phone);
    case ReceiverType.payBill:
      if ((business ?? '').trim().isEmpty) return null;
      key = deriveCounterpartyKey(
        sourceType: SmsSourceType.payBill,
        counterpartyLabel: business,
        paybillAccountNumber: account,
      );
    case ReceiverType.buyGoods:
      key = deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: shopName);
    case ReceiverType.pochi:
      if (!pochiRemembered) return null;
      key = deriveRecipientNameKey(name ?? '');
  }
  if (key.trim().isEmpty || key.length > kRuleKeyMaxLength) return null;
  return key;
}

/// True when [name] is remembered as a Pochi in the recipient memory (the
/// caller passes the result as `pochiRemembered`). Never throws.
Future<bool> isRememberedPochi(String name, {RecipientMemory? memory}) async {
  try {
    final r = await (memory ?? RecipientMemory()).lookup(deriveRecipientNameKey(name));
    return r != null && r.type == SmsSourceType.pochi;
  } catch (_) {
    return false;
  }
}
