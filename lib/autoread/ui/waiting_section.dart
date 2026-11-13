/// §AUTOREAD.WAITING_SECTION — the To do view's lists, built on [WaitingRow].
/// Autoread build only: shared code reaches it inside `if (kAutoReadCompiled)`.
/// Sorting and counts come from `waiting_logic.dart`; nothing is re-implemented.
/// Rows take callbacks only (no repository); the page wires them.
library;

import 'package:flutter/material.dart';

import '../logic/airtime_auto.dart';
import '../model/held_description.dart';
import '../model/waiting_item.dart';
import 'auto_group.dart';
import 'category_choices.dart';
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
  const WaitingActions({this.onParse, this.onCategorize, this.onPaste, this.onRemove, this.onParseAll, this.onDetails, this.airtime, this.describe, this.onChangeInSettings, this.clearDescriptions, this.onPickCategory, this.choicesFor, this.onLater, this.choosing});

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
  });

  final List<WaitingItem> waiting;
  final DateTime now;
  final WaitingActions actions;

  /// A row to scroll into view when it is listed (a phone-notification tap).
  final String? focusId;

  Widget _row(BuildContext context, WaitingItem w) {
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

  @override
  Widget build(BuildContext context) {
    // It listens to the choosing ids so a row parsed on this page turns into a
    // choose row.
    return ListenableBuilder(
      listenable: actions.choosing ?? Listenable.merge(const []),
      builder: (context, _) => TodoSection(
        waiting: waiting,
        now: now,
        rowBuilder: (w) => _row(context, w),
        parseAllBar: actions.onParseAll == null || readableReady(waiting, now).isEmpty
            ? null
            : ParseAllBar(waiting: waiting, now: now, onParseAll: actions.onParseAll!),
        trail: actions.airtime == null || actions.onChangeInSettings == null
            ? null
            : AutoGroup(actions.airtime!, now, onChangeInSettings: actions.onChangeInSettings!),
      ),
    );
  }
}
