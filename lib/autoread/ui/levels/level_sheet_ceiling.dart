/// §AUTOREAD.LEVELS.LEVEL_SHEET_CEILING: the level sheet's Auto-record ceiling ("Ask first above Ksh"):
/// the pure parser [parseCeiling] and the field [CeilingField] drawn inside the Auto-record option
/// (mock lvl-tim / lvl-amina / lvl-mboga). Empty = no ceiling. Whole shillings only, stored as cents.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart' show kCeilingMaxCents;
import 'hard_rule_copy.dart';

/// Why a ceiling text was refused.
enum CeilingProblem { bad, tooHigh }

/// The result of [parseCeiling]: [cents] (null = no ceiling) when [problem] is null.
class CeilingParse {
  const CeilingParse.ok(this.cents) : problem = null;
  const CeilingParse.refused(CeilingProblem this.problem) : cents = null;
  final int? cents;
  final CeilingProblem? problem;
  bool get ok => problem == null;
}

// Plain digits, or commas as thousands separators only (first group 1-3 digits, every later group
// exactly 3). No leading zero in either form, so "0", "0500" and "0,500" are refused.
final RegExp _wellFormed = RegExp(r'^(?:[1-9][0-9]*|[1-9][0-9]{0,2}(?:,[0-9]{3})+)$');

/// Parses the field text. Trimmed; empty = no ceiling; plain digits or thousands commas (1,500 / 12,000;
/// never 1,5,00 / 15,50 / ,500 / 1,50); no leading zero; whole shillings above 0 and at most
/// Ksh 1,000,000 ([kCeilingMaxCents]); returned as cents (x100). Anything else is refused:
/// [CeilingProblem.tooHigh] above the cap, [CeilingProblem.bad] for the rest (letters, "0", "1.5", ",").
CeilingParse parseCeiling(String text) {
  final t = text.trim();
  if (t.isEmpty) return const CeilingParse.ok(null);
  if (!_wellFormed.hasMatch(t)) return const CeilingParse.refused(CeilingProblem.bad);
  final digits = t.replaceAll(',', '');
  // More digits than the cap has: above the cap (and never overflows an int).
  if (digits.length > 7) return const CeilingParse.refused(CeilingProblem.tooHigh);
  final cents = int.parse(digits) * 100;
  if (cents > kCeilingMaxCents) return const CeilingParse.refused(CeilingProblem.tooHigh);
  return CeilingParse.ok(cents);
}

/// The text a stored ceiling shows in the field: whole shillings, plain digits as the mock draws it.
String ceilingFieldText(int? cents) => cents == null ? '' : '${cents ~/ 100}';

/// The error line for a refused text.
String ceilingProblemText(CeilingProblem p) => switch (p) {
  CeilingProblem.bad => kHardCeilingError,
  CeilingProblem.tooHigh => kTodoHardCeilingTooHigh,
};

/// "Ask first above Ksh" with the "Ksh" prefix, the hint line, or the error line (announced) instead.
class CeilingField extends StatelessWidget {
  const CeilingField({super.key, required this.controller, this.focusNode, this.problem, this.onChanged});
  final TextEditingController controller;
  final FocusNode? focusNode;
  final CeilingProblem? problem;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final bad = problem;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: 1.5),
    );
    return Container(
      key: const Key('ceilingBox'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              kHardCeilingLabel,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              ExcludeSemantics(
                child: Text(
                  kHardCeilingPrefix,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.ink),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  label: kHardCeilingLabel,
                  child: TextField(
                    key: const Key('ceilingInput'),
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: TextInputType.number,
                    onChanged: onChanged,
                    style: TextStyle(fontSize: 15, color: p.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      constraints: const BoxConstraints(minHeight: 44),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      hintText: kHardLimitNotSet,
                      hintStyle: TextStyle(color: p.mutedInk),
                      filled: true,
                      fillColor: p.card,
                      enabledBorder: border(bad == null ? p.line : p.error),
                      focusedBorder: border(bad == null ? p.primary : p.error),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (bad == null)
            Text(
              kHardLimitEmptyHint,
              key: const Key('ceilingHint'),
              style: TextStyle(fontSize: 12, height: 1.35, color: p.mutedInk),
            )
          else
            Semantics(
              liveRegion: true,
              child: Text(
                ceilingProblemText(bad),
                key: const Key('ceilingError'),
                style: TextStyle(fontSize: 12, height: 1.35, color: p.error, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
