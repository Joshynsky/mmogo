/// §AUTOREAD.LEVELS.LEVEL_SHEET_OPEN: one person's level sheet, opened from anywhere, and the ONE save it
/// does (0.2.2 item 2, I1). The Remembered page's second tab and the offer pill's "Change ceiling" both use
/// it, so the save rules live in one place: Suggested KEEPS the rule (level Suggested, stored category and
/// stored chosen Suggest list passed through unchanged; PM 25-11), nobody without a rule gets one for
/// Suggested, Ask first / Auto-record pass the chosen category (the stored one when none) and the limit
/// (Auto-record only). After a stored change the notice ([LevelsDeps.notice]) follows while the Auto-record
/// screens are on, with the PLAIN name (never a number; redesign U-PERSON) and the category's name.
library;

import 'package:flutter/material.dart';

import '../../../ui/shell/app_messenger.dart' show appNavigatorKey;
import '../../logic/phone_mask.dart' show nameWithMask;
import '../../logic/plain_name.dart' show pillPersonName;
import '../../rules/rule_engine.dart' show Offer;
import '../../rules/rule_model.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'level_sheet.dart';
import 'levels_deps.dart';
import 'levels_person_row.dart';

/// The name with the masked number for Send Money (the 0.2.1 sheet's title). Never for the notice.
String levelWho(LevelPerson x) => x.type == ReceiverType.sendMoney ? nameWithMask(x.name, x.key) : x.name;

/// The name the notice (the pill) gets: the plain name only, never the number or its mask (sign-off
/// "Pill: no phone number"). A nameless Send Money person's name can be the masked number (Set up's
/// displayName) or the full number (a rule named by its key), so it goes through [pillPersonName] (I2c):
/// no digit and no '*' is left; nothing left = the W2 placeholder.
String levelNoticeName(LevelPerson x) => pillPersonName(x.name);

/// The name of category [id] in [type]'s own group; null when it is not there or the list cannot be read.
Future<String?> levelCategoryName(LevelsDeps d, ReceiverType type, int id) async {
  try {
    final list = await d.choicesFor(type).categories();
    return list.where((c) => int.tryParse(c.id) == id).map((c) => c.name).firstOrNull;
  } catch (_) {
    return null;
  }
}

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
/// never undoes a stored change (a throwing notice, or a category list that cannot be read, is ignored).
/// The notice gets the plain name ([levelNoticeName]) and the saved category's name (none at Suggested).
Future<LevelSaveResult> saveLevelChoice(LevelsDeps d, LevelPerson x, RuleLevel level, int? cat, int? ceilingCents,
    {required bool notify, VoidCallback? onChangeCeiling}) async {
  final ceiling = level == RuleLevel.autoRecord ? ceilingCents : null;
  int? savedCat;
  try {
    final stored = await d.store.get(x.type, x.key);
    final bool ok;
    if (level == RuleLevel.suggested) {
      // No rule = already Suggested: nothing is saved, so no notice either.
      if (stored == null) return LevelSaveResult.ok;
      // Suggested keeps the rule: the stored category and the stored chosen Suggest list go back in
      // unchanged (setLevel stores the list exactly as passed; leaving it out would wipe it).
      ok = await d.store.setLevel(x.type, x.key,
          name: x.name,
          level: RuleLevel.suggested,
          categoryId: stored.categoryId,
          chosenCategoryIds: stored.chosenCategoryIds,
          at: d.now());
    } else {
      savedCat = cat ?? stored?.categoryId;
      ok = await d.store.setLevel(x.type, x.key,
          name: x.name, level: level, categoryId: savedCat, ceilingCents: ceiling, at: d.now());
    }
    if (!ok) return LevelSaveResult.capReached;
  } catch (_) {
    return LevelSaveResult.failed;
  }
  if (notify) {
    final catName = savedCat == null ? null : await levelCategoryName(d, x.type, savedCat);
    try {
      d.notice.show(levelNoticeName(x), level, ceiling, level == RuleLevel.autoRecord ? onChangeCeiling : null,
          categoryName: catName);
    } catch (_) {}
  }
  return LevelSaveResult.ok;
}

/// The person's payment count for the sheet's "{k} payments": [given] when the caller knows it (the Set up
/// list), else read from [LevelsDeps.setup] (null when there is no Set up source, no row, or it fails).
Future<int?> levelPaymentCount(LevelsDeps d, ReceiverType t, String key, {int? given}) async {
  if (given != null) return given;
  final setup = d.setup;
  if (setup == null) return null;
  try {
    return (await setup.list(type: t)).where((r) => r.key == key).map((r) => r.paymentCount).firstOrNull;
  } catch (_) {
    return null;
  }
}

/// Opens the level sheet of one person read fresh from the store ([focusCeiling]: the limit field has
/// the focus). A save's "Set a limit" / "Change" opens it again on the app navigator. A failed read opens
/// nothing. The 0.2.2 sheet gets the chips picker ([LevelsDeps.pickCategories]) and the payment count
/// ([paymentCount], else read from the Set up source).
Future<void> openLevelSheetFor(BuildContext context, LevelsDeps d, ReceiverType t, String key, String name,
    {bool focusCeiling = false, int? paymentCount}) async {
  final LevelPerson x;
  final int? count;
  try {
    final r = await d.store.get(t, key);
    x = await buildLevelPerson(d, t, key, r?.name ?? name, r, await levelCategoryNames(d));
    count = autoRecordUi ? await levelPaymentCount(d, t, key, given: paymentCount) : null;
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await showLevelSheet(context,
      person: x,
      categories: d.choicesFor(t),
      focusCeiling: focusCeiling,
      pickCategories: d.pickCategories,
      paymentCount: count,
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
