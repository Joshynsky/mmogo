/// §AUTOREAD.WAITING_SECTION — the To do view's lists, built on [WaitingRow].
/// Autoread build only: shared code reaches it inside `if (kAutoReadCompiled)`.
/// Sorting and counts come from `waiting_logic.dart`; nothing is re-implemented.
/// Rows take callbacks only (no repository); the page wires them.
/// 0.2.2 (I1): while the Auto-record screens are on and a pause port exists, the amber paused banner sits
/// at the top of To do (mock ctl-a-todo), and an Ask first row gets its hint so the paused tag can show.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../data/db/analytics_dao.dart' show AnalyticsTransactionRow;
import '../../ui/widgets/collapsing_padding.dart';
import '../../ui/widgets/pill_toast.dart';

import '../logic/airtime_auto.dart';
import '../model/held_description.dart';
import '../model/rule_hint.dart';
import '../model/waiting_item.dart';
import 'category_choices.dart';
import 'decision_item.dart';
import 'levels/hard_rule_confirm_dialog.dart';
import 'levels/hard_rule_paused_banner.dart';
import 'levels/hard_rule_ports.dart' show HardRulePausePort, autoRecordUi;
import 'levels/levels_deps.dart' show LevelsDeps;
import 'notifications/ask_first_row.dart';
import 'notifications/notifications_rule_copy.dart';
import 'notifications/recorded_auto_section.dart';
import 'notifications/suggestion_card.dart';
import 'notifications/suggestions_controller.dart';
import 'parse_all_bar.dart';
import 'paste_sheet.dart';
import 'remove_confirm.dart';
import 'row_parts.dart';
import 'todo_choose.dart';
import 'todo_section.dart';
import 'held_row_describer.dart';
import 'waiting_row.dart';

/// What a tap on a waiting row does. All optional: an unwired action is a
/// no-op (an UNREADABLE row is shown with Details and Remove either way).
class WaitingActions {
  const WaitingActions({this.onParse, this.onCategorize, this.onPaste, this.onRemove, this.onParseAll, this.onDetails, this.airtime, this.describe, this.onChangeInSettings, this.clearDescriptions, this.onPickCategory, this.choicesFor, this.onLater, this.choosing, this.undecided, this.onWithdrawalCashOnly, this.onWithdrawalCategorize, this.onDecisionCashOnly, this.onDecisionCashOnlyAll, this.onDecisionCategorize, this.suggestions, this.ruleHintFor, this.categoryNameOf, this.onAskFirstYes, this.onAskFirstChange, this.onAskFirstLater, this.askFirstChanges, this.toChoose, this.chipsFor, this.onPickChip});

  final void Function(WaitingItem item)? onParse;
  final void Function(WaitingItem item)? onCategorize;
  final void Function(WaitingItem item)? onPaste;
  final void Function(WaitingItem item)? onRemove;

  /// Opens the Details sheet of a row. Null: rows show no Details link.
  final void Function(WaitingItem item)? onDetails;

  /// The Auto-record airtime trail. Null: no trail (it also needs [onChangeInSettings]).
  final AirtimeAutoController? airtime;

  /// Called with the readable ready items when Parse all runs (after the
  /// question, when there are more than 3). Null: the bar is not shown.
  final void Function(List<WaitingItem> items)? onParseAll;

  /// Describes a held message for its row (in memory only). Null: no description.
  final Future<HeldDescription?> Function(WaitingItem item)? describe;

  /// Makes the repository forget every description (page left, app hidden).
  final void Function()? clearDescriptions;

  /// Opens the Remembered page on its Recorded automatically tab. The trail shows only with it.
  final void Function()? onChangeInSettings;

  /// Saves [categoryId] for a freshly read row (same write as the sheet).
  final Future<void> Function(WaitingItem item, String categoryId)? onPickCategory;

  /// The categories to offer for a row.
  final Future<CategoryChoices> Function(WaitingItem item)? choicesFor;

  /// Moves a freshly read row to the categorize list without choosing.
  final void Function(WaitingItem item)? onLater;

  /// The ids parsed on this page visit (they get the Later chip). Null: none.
  final ChoosingIds? choosing;

  /// 0.2.1: recorded withdrawals still waiting for Cash only / a category. Not empty: the ONE
  /// "N withdrawals need a decision" item shows (it counts as 1 row in To categorize). Null: none.
  final ValueListenable<List<AnalyticsTransactionRow>>? undecided;

  /// 0.2.1: a parsed withdrawal ITEM (not recorded yet): Cash only | Categorize.
  final Future<void> Function(WaitingItem item)? onWithdrawalCashOnly;
  final Future<void> Function(WaitingItem item)? onWithdrawalCategorize;

  /// 0.2.1: a row of the Review sheet (a recorded withdrawal).
  final Future<void> Function(AnalyticsTransactionRow row)? onDecisionCashOnly;

