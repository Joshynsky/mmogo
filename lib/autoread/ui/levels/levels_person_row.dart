/// §AUTOREAD.LEVELS.PERSON_ROW: one person or account on the second tab: name,
/// type code, a detail line (categories) and the level button that opens the
/// level sheet.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import 'level_filter_row.dart' show levelTagText;
import 'levels_copy.dart';
import 'type_chips_row.dart';

/// Send Money people are keyed by phone number. Two numbers can share one name
/// (the same person on two phones), so the row ends with the last 3 digits.
String? phoneEnding(ReceiverType type, String key) {
  if (type != ReceiverType.sendMoney) return null;
  final digits = key.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 6) return null;
  return digits.substring(digits.length - 3);
}

/// What a row shows; built by the tab from rules, known names and history.
class LevelPerson {
  final ReceiverType type;
  final String key;
  final String name;
  final RuleLevel level;
  final int? categoryId;

  /// Most-used category ids (up to 2) from history, for the sheet's suggestions.
  final List<int> topIds;

  /// Category names for the detail line (rule category, or most-used ones).
  final List<String> categoryNames;
  const LevelPerson({
    required this.type,
    required this.key,
    required this.name,
    required this.level,
    this.categoryId,
    this.topIds = const [],
    this.categoryNames = const [],
  });
}

class LevelsPersonRow extends StatelessWidget {
  const LevelsPersonRow({super.key, required this.person, required this.onLevelTap});
  final LevelPerson person;
  final VoidCallback onLevelTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final chip = chipOf(person.type);
    final tag = levelTagText(person.level);
    final ending = phoneEnding(person.type, person.key);
    final detail = person.categoryNames.isEmpty ? kLevelsNoHistory : person.categoryNames.join(', ');
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: person.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.ink)),
                TextSpan(text: '  ${chip.code}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: chip.color(p))),
                if (ending != null)
                  TextSpan(text: '  …$ending', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.mutedInk)),
              ]),
            ),
            const SizedBox(height: 2),
            Text(detail, style: TextStyle(fontSize: 12, height: 1.35, color: p.mutedInk)),
          ]),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: levelButtonSpoken(ending == null ? person.name : '${person.name}, number ending $ending', tag),
          excludeSemantics: true,
          onTap: onLevelTap,
          child: InkWell(
            key: Key('levelButton.${person.type.code}.${person.key}'),
            borderRadius: BorderRadius.circular(999),
            onTap: onLevelTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: BoxDecoration(
                color: person.level == RuleLevel.suggested ? Colors.transparent : p.tint,
                border: Border.all(color: person.level == RuleLevel.suggested ? p.line : p.primary, width: 1.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tag, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink)),
                Icon(Icons.arrow_drop_down, size: 22, color: p.mutedInk),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
