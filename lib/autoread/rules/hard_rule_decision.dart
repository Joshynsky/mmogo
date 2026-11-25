/// §AUTOREAD.HARD_RULE_DECISION - the pure Auto-record decision (0.2.2 item 2, S-2).
///
/// DORMANT: nothing calls [decideHardRule] yet. The labeler and Kotlin still
/// treat level 2 as Ask first; [autoRecordLive] stays false until the PM says go.
library;

import 'rule_model.dart';

/// Master dormancy guard. A test pins it false.
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
/// Any doubt resolves to Ask first, never to record.
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
  if (amountCents <= 0) return HardRuleDecision.askFirst;
  final ceiling = rule.ceilingCents;
  if (ceiling != null) {
    if (!isValidCeilingCents(ceiling)) return HardRuleDecision.askFirst;
    if (amountCents > ceiling) return HardRuleDecision.askFirst;
  }
  return HardRuleDecision.record;
}
