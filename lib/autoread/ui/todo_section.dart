/// §AUTOREAD.TODO_SECTION - the body of the To do chip: To parse (n) with the
/// Parse all bar, To choose, Suggestions, To categorize (n), Could not read (n), the trail slot LAST, and
/// one empty card when nothing is left. Rows come from [rowBuilder] and the bar
/// and trail slot are passed in, so this file holds order, headings and counts
/// only and stays testable without a repository. Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../domain/notifications/news_logic.dart' show capCount;
import '../../ui/theme/app_colors.dart';
import '../logic/waiting_logic.dart';
import '../model/waiting_item.dart';
import 'notifications/nothing_waiting_line.dart';
import 'notifications/notifications_rule_copy.dart';
import 'notifications_autoread_copy.dart';
import 'row_parts.dart' show SectionHeading;

class TodoSection extends StatelessWidget {
  const TodoSection({
    super.key,
    required this.waiting,
    required this.now,
    required this.rowBuilder,
    this.parseAllBar,
    this.trail,
    this.decision,
    this.isAskFirst,
    this.toChoose,
    this.hasToChoose = false,
    this.suggestions,
    this.hasSuggestions = false,
    this.hasTrail = false,
  });

  /// 0.2.1: true for a waiting item whose person is on Ask first; those rows go under To confirm,
  /// first. Null: none.
  final bool Function(WaitingItem item)? isAskFirst;

  /// The To choose section ("Choose Pochi or Send Money"), built elsewhere; shown after To parse and
  /// before To categorize. [hasToChoose] says it is not empty.
  final Widget? toChoose;
  final bool hasToChoose;

  /// The Suggestions section (one card), after To parse / To choose. [hasSuggestions]: at least one offer.
  final Widget? suggestions;
  final bool hasSuggestions;

  /// True when [trail] holds at least one row (decides where Nothing waiting sits).
  final bool hasTrail;

  /// 0.2.1: the ONE "N withdrawals need a decision" item (counts as 1 row in To categorize). Null: none.
  final Widget? decision;

  final List<WaitingItem> waiting;
  final DateTime now;

  /// One finished row (padding and focus included) for an item.
  final Widget Function(WaitingItem item) rowBuilder;

  /// The Parse all bar, shown beside the To parse heading. Null: none.
  final Widget? parseAllBar;

  /// The Recorded automatically slot, last on the page. Null: none.
  final Widget? trail;

  @override
  Widget build(BuildContext context) {
    final toParse = sortReadyToParse(waiting, now);
    final readable = [for (final w in toParse) if (effectiveKind(w, now) == WaitingKind.readyToParse) w];
    final unreadable = [for (final w in toParse) if (effectiveKind(w, now) != WaitingKind.readyToParse) w];
    final allCategorize = sortWaitingCategory(waiting, now);
    final ask = isAskFirst;
    final confirm = ask == null ? const <WaitingItem>[] : [for (final w in allCategorize) if (ask(w)) w];
    final toCategorize = ask == null ? allCategorize : [for (final w in allCategorize) if (!ask(w)) w];
    final nothing = readable.isEmpty &&
        unreadable.isEmpty &&
        toCategorize.isEmpty &&
        confirm.isEmpty &&
        decision == null &&
        !hasToChoose &&
        !hasSuggestions;
    // F10 (PM 24-11): To confirm, To parse, To choose, Suggestions (one card), To categorize, then
    // Could not read (F-1 25-11 replaces F11), then Recorded automatically at the very bottom.
    final children = <Widget>[
      if (confirm.isNotEmpty) ...[
        SectionHeading('$kHeadingToConfirm (${capCount(confirm.length)})'),
        ...confirm.map(rowBuilder),
      ],
      if (readable.isNotEmpty) ...[
        _TodoHeading('$kHeadingToParse (${capCount(readable.length)})', trailing: parseAllBar),
        ...readable.map(rowBuilder),
      ],
      if (hasToChoose) ?toChoose,
      if (hasSuggestions) ?suggestions,
      // 0.2.2 item 2 (B-3, F-1, PM 25-11): unreadable and gone messages left To categorize and its
      // count; they get their own heading right after it. kHeadingCouldNotRead keeps the signed
      // 11-11 words "Could not read" (the sign-off says "Could not be read"; W2 decides).
      if (toCategorize.isNotEmpty || decision != null) ...[
        _TodoHeading('$kHeadingToCategorize (${capCount(toCategorize.length + (decision == null ? 0 : 1))})'),
        const _Quiet(kWaitingNotCounted),
        if (decision != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: decision),
        ...toCategorize.map(rowBuilder),
      ],
      if (unreadable.isNotEmpty) ...[
        _TodoHeading('$kHeadingCouldNotRead (${capCount(unreadable.length)})'),
        ...unreadable.map(rowBuilder),
      ],
      if (nothing) NothingWaitingLine(top: hasTrail),
      ?trail,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _TodoHeading extends StatelessWidget {
  const _TodoHeading(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final title = Semantics(
      header: true,
      child: Text(text, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
      child: trailing == null
          ? title
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [title, trailing!],
            ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: AppPalette.of(context).mutedInk),
        ),
      );
}
