import '../../domain/format/money.dart';

/// 0.2.1 — every word of the "withdrawal with a linked Cash entry" screens.
/// WORDING-DRAFT: all lines in this file are drafts for the PM to sign.

// WORDING-DRAFT
const String kWdQuestion = 'What was this money for?';
const String kWdCashOnly = 'Cash only';
const String kWdFromWithdrawalTag = 'from withdrawal';
const String kWdChangeAlsoChanges = 'Changing the category here also changes the linked Cash entry.';

/// "→ Rent" / "→ Rent, Groceries": the small line on a withdrawal row.
String wdArrowText(List<String> names) => '→ ${names.join(', ')}';

/// Cash entry title: "Cash — Rent".
String wdCashTitle(String category) => 'Cash — $category';

// WORDING-DRAFT: the sentence under the chips (Analytics withdrawal sheet).
String wdSentenceNoEntry({required int? categoryId, required String? categoryName, required int amountCents, required int feeCents, required String dayText}) =>
    categoryId == null
        ? 'Save records the withdrawal with only its fee of ${formatKsh(feeCents)} counted. Nothing else is added.'
        : 'Save adds ${wdCashTitle(categoryName ?? '')} for ${formatKsh(amountCents)}, counted as spent on $dayText.';

// WORDING-DRAFT
String wdSentenceOneEntry({
  required int? categoryId,
  required String? categoryName,
  required String entryCategory,
  required int entryCents,
  required int withdrawalCents,
}) {
  if (categoryId == null) {
    return 'Save removes the linked ${wdCashTitle(entryCategory)} entry. The withdrawal stays, only its fee is counted.';
  }
  if (categoryName != entryCategory) {
    return 'Save moves the linked Cash entry from $entryCategory to ${categoryName ?? ''}.';
  }
  final left = withdrawalCents - entryCents;
  return '${wdCashTitle(entryCategory)} is linked: ${formatKsh(entryCents)} of ${formatKsh(withdrawalCents)} spent'
      '${left > 0 ? '; ${formatKsh(left)} is still cash, not spent.' : '.'}';
}

// WORDING-DRAFT
String wdSentenceSplit({required int count, required int spentCents, required int stillCashCents}) =>
    'This withdrawal is split into $count Cash entries (${formatKsh(spentCents)} spent, '
    '${formatKsh(stillCashCents)} still cash). Change each one on its own below.';

// WORDING-DRAFT: the sentence on Add (type W) and on Notifications' Categorize sheet.
String wdSentenceAdd({required int? categoryId, required String? categoryName, required int? amountCents}) => categoryId == null
    ? 'Save records the withdrawal with only its fee counted. Nothing else is added.'
    : 'Save adds ${wdCashTitle(categoryName ?? '')}${amountCents == null ? '' : ' for ${formatKsh(amountCents)}'}, counted as spent.';

// WORDING-DRAFT: the "Spent on" line of Add's "Check before saving" (type W).
String wdReviewSpentOn({required String? categoryName, required int amountCents}) => categoryName == null
    ? 'Cash only (only the fee is counted)'
    : '$categoryName (adds ${wdCashTitle(categoryName)}, ${formatKsh(amountCents)})';

// WORDING-DRAFT: linked entry sheet.
const String kWdEntrySameDate = 'Same as the withdrawal.';
const String kWdAddAnother = 'Add another entry from this withdrawal';
const String kWdNothingLeft = 'Nothing left to add';
const String kWdNewEntry = 'new entry';
const String kWdSavedEntry = 'saved';
String wdEntryFromLine(int withdrawalCents, String dayText) => 'From a withdrawal. ${formatKsh(withdrawalCents)} taken out on $dayText.';
String wdEntryRestWords(int stillCents, int maxCents) =>
    '${stillCents > 0 ? '${formatKsh(stillCents)} of the withdrawal stays as cash, not spent.' : 'All of the withdrawal is spent.'}'
    ' You can enter up to ${formatKsh(maxCents)} here (what is left of the withdrawal).';

// WORDING-DRAFT: prompts.
const String kWdDeleteWithdrawalTitle = 'Delete this withdrawal?';
const String kWdCancel = 'Cancel';
const String kWdDeleteBoth = 'Delete both';
const String kWdDelete = 'Delete';
const String kWdKeepWithdrawal = 'Keep withdrawal';
const String kWdDeleteWithdrawalToo = 'Delete withdrawal too';
const String kWdRemoveLinked = 'Remove it';
const String kWdKeepIt = 'Keep it';
String wdDeleteBothBody(int withdrawalCents, List<String> parts) =>
    'This deletes the withdrawal (${formatKsh(withdrawalCents)}) and its Cash ${parts.length > 1 ? 'entries' : 'entry'} (${parts.join(', ')}), both. You can undo for 1 hour.';
String wdDeletePlainBody(int feeCents) =>
    '${feeCents > 0 ? 'Only its fee of ${formatKsh(feeCents)} was counted. ' : ''}You can undo for 1 hour.';
String wdDeleteEntryTitle(String category) => 'Delete ${wdCashTitle(category)}?';
String wdDeleteEntryBody(int withdrawalCents) =>
    'This entry came from a withdrawal of ${formatKsh(withdrawalCents)}. Keep the withdrawal, or delete it too. You can undo for 1 hour.';
const String kWdCashOnlyAskTitle = 'Go back to Cash only?';
String wdCashOnlyAskBody(int count) =>
    'This removes the linked Cash ${count > 1 ? 'entries' : 'entry'} from your spending. The withdrawal stays, only its fee is counted.';
const String kWdMovedBoth = 'Withdrawal and its Cash entry moved to Recently Deleted';
const String kWdMovedEntryKept = 'Cash entry moved to Recently Deleted. The withdrawal stays.';

// WORDING-DRAFT: Notifications (auto-read build).
const String kWdTodoRowCashOnly = 'Cash only';
String wdDecisionTitle(int n) => n == 1 ? '1 withdrawal needs a decision' : '$n withdrawals need a decision';
const String kWdDecisionHelp = 'Choose Cash only, or the category the money went to.';
const String kWdDecisionReview = 'Review';
const String kWdDecisionDone = 'All decided';
const String kWdDecisionReviewHelp = 'These came before this update, or were not decided yet. Each one can stay cash only or get a category.';
// WORDING-DRAFT: the "Cash only for all" button on the decision Review sheet and its confirm.
const String kWdCashOnlyAll = 'Cash only for all';
String wdCashOnlyAllTitle(int n) => 'Cash only for all $n?';
const String kWdCashOnlyAllBody =
    'Each of these withdrawals stays cash only: only its fee counts, nothing else is added. You can still categorize any of them later from Analytics.';
const String kWdCashOnlyAllCancel = 'Cancel';
const String kWdCashOnlyAllError = 'Could not save. Try again.';
String wdAddCashButton(String category) => 'Add ${wdCashTitle(category)}';

// WORDING-DRAFT: Add, when the withdrawal saved but its Cash entry did not.
const String kWdLinkedNotAdded =
    'The withdrawal was saved, but its Cash entry could not be added. Open the withdrawal in Analytics to add it.';
