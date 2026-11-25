/// §AUTOREAD.LEVELS.LEVEL_SHEET_OPEN: one person's level sheet, opened from anywhere, and the ONE save it
/// does (0.2.2 item 2, I1). The Remembered page's second tab and the offer pill's "Change ceiling" both use
/// it, so the save rules live in one place: Suggested KEEPS the rule (level Suggested, stored category
/// passed explicitly; PM 25-11), nobody without a rule gets one for Suggested, Ask first / Auto-record pass
/// the chosen category (the stored one when none) and the ceiling (Auto-record only). After a stored change
/// the notice ([LevelsDeps.notice]) follows while the Auto-record screens are on.
library;

import 'package:flutter/material.dart';

import '../../../ui/shell/app_messenger.dart' show appNavigatorKey;
import '../../logic/phone_mask.dart' show nameWithMask;
import '../../rules/rule_engine.dart' show Offer;
import '../../rules/rule_model.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'level_sheet.dart';
import 'levels_deps.dart';
import 'levels_person_row.dart';

/// The name the sheet and the notice use (masked number for Send Money).
String levelWho(LevelPerson x) => x.type == ReceiverType.sendMoney ? nameWithMask(x.name, x.key) : x.name;

/// Category id -> name, for the people's detail lines (ids that are not numbers are skipped).
Future<Map<int, String>> levelCategoryNames(LevelsDeps d) async =>
    {for (final c in await d.categories.categories()) if (int.tryParse(c.id) != null) int.parse(c.id): c.name};

/// The person as the page and the sheet see them. A rule above Suggested gives its level, category,
/// ceiling and mark; otherwise the person is Suggested with their most-used categories from history.
Future<LevelPerson> buildLevelPerson(
    LevelsDeps d, ReceiverType t, String key, String name, ReceiverRule? r, Map<int, String> cats) async {
  if (r != null && r.level != RuleLevel.suggested) {
    final id = r.categoryId;
    return LevelPerson(
        type: t,
        key: key,
        name: name,
        level: r.level,
        categoryId: id,
        categoryNames: [if (id != null && cats[id] != null) cats[id]!],
        ceilingCents: r.ceilingCents,
        autoPending: r.autoPending);
  }
  List<int>? top;
  try {
    top = await d.history.topTwo(t, key);
  } catch (_) {}
  final ids = top ?? const <int>[];
  return LevelPerson(
      type: t,
      key: key,
      name: name,
      level: RuleLevel.suggested,
      topIds: ids,
      categoryNames: [for (final i in ids) if (cats[i] != null) cats[i]!],
      autoPending: r?.autoPending ?? false);
}

/// The level sheet's save for [x]. [notify]: show the notice after a stored change (the Auto-record
/// screens are on); [onChangeCeiling] is offered on the notice for an Auto-record save only. The notice
/// never undoes a stored change (a throwing notice is ignored).
Future<LevelSaveResult> saveLevelChoice(LevelsDeps d, LevelPerson x, RuleLevel level, int? cat, int? ceilingCents,
    {required bool notify, VoidCallback? onChangeCeiling}) async {
  final ceiling = level == RuleLevel.autoRecord ? ceilingCents : null;
  try {
    final stored = await d.store.get(x.type, x.key);
    final bool ok;
    if (level == RuleLevel.suggested) {
      // No rule = already Suggested: nothing is saved, so no notice either.
      if (stored == null) return LevelSaveResult.ok;
      ok = await d.store.setLevel(x.type, x.key,
          name: x.name, level: RuleLevel.suggested, categoryId: stored.categoryId, at: d.now());
    } else {
      ok = await d.store.setLevel(x.type, x.key,
          name: x.name, level: level, categoryId: cat ?? stored?.categoryId, ceilingCents: ceiling, at: d.now());
    }
    if (!ok) return LevelSaveResult.capReached;
  } catch (_) {
    return LevelSaveResult.failed;
  }
  if (notify) {
    try {
      d.notice.show(levelWho(x), level, ceiling, level == RuleLevel.autoRecord ? onChangeCeiling : null);
    } catch (_) {}
  }
  return LevelSaveResult.ok;
}

/// Opens the level sheet of one person read fresh from the store ([focusCeiling]: the ceiling field has
/// the focus). A save's "Change ceiling" opens it again on the app navigator. A failed read opens nothing.
Future<void> openLevelSheetFor(BuildContext context, LevelsDeps d, ReceiverType t, String key, String name,
    {bool focusCeiling = false}) async {
  final LevelPerson x;
  try {
    final r = await d.store.get(t, key);
    x = await buildLevelPerson(d, t, key, r?.name ?? name, r, await levelCategoryNames(d));
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await showLevelSheet(context,
      person: x,
      categories: d.choicesFor(t),
      focusCeiling: focusCeiling,
      onSave: (l, c, {ceilingCents}) => saveLevelChoice(d, x, l, c, ceilingCents,
          notify: autoRecordUi, onChangeCeiling: () => openCeilingSheetOnApp(d, t, key, x.name)));
}

/// The sheet with the ceiling focused, on the app navigator (a pill's button has no page context).
/// Nothing when the app navigator is not up.
void openCeilingSheetOnApp(LevelsDeps d, ReceiverType t, String key, String name) {
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null) return;
  openLevelSheetFor(ctx, d, t, key, name, focusCeiling: true);
}

/// The offer pill's "Change ceiling" (suggestions controller): the offered person's sheet, ceiling
/// focused, with the app's [LevelsDeps.instance] (none = nothing).
void openOfferCeilingSheet(Offer o) {
  final d = LevelsDeps.instance;
  if (d == null) return;
  openCeilingSheetOnApp(d, o.type, o.key, o.name);
}
