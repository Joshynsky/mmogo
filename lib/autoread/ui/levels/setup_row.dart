/// §AUTOREAD.LEVELS.SETUP_ROW: one recipient in the Set up sheet (0.2.2 item 2, slice U-SETUP; mock-remembered-v2
/// setup-half, rows style B). Top line: the name, and at the end the masked number (Send Money) or else
/// "{k} payments". Second line: the payment type, plus "{k} payments" when the number took the end slot. A level
/// tag on rows already set up (Ask first, Auto-record; Suggested is the default, so no tag: the chosen
/// Suggest lists that made the mock tag it are 0.2.3). Plain text, no boxes behind name or number.
/// PRIVACY: draws [SetupRecipient.displayName] and [SetupRecipient.maskedNumber] ONLY. Never [SetupRecipient.key]
/// (a Send Money key is the full phone number). Paybill rows of one business with several accounts share a
/// name (the port has no account field). At large text the end slot and the tag go under the name.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/tap_target.dart' show kMinTapTarget;
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'setup_ports.dart';
import 'setup_type_chips.dart';

/// The payment type's name (the chip names, one source).
String setupRowTypeName(SetupRecipient r) => setupTypeChip(r.type).$2;

/// The end of the top line: the masked number, else "{k} payments".
String setupRowEnd(SetupRecipient r) => r.maskedNumber ?? hardPaymentsCount(r.paymentCount);

/// The second line: the type, plus "{k} payments" when the number took the end slot.
String setupRowLine(SetupRecipient r) => [
      setupRowTypeName(r),
      if (r.maskedNumber != null) hardPaymentsCount(r.paymentCount),
    ].join(' · ');

/// The level tag, or null (no rule yet, or Suggested).
RuleLevel? setupRowTag(SetupRecipient r) => r.level == RuleLevel.suggested ? null : r.level;

/// What a screen reader says: the row's visible words, in reading order (no new words, no key).
String setupRowSpoken(SetupRecipient r) {
  final tag = setupRowTag(r);
  return [
    r.displayName,
    if (r.maskedNumber != null) r.maskedNumber!,
    setupRowTypeName(r),
    hardPaymentsCount(r.paymentCount),
    if (tag != null) hardRuleLevelName(tag),
  ].join(', ');
}

/// Text scale from which the row stacks its parts (the end slot and the tag go under the name).
const double kSetupRowStackScale = 1.5;

class SetupRow extends StatelessWidget {
  const SetupRow({super.key, required this.recipient, required this.onTap, this.focusNode});
  final SetupRecipient recipient;
  final VoidCallback onTap;

  /// The row's focus (the sheet puts the focus back here after the person sheet closes).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final r = recipient;
    final tag = setupRowTag(r);
    final stack = MediaQuery.textScalerOf(context).scale(10) >= 10 * kSetupRowStackScale;
    final name = Text(r.displayName,
        key: const Key('setupRowName'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink));
    final end = Text(setupRowEnd(r),
        key: const Key('setupRowEnd'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.softInk));
    final line = Text(setupRowLine(r),
        key: const Key('setupRowLine'), style: TextStyle(fontSize: 12.5, height: 1.35, color: p.mutedInk));
    final tagW = tag == null ? null : SetupLevelTag(level: tag);

    final Widget body = stack
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            name,
            end,
            line,
            if (tagW != null) Padding(padding: const EdgeInsets.only(top: 4), child: tagW),
          ])
        : Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // On a narrow row the end slot moves under the name instead of overflowing.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [name, end],
                ),
                const SizedBox(height: 2),
                line,
              ]),
            ),
            if (tagW != null) ...[const SizedBox(width: 8), tagW],
          ]);

    return Semantics(
      button: true,
      label: setupRowSpoken(r),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTapTarget + 12),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 14, 10),
          child: body,
        ),
      ),
    );
  }
}

/// The level tag: an outlined pill with the level's name (the words carry the meaning; the border colour only
/// helps: amber for Auto-record, the primary colour for Ask first).
class SetupLevelTag extends StatelessWidget {
  const SetupLevelTag({super.key, required this.level});
  final RuleLevel level;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final border = switch (level) {
      RuleLevel.autoRecord => p.sun,
      RuleLevel.askFirst => p.primary,
      RuleLevel.suggested => p.line,
    };
    return Container(
      key: Key('setupTag.${level.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Text(hardRuleLevelName(level),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.ink, height: 1.2)),
    );
  }
}
