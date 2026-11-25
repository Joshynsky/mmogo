/// §AUTOREAD.SUGGESTED_CHIPS_SOURCE (0.2.2, item 0 Part 1) - works out the suggested chips for ONE waiting
/// item: its own person key, that person's rule level (Suggested only), their history (the summary the app
/// keeps), and the categories that are active now. Reads only; never writes. Any failure, no key, no summary
/// or an unreadable one gives NO chips (never an error). Autoread build only.
library;

import '../../domain/parsing/parsed_sms_fields.dart';
import '../history/history_reader.dart';
import '../history/suggested_chips.dart';
import '../rules/receiver_key.dart';
import '../rules/rule_model.dart';
import '../rules/rule_store.dart';
import '../model/waiting_item.dart';
import '../ui/category_choices.dart';

class SuggestedChipsSource {
  SuggestedChipsSource({
    required this.rules,
    required this.history,
    required Future<bool> Function() recordReceiverDetails,
    Future<bool> Function(String name)? pochiRemembered,
  })  : _details = recordReceiverDetails,
        _pochiRemembered = pochiRemembered ?? ((n) => isRememberedPochi(n));

  final RuleStore rules;
  final HistoryReader history;
  final Future<bool> Function() _details;
  final Future<bool> Function(String name) _pochiRemembered;

  static ReceiverType? _typeOf(SmsSourceType t) => switch (t) {
        SmsSourceType.sendMoney => ReceiverType.sendMoney,
        SmsSourceType.pochi => ReceiverType.pochi,
        SmsSourceType.buyGoods => ReceiverType.buyGoods,
        // Paybill is held to 0.2.3; withdrawal and airtime have their own flow.
        SmsSourceType.payBill || SmsSourceType.agentWithdrawal || SmsSourceType.airtime => null,
      };

  /// The chips for [item], left to right (most used last); [choices] are the categories the sheet would
  /// offer (they decide which are active). Empty list when there is nothing to show.
  Future<List<CategoryChoice>> chipsFor(WaitingItem item, CategoryChoices choices) async {
    try {
      final p = item.parsed;
      if (p == null) return const [];
      final type = _typeOf(p.sourceType);
      if (type == null || !kChipReceiverTypes.contains(type)) return const [];
      final h = item.hint;
      final String? key;
      if (h != null && h.type == type && h.key.isNotEmpty) {
        key = h.key; // the item's OWN key, found when it was parsed
      } else {
        key = receiverKey(
          type,
          phone: p.counterpartyPhone,
          shopName: p.counterpartyLabel,
          name: p.counterpartyLabel,
          pochiRemembered: type == ReceiverType.pochi && await _pochiRemembered(p.counterpartyLabel ?? ''),
          recordReceiverDetails: await _details(),
        );
      }
      if (key == null) return const [];
      final rule = await rules.get(type, key);
      if (rule != null && rule.level != RuleLevel.suggested) return const []; // Ask first / Auto-record keep their flow
      final top = await history.topTwo(type, key);
      if (top == null || top.isEmpty) return const [];
      final all = await choices.categories();
      final active = <int>{for (final c in all) ?int.tryParse(c.id)};
      final ids = suggestedChips(type: type, history: top, activeCategoryIds: active);
      final byId = {for (final c in all) c.id: c};
      return [for (final id in ids) ?byId['$id']];
    } catch (_) {
      return const [];
    }
  }
}