  /// "Cash only for all" on the Review sheet (every undecided withdrawal in one go). Null: no button.
  final Future<void> Function(List<AnalyticsTransactionRow> rows)? onDecisionCashOnlyAll;
  final Future<void> Function(AnalyticsTransactionRow row)? onDecisionCategorize;

  /// 0.2.1 rules (Suggested + Ask first only). The "Ask first next time?" offers. Null: no Suggestions section.
  final SuggestionsController? suggestions;

  /// The rule hint of a waiting item (labels only). Null: no item is asked about.
  final RuleHint? Function(WaitingItem item)? ruleHintFor;

  /// Name of a category id, or null when unknown (an Ask first row then shows as a normal row).
  final String? Function(int categoryId)? categoryNameOf;

  /// Ask first row answers. Yes records the item as the hint's first category. Change category opens
  /// the Categorize sheet. Categorize later must make [ruleHintFor] return null for the item (it then
  /// shows under To categorize). All three needed for the row; any null: normal row.
  final Future<void> Function(WaitingItem item, RuleHint hint)? onAskFirstYes;
  final void Function(WaitingItem item, RuleHint hint)? onAskFirstChange;
  final void Function(WaitingItem item, RuleHint hint)? onAskFirstLater;

  /// Fires when what [ruleHintFor] or [categoryNameOf] answer may have changed (names loaded, a row sent
  /// to Categorize later). Null: they never change.
  final Listenable? askFirstChanges;

  /// 0.2.2 suggested chips on a choose row: which chips an item has, and what a chip tap does (records at once;
  /// false = nothing recorded). Both needed; either null: no chips.
  final Future<List<CategoryChoice>> Function(WaitingItem item)? chipsFor;
  final Future<bool> Function(WaitingItem item, CategoryChoice chip)? onPickChip;

  /// The To choose section ("Choose Pochi or Send Money"), built by its own code. Null: none. Only placed here.
  final ({Widget section, bool isEmpty})? toChoose;
}

/// The body of the To do view: the lists of readable, unreadable and waiting
/// messages and the trail, built on [WaitingRow] and the choose-a-category row.
/// [focusId] scrolls a row into view (no outline).
class WaitingSection extends StatelessWidget {
  const WaitingSection({
    super.key,
    required this.waiting,
    required this.now,
    this.actions = const WaitingActions(),
    this.focusId,
    this.pause,
  });

  final List<WaitingItem> waiting;
  final DateTime now;
  final WaitingActions actions;

  /// A row to scroll into view when it is listed (a phone-notification tap).
  final String? focusId;

  /// The "Pause all Auto-record" switch (0.2.2) for the To do banner and the rows' paused tag; null = the
  /// app's one ([LevelsDeps.instance]); none = no banner and no tag.
  final HardRulePausePort? pause;

  /// The Ask first hint and category name for [w], or null when it is a normal row.
  (RuleHint, String)? _ask(WaitingItem w) {
    final names = actions.categoryNameOf;
    if (names == null || actions.ruleHintFor == null) return null;
    if (actions.onAskFirstYes == null || actions.onAskFirstChange == null || actions.onAskFirstLater == null) return null;
    final hint = actions.ruleHintFor!(w);
    final cat = askFirstCategory(w, hint, now, names);
    return cat == null ? null : (hint!, cat);
  }

