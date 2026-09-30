import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';

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
    required this.typeFilterIndex,
    required this.emptyMessage,
    required this.onSwipe,
    required this.onBucket,
  });

  final AppPalette palette;
  final ChartSpec spec;
  final List<List<int>> bucketCents;
  final int? typeFilterIndex;

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

  static const _threshold = 45.0;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final n = spec.buckets.length;
    final empty = analyticsChartIsEmpty(widget.bucketCents);
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
              final s = c.maxWidth / _ChartPainter.w;
              final slot = (_ChartPainter.r - _ChartPainter.l) / math.max(n, 1);
              return SizedBox(
                width: c.maxWidth,
                height: _ChartPainter.h * s,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        key: Key(empty ? 'analyticsChartPaintEmpty' : 'analyticsChartPaint'),
                        painter: _ChartPainter(
                          palette: widget.palette,
                          spec: spec,
                          bucketCents: widget.bucketCents,
                          typeFilterIndex: widget.typeFilterIndex,
                          textScaler: MediaQuery.textScalerOf(context),
                          empty: empty,
                        ),
                      ),
                    ),
                    if (empty)
                      Positioned(
                        left: _ChartPainter.l * s,
                        right: (_ChartPainter.w - _ChartPainter.r) * s,
                        top: _ChartPainter.t * s,
                        height: (_ChartPainter.b - _ChartPainter.t) * s,
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
                        left: (_ChartPainter.l + slot * i) * s,
                        top: _ChartPainter.t * s,
                        width: slot * s,
                        height: (_ChartPainter.b - _ChartPainter.t + 16) * s,
                        child: _barHit(i),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _barHit(int i) {
    final b = widget.spec.buckets[i];
    final cents = widget.bucketCents[i].fold<int>(0, (s, c) => s + c);
    final tap = widget.onBucket != null && b.tappable;
    return Semantics(
      button: tap,
      label: '${b.label}: ${formatKsh(cents)}',
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('analyticsBar-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: tap ? () => widget.onBucket!(b) : null,
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.palette,
    required this.spec,
    required this.bucketCents,
    required this.typeFilterIndex,
    required this.textScaler,
    this.empty = false,
  });

  // The mock's SVG geometry (viewBox 0 0 320 146).
  static const w = 320.0;
  static const h = 146.0;
  static const l = 30.0;
  static const r = 318.0;
  static const t = 12.0;
  static const b = 118.0;

  final AppPalette palette;
  final ChartSpec spec;
  final List<List<int>> bucketCents;
  final int? typeFilterIndex;
  final TextScaler textScaler;

  /// Every bucket is 0 (F2): no y labels, no dashed gridlines, no average —
  /// just the baseline and the x labels.
  final bool empty;

  static const _types = ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'CASH'];

  void _text(
    Canvas canvas,
    String text,
    Offset anchor, {
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w400,
    TextAlign align = TextAlign.left,
    bool halo = false,
  }) {
    TextPainter painter(Paint? foreground) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: foreground == null ? color : null,
          foreground: foreground,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final fill = painter(null);
    // SVG `y` is the baseline; `text-anchor` start / middle / end.
    final baseline = fill.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final dx = switch (align) {
      TextAlign.center => -fill.width / 2,
      TextAlign.right => -fill.width,
      _ => 0.0,
    };
    final at = Offset(anchor.dx + dx, anchor.dy - baseline);
    if (halo) {
      final stroke = painter(
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..color = palette.card,
      );
      stroke.paint(canvas, at);
      stroke.dispose();
    }
    fill.paint(canvas, at);
    fill.dispose();
  }

  void _dashed(Canvas canvas, double y, Paint paint, double dash, double gap) {
    for (var x = l; x < r; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, r), y), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / w);

    final n = spec.buckets.length;
    final totals = [for (final v in bucketCents) v.fold<int>(0, (s, c) => s + c) / 100.0];
    final max = totals.fold<double>(1, math.max);
    final nice = niceAxisMax(max);
    const hh = b - t;
    double y(double v) => b - v / nice * hh;
    final slot = (r - l) / n;
    final bw = math.max(math.min(slot * 0.56, 28.0), 3.0);

    // Gridlines at 0, ½ and the nice max, with short labels.
    final grid = Paint()
      ..color = palette.line
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final v = nice * f;
      if (empty) {
        if (f == 0) canvas.drawLine(Offset(l, y(v)), Offset(r, y(v)), grid);
        continue;
      }
      if (f == 0) {
        canvas.drawLine(Offset(l, y(v)), Offset(r, y(v)), grid);
      } else {
        _dashed(canvas, y(v), grid, 2, 4);
      }
      _text(canvas, kshShort(v), Offset(l - 5, y(v) + 3), size: 9, color: palette.mutedInk, align: TextAlign.right);
    }

    for (var i = 0; i < n; i++) {
      final bucket = spec.buckets[i];
      final x = l + slot * i + (slot - bw) / 2;
      final barH = totals[i] / nice * hh;
      if (barH > 0) {
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, b - barH, bw, barH), Radius.circular(math.min(4, bw / 2))),
        );
        final dim = bucket.selected ? 1.0 : 0.3;
        var acc = 0.0;
        for (var k = 0; k < _types.length; k++) {
          final cents = bucketCents[i][k];
          if (cents == 0) continue;
          final sh = cents / 100.0 / nice * hh;
          acc += sh;
          final faded = typeFilterIndex != null && typeFilterIndex != k ? 0.22 : 1.0;
          canvas.drawRect(
            Rect.fromLTWH(x, b - acc, bw, sh),
            Paint()..color = palette.typeColor(_types[k]).withValues(alpha: dim * faded),
          );
          if (acc < barH - 0.5) {
            canvas.drawLine(
              Offset(x, b - acc),
              Offset(x + bw, b - acc),
              Paint()
                ..color = palette.card.withValues(alpha: dim)
                ..strokeWidth = 1.5,
            );
          }
        }
        canvas.restore();
      }
      if (bucket.label.isNotEmpty) {
        final bold = bucket.selected && spec.labelSelected;
        _text(
          canvas,
          bucket.label,
          Offset(x + bw / 2, b + 13),
          size: 9.5,
          align: TextAlign.center,
          weight: bold ? FontWeight.w800 : FontWeight.w400,
          color: bold ? palette.ink : palette.mutedInk.withValues(alpha: bucket.future ? 0.5 : 1),
        );
      }
    }

    // Dashed daily-average line (Week and Custom), over the days so far.
    if (spec.showAverage && !empty) {
      var sum = 0.0;
      var live = 0;
      for (var i = 0; i < n; i++) {
        if (spec.buckets[i].future) continue;
        sum += totals[i];
        live++;
      }
      final avg = live == 0 ? 0.0 : sum / live;
      if (avg > 0) {
        final p = Paint()
          ..color = palette.ink.withValues(alpha: 0.55)
          ..strokeWidth = 1.2;
        _dashed(canvas, y(avg), p, 5, 4);
        _text(
          canvas,
          'avg ${kshShort(avg.roundToDouble())}',
          Offset(l + 3, y(avg) - 4),
          size: 9,
          weight: FontWeight.w700,
          color: palette.softInk,
          halo: true,
        );
      }
    }

    // Month: the chosen month's value above its bar.
    if (spec.labelSelected && !empty) {
      final i = spec.buckets.indexWhere((bk) => bk.selected);
      if (i >= 0) {
        final x = l + slot * i + slot / 2;
        _text(
          canvas,
          kshShort(totals[i]),
          Offset(x, math.max(y(totals[i]) - 5, t + 8)),
          size: 10,
          weight: FontWeight.w800,
          align: TextAlign.center,
          color: palette.ink,
          halo: true,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.palette != palette ||
      old.spec != spec ||
      old.bucketCents != bucketCents ||
      old.typeFilterIndex != typeFilterIndex ||
      old.empty != empty;
}

/// `true` when every bucket of the chart is 0 (F2's empty-chart state).
bool analyticsChartIsEmpty(List<List<int>> bucketCents) => bucketCents.every((b) => b.every((c) => c == 0));
