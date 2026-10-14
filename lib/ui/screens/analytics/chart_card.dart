import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import 'analytics_view.dart';
import 'parts.dart';
import 'swipe_chart.dart';

/// §ANALYTICS.CHART — the chart card: title, prev/next period buttons, the
/// swipeable chart and its hint. [canBack]/[canForward] come from the shell's
/// live `_period` (not `view.period`); [typeFilterIndexes] are the indexes of
/// the picked types in `analyticsTypeOrder` (empty = none).
class AnalyticsChartCard extends StatelessWidget {
  const AnalyticsChartCard({
    super.key,
    required this.palette,
    required this.view,
    required this.typeFilterIndexes,
    required this.canBack,
    required this.canForward,
    required this.onStep,
    required this.onBucket,
  });

  final AppPalette palette;
  final AnalyticsView view;
  final Set<int> typeFilterIndexes;
  final bool canBack;
  final bool canForward;
  final ValueChanged<int> onStep;
  final ValueChanged<ChartBucket> onBucket;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final canFwd = canForward;
    final legend = chartLegendText(v.chart.legend, hatched: v.showHatch, hasCash: v.hasHatch);
    return AppCard(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  v.chart.title.toUpperCase(),
                  key: const Key('analyticsChartTitle'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.66,
                    color: palette.mutedInk,
                  ),
                ),
              ),
              AnalyticsRoundButton(
                key: const Key('analyticsPrev'),
                size: 28,
                icon: Icons.chevron_left_rounded,
                iconSize: 18,
                tooltip: 'Previous period',
                background: palette.track,
                foreground: palette.ink,
                onTap: canBack ? () => onStep(-1) : null,
              ),
              const SizedBox(width: 2),
              AnalyticsRoundButton(
                key: const Key('analyticsNext'),
                size: 28,
                icon: Icons.chevron_right_rounded,
                iconSize: 18,
                tooltip: 'Next period',
                background: palette.track,
                foreground: palette.ink,
                onTap: canFwd ? () => onStep(1) : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          AnalyticsSwipeChart(
            palette: palette,
            spec: v.chart,
            bucketCents: v.bucketCents,
            typeFilterIndexes: typeFilterIndexes,
            hatchCents: v.hatchCents,
            showHatch: v.showHatch,
            // F2: an all-zero chart has no scale to show; one muted line instead.
            emptyMessage: v.period.granularity == AnalyticsGranularity.day && v.range.start == v.today
                ? 'No spending yet today'
                : 'No spending in this period',
            // Future buckets don't count towards the daily average.
            onSwipe: (dir) => onStep(dir),
            onBucket: onBucket,
          ),
          if (legend.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                legend,
                key: const Key('analyticsChartLegend'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: palette.mutedInk),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 13),
            child: Text(
              v.chart.hint,
              key: const Key('analyticsChartHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: palette.mutedInk),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line under the chart: the spec's own text (the part-week note) and, when
/// the chart's period holds cash taken out, one more part joined with " · ":
/// what the hatching means (preference on) or that it is not shown (off).
String chartLegendText(String specLegend, {required bool hatched, required bool hasCash}) => [
  if (specLegend.isNotEmpty) specLegend,
  if (hasCash) hatched ? 'Hatched = cash withdrawn, not spent' : 'Cash withdrawn is not shown here (not spending)',
].join(' · ');
