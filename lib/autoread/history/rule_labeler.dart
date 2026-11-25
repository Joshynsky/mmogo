/// AUTOREAD RULES labeler: from a freshly parsed message's FIELDS (never its text) it
/// works out who the receiver is, reads that person's rule (RuleStore) and history (HistoryReader), and returns
/// the [RuleHint] the waiting item carries. It only READS; it never writes a rule, the database or the summary.
///
/// While [autoRecordLive] is false (today) it emits Suggested and Ask first only: a stored Auto-record level is
/// labelled Ask first, so a tap always decides. Live (0.2.2 B2a): an Auto-record person gets an `auto` hint ONLY
/// when [decideHardRule] says record; otherwise an Ask first hint with `fromAutoRecord = true` (paused, above the
/// ceiling, Paybill level 2 in storage, ...). The hint is a label: nothing records from it alone (Kotlin decides
/// again natively, and the app re-checks at import). Any failure returns null (no hint); it never throws and
/// logs nothing.
library;

import 'dart:async';

import '../../domain/parsing/parsed_sms_fields.dart';
import '../model/rule_hint.dart';
import '../rules/hard_rule_decision.dart';
import '../rules/prefs_hard_rule_pause.dart';
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
    Future<bool> Function()? paused,
    bool? live,
  })  : _details = recordReceiverDetails ?? (() async => true),
        _keyOf = keyOf ?? receiverKey,
        _paused = paused ?? PrefsHardRulePause().isPaused,
        _live = live ?? autoRecordLive;

  final RuleStore rules;
  final HistoryReader history;
  final Future<bool> Function() _details;
  final ReceiverKeyFn _keyOf;
  final Duration cap;

  /// The pause switch (fails closed: any doubt reads as paused). Read only for an Auto-record person, live.
  final Future<bool> Function() _paused;

  /// [autoRecordLive]; a test passes true to run the live path.
  final bool _live;

  /// The hint for [p], or null (no person key, details off, nothing known, or any failure).
  Future<RuleHint?> label(ParsedSmsFields p) async {
    try {
      return await _label(p).timeout(cap);
    } catch (_) {
      return null;
    }
  }

  Future<RuleHint?> _label(ParsedSmsFields p) async {
    // Withdrawal, Airtime and Pochi are never labelled (see ruleKindOfSource).
    final type = ruleKindOfSource(p.sourceType);
    if (type == null) return null;
    final details = await _details();
    final key = _keyOf(
      type,
      phone: p.counterpartyPhone,
      business: p.counterpartyLabel,
      account: p.paybillAccountNumber,
      shopName: p.counterpartyLabel,
      recordReceiverDetails: details,
    );
    if (key == null) return null;

    final rule = await rules.get(type, key);
    final top = await _topTwo(type, key);

    if (rule != null && rule.level != RuleLevel.suggested) {
      final cat = rule.categoryId;
      if (_live && rule.level == RuleLevel.autoRecord) return _autoHint(rule, type, key, p.amountCents, details, top);
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

  /// B2a: `auto` only when the decision is record (the rule then has a category); any other answer is an Ask
  /// first hint that remembers it came from an Auto-record rule.
  Future<RuleHint> _autoHint(ReceiverRule rule, ReceiverType type, String key, int amountCents, bool details, List<int> top) async {
    var paused = true;
    try {
      paused = await _paused();
    } catch (_) {}
    final d = decideHardRule(rule: rule, kind: type, amountCents: amountCents, paused: paused, detailsOn: details);
    final cat = rule.categoryId;
    if (d == HardRuleDecision.record && cat != null) {
      return RuleHint(level: RuleLevel.autoRecord, type: type, key: key, suggested: [cat]);
    }
    return RuleHint(level: RuleLevel.askFirst, type: type, key: key, suggested: cat != null ? [cat] : top, fromAutoRecord: true);
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
