import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';
import 'chart_painter.dart';

export 'chart_painter.dart' show ChartAmountLine, chartAmountLines, analyticsChartIsEmpty;

/// §ANALYTICS.CHART.PAINT — the swipeable stacked bar chart and its painter.
/// The stacked bar chart in the mock's 320×146 SVG space, scaled to the card
/// width. Swipe right = earlier, left = later (a ~45dp threshold); bars that
/// lead somewhere are tappable.
class AnalyticsSwipeChart extends StatefulWidget {
  const AnalyticsSwipeChart({
    super.key,
    required this.palette,
    required this.spec,
    required this.bucketCents,
    required this.typeFilterIndexes,
    required this.emptyMessage,
    required this.onSwipe,
    required this.onBucket,
    this.hatchCents = const [],
    this.showHatch = false,
  });

  final AppPalette palette;
  final ChartSpec spec;
  final List<List<int>> bucketCents;

  /// The picked types as indexes into the bucket columns (empty = no filter):
  /// the others fade.
  final Set<int> typeFilterIndexes;

  /// Per bucket, cash taken out in cents (S6c). Drawn as a hatched segment on
  /// top of the bar only when [showHatch] is on; never part of [bucketCents].
  final List<int> hatchCents;
  final bool showHatch;

  /// Shown, centred and muted, when every bucket is 0 (F2).
  final String emptyMessage;
  final ValueChanged<int> onSwipe;
  final ValueChanged<ChartBucket>? onBucket;

  @override
  State<AnalyticsSwipeChart> createState() => _SwipeChartState();
}

class _SwipeChartState extends State<AnalyticsSwipeChart> {
  double _dx = 0;
  bool _dragging = false;

  /// The bar whose tooltip is showing (Month: first tap = tooltip, second
  /// tap = open). Cleared whenever the chart shows another period.
  int? _tip;

  static const _threshold = 45.0;

  @override
  void didUpdateWidget(AnalyticsSwipeChart old) {
    super.didUpdateWidget(old);
    if (_tip != null && !_sameWindow(old.spec, widget.spec)) _tip = null;
  }

