import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import 'analytics_view.dart';
import 'parts.dart';
import 'swipe_chart.dart';

/// §ANALYTICS.CHART — the chart card: title, prev/next period buttons, the
/// swipeable chart and its hint. [canBack]/[canForward] come from the shell's
/// live `_period` (not `view.period`); [typeFilterIndex] is the index of the
/// active type filter in `analyticsTypeOrder`, or null.
class AnalyticsChartCard extends StatelessWidget {
  const AnalyticsChartCard({
    super.key,
    required this.palette,
    required this.view,
    required this.typeFilterIndex,
    required this.canBack,
    required this.canForward,
    required this.onStep,
    required this.onBucket,
  });

  final AppPalette palette;
  final AnalyticsView view;
  final int? typeFilterIndex;
  final bool canBack;
  final bool canForward;
  final ValueChanged<int> onStep;
  final ValueChanged<ChartBucket> onBucket;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final canFwd = canForward;
    final typeIndex = typeFilterIndex;
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
            typeFilterIndex: typeIndex,
            // F2: an all-zero chart has no scale to show; one muted line instead.
            emptyMessage: v.period.granularity == AnalyticsGranularity.day && v.range.start == v.today
                ? 'No spending yet today'
                : 'No spending in this period',
            // Future buckets don't count towards the daily average.
            onSwipe: (dir) => onStep(dir),
            onBucket: onBucket,
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
