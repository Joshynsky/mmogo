import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/analytics/chart_blocks.dart' show fitAmount;
import '../../../domain/format/source_types.dart';
import '../../theme/app_colors.dart';

/// §ANALYTICS.CHART.PAINTER — the chart's painter, amount-line plan and empty
/// test (moved out of swipe_chart.dart in 0.1.2 S6c, no change).
class AnalyticsChartPainter extends CustomPainter {
  AnalyticsChartPainter({
    required this.palette,
    required this.spec,
    required this.bucketCents,
    required this.typeFilterIndexes,
    required this.textScaler,
    this.hatchCents = const [],
    this.empty = false,
    this.tipIndex,
  });

  /// Chart height in chart units: Year with amount lines under the months is
  /// taller (the mock's viewBox 152).
  static double heightFor(ChartSpec spec) => spec.under == ChartUnder.none ? h : 152.0;

  /// The bar showing its tooltip: the others dim.
  final int? tipIndex;

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
  final Set<int> typeFilterIndexes;
  final TextScaler textScaler;

  /// Cash taken out per bucket (cents), drawn as a hatched segment on top of
  /// the bar; empty = not drawn. It adds to the bar's height only: the
  /// average line and the amount lines stay on spending.
  final List<int> hatchCents;

  /// Every bucket is 0 (F2): no y labels, no dashed gridlines, no average —
  /// just the baseline and the x labels.
  final bool empty;

  /// Same order as the bucket columns (`sourceTypeOrder`).
  static final _types = [for (final (code, _) in sourceTypeOrder) code];

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

