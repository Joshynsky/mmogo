/// §AUTOREAD.LEVELS.GROUPS: the people of the Remembered page's second tab in folded groups by level
/// (0.2.2 item 2 redesign, mock-remembered-v2 page-all / page-open / page-auto): Suggested, Ask first,
/// Auto-record, each a card with the level name, its count and Show / Hide. At most ONE group is open:
/// opening one closes the other (mock page-open). A group with nobody is not drawn. No chips and no search
/// on the page (search lives in the Set up sheet). The header's spoken label says the level, the count and
/// what a tap does ("Show n" / "Hide"), and carries the expanded state.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/tap_target.dart' show kMinTapTarget;
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'levels_person_row.dart';

/// Group order on the page, top to bottom (mock page-all).
const List<RuleLevel> kLevelGroupOrder = [RuleLevel.suggested, RuleLevel.askFirst, RuleLevel.autoRecord];

/// The people of one level, by name.
List<LevelPerson> peopleAt(List<LevelPerson> all, RuleLevel l) {
  final out = [for (final x in all) if (x.level == l) x];
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// The group open when the page first shows people: Auto-record (signed, Suggested and Ask first closed).
/// Decision in code (U-PAGE): with nobody on Auto-record that group is not drawn, so Ask first opens
/// instead (mock page-noauto); with nobody there either, everything stays closed (Suggested is never
/// opened by itself).
RuleLevel? initialOpenGroup(List<LevelPerson> all) {
  if (all.any((x) => x.level == RuleLevel.autoRecord)) return RuleLevel.autoRecord;
  if (all.any((x) => x.level == RuleLevel.askFirst)) return RuleLevel.askFirst;
  return null;
}

/// The next open group after a tap on [tapped]'s header: the open one closes, any other opens alone.
RuleLevel? toggledGroup(RuleLevel? open, RuleLevel tapped) => open == tapped ? null : tapped;

class LevelsGroups extends StatelessWidget {
  const LevelsGroups({
    super.key,
    required this.people,
    required this.open,
    required this.onToggle,
    required this.rowBuilder,
  });

  final List<LevelPerson> people;

  /// The one open group (null = all closed).
  final RuleLevel? open;
  final ValueChanged<RuleLevel> onToggle;
  final Widget Function(LevelPerson person) rowBuilder;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final children = <Widget>[];
    for (final l in kLevelGroupOrder) {
      final all = peopleAt(people, l);
      if (all.isEmpty) continue;
      final isOpen = open == l;
      children.add(Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Header(level: l, count: all.length, open: isOpen, onTap: () => onToggle(l)),
          if (isOpen)
            for (final x in all)
              DecoratedBox(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                child: rowBuilder(x),
              ),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.level, required this.count, required this.open, required this.onTap});
  final RuleLevel level;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final name = hardGroupName(level);
    final action = open ? kHardGroupHide : hardGroupShow(count);
    return Semantics(
      key: Key('levelGroup.${level.name}'),
      header: true,
      button: true,
      expanded: open,
      label: '$name, $count, $action',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTapTarget + 8),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
          // Item 4 emulator look (200% text): a Row squeezed the title until it broke mid-word
          // ("Sugges/ted"). A Wrap keeps the title whole and drops the action to its own line.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(999)),
                  child: Text('$count', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.tintInk)),
                ),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(action,
                    key: Key('levelGroupToggle.${level.name}'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.primary)),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 20, color: p.primary),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
