// Stand-in for S2a's receiverKey (the contract's key table) so S2b tests do not depend on that slice.
// After S2a merges the real function can replace it.
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/domain/counterparty/phone_key.dart';

/// The contract's key table (a stand-in for S2a's receiverKey so these tests do not depend on that slice).
String? standInReceiverKey(
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
  final k = switch (type) {
    ReceiverType.sendMoney => normalizePhoneKey(phone),
    ReceiverType.payBill => '${(business ?? '').trim().toUpperCase()}#${(account ?? '').trim()}',
    ReceiverType.buyGoods => (shopName ?? '').trim().toUpperCase(),
    ReceiverType.pochi => pochiRemembered ? (name ?? '').trim() : '',
  };
  return k.isEmpty || k == '#' ? null : k;
}
