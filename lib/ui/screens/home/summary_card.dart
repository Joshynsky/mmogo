import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../../domain/home/home_diff.dart';
import '../../../domain/home/home_period.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import 'home_consts.dart';
import 'split_line.dart';

/// §HOME.SUMMARY — the merged card: period label, total, change vs the prior
/// period, one bar per transaction type and the transaction cost row.
class HomeSummaryCard extends StatelessWidget {
  const HomeSummaryCard({
    super.key,
    required this.palette,
    required this.period,
    required this.totalCents,
    required this.diff,
    required this.typeTotals,
    required this.costCents,
    required this.onPeriodTap,
    this.periodTourKey,
  });

  /// Lets Home's coach tour spotlight the period button.
  final GlobalKey? periodTourKey;

  final AppPalette palette;
  final HomePeriod period;
  final int totalCents;
  final HomeDiffResult diff;
  final Map<String, int> typeTotals;
  final int costCents;
  final VoidCallback onPeriodTap;

  @override
  Widget build(BuildContext context) {
    final isDark = palette.brightness == Brightness.dark;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Container(
      key: const Key('homeSummaryCard'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        // rgba(10,40,50,.06) on light; no shadow on dark (mock).
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x0F0A2832), blurRadius: 6, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeSplitLine(
            crossAxisAlignment: CrossAxisAlignment.start,
            gap: 10,
            endAlignment: Alignment.topRight,
            start: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeyedSubtree(
                  key: periodTourKey,
                  child: _PeriodButton(palette: palette, label: period.label, onTap: onPeriodTap),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatKsh(totalCents),
                    key: const Key('homeTotal'),
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.54,
                      height: 1.15,
                      fontFeatures: tabularFigures,
                      color: palette.ink,
                    ),
                  ),
                ),
              ],
            ),
            end: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _DiffLine(palette: palette, diff: diff, priorSuffix: period.priorSuffix),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < homeTypeOrder.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _TypeBar(
              palette: palette,
              code: homeTypeOrder[i].$1,
              label: homeTypeOrder[i].$2,
              cents: typeTotals[homeTypeOrder[i].$1] ?? 0,
              totalCents: totalCents,
              animate: animate,
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.line)),
            ),
            child: HomeSplitLine(
              start: Text('Transaction cost (all M-Pesa)', style: TextStyle(fontSize: 12, color: palette.mutedInk)),
              end: Text(
                formatKsh(costCents),
                key: const Key('homeCost'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                  color: palette.softInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The period label + chevron. Tapping it CYCLES Today → This week → This
/// month (it is not a menu).
class _PeriodButton extends StatelessWidget {
  const _PeriodButton({required this.palette, required this.label, required this.onTap});

  final AppPalette palette;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Period: $label. Tap to change',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('homePeriodButton'),
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 6, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.softInk),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: palette.softInk),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.palette, required this.diff, required this.priorSuffix});

  final AppPalette palette;
  final HomeDiffResult diff;
  final String priorSuffix;

  @override
  Widget build(BuildContext context) {
    // The two "no prior spend" states stay plain muted text; they may wrap
    // (right-aligned) rather than squeeze the total.
    Widget muted(String text) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 130),
      child: Text(
        text,
        key: const Key('homeDiff'),
        textAlign: TextAlign.end,
        style: TextStyle(fontSize: 12, color: palette.mutedInk),
      ),
    );
    Widget strong(String text, Color color) => Text(
      text,
      key: const Key('homeDiff'),
      softWrap: false,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
    );

    return switch (diff.kind) {
      HomeDiffKind.noPriorNoSpend => muted('—'),
      HomeDiffKind.noPriorHasSpend => muted('No spend in the prior period to compare'),
      HomeDiffKind.up => strong('▲ ${diff.percent}% $priorSuffix', palette.diffUp),
      HomeDiffKind.down => strong('▼ ${diff.percent}% $priorSuffix', palette.diffDown),
    };
  }
}

/// One type's row: name and amount on a line, then an 8px rounded bar whose
/// length is that type's share of the period total. A zero type keeps its
/// row, faded, showing Ksh 0.00.
class _TypeBar extends StatelessWidget {
  const _TypeBar({
    required this.palette,
    required this.code,
    required this.label,
    required this.cents,
    required this.totalCents,
    required this.animate,
  });

  final AppPalette palette;
  final String code;
  final String label;
  final int cents;
  final int totalCents;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final share = totalCents > 0 ? (cents / totalCents).clamp(0.0, 1.0) : 0.0;
    return Padding(
      key: Key('homeTypeRow-$code'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Opacity(
            key: Key('homeTypeLabel-$code'),
            opacity: cents == 0 ? 0.6 : 1.0,
            child: HomeSplitLine(
              start: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.softInk),
              ),
              end: Text(
                formatKsh(cents),
                key: Key('homeTypeAmount-$code'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                  color: palette.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            child: Container(
              height: 8,
              color: palette.track,
              child: AnimatedFractionallySizedBox(
                key: Key('homeBar-$code'),
                duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
                curve: Curves.easeOut,
                alignment: Alignment.centerLeft,
                widthFactor: share,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.typeColor(code),
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
