/// §AUTOREAD.TODO_SECTION - the body of the To do chip: To parse (n) with the
/// Parse all bar, Could not read (n), To categorize (n), the trail slot, and
/// one empty card when nothing is left. Rows come from [rowBuilder] and the bar
/// and trail slot are passed in, so this file holds order, headings and counts
/// only and stays testable without a repository. Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../domain/notifications/news_logic.dart' show capCount;
import '../../ui/theme/app_colors.dart';
import '../logic/waiting_logic.dart';
import '../model/waiting_item.dart';
import 'notifications_autoread_copy.dart';
import 'todo_copy.dart';

class TodoSection extends StatelessWidget {
  const TodoSection({
    super.key,
    required this.waiting,
    required this.now,
    required this.rowBuilder,
    this.parseAllBar,
    this.trail,
    this.decision,
  });

  /// 0.2.1: the ONE "N withdrawals need a decision" item (counts as 1 row in To categorize). Null: none.
  final Widget? decision;

  final List<WaitingItem> waiting;
  final DateTime now;

  /// One finished row (padding and focus included) for an item.
  final Widget Function(WaitingItem item) rowBuilder;

  /// The Parse all bar, shown beside the To parse heading. Null: none.
  final Widget? parseAllBar;

  /// The Recorded automatically slot, after the three groups. Null: none.
  final Widget? trail;

  @override
  Widget build(BuildContext context) {
    final toParse = sortReadyToParse(waiting, now);
    final readable = [for (final w in toParse) if (effectiveKind(w, now) == WaitingKind.readyToParse) w];
    final unreadable = [for (final w in toParse) if (effectiveKind(w, now) != WaitingKind.readyToParse) w];
    final toCategorize = sortWaitingCategory(waiting, now);
    final children = <Widget>[
      if (readable.isNotEmpty) ...[
        _TodoHeading('$kHeadingToParse (${capCount(readable.length)})', trailing: parseAllBar),
        ...readable.map(rowBuilder),
      ],
      if (unreadable.isNotEmpty) ...[
        _TodoHeading('$kHeadingCouldNotRead (${capCount(unreadable.length)})', small: readable.isNotEmpty),
        ...unreadable.map(rowBuilder),
      ],
      if (toCategorize.isNotEmpty || decision != null) ...[
        _TodoHeading('$kHeadingToCategorize (${capCount(toCategorize.length + (decision == null ? 0 : 1))})'),
        const _Quiet(kWaitingNotCounted),
        if (decision != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: decision),
        ...toCategorize.map(rowBuilder),
      ],
      if (readable.isEmpty && unreadable.isEmpty && toCategorize.isEmpty && decision == null) const _EmptyCard(),
      ?trail,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _TodoHeading extends StatelessWidget {
  const _TodoHeading(this.text, {this.trailing, this.small = false});
  final String text;
  final Widget? trailing;

  /// Could not read sits under To parse as a smaller heading.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final title = Semantics(
      header: true,
      child: Text(text, style: (small ? t.titleSmall : t.titleMedium)?.copyWith(fontWeight: FontWeight.w700)),
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Semantics(
        container: true,
        key: const Key('todo-empty'),
        child: Column(
          children: [
            Text(kTodoEmptyTitle,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 4),
            Text(kTodoEmptyBody,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.4, color: p.mutedInk)),
          ],
        ),
      ),
    );
  }
}
