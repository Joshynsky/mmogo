/// AUTOREAD RULES labeler: from a freshly parsed message's FIELDS (never its text) it works out who the
/// receiver is, reads that person's rule (RuleStore) and history (HistoryReader), and returns the [RuleHint]
/// the waiting item carries. It only READS; it never writes a rule, the database or the summary.
///
/// 0.2.1 emits Suggested and Ask first only: a stored Auto-record level is labelled Ask first, so a tap
/// always decides. Any failure returns null (no hint); it never throws and logs nothing.
library;

import 'dart:async';

import '../../domain/parsing/parsed_sms_fields.dart';
import '../model/rule_hint.dart';
import '../rules/receiver_key.dart';
import '../rules/rule_model.dart';
import '../rules/rule_store.dart';
import 'history_reader.dart';

/// The whole labelling step may take at most this long before the item is stored without a hint.
const Duration kLabelCap = Duration(milliseconds: 2500);

/// The shape of `receiverKey` (S2a); a test passes its own.
typedef ReceiverKeyFn = String? Function(
  ReceiverType type, {
  String? phone,
  String? business,
  String? account,
  String? shopName,
  String? name,
  bool pochiRemembered,
  bool recordReceiverDetails,
});

class RuleLabeler {
  RuleLabeler({
    required this.rules,
    required this.history,
    Future<bool> Function()? recordReceiverDetails,
    this.cap = kLabelCap,
    ReceiverKeyFn? keyOf,
  })  : _details = recordReceiverDetails ?? (() async => true),
        _keyOf = keyOf ?? receiverKey;

  final RuleStore rules;
  final HistoryReader history;
  final Future<bool> Function() _details;
  final ReceiverKeyFn _keyOf;
  final Duration cap;

  /// The hint for [p], or null (no person key, details off, nothing known, or any failure).
  Future<RuleHint?> label(ParsedSmsFields p) async {
    try {
      return await _label(p).timeout(cap);
    } catch (_) {
      return null;
    }
  }

  Future<RuleHint?> _label(ParsedSmsFields p) async {
    final ReceiverType type;
    switch (p.sourceType) {
      case SmsSourceType.sendMoney:
        type = ReceiverType.sendMoney;
      case SmsSourceType.payBill:
        type = ReceiverType.payBill;
      case SmsSourceType.buyGoods:
        type = ReceiverType.buyGoods;
      // The parser never produces Pochi (a name-only message waits as a choice), and Withdrawal and
      // Airtime never have a rule.
      case SmsSourceType.pochi:
      case SmsSourceType.agentWithdrawal:
      case SmsSourceType.airtime:
        return null;
    }
    final key = _keyOf(
      type,
      phone: p.counterpartyPhone,
      business: p.counterpartyLabel,
      account: p.paybillAccountNumber,
      shopName: p.counterpartyLabel,
      recordReceiverDetails: await _details(),
    );
    if (key == null) return null;

    final rule = await rules.get(type, key);
    final top = await _topTwo(type, key);

    if (rule != null && rule.level != RuleLevel.suggested) {
      final cat = rule.categoryId;
      return RuleHint(
        level: RuleLevel.askFirst,
        type: type,
        key: key,
        suggested: cat != null ? [cat] : top,
      );
    }
    if (rule == null && top.isEmpty) return null;
    return RuleHint(level: RuleLevel.suggested, type: type, key: key, suggested: top);
  }

  Future<List<int>> _topTwo(ReceiverType type, String key) async {
    try {
      final r = await history.topTwo(type, key);
      return r == null ? const <int>[] : (r.length > 2 ? r.sublist(0, 2) : r);
    } catch (_) {
      return const <int>[];
    }
  }
}
