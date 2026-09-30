// Unit tests for lib/domain/home/home_diff.dart — pure Dart, no database.
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/domain/home/home_diff.dart';

void main() {
  test('both totals zero -> noPriorNoSpend', () {
    final r = HomeDiff.compute(thisTotalCents: 0, priorTotalCents: 0);
    expect(r.kind, HomeDiffKind.noPriorNoSpend);
  });

  test('prior zero, this period has spend -> noPriorHasSpend', () {
    final r = HomeDiff.compute(thisTotalCents: 5000, priorTotalCents: 0);
    expect(r.kind, HomeDiffKind.noPriorHasSpend);
  });

  test('spend increased -> up, correct rounded percentage', () {
    // 15000 vs 10000 -> +50%
    final r = HomeDiff.compute(thisTotalCents: 15000, priorTotalCents: 10000);
    expect(r.kind, HomeDiffKind.up);
    expect(r.percent, 50);
  });

  test('equal totals count as up (design: diff >= 0 is the up/red branch)', () {
    final r = HomeDiff.compute(thisTotalCents: 10000, priorTotalCents: 10000);
    expect(r.kind, HomeDiffKind.up);
    expect(r.percent, 0);
  });

  test('spend decreased -> down, correct rounded percentage', () {
    // 5000 vs 10000 -> -50%
    final r = HomeDiff.compute(thisTotalCents: 5000, priorTotalCents: 10000);
    expect(r.kind, HomeDiffKind.down);
    expect(r.percent, 50);
  });

  test('percentage rounds to nearest whole number', () {
    // diff = 1, prior = 3 -> 33.33...% rounds to 33
    final r = HomeDiff.compute(thisTotalCents: 4, priorTotalCents: 3);
    expect(r.kind, HomeDiffKind.up);
    expect(r.percent, 33);
  });
}
