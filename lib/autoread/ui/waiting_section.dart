/// §AUTOREAD.WAITING_SECTION — the lists of the Parse, Categorize and All
/// chips, built on [WaitingRow]. Autoread build only: shared code reaches it
/// inside `if (kAutoReadCompiled)`. Sorting and counts come from
/// `waiting_logic.dart` and `all_view_logic.dart`; nothing is re-implemented.
/// Rows take callbacks only (no repository); the page wires them.
library;

import 'package:flutter/material.dart';

import '../../domain/notifications/news_item.dart';
import '../../domain/notifications/news_logic.dart' show capCount, unreadNewsCount;
import '../../domain/notifications/notif_chip.dart';
import '../../ui/copy/notifications_copy.dart';
import '../../ui/theme/app_colors.dart';
import '../logic/all_view_logic.dart' as all;
import '../logic/waiting_logic.dart';
import '../model/waiting_item.dart';
import 'notifications_autoread_copy.dart';
import 'parse_all_bar.dart';
import 'paste_sheet.dart';
import 'remove_confirm.dart';
import 'waiting_row.dart';

/// What a tap on a waiting row does. All optional: an unwired action is a
/// no-op (slice F6 wires them; an UNREADABLE row is shown with Paste and
/// Remove either way).
class WaitingActions {
  const WaitingActions({this.onParse, this.onCategorize, this.onPaste, this.onRemove, this.onParseAll});

  final void Function(WaitingItem item)? onParse;
  final void Function(WaitingItem item)? onCategorize;
  final void Function(WaitingItem item)? onPaste;
  final void Function(WaitingItem item)? onRemove;

  /// Called with the readable ready items when Parse all runs (after the
  /// question, when there are more than 3). Null: the bar is not shown.
  final void Function(List<WaitingItem> items)? onParseAll;
}

/// The body of the Parse, Categorize or All chip.
///
/// [chip] must be [NotifChip.all], [NotifChip.parse] or [NotifChip.categorize]
/// (News is the page's own list). [newsRowBuilder] builds one news row (used
/// only under All, which lists UNREAD news only, with no Unread | Read switch).
class WaitingSection extends StatelessWidget {
  const WaitingSection({
    super.key,
    required this.chip,
    required this.waiting,
    required this.news,
    required this.now,
    required this.newsRowBuilder,
    this.actions = const WaitingActions(),
    this.focusId,
  }) : assert(chip != NotifChip.news);

  final NotifChip chip;
  final List<WaitingItem> waiting;
  final List<NewsItem> news;
  final DateTime now;
  final Widget Function(NewsItem item) newsRowBuilder;
  final WaitingActions actions;

  /// A row to scroll into view and highlight when it is listed (a phone-notification tap).
  final String? focusId;

  Widget _row(BuildContext context, WaitingItem w) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _Focus(
          on: w.id == focusId,
          child: WaitingRow(
            w,
            now,
            key: Key('waiting-row-${w.id}'),
            onParse: actions.onParse == null ? null : () => actions.onParse!(w),
            onCategorize: actions.onCategorize == null ? null : () => actions.onCategorize!(w),
            onPaste: actions.onPaste == null
                ? null
                : () => showPasteSheet(context, onContinueToAdd: () => actions.onPaste!(w)),
            onRemove: actions.onRemove == null
                ? null
                : () async {
                    if (await showRemoveConfirm(context, item: w)) actions.onRemove!(w);
                  },
          ),
        ),
      );

  Widget _newsRow(NewsItem n) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: KeyedSubtree(key: Key('news-row-${n.id}'), child: newsRowBuilder(n)),
      );

  @override
  Widget build(BuildContext context) {
    final toParse = sortReadyToParse(waiting, now);
    final toCategorize = sortWaitingCategory(waiting, now);
    final children = <Widget>[];

    void parseGroup() {
      if (toParse.isEmpty) return;
      children.add(_Heading(
        '$kHeadingToParse (${capCount(parseCount(waiting, now))})',
        trailing: actions.onParseAll == null
            ? null
            : ParseAllBar(waiting: waiting, now: now, onParseAll: actions.onParseAll!),
      ));
      children.addAll(toParse.map((w) => _row(context, w)));
    }

    void categorizeGroup() {
      if (toCategorize.isEmpty) return;
      children.add(_Heading('$kHeadingToCategorize (${capCount(categorizeCount(waiting, now))})'));
      children.add(const _Quiet(kWaitingNotCounted));
      children.addAll(toCategorize.map((w) => _row(context, w)));
    }

    switch (chip) {
      case NotifChip.parse:
        parseGroup();
        if (children.isEmpty) children.add(const _Empty(kEmptyParseTitle, kEmptyParseBody));
      case NotifChip.categorize:
        categorizeGroup();
        if (children.isEmpty) children.add(const _Empty(kEmptyCategorizeTitle, kEmptyCategorizeBody));
      case NotifChip.all:
        final rows = all.allViewOrder(waiting, news, now);
        if (rows.isEmpty) {
          children.add(const _Empty(kEmptyAllTitle, kEmptyAllBody));
        } else {
          parseGroup();
          categorizeGroup();
          final unread = [
            for (final r in rows)
              if (r is all.NewsRow) r.item,
          ];
          if (unread.isNotEmpty) {
            children.add(_Heading(newsHeadingWithCount(capCount(unreadNewsCount(news)))));
            children.addAll(unread.map(_newsRow));
          }
        }
      case NotifChip.news:
        break;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Wraps the focused row: after the first frame it scrolls into view and keeps
/// a primary outline so the user can see which message the tap was about.
class _Focus extends StatefulWidget {
  const _Focus({required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  State<_Focus> createState() => _FocusState();
}

class _FocusState extends State<_Focus> {
  @override
  void initState() {
    super.initState();
    if (widget.on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: 0.3);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.on) return widget.child;
    return DecoratedBox(
      key: const Key('waiting-row-focused'),
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(color: AppPalette.of(context).primary, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: widget.child,
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
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
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: AppPalette.of(context).mutedInk,
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Semantics(
        container: true,
        child: Column(
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 4),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: p.mutedInk)),
          ],
        ),
      ),
    );
  }
}
