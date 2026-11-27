/// §AUTOREAD.LEVELS.PEOPLE_COUNT: how many people the Suggest and auto-record tab lists (Suggested +
/// Ask first + Auto-record, each person once). The same rule the tab uses: every rule (a Pochi rule only
/// when the name is remembered) plus every remembered person who has no rule yet. A count only, never a
/// name. Used by the Settings "Remembered" row and by the Remembered page to choose its first tab.
library;

import '../../rules/rule_model.dart';
import 'levels_deps.dart';

Future<int> levelsPeopleCount(LevelsDeps d) async {
  final rules = await d.store.all();
  final known = d.known == null ? const <KnownPerson>[] : await d.known!();
  final knownPochi = {for (final k in known) if (k.type == ReceiverType.pochi) k.key};
  final ids = <String>{
    for (final r in rules)
      if (!(r.type == ReceiverType.pochi && !knownPochi.contains(r.key))) '${r.type.code}.${r.key}',
    for (final k in known) '${k.type.code}.${k.key}',
  };
  return ids.length;
}
