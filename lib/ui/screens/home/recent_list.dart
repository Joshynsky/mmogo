import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../../domain/home/recent_transaction.dart';
import '../../copy/spend_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import 'home_consts.dart';
import 'split_line.dart';

/// §HOME.RECENT — the recent transactions: whole rows only, as the last sliver.
///
/// The recent list as the last sliver. It measures the height left below
/// the card and label (`viewportMainAxisExtent - precedingScrollExtent`, the
/// real laid-out sizes, at the current text scale) and:
///  - shows as many WHOLE rows as fit, in a card that fills the rest of the
///    screen — the page then doesn't scroll (no partial row, ever); or
///  - when not even one row fits (tiny screen / very large text), falls back
///    to an ordinary scrolling page with [homeRecentFallbackRows] rows.
class HomeRecentSliver extends StatelessWidget {
  const HomeRecentSliver({
    super.key,
    required this.palette,
    required this.recent,
    required this.onTap,
    this.firstRowTourKey,
  });

  /// Lets Home's coach tour spotlight the first recent row.
  final GlobalKey? firstRowTourKey;

  final AppPalette palette;
  final List<RecentTransaction> recent;
  final ValueChanged<RecentTransaction> onTap;

  static const _nameStyleBase = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
  static const _subStyleBase = TextStyle(fontSize: 11);

  /// Every row has this fixed height (10px padding top and bottom around the
  /// name + subtitle lines, as laid out at the current text scale), so the
  /// fit count is exact.
  static double rowHeight(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: 'Ag', style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final h = tp.height;
      tp.dispose();
      return h;
    }

    return (10 + line(_nameStyleBase) + 1 + line(_subStyleBase) + 10).ceilToDouble();
  }

  BoxDecoration get _card =>
      BoxDecoration(color: palette.card, borderRadius: const BorderRadius.all(Radius.circular(18)));

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: Container(
            key: const Key('homeRecentCard'),
            alignment: Alignment.topLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: _card,
            child: Text(
              'No transactions yet. Tap + to add one.',
              style: TextStyle(fontSize: 13, color: palette.mutedInk),
            ),
          ),
        ),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final rowH = rowHeight(context);
        final remaining = constraints.viewportMainAxisExtent - constraints.precedingScrollExtent;
        // n rows take n*rowH + (n-1) dividers.
        final fit = remaining <= 0 ? 0 : ((remaining + 1) / (rowH + 1)).floor();

        if (fit >= 1) {
          final n = math.min(fit, recent.length);
          return SliverToBoxAdapter(
            child: SizedBox(
              key: const Key('homeRecentFit'),
              height: remaining,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  key: const Key('homeRecentCard'),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.topCenter,
                  decoration: _card,
                  child: _rows(recent.take(n).toList(), rowH),
                ),
              ),
            ),
          );
        }

        // Fallback: not even one whole row fits — scroll instead of squeeze.
        return SliverPadding(
          key: const Key('homeRecentFallback'),
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          sliver: SliverToBoxAdapter(
            child: Container(
              key: const Key('homeRecentCard'),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: _card,
              child: _rows(recent.take(homeRecentFallbackRows).toList(), rowH),
            ),
          ),
        );
      },
    );
  }

  Widget _rows(List<RecentTransaction> rows, double rowH) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Container(height: 1, color: palette.line),
          KeyedSubtree(
            key: i == 0 ? firstRowTourKey : null,
            child: _RecentRow(
              palette: palette,
              tx: rows[i],
              height: rowH,
              nameStyle: _nameStyleBase.copyWith(color: palette.ink),
              subStyle: _subStyleBase.copyWith(color: palette.mutedInk),
              onTap: () => onTap(rows[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.palette,
    required this.tx,
    required this.height,
    required this.nameStyle,
    required this.subStyle,
    required this.onTap,
  });

  final AppPalette palette;
  final RecentTransaction tx;
  final double height;
  final TextStyle nameStyle;
  final TextStyle subStyle;
  final VoidCallback onTap;

  /// Second line: `Type · agent number (when it has one) · date`.
  String get _subtitle {
    final agent = tx.agentNumber;
    return [
      sourceTypeName(tx.sourceType),
      if (agent != null && agent.isNotEmpty) agent,
      formatShortDate(tx.occurredAt),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final wd = tx.isWithdrawalRow;
    final amountStyle = nameStyle.copyWith(
      fontFeatures: tabularFigures,
      // Withdrawal: tracked, not spent, so its amount is muted (mock `.row.wd .amt`).
      color: wd ? palette.mutedInk : null,
      fontWeight: wd ? FontWeight.w600 : null,
    );
    final row = InkWell(
      key: Key('homeRecentRow-${tx.id}'),
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Container(
              key: Key('homeRecentDot-${tx.id}'),
              width: 9,
              height: 9,
              decoration: wd
                  // Hollow dot: a Withdrawal is not spending (mock `.row.wd .dot`).
                  ? BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.typeColor(tx.sourceType), width: 2),
                    )
                  : BoxDecoration(color: palette.typeColor(tx.sourceType), shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HomeSplitLine(
                gap: 10,
                start: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                    const SizedBox(height: 1),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subStyle,
                    ),
                  ],
                ),
                end: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatKsh(tx.amountCents), key: Key('homeRecentAmount-${tx.id}'), style: amountStyle),
                    // Any row with a cost: a small muted note under the amount.
                    // The row height is fixed, so the note never makes it taller.
                    if (tx.feeCents > 0) ...[
                      const SizedBox(height: 1),
                      Text(
                        '+ ${formatKsh(tx.feeCents)} fee',
                        key: Key('homeRecentFee-${tx.id}'),
                        maxLines: 1,
                        style: subStyle.copyWith(fontFeatures: tabularFigures),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!wd) return row;
    // The long sentence is for the screen reader only; the row prints no words.
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      label:
          '${tx.displayName}, ${formatKsh(tx.amountCents)}, ${notCountedLabel(feeCents: tx.feeCents)}, '
          '${_subtitle.replaceAll(' · ', ', ')}',
      child: row,
    );
  }
}
