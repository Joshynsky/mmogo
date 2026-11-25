/// §AUTOREAD.ASK_FIRST_ROW - a waiting item whose person is on Ask first: "Record as [Category]?"
/// and three buttons, left to right: Change category, Categorize later, Yes (Yes on the far
/// right). At most three buttons. The row holds no repository: the page wires the callbacks.
/// 0.2.2: an item whose person is on Auto-record but was NOT recorded (an Ask first hint made from
/// Auto-record, or an `auto` hint still waiting) shows the same row; while "Pause all Auto-record" is on,
/// a hint made from Auto-record carries the amber "Auto-record paused: asking first" tag (mock ctl-a-todo).
/// Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../../ui/screens/notifications/news_row.dart' show rowAgeText;
import '../../../ui/theme/app_colors.dart';
import '../../logic/waiting_logic.dart';
import '../../model/rule_hint.dart';
import '../../model/waiting_item.dart';
import '../../rules/rule_model.dart';
import '../levels/hard_rule_copy.dart' show kHardPausedTag;
import '../levels/hard_rule_pause_card.dart' show HardRulePauseWatch;
import '../levels/hard_rule_ports.dart' show HardRulePausePort, autoRecordUi;
import '../levels/levels_deps.dart' show LevelsDeps;
import '../waiting_row.dart' show waitingTitle;
import 'notifications_rule_copy.dart';
import 'rule_pill.dart';

/// Whether [hint] asks one tap: an Ask first hint, or an Auto-record one that did not record (a waiting
/// item is by definition not recorded: an `auto` hint left waiting, or an Ask first hint made from
/// Auto-record). Suggested never asks.
bool hintAsksFirst(RuleHint hint) =>
    hint.level == RuleLevel.askFirst || hint.level == RuleLevel.autoRecord || hint.fromAutoRecord;

/// The category the row asks about: the first suggested one, when [item] is a parsed item that can
/// be asked about and [categoryName] knows it. Null: the item is shown as a normal row.
String? askFirstCategory(WaitingItem item, RuleHint? hint, DateTime now, String? Function(int id) categoryName) {
  if (hint == null || !hintAsksFirst(hint) || hint.suggested.isEmpty) return null;
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
    this.hint,
    this.pause,
  });

  final WaitingItem item;
  final DateTime now;
  final String categoryName;
  final VoidCallback onChange;
  final VoidCallback onLater;
  final VoidCallback onYes;

  /// The item's hint (0.2.2): the paused tag is drawn only when it was made from Auto-record.
  final RuleHint? hint;

  /// The pause switch; null = the app's one ([LevelsDeps.instance]); none = no tag.
  final HardRulePausePort? pause;

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
            if (autoRecordUi && (hint?.fromAutoRecord ?? false))
              _PausedTag(port: pause ?? LevelsDeps.instance?.pause),
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

/// The amber tag "Auto-record paused: asking first", only while paused (follows the switch). Its own
/// live region so the reason is read out when it appears.
class _PausedTag extends StatefulWidget {
  const _PausedTag({required this.port});
  final HardRulePausePort? port;

  @override
  State<_PausedTag> createState() => _PausedTagState();
}

class _PausedTagState extends State<_PausedTag> with HardRulePauseWatch<_PausedTag> {
  @override
  HardRulePausePort? get pausePort => widget.port;

  @override
  Widget build(BuildContext context) {
    if (paused != true) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          key: const Key('ask-first-paused-tag'),
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: p.highlight,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.sun),
          ),
          child: Text(kHardPausedTag, style: TextStyle(color: p.ink, fontSize: 11.5, fontWeight: FontWeight.w800, height: 1.3)),
        ),
      ),
    );
  }
}
