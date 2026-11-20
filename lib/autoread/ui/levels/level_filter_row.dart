/// §AUTOREAD.LEVELS.FILTER_ROW: the level filter under the page title. 0.2.1
/// shows All, Suggested and Ask first; the 0.2.2 Auto-record level adds one
/// value to [LevelFilter] and nothing else here.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import 'levels_copy.dart';

enum LevelFilter {
  all(null, kLevelFilterAll),
  suggested(RuleLevel.suggested, kLevelSuggested),
  askFirst(RuleLevel.askFirst, kLevelAskFirst);

  final RuleLevel? level;
  final String label;
  const LevelFilter(this.level, this.label);

  bool matches(RuleLevel l) => level == null || level == l;
}

/// The words of a level tag.
String levelTagText(RuleLevel l) => switch (l) {
      RuleLevel.askFirst => kLevelAskFirst,
      _ => kLevelSuggested,
    };

class LevelFilterRow extends StatelessWidget {
  const LevelFilterRow({super.key, required this.value, required this.onChanged});
  final LevelFilter value;
  final ValueChanged<LevelFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Semantics(
        container: true,
        label: kLevelFilterGroup,
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          for (final f in LevelFilter.values)
            Semantics(
              button: true,
              selected: f == value,
              label: f.label,
              excludeSemantics: true,
              onTap: () => onChanged(f),
              child: InkWell(
                key: Key('levelFilter${f.name}'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => onChanged(f),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: f == value ? p.primary : Colors.transparent,
                    border: Border.all(color: f == value ? p.primary : p.line, width: 1.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(f.label,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: f == value ? p.onPrimary : p.ink)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
