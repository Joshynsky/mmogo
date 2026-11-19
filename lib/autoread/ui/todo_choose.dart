/// §AUTOREAD.TODO_CHOOSE - how a parsed message shows on the To do view: as a
/// choose-a-category row (the category chips in place of the Categorize button).
/// [ChoosingIds] remembers which rows were parsed on this page visit, so they
/// get the Later chip; a row that is only waiting (opened later) has none.
/// Holds no repository; the page wires the callbacks. Autoread build only.
library;

import 'package:flutter/material.dart';

import '../logic/held_describe.dart' show describeReadable;
import '../logic/waiting_logic.dart';
import '../model/waiting_item.dart';
import 'category_choices.dart';
import 'choose_category_row.dart';

/// The ids parsed on this page visit and still choosing. In memory only.
class ChoosingIds extends ChangeNotifier {
  final Set<String> _ids = {};

  bool contains(String id) => _ids.contains(id);

  void add(String id) {
    if (_ids.add(id)) notifyListeners();
  }

  void remove(String id) {
    if (_ids.remove(id)) notifyListeners();
  }

  /// Keeps only the ids [keep] says are still choosing.
  void retainWhere(bool Function(String id) keep) {
    final before = _ids.length;
    _ids.removeWhere((id) => !keep(id));
    if (_ids.length != before) notifyListeners();
  }
}

/// True when [w] is a parsed message the row can take a category for in place.
/// A row flagged "same code, different details" keeps its Categorize sheet so
/// the flag stays visible.
bool showsChooseRow(WaitingItem w, DateTime now) =>
    effectiveKind(w, now) == WaitingKind.waitingCategory && w.parsed != null && !w.sameCodeDifferentDetails;

/// The choose-a-category row for [item]. [fresh]: parsed on this visit, so Later shows.
Widget buildChooseRow({
  required WaitingItem item,
  required bool fresh,
  required Future<CategoryChoices> Function(WaitingItem item) choicesFor,
  required Future<void> Function(WaitingItem item, String categoryId) onPickCategory,
  void Function(WaitingItem item)? onLater,
  Future<void> Function(WaitingItem item)? onCashOnly,
  Future<void> Function(WaitingItem item)? onCategorizeWithdrawal,
}) =>
    KeyedSubtree(
      key: Key('waiting-row-${item.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChooseCategoryRow(
            key: ValueKey('choose-${item.id}-$fresh'),
            item: item,
            description: describeReadable(item.parsed!),
            choicesFor: choicesFor,
            onPickCategory: onPickCategory,
            onLater: onLater,
            fresh: fresh,
            onCashOnly: onCashOnly,
            onCategorizeWithdrawal: onCategorizeWithdrawal,
          ),
        ],
      ),
    );
