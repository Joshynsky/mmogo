// S11b CB5 / addendum B2: adjacent stacked segments are split by a thin line in
// the card colour (chart_painter.dart, 1.5 wide, skipped for the top segment,
// dim applied). A recording canvas lists every drawLine; no widgets, no database.
//
// Cash hatch finding (checked once): the hatch is drawn after the type loop, and
// the loop draws the line above the last type segment whenever anything sits
// above it, so a type segment under a hatch also gets its boundary line. Pinned
// in the third test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/format/source_types.dart';
import 'package:mmogo/ui/screens/analytics/chart_painter.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

class _Line {
  _Line(this.a, this.b, this.paint);
  final Offset a;
  final Offset b;
  final Paint paint;
}

/// Records drawLine only; every other call is accepted and ignored.
class _Recorder implements Canvas {
  final lines = <_Line>[];
  final rectColours = <int>[];

  @override
  void drawRect(Rect rect, Paint paint) => rectColours.add(paint.color.toARGB32());

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add(_Line(p1, p2, Paint()..color = paint.color..strokeWidth = paint.strokeWidth));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 7 day-buckets. [cells] maps a bucket index to its per-type cents (index = sourceTypeOrder).
AnalyticsChartPainter _painter(Map<int, Map<int, int>> cells, {List<int> hatch = const [], AppPalette? palette}) {
  final spec = ChartSpec(
    buckets: [for (var i = 0; i < 7; i++) ChartBucket(label: 'M', startMs: i, endMs: i + 1)],
    title: 'By day',
    hint: '',
    showAverage: false,
    labelSelected: false,
  );
  return AnalyticsChartPainter(
    palette: palette ?? AppPalette.light,
    spec: spec,
    bucketCents: [
      for (var i = 0; i < 7; i++)
        [for (var k = 0; k < sourceTypeOrder.length; k++) cells[i]?[k] ?? 0],
    ],
    typeFilterIndexes: const {},
    textScaler: TextScaler.noScaling,
    hatchCents: hatch,
  );
}

/// The card-coloured 1.5 px lines, grouped by the bucket they sit in (by x).
List<_Line> _separators(AnalyticsChartPainter p, AppPalette palette) {
  final rec = _Recorder();
  p.paint(rec, const Size(320, 146));
  return [
    for (final l in rec.lines)
      if (l.paint.strokeWidth == 1.5 && l.paint.color.toARGB32() == palette.card.toARGB32()) l,
  ];
}

int _bucketOf(_Line l) {
  const slot = (AnalyticsChartPainter.r - AnalyticsChartPainter.l) / 7;
  return ((l.a.dx - AnalyticsChartPainter.l) / slot).floor();
}

void main() {
  for (final (name, palette) in [('light', AppPalette.light), ('dark', AppPalette.dark)]) {
    group('separator lines, $name palette', () {
      test('one line at each internal boundary, none above the top segment', () {
        // bucket 0: three segments (two boundaries); bucket 1: two (one); bucket 2: one (none)
        final p = _painter({
          0: {0: 10000, 1: 5000, 3: 2000},
          1: {2: 8000, 4: 1000},
          2: {0: 9000},
        }, palette: palette);
        final lines = _separators(p, palette);
        final per = <int, int>{};
        for (final l in lines) {
          per[_bucketOf(l)] = (per[_bucketOf(l)] ?? 0) + 1;
        }
        expect(per, {0: 2, 1: 1});
        // Each is horizontal and as wide as the bar.
        for (final l in lines) {
          expect(l.a.dy, l.b.dy);
          expect(l.b.dx - l.a.dx, greaterThan(3));
        }
      });

      test('a single-segment bar has no separator', () {
        expect(_separators(_painter({0: {0: 10000}, 3: {5: 700}}, palette: palette), palette), isEmpty);
      });

      test('a type segment under a cash hatch gets its boundary line; the hatch top does not', () {
        final p = _painter({0: {0: 10000}}, hatch: const [4000], palette: palette);
        final lines = _separators(p, palette);
        expect(lines.length, 1, reason: 'type segment | hatch');
        expect(_bucketOf(lines.single), 0);
      });

      test('the line is the card colour (dim applied through alpha, never another colour)', () {
        final p = _painter({0: {0: 10000, 1: 5000}}, palette: palette);
        final rec = _Recorder();
        p.paint(rec, const Size(320, 146));
        final sep = rec.lines.where((l) => l.paint.strokeWidth == 1.5).toList();
        expect(sep, isNotEmpty);
        for (final l in sep) {
          expect(l.paint.color.toARGB32() | 0xFF000000, palette.card.toARGB32());
        }
      });
    });
  }

  // CB5: the colour the chart draws a type in is the colour its By type tile (the
  // legend, name beside it) shows: both come from palette.typeColor(code).
  for (final (name, palette) in [('light', AppPalette.light), ('dark', AppPalette.dark)]) {
    test('each series is drawn in its type colour, in sourceTypeOrder ($name)', () {
      for (var k = 0; k < sourceTypeOrder.length; k++) {
        final p = _painter({0: {k: 10000}}, palette: palette);
        final rec = _Recorder();
        p.paint(rec, const Size(320, 146));
        final want = palette.typeColor(sourceTypeOrder[k].$1).toARGB32() | 0xFF000000;
        expect(rec.rectColours.any((c) => (c | 0xFF000000) == want), isTrue, reason: '${sourceTypeOrder[k].$2} is drawn in its colour');
      }
    });
  }
}