  Widget _row(BuildContext context, WaitingItem w) {
    final ask = _ask(w);
    if (ask != null) {
      final (hint, cat) = ask;
      return Padding(
        key: ValueKey('row-${w.id}'),
        padding: const EdgeInsets.only(bottom: 8),
        child: RowFocus(
          key: ValueKey('focus-${w.id}-ask'),
          on: w.id == focusId,
          child: AskFirstRow(
            key: Key('waiting-row-${w.id}'),
            item: w,
            now: now,
            categoryName: cat,
            onChange: () => actions.onAskFirstChange!(w, hint),
            onLater: () => actions.onAskFirstLater!(w, hint),
            onYes: () => actions.onAskFirstYes!(w, hint),
            hint: hint,
            pause: pause,
          ),
        ),
      );
    }
    final choose = actions.onPickCategory != null && actions.choicesFor != null && showsChooseRow(w, now);
    final fresh = actions.choosing?.contains(w.id) ?? false;
    return Padding(
      key: ValueKey('row-${w.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: RowFocus(
        key: ValueKey('focus-${w.id}-${choose ? 'choose' : w.kind.name}'),
        on: w.id == focusId || (choose && fresh),
        child: choose
            ? buildChooseRow(
                item: w,
                fresh: fresh,
                choicesFor: actions.choicesFor!,
                onPickCategory: actions.onPickCategory!,
                onLater: actions.onLater,
                onCashOnly: actions.onWithdrawalCashOnly,
                onCategorizeWithdrawal: actions.onWithdrawalCategorize,
                chipsFor: actions.chipsFor,
                onPickChip: actions.onPickChip,
              )
            : HeldRowDescriber(
                key: ValueKey('described-${w.id}'),
                item: w,
                describe: actions.describe ?? (_) async => null,
                clear: actions.clearDescriptions,
                builder: (context, description) => WaitingRow(
                  w,
                  now,
                  key: Key('waiting-row-${w.id}'),
                  description: description,
                  onParse: actions.onParse == null ? null : () => actions.onParse!(w),
                  onCategorize: actions.onCategorize == null ? null : () => actions.onCategorize!(w),
                  onPaste: actions.onPaste == null
                      ? null
                      : () => showPasteSheet(context, onContinueToAdd: () => actions.onPaste!(w)),
                  onDetails: actions.onDetails == null ? null : () => actions.onDetails!(w),
                    onRemove: actions.onRemove == null ? null : () => _confirmRemove(context, w),
                ),
              ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WaitingItem w) async {
    if (await showRemoveConfirm(context, item: w)) actions.onRemove!(w);
  }

  /// The one "N withdrawals need a decision" item, or null when there is none to decide.
  Widget? _decision(BuildContext context) {
    final list = actions.undecided?.value ?? const <AnalyticsTransactionRow>[];
    if (list.isEmpty || actions.onDecisionCashOnly == null || actions.onDecisionCategorize == null) return null;
    return DecisionItem(
      count: list.length,
      onReview: () => showDecisionReview(
        context,
        rows: actions.undecided!,
        onCashOnly: actions.onDecisionCashOnly!,
        onCashOnlyAll: actions.onDecisionCashOnlyAll,
        onCategorize: actions.onDecisionCategorize!,
      ),
    );
  }

  /// The Recorded automatically rows; empty without the trail wiring.
  List<AutoRecorded> _trail() => actions.airtime == null || actions.onChangeInSettings == null
      ? const <AutoRecorded>[]
      : actions.airtime!.trailNewestFirst;

  Widget _suggestions(BuildContext context, SuggestionsController c) => SuggestionsSection(
        offers: c.offers,
        categoryName: actions.categoryNameOf ?? (_) => null,
        onNotNow: (o) => c.notNow(o),
        // U-OFFER (B-1): the controller hides the card at once; a failed save brings it back with this toast.
        onConfirm: (o) async {
          final cat = actions.categoryNameOf?.call(o.categoryId);
          if (!await c.confirm(o, categoryName: cat)) PillToast.show(kSuggestionNotSaved);
        },
        // U2: Auto-record asks first (C0 dialog, no ceiling), then the controller saves and shows the notice.
        onAutoRecord: (o) async {
          final cat = actions.categoryNameOf?.call(o.categoryId);
          if (cat == null || !offersAutoRecord(o, cat)) return;
          if (!await showHardRuleConfirm(context, name: offerWho(o), category: cat)) return;
          if (!await c.confirmAuto(o, categoryName: cat)) PillToast.show(kSuggestionNotSaved);
        },
        times: c.suggestAfter,
      );

  @override
  Widget build(BuildContext context) {
    final todo = _todo();
    final port = pause ?? LevelsDeps.instance?.pause;
    if (!autoRecordUi || port == null) return todo;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CollapsingPadding(
        padding: const EdgeInsets.only(bottom: 12),
        child: HardRulePausedBanner(key: const Key('todoPausedBanner'), port: port, bulk: LevelsDeps.instance?.bulk),
      ),
      todo,
    ]);
  }

  Widget _todo() {
    // It listens to the choosing ids so a row parsed on this page turns into a
    // choose row.
    return ListenableBuilder(
      listenable: Listenable.merge([?actions.choosing, ?actions.undecided, ?actions.suggestions, ?actions.airtime, ?actions.askFirstChanges]),
      builder: (context, _) => TodoSection(
        waiting: waiting,
        now: now,
        rowBuilder: (w) => _row(context, w),
        decision: _decision(context),
        parseAllBar: actions.onParseAll == null || readableReady(waiting, now).isEmpty
            ? null
            : ParseAllBar(waiting: waiting, now: now, onParseAll: actions.onParseAll!),
        isAskFirst: (w) => _ask(w) != null,
        toChoose: actions.toChoose?.section,
        hasToChoose: actions.toChoose != null && !actions.toChoose!.isEmpty,
        hasTrail: _trail().isNotEmpty,
        trail: _trail().isEmpty
            ? null
            : RecordedAutoSection(
                entries: _trail(),
                now: now,
                onUndo: actions.airtime!.onUndo,
                onChangeInSettings: actions.onChangeInSettings!,
              ),
        hasSuggestions: (actions.suggestions?.offers ?? const []).isNotEmpty,
        suggestions: actions.suggestions == null ? null : _suggestions(context, actions.suggestions!),
      ),
    );
  }
}
