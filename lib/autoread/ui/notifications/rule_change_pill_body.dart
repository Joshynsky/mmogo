/// §AUTOREAD.RULE_CHANGE_PILL_BODY - what the one pill says, and its two drawn stages (0.2.2 item 2, slice U-PILL;
/// mock-remembered-v2 scenes p-auto-pill, p-auto-pill-any, p-ask-pill).
///
/// [ruleChangePillLines] picks the signed lines (hard_rule_copy.dart, "Pill", signed 25-11): Suggested =
/// hardPillSuggested; Ask first = hardPillAskFirst with the category; Auto-record = hardPillAuto with the category,
/// and at stage 2 "Records any amount." + "Set a limit" or "Records up to Ksh {limit}." + "Change". The pill gets the
/// plain name from its caller and never a phone number. [RuleChangePillBody] draws one stage: stage 2 keeps the
/// stage 1 line and adds the limit line under it (one message that grows; no animation now, PM 25-11 F-2).
library;

import 'package:flutter/material.dart';

import '../../../ui/widgets/tap_target.dart';
import '../../rules/rule_model.dart';
import '../levels/hard_rule_copy.dart';

// WORDING-MISSING -> W2: the category name is not known (a caller that does not pass it yet).
const String _kTodoPillCategory = '[PM to write: pill category when the category name is not known]';

/// Above this text size the stage 2 limit line and its button stack (the button goes under the line, at the end).
const double kRuleChangePillStackScale = 1.5;

/// The words of one pill. [line2] and [button] are only set at Auto-record stage 2; [button] only when there is a
/// callback for it.
class RuleChangePillLines {
  const RuleChangePillLines(this.line1, {this.line2, this.button});

  final String line1;
  final String? line2;
  final String? button;

  /// What the screen reader hears for this stage (the button is read on its own).
  String get spoken => line2 == null ? line1 : '$line1 $line2';
}

/// The lines for [level] at [stage2] (stage 2 is Auto-record only). [category] null or blank = the W2 placeholder.
RuleChangePillLines ruleChangePillLines({
  required String name,
  required RuleLevel level,
  required String? category,
  required int? limitCents,
  required bool stage2,
  required bool hasButton,
}) {
  final cat = (category == null || category.trim().isEmpty) ? _kTodoPillCategory : category;
  switch (level) {
    case RuleLevel.suggested:
      return RuleChangePillLines(hardPillSuggested(name));
    case RuleLevel.askFirst:
      return RuleChangePillLines(hardPillAskFirst(name, cat));
    case RuleLevel.autoRecord:
      final line1 = hardPillAuto(name, cat);
      if (!stage2) return RuleChangePillLines(line1);
      final noLimit = limitCents == null;
      return RuleChangePillLines(
        line1,
        line2: noLimit ? kHardPillAnyAmount : hardPillUpTo(limitCents),
        button: hasButton ? (noLimit ? kHardPillSetLimit : kHardPillChange) : null,
      );
  }
}

/// One stage of the pill's inside: the live region with the line(s), and at stage 2 the limit button (44 px).
class RuleChangePillBody extends StatelessWidget {
  const RuleChangePillBody({
    super.key,
    required this.lines,
    required this.ink,
    required this.accent,
    required this.onButton,
  });

  final RuleChangePillLines lines;
  final Color ink;
  final Color accent;
  final VoidCallback onButton;

  @override
  Widget build(BuildContext context) {
    final line1 = Text(
      lines.line1,
      style: TextStyle(color: ink, fontSize: 14, height: 1.3, fontWeight: FontWeight.w700),
    );
    final l2 = lines.line2;
    if (l2 == null) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 16, end: 18, top: 6, bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: Icon(Icons.check_circle_rounded, size: 18, color: accent)),
            const SizedBox(width: 10),
            Flexible(child: Semantics(container: true, liveRegion: true, child: line1)),
          ],
        ),
      );
    }
    final line2 = Text(l2, style: TextStyle(color: ink.withValues(alpha: 0.9), fontSize: 13, height: 1.3));
    final label = lines.button;
    final Widget? button = label == null
        ? null
        : TextButton(
            onPressed: onButton,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
            ),
            child: Text(label),
          );
    final stack = MediaQuery.textScalerOf(context).scale(14) / 14 > kRuleChangePillStackScale;
    final Widget second;
    if (button == null) {
      second = Padding(padding: const EdgeInsetsDirectional.only(end: 8, bottom: 8), child: line2);
    } else if (stack) {
      second = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: line2),
          Align(alignment: AlignmentDirectional.centerEnd, child: button),
        ],
      );
    } else {
      second = Row(
        children: [
          Expanded(child: line2),
          const SizedBox(width: 8),
          button,
        ],
      );
    }
    return Padding(
      padding: EdgeInsetsDirectional.only(start: 16, end: 8, top: 12, bottom: button == null ? 4 : 0),
      // One live region for the whole message: when the pill grows, the same region gains the limit line.
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: line1),
            const SizedBox(height: 4),
            second,
          ],
        ),
      ),
    );
  }
}
