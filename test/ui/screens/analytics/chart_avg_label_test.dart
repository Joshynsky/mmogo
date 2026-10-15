// 0.1.2 S9a: the "avg" label never sits on a hatched (withdrawal) segment.
// Pure geometry on the painter: no widgets, no database.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/format/source_types.dart';
import 'package:mmogo/ui/screens/analytics/chart_painter.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

ChartSpec _week({bool avg = true}) => ChartSpec(
  buckets: [for (var i = 0; i < 7; i++) ChartBucket(label: 'M', startMs: i, endMs: i + 1)],
  title: 'By day',
  hint: '',
  showAverage: avg,
  labelSelected: false,
);

AnalyticsChartPainter _painter({required List<int> hatch, bool avg = true, int spend = 10000}) => AnalyticsChartPainter(
  palette: AppPalette.light,
  spec: _week(avg: avg),
  bucketCents: [
    for (var i = 0; i < 7; i++) [spend, for (var k = 1; k < sourceTypeOrder.length; k++) 0],
  ],
  typeFilterIndexes: const {},
  textScaler: TextScaler.noScaling,
  hatchCents: hatch,
);

void main() {
  test('no hatch: the label stays at the left end', () {
    final box = _painter(hatch: const []).avgLabelRect();
    expect(box, isNotNull);
    expect(box!.left, AnalyticsChartPainter.l + 3);
  });

  test('a hatched segment under the left end pushes the label right, clear of every hatch', () {
    final p = _painter(hatch: const [5000, 0, 0, 0, 0, 0, 0]);
    final box = p.avgLabelRect();
    expect(box, isNotNull);
    expect(box!.left, greaterThan(AnalyticsChartPainter.l + 3), reason: 'it moved');
    for (final h in p.hatchRects()) {
      expect(h.overlaps(box.inflate(2)), isFalse, reason: 'no overlap with $h');
    }
  });

  test('hatch on every bar and no free spot: the label is hidden, never drawn on a hatch', () {
    final p = _painter(hatch: List.filled(7, 5000));
    final box = p.avgLabelRect();
    if (box != null) {
      for (final h in p.hatchRects()) {
        expect(h.overlaps(box.inflate(2)), isFalse);
      }
    }
    expect(box, isNull, reason: 'seven wide hatched bars at the average line leave no gap of label width');
  });

  test('no average line, no label', () {
    expect(_painter(hatch: const [], avg: false).avgLabelRect(), isNull);
  });
}
