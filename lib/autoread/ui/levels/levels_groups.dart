/// §AUTOREAD.LEVELS.GROUPS: the people of the Remembered page's second tab in sections by level (layout A,
/// 0.2.2 U5): Auto-record first, then Ask first, then Suggested (folded by default, "Show {n}"). Each header
/// shows the level name and its count and folds or opens its section; a section with nobody is not drawn.
/// While a search text is present every section opens and only matches show; no match = "Nobody matches.".
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'levels_person_row.dart';
import 'levels_search.dart';

/// Section order: the riskiest level first.
const List<RuleLevel> kLevelGroupOrder = [RuleLevel.autoRecord, RuleLevel.askFirst, RuleLevel.suggested];

/// Folded when the page opens.
const Set<RuleLevel> kLevelGroupsFoldedAtStart = {RuleLevel.suggested};

/// The people of one level, by name.
List<LevelPerson> peopleAt(List<LevelPerson> all, RuleLevel l) {
  final out = [for (final x in all) if (x.level == l) x];
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

class LevelsGroups extends StatelessWidget {
  const LevelsGroups({
    super.key,
    required this.people,
    required this.query,
    required this.folded,
    required this.onToggle,
    required this.rowBuilder,
  });

  final List<LevelPerson> people;
  final String query;
  final Set<RuleLevel> folded;
  final ValueChanged<RuleLevel> onToggle;
  final Widget Function(LevelPerson person) rowBuilder;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final searching = query.trim().isNotEmpty;
    final children = <Widget>[];
    for (final l in kLevelGroupOrder) {
      final all = peopleAt(people, l);
      if (all.isEmpty) continue;
      final shown = [for (final x in all) if (levelPersonMatches(x, query)) x];
      if (searching && shown.isEmpty) continue;
      final open = searching || !folded.contains(l);
      children.add(_Header(level: l, count: all.length, open: open, searching: searching, onTap: () => onToggle(l)));
      if (open) {
        for (final (i, x) in shown.indexed) {
          children.add(DecoratedBox(
            decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
            child: rowBuilder(x),
          ));
        }
      }
    }
    if (children.isEmpty && searching) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 8),
        child: Semantics(
          liveRegion: true,
          child: Text(kHardSearchEmpty,
              key: const Key('levelsSearchEmpty'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.mutedInk)),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.level, required this.count, required this.open, required this.searching, required this.onTap});
  final RuleLevel level;
  final int count;
  final bool open;
  final bool searching;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final name = hardGroupName(level);
    final color = level == RuleLevel.autoRecord ? p.typeAirtime : p.mutedInk;
    final action = open ? kHardGroupHide : hardGroupShow(count);
    // While searching every section is open; the header does not fold it then.
    final VoidCallback? tap = searching ? null : onTap;
    return Semantics(
      key: Key('levelGroup.${level.name}'),
      header: true,
      button: tap != null,
      expanded: open,
      label: '$name, $count',
      onTap: tap,
      excludeSemantics: true,
      child: InkWell(
        onTap: tap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(16, 10, 14, 4),
          child: Row(children: [
            Flexible(
              child: Text(name.toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: color)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(999)),
              child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.tintInk)),
            ),
            const Spacer(),
            if (!searching)
              Text(action,
                  key: Key('levelGroupToggle.${level.name}'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.primary)),
          ]),
        ),
      ),
    );
  }
}
