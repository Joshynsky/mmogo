/// §AUTOREAD.ASK_FIRST_ROW - a waiting item whose person is on Ask first: "Record as [Category]?"
/// and three buttons, left to right: Change category, Categorize later, Yes (Yes on the far
/// right). At most three buttons. The row holds no repository: the page wires the callbacks.
/// Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../../ui/screens/notifications/news_row.dart' show rowAgeText;
import '../../../ui/theme/app_colors.dart';
import '../../logic/waiting_logic.dart';
import '../../model/rule_hint.dart';
import '../../model/waiting_item.dart';
import '../../rules/rule_model.dart';
import '../waiting_row.dart' show waitingTitle;
import 'notifications_rule_copy.dart';
import 'rule_pill.dart';

/// The category the row asks about: the first suggested one, when [item] is a parsed item that can
/// be asked about and [categoryName] knows it. Null: the item is shown as a normal row.
String? askFirstCategory(WaitingItem item, RuleHint? hint, DateTime now, String? Function(int id) categoryName) {
  if (hint == null || hint.level != RuleLevel.askFirst || hint.suggested.isEmpty) return null;
  if (effectiveKind(item, now) != WaitingKind.waitingCategory || item.parsed == null || item.sameCodeDifferentDetails) return null;
  return categoryName(hint.suggested.first);
}

class AskFirstRow extends StatelessWidget {
  const AskFirstRow({
    super.key,
    required this.item,
    required this.now,
    required this.categoryName,
    required this.onChange,
    required this.onLater,
    required this.onYes,
  });

  final WaitingItem item;
  final DateTime now;
  final String categoryName;
  final VoidCallback onChange;
  final VoidCallback onLater;
  final VoidCallback onYes;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final title = askFirstTitle(categoryName);
    final what = waitingTitle(item.parsed!, withMask: true);
    final age = 'Received ${rowAgeText(item.heldAt, now)}';
    return Semantics(
      container: true,
      label: '$kSpokenAskFirst. $title $what. $age.',
      child: Container(
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: p.ink, fontSize: 14, height: 1.3, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(what, style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.35)),
                  Text(age, style: TextStyle(color: p.mutedInk, fontSize: 12, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              key: const Key('ask-first-actions'),
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                RulePill(key: const Key('ask-first-change'), label: kAskFirstChange, onTap: onChange, spoken: '$kAskFirstChange: $what'),
                RulePill(key: const Key('ask-first-later'), label: kAskFirstLater, onTap: onLater, spoken: '$kAskFirstLater: $what'),
                RulePill(key: const Key('ask-first-yes'), label: kAskFirstYes, onTap: onYes, fill: true, spoken: '$kAskFirstYes, record as $categoryName: $what'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
