/// §AUTOREAD.HARD_RULE_DECISION - the pure Auto-record decision (0.2.2 item 2, S-2; B2 callers).
///
/// The ONE decision for Dart callers: the labeler (B2a) and the import re-check of an automatic mark (B2d).
/// Kotlin mirror: HardRuleLogic.kt. Both run the shared case table test/autoread/hard_rule_parity_cases.json.
/// [autoRecordLive] stays false (and its Kotlin mirror HardRuleLogic.AUTO_RECORD_LIVE) until the PM flip (G2).
library;

import '../../domain/parsing/parsed_sms_fields.dart';
import 'rule_model.dart';

/// Master dormancy guard. A test pins it false, and pins the Kotlin mirror to the same value.
const bool autoRecordLive = false;

enum HardRuleDecision {
  /// Record with no tap.
  record,

  /// Show the Ask first prompt.
  askFirst,

  /// The hard rule does not apply (Suggested, no rule, or a kind with no rule).
  notApplicable,
}

/// Decides what to do with one arriving message.
///
/// [kind] is the receiver kind (null for withdrawal, airtime or unknown: no
/// rule). [amountCents] is the amount ALONE: the transaction fee is not an
/// input (A1). Ceiling: amount <= ceiling records, ceiling + 1 cent asks first.
/// Any doubt resolves to Ask first, never to record. B2 adds two doubts: a rule
/// still marked restored-pending ([ReceiverRule.autoPending]) and a rule with no
/// category (nothing to record into).
HardRuleDecision decideHardRule({
  required ReceiverRule? rule,
  required ReceiverType? kind,
  required int amountCents,
  required bool paused,
  required bool detailsOn,
}) {
  if (rule == null || kind == null) return HardRuleDecision.notApplicable;
  if (rule.level == RuleLevel.suggested) return HardRuleDecision.notApplicable;
  if (rule.level == RuleLevel.askFirst) return HardRuleDecision.askFirst;
  // Level 2 (Auto-record) from here: every doubt is Ask first.
  if (!detailsOn || paused) return HardRuleDecision.askFirst;
  if (!canHoldAutoRecord(kind) || rule.type != kind) return HardRuleDecision.askFirst;
  if (rule.autoPending || rule.categoryId == null) return HardRuleDecision.askFirst;
  if (amountCents <= 0) return HardRuleDecision.askFirst;
  final ceiling = rule.ceilingCents;
  if (ceiling != null) {
    if (!isValidCeilingCents(ceiling)) return HardRuleDecision.askFirst;
    if (amountCents > ceiling) return HardRuleDecision.askFirst;
  }
  return HardRuleDecision.record;
}

/// The rule kind of a parsed message, or null when that kind never has a rule. Same mapping as the labeler:
/// the parser never produces Pochi (a name-only message waits as a choice), and Withdrawal and Airtime have
/// no rule. Kotlin mirror: HardRuleLogic.kindOfSource.
ReceiverType? ruleKindOfSource(SmsSourceType source) => switch (source) {
      SmsSourceType.sendMoney => ReceiverType.sendMoney,
      SmsSourceType.payBill => ReceiverType.payBill,
      SmsSourceType.buyGoods => ReceiverType.buyGoods,
      SmsSourceType.pochi || SmsSourceType.agentWithdrawal || SmsSourceType.airtime => null,
    };

/// The pause switch from its raw stored value: absent = not paused, a bool = itself, anything else = paused
/// (doubt). Same as PrefsHardRulePause.isPaused; Kotlin mirror: HardRuleLogic.pausedFrom.
bool hardPausedFromRaw(Object? raw) => raw == null ? false : (raw is bool ? raw : true);

/// "Record receiver details" from its raw stored value for the hard rule: absent = ON (the app default), a
/// bool = itself, anything else = OFF (doubt, so Ask first). Kotlin mirror: HardRuleLogic.detailsOnFrom.
bool hardDetailsOnFromRaw(Object? raw) => raw == null ? true : (raw is bool ? raw : false);
