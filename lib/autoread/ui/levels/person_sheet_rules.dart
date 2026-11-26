/// §AUTOREAD.LEVELS.PERSON_SHEET_RULES: the pure choices of the 0.2.2 person sheet (item 2 redesign, slice
/// U-PERSON; mock-remembered-v2 p-*): the fixed height, where the level and the category start, which line
/// sits under the category, and the "How ... works" box of each level. No widgets, no store.
library;

import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'levels_person_row.dart';

/// The person sheet's one height, as a share of the screen height (mock p-*: the Auto-record layout, the
/// tallest one). Every level uses it, so the sheet never jumps when the level changes; the body scrolls.
const double kPersonSheetHeightFactor = 0.88;

/// Above this text scale the level buttons and the footer buttons stack (200% text never clips).
const double kPersonSheetStackScale = 1.5;

/// Stands in for a category not chosen yet inside the "How ..." text (the mock's `&hellip;`,
/// p-wait: 'asks "Record as …?"'). Punctuation, not words.
const String kPersonSheetNoCategoryMark = '…';

/// The level the sheet opens on. A stored Auto-record the type cannot hold (the store never writes one)
/// opens on Ask first, its highest level.
RuleLevel personSheetStartLevel(LevelPerson x) {
  if (x.level == RuleLevel.autoRecord && !canHoldAutoRecord(x.type)) return RuleLevel.askFirst;
  return x.level;
}

/// The category the sheet starts with: the rule's own, else the most-used one from history (mock p-ask:
/// pre-filled, [fromHistory] = true). None = the person must choose.
({int? id, bool fromHistory}) personSheetStartCategory(LevelPerson x) {
  if (x.categoryId != null) return (id: x.categoryId, fromHistory: false);
  if (x.topIds.isNotEmpty) return (id: x.topIds.first, fromHistory: true);
  return (id: null, fromHistory: false);
}

/// The start category once the person's own group is known ([offered] = its ids). Kept when offered;
/// otherwise the first most-used one that is offered (pre-filled), else none.
({int? id, bool fromHistory}) personSheetFitCategory(
  LevelPerson x,
  ({int? id, bool fromHistory}) start,
  Set<int> offered,
) {
  if (start.id != null && offered.contains(start.id)) return start;
  final top = [
    for (final i in x.topIds)
      if (offered.contains(i)) i,
  ].firstOrNull;
  return top == null ? (id: null, fromHistory: false) : (id: top, fromHistory: true);
}

/// The small line under the category (mock p-ask, p-wait): "Most used, you can change it." for a pre-filled
/// category, nothing for a chosen or stored one; with no category, the "only payment is still waiting" line
/// when the person has exactly one payment (it has no category, or it would be pre-filled), else the
/// "choose a category" line.
String? personSheetCategoryHint({
  required bool hasCategory,
  required bool fromHistory,
  required String name,
  int? paymentCount,
}) {
  if (hasCategory) return fromHistory ? kHardCategoryMostUsed : null;
  return paymentCount == 1 ? hardCategoryWaiting(name) : kHardCategoryNeed;
}

/// The heading of the level's "How ... works" box.
String personSheetHowTitle(RuleLevel l) => switch (l) {
  RuleLevel.suggested => kHardSuggestHowTitle,
  RuleLevel.askFirst => kHardAskHowTitle,
  RuleLevel.autoRecord => kHardAutoHowTitle,
};

/// The paragraph of the level's box. Suggested: the sheet's Suggested note (PM 25-11, plan section 11: no
/// "Suggest from:" choice and no "How Suggest works" texts in 0.2.2). [category] null = not chosen yet.
String personSheetHowText(RuleLevel l, String name, String? category) => switch (l) {
  RuleLevel.suggested => hardSheetNoteSuggested(name),
  RuleLevel.askFirst => hardAskHow(name, category ?? kPersonSheetNoCategoryMark),
  RuleLevel.autoRecord => hardAutoHow(name, category ?? kPersonSheetNoCategoryMark),
};

/// The words on a level button (mock p-*: "Suggest", "Ask first", "Auto-record").
String personSheetLevelButton(RuleLevel l) => l == RuleLevel.suggested ? kHardLevelSuggestButton : hardRuleLevelName(l);