  static bool _sameWindow(ChartSpec a, ChartSpec b) =>
      a.title == b.title &&
      a.buckets.length == b.buckets.length &&
      (a.buckets.isEmpty ||
          (a.buckets.first.startMs == b.buckets.first.startMs && a.buckets.last.endMs == b.buckets.last.endMs));

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final n = spec.buckets.length;
    final hatch = _hatchList();
    final empty = analyticsChartIsEmpty(widget.bucketCents) && hatch.every((c) => c == 0);
    final tip = _tip != null && _tip! < n && spec.buckets[_tip!].hasTip ? _tip : null;
    final under = spec.under != ChartUnder.none;
    return GestureDetector(
      key: const Key('analyticsChart'),
      onHorizontalDragStart: (_) => setState(() {
        _dragging = true;
        _dx = 0;
      }),
      onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
      onHorizontalDragEnd: (_) {
        final dx = _dx;
        setState(() {
          _dragging = false;
          _dx = 0;
        });
        if (dx.abs() > _threshold) widget.onSwipe(dx > 0 ? -1 : 1);
      },
      onHorizontalDragCancel: () => setState(() {
        _dragging = false;
        _dx = 0;
      }),
      child: AnimatedOpacity(
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
        opacity: 1 - math.min(_dx.abs(), 60) / 150,
        child: AnimatedContainer(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(_dx.abs() > 6 ? _dx.clamp(-60.0, 60.0) : 0, 0, 0),
          child: LayoutBuilder(
            builder: (context, c) {
              final s = c.maxWidth / AnalyticsChartPainter.w;
              final slot = (AnalyticsChartPainter.r - AnalyticsChartPainter.l) / math.max(n, 1);
              return SizedBox(
                width: c.maxWidth,
                height: AnalyticsChartPainter.heightFor(spec) * s,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        key: Key(empty ? 'analyticsChartPaintEmpty' : 'analyticsChartPaint'),
                        painter: AnalyticsChartPainter(
                          palette: widget.palette,
                          spec: spec,
                          bucketCents: widget.bucketCents,
                          typeFilterIndexes: widget.typeFilterIndexes,
                          hatchCents: hatch,
                          textScaler: MediaQuery.textScalerOf(context),
                          empty: empty,
                          tipIndex: tip,
                        ),
                      ),
                    ),
                    if (empty)
                      Positioned(
                        left: AnalyticsChartPainter.l * s,
                        right: (AnalyticsChartPainter.w - AnalyticsChartPainter.r) * s,
                        top: AnalyticsChartPainter.t * s,
                        height: (AnalyticsChartPainter.b - AnalyticsChartPainter.t) * s,
                        child: Center(
                          child: Text(
                            widget.emptyMessage,
                            key: const Key('analyticsChartEmpty'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: widget.palette.mutedInk,
                            ),
                          ),
                        ),
                      ),
                    for (var i = 0; i < n; i++)
                      Positioned(
                        left: (AnalyticsChartPainter.l + slot * i) * s,
                        top: AnalyticsChartPainter.t * s,
                        width: slot * s,
                        height: (AnalyticsChartPainter.b - AnalyticsChartPainter.t + (under ? 32 : 16)) * s,
                        child: _barHit(i),
                      ),
                    if (tip != null) _tipBox(tip, slot, s),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The hatched amounts to draw: the preference's, one per bucket, else none.
  List<int> _hatchList() => widget.showHatch && widget.hatchCents.length == widget.spec.buckets.length
      ? widget.hatchCents
      : const [];

  Widget _barHit(int i) {
    final b = widget.spec.buckets[i];
    final cents = widget.bucketCents[i].fold<int>(0, (s, c) => s + c);
    final hatch = _hatchList();
    final cash = hatch.isEmpty ? 0 : hatch[i];
    final tap = widget.onBucket != null && b.tappable;
    return Semantics(
      button: tap,
      label: '${b.name ?? b.label}: ${formatKsh(cents)}${cash > 0 ? ' spent, ${formatKsh(cash)} withdrawn (not spent)' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('analyticsBar-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: tap
            ? () {
                // Month: the first tap shows the bar's tooltip, the second opens it.
                if (b.hasTip && _tip != i) {
                  setState(() => _tip = i);
                  return;
                }
                widget.onBucket!(b);
              }
            : null,
      ),
    );
  }

  /// The tooltip of the tapped bar (mock: a small ink box near the top, kept
  /// inside the chart).
  Widget _tipBox(int i, double slot, double s) {
    final cents = widget.bucketCents[i].fold<int>(0, (a, c) => a + c);
    final lines = widget.spec.buckets[i].tipLines!(cents);
    final longest = lines.fold<int>(0, (m, l) => math.max(m, l.length));
    final w = longest * 5.0 + 14;
    final h = lines.length * 12.0 + 8;
    final cx = AnalyticsChartPainter.l + slot * i + slot / 2;
    final x = math.max(2.0, math.min(cx - w / 2, AnalyticsChartPainter.r - w));
    final p = widget.palette;
    return Positioned(
      left: x * s,
      top: 0,
      width: w * s,
      height: h * s,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: lines.join('. '),
          excludeSemantics: true,
          child: Container(
            key: const Key('analyticsChartTip'),
            padding: EdgeInsets.fromLTRB(7 * s, 3 * s, 4 * s, 1 * s),
            decoration: BoxDecoration(color: p.ink.withValues(alpha: 0.96), borderRadius: BorderRadius.circular(6 * s)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < lines.length; k++)
                  SizedBox(
                    height: 12 * s,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        lines[k],
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: (k == 1 ? 10 : 9) * s,
                          fontWeight: k == 1 ? FontWeight.w800 : FontWeight.w600,
                          color: p.background,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