  /// A part week: light diagonal stripes over the colours (the mock's `phatch`).
  void _stripes(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = palette.card.withValues(alpha: 0.28));
    final p = Paint()
      ..color = palette.card
      ..strokeWidth = 2.5;
    for (var off = -r.height; off < r.width; off += 6) {
      canvas.drawLine(Offset(r.left + off, r.bottom), Offset(r.left + off + r.height, r.top), p);
    }
  }

  /// Cash taken out: the Withdrawal colour in 45 degree lines on the card
  /// colour, with a 1 px outline (the mock's `hatch`).
  void _hatch(Canvas canvas, Rect r, double opacity) {
    final c = palette.typeWithdrawal.withValues(alpha: opacity);
    canvas.drawRect(r, Paint()..color = palette.card.withValues(alpha: opacity));
    final p = Paint()
      ..color = c
      ..strokeWidth = 2;
    for (var off = -r.height; off < r.width; off += 5 * math.sqrt2) {
      canvas.drawLine(Offset(r.left + off, r.bottom), Offset(r.left + off + r.height, r.top), p);
    }
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = c,
    );
  }

  /// A thin line with end ticks and the amount on it, |--48k--| (Year).
  void _amountLine(Canvas canvas, ChartAmountLine a) {
    const ly = b + 25;
    final line = Paint()
      ..color = palette.line.withValues(alpha: a.off ? 0.4 : 1)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(a.x1, ly - 2.5), Offset(a.x1, ly + 2.5), line);
    canvas.drawLine(Offset(a.x1, ly), Offset(a.x2, ly), line);
    canvas.drawLine(Offset(a.x2, ly - 2.5), Offset(a.x2, ly + 2.5), line);
    if (a.label.isNotEmpty) {
      _text(
        canvas,
        a.label,
        Offset((a.x1 + a.x2) / 2, ly + 3),
        size: 8.5,
        weight: FontWeight.w700,
        align: TextAlign.center,
        color: palette.softInk,
        halo: true,
      );
    }
  }

  // ---- S9a: the avg label stays off the hatched segments ----

  List<double> get _totals => [for (final v in bucketCents) v.fold<int>(0, (s, c) => s + c) / 100.0];

  double _hatchAt(int i) => i < hatchCents.length ? hatchCents[i] / 100.0 : 0.0;

  double get _nice {
    final totals = _totals;
    final max = [for (var i = 0; i < spec.buckets.length; i++) totals[i] + _hatchAt(i)].fold<double>(1, math.max);
    return niceAxisMax(max);
  }

  /// The daily average over the days so far (0 when there is none).
  double get _average {
    final totals = _totals;
    var sum = 0.0;
    var live = 0;
    for (var i = 0; i < spec.buckets.length; i++) {
      if (spec.buckets[i].future) continue;
      sum += totals[i];
      live++;
    }
    return live == 0 ? 0.0 : sum / live;
  }

  String _avgText(double avg) => 'avg ${kshShort(avg.roundToDouble())}';

  /// The hatched segment of every bucket, in chart units.
  List<Rect> hatchRects() {
    final n = spec.buckets.length;
    final totals = _totals;
    final nice = _nice;
    const hh = b - t;
    final slot = (r - l) / n;
    final bw = math.max(math.min(slot * (n > 20 && n < 32 ? 0.72 : 0.56), 28.0), 3.0);
    return [
      for (var i = 0; i < n; i++)
        if (_hatchAt(i) > 0)
          Rect.fromLTWH(
            l + slot * i + (slot - bw) / 2,
            b - (totals[i] + _hatchAt(i)) / nice * hh,
            bw,
            _hatchAt(i) / nice * hh,
          ),
    ];
  }

  /// Where the "avg" label goes (chart units): at the left end, slid right
  /// until it clears every hatched segment; null (label hidden) when there is
  /// no free spot, or no average to show.
  Rect? avgLabelRect() {
    if (!spec.showAverage || empty) return null;
    final avg = _average;
    if (avg <= 0) return null;
    final tp = TextPainter(
      text: TextSpan(text: _avgText(avg), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final width = tp.width;
    tp.dispose();
    final yAvg = b - avg / _nice * (b - t);
    final hatches = hatchRects();
    for (var x = l + 3; x + width <= r; x += 2) {
      // 9 above the baseline (y - 4), 3 below, 2 of halo each side.
      final box = Rect.fromLTWH(x - 2, yAvg - 4 - 11, width + 4, 16);
      if (hatches.every((h) => !h.overlaps(box))) return Rect.fromLTWH(x, box.top, width, box.height);
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / w);

    final n = spec.buckets.length;
    final totals = [for (final v in bucketCents) v.fold<int>(0, (s, c) => s + c) / 100.0];
    double hatchAt(int i) => i < hatchCents.length ? hatchCents[i] / 100.0 : 0.0;
    final max = [for (var i = 0; i < n; i++) totals[i] + hatchAt(i)].fold<double>(1, math.max);
    final nice = niceAxisMax(max);
    const hh = b - t;
    double y(double v) => b - v / nice * hh;
    final slot = (r - l) / n;
    final bw = math.max(math.min(slot * (n > 20 && n < 32 ? 0.72 : 0.56), 28.0), 3.0);

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
      final barH = (totals[i] + hatchAt(i)) / nice * hh;
      if (bucket.future && spec.futureStubs) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, b - 3, bw, 3), const Radius.circular(1.5)),
          Paint()..color = palette.line.withValues(alpha: 0.6),
        );
      }
      if (barH > 0) {
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, b - barH, bw, barH), Radius.circular(math.min(4, bw / 2))),
        );
        final dim = tipIndex != null && i != tipIndex ? 0.35 : (bucket.selected ? 1.0 : 0.3);
        var acc = 0.0;
        for (var k = 0; k < _types.length; k++) {
          final cents = bucketCents[i][k];
          if (cents == 0) continue;
          final sh = cents / 100.0 / nice * hh;
          acc += sh;
          final faded = typeFilterIndexes.isNotEmpty && !typeFilterIndexes.contains(k) ? 0.22 : 1.0;
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
        final cash = hatchAt(i);
        if (cash > 0) {
          final sh = cash / nice * hh;
          acc += sh;
          final withdrawalIndex = _types.indexOf('AGENT_WITHDRAWAL');
          final faded = typeFilterIndexes.isNotEmpty && !typeFilterIndexes.contains(withdrawalIndex) ? 0.22 : 1.0;
          _hatch(canvas, Rect.fromLTWH(x, b - acc, bw, sh), dim * faded);
        }
        if (bucket.part) _stripes(canvas, Rect.fromLTWH(x, b - barH, bw, barH));
        canvas.restore();
      }
      final bold = (bucket.selected && spec.labelSelected) || tipIndex == i;
      if (bucket.label.isNotEmpty) {
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
      if (bucket.sub.isNotEmpty) {
        _text(
          canvas,
          bucket.sub,
          Offset(x + bw / 2, b + 24),
          size: 8.5,
          align: TextAlign.center,
          color: palette.mutedInk.withValues(alpha: bucket.future ? 0.5 : 1),
        );
      }
    }
    for (final line in chartAmountLines(spec, bucketCents)) {
      _amountLine(canvas, line);
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
        // S9a: the label never sits on a hatched segment; hidden when no spot is free.
        final box = avgLabelRect();
        if (box != null) {
          _text(
            canvas,
            _avgText(avg),
            Offset(box.left, y(avg) - 4),
            size: 9,
            weight: FontWeight.w700,
            color: palette.softInk,
            halo: true,
          );
        }
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
  bool shouldRepaint(AnalyticsChartPainter old) =>
      old.palette != palette ||
      old.spec != spec ||
      old.bucketCents != bucketCents ||
      old.typeFilterIndexes != typeFilterIndexes ||
      old.hatchCents != hatchCents ||
      old.tipIndex != tipIndex ||
      old.empty != empty;
}

