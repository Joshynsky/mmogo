/// AUTOREAD SUGGESTED CHIPS (0.2.2, Part 1, signed by the PM on 24-11-2026): the pure rule that turns a
/// person's history into the category chips shown after a Parse tap (waiting card and Categorize sheet).
///
/// Rules (contract: _pipeline/v0.2.2/ITEM0-SUGGESTED-CATEGORIES-CONTRACT-AND-WBS-2026-11-24.md):
/// - [history] is the person's up-to-2 most used category ids of their last 10 records, most used FIRST
///   (what `HistoryReader.topTwo` returns). Null or empty gives no chips.
/// - Chips are listed LEFT TO RIGHT, so the most used is LAST (on the right, filled).
/// - A category that is no longer active (deleted or inactive) is dropped quietly.
/// - Paybill gets NO history chips in 0.2.2 (PM 24-11, held to 0.2.3). Only Send Money, Pochi and Buy Goods
///   (Till) do.
/// - At most 2 chips, no repeats.
library;

import '../rules/rule_model.dart';

/// The receiver kinds that get history chips in 0.2.2.
const Set<ReceiverType> kChipReceiverTypes = {ReceiverType.sendMoney, ReceiverType.pochi, ReceiverType.buyGoods};

/// The chips for one waiting item, left to right (most used last). Empty when there is nothing to show.
List<int> suggestedChips({
  required ReceiverType type,
  required List<int>? history,
  required Set<int> activeCategoryIds,
}) {
  if (!kChipReceiverTypes.contains(type)) return const <int>[];
  if (history == null || history.isEmpty) return const <int>[];
  final kept = <int>[];
  for (final id in history) {
    if (kept.length >= 2) break;
    if (activeCategoryIds.contains(id) && !kept.contains(id)) kept.add(id);
  }
  return kept.reversed.toList(growable: false);
}