/// `true` when every bucket of the chart is 0 (F2's empty-chart state).
bool analyticsChartIsEmpty(List<List<int>> bucketCents) => bucketCents.every((b) => b.every((c) => c == 0));

/// One |--amount--| line under the Year bars, in chart units. [label] is ''
/// when nothing is shown on it (a future month or no spending); [off] draws
/// the line faint.
class ChartAmountLine {
  const ChartAmountLine({required this.x1, required this.x2, required this.label, required this.off});

  final double x1;
  final double x2;
  final String label;
  final bool off;
}

/// The amount lines a Year chart draws under its months (S6b): one spanning a
/// quarter's three months (default), or one per month, each in the compact
/// form (48k). Empty for every other chart. The amounts are spending only.
List<ChartAmountLine> chartAmountLines(ChartSpec spec, List<List<int>> bucketCents) {
  if (spec.under == ChartUnder.none || spec.buckets.isEmpty) return const [];
  final n = spec.buckets.length;
  final totals = [for (final v in bucketCents) v.fold<int>(0, (s, c) => s + c) / 100.0];
  const l = AnalyticsChartPainter.l;
  final slot = (AnalyticsChartPainter.r - l) / n;
  String label(double ksh, bool off) => !off && ksh > 0 ? fitAmount(ksh, slot) : '';
  if (spec.under == ChartUnder.months) {
    return [
      for (var i = 0; i < n; i++)
        ChartAmountLine(
          x1: l + slot * i + 2,
          x2: l + slot * (i + 1) - 2,
          label: label(totals[i], spec.buckets[i].future),
          off: spec.buckets[i].future,
        ),
    ];
  }
  return [
    for (var q = 0; q < 4 && 3 * q + 2 < n; q++)
      ChartAmountLine(
        x1: l + slot * 3 * q + 3,
        x2: l + slot * 3 * (q + 1) - 3,
        label: label(totals[3 * q] + totals[3 * q + 1] + totals[3 * q + 2], spec.buckets[3 * q].future),
        off: spec.buckets[3 * q].future,
      ),
  ];
}
