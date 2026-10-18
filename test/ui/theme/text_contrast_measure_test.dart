// 0.1.2 F7 (R12, R56): a MEASUREMENT, not a gate. It computes the WCAG contrast of the text and button
// pairs the app really draws, in all 6 shipped themes, and prints a table. Failures go in the table
// (the PM decides any colour fix); the only assertions are that the measuring code itself is right.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a);
  final lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [c] drawn over an opaque [under] (alpha composite).
Color _over(Color c, Color under) => Color.alphaBlend(c, under);

/// Smallest HSL-lightness change (percentage points, signed) on [fg] that reaches [need] against [bg];
/// null when no lightness change gets there.
String _fix(Color fg, Color bg, double need) {
  final hsl = HSLColor.fromColor(fg);
  for (var step = 1; step <= 100; step++) {
    for (final dir in [1, -1]) {
      final l = hsl.lightness + dir * step / 100;
      if (l < 0 || l > 1) continue;
      if (_ratio(hsl.withLightness(l).toColor(), bg) >= need) return '${dir > 0 ? '+' : '-'}$step pt';
    }
  }
  return 'none';
}

class _Row {
  _Row(this.theme, this.pair, this.fg, this.bg, this.need, {this.reportOnly = false});
  final String theme, pair;
  final Color fg, bg;
  final double need;
  final bool reportOnly;
  double get ratio => _ratio(fg, bg);
  bool get pass => ratio >= need;
}

void main() {
  test('measuring code: black on white = 21:1, #767676 on white = 4.54:1', () {
    expect(_ratio(Colors.black, Colors.white), closeTo(21.0, 0.001));
    expect(_ratio(const Color(0xFF767676), Colors.white), closeTo(4.54, 0.005));
    expect(_ratio(Colors.white, Colors.black), closeTo(21.0, 0.001));
    // Alpha: 50% black over white is #808080-ish (about 4.0:1 on white), not black.
    expect(_ratio(_over(const Color(0x80000000), Colors.white), Colors.white), closeTo(4.0, 0.05));
  });

  test('F7 contrast table (prints; failures are data, not test failures)', () {
    final sets = <String, AppPalette>{
      'Ocean light': AppPalette.light,
      'Ocean dark': AppPalette.dark,
      'Leaf light': AppPalette.leafLight,
      'Leaf dark': AppPalette.leafDark,
      'Indigo light': AppPalette.indigoLight,
      'Indigo dark': AppPalette.indigoDark,
    };
    const sun = Color(0xFFFFB703); // literal in SettingsSectionLabel's careful tag
    const sunInk = Color(0xFF3A2A00);
    final rows = <_Row>[];
    for (final e in sets.entries) {
      final p = e.value;
      final t = e.key;
      // The real ThemeData the widgets inherit: page background and card must be the palette's.
      final theme = AppTheme.forPalette(p);
      final page = theme.scaffoldBackgroundColor;
      final card = theme.colorScheme.surface;
      expect(page, p.background);
      expect(card, p.card);
      void add(String pair, Color fg, Color bg, double need, {bool only = false}) =>
          rows.add(_Row(t, pair, fg, bg, need, reportOnly: only));

      add('1 muted (mutedInk) on page', p.mutedInk, page, 4.5);
      add('1 muted (mutedInk) on card', p.mutedInk, card, 4.5);
      add('1 secondary (softInk) on page', p.softInk, page, 4.5);
      add('1 secondary (softInk) on card', p.softInk, card, 4.5);
      add('2 body (ink) on page', p.ink, page, 4.5);
      add('2 body (ink) on card', p.ink, card, 4.5);
      add('3 section label (mutedInk 11.5 bold) on page', p.mutedInk, page, 4.5);
      add('3 "careful" tag (fixed 3A2A00 on FFB703)', sunInk, sun, 4.5);
      add('3 "NEW" pill (onPrimary on primary)', p.onPrimary, p.primary, 4.5);
      add('3 "Default" tag (mutedInk on card)', p.mutedInk, card, 4.5);
      add('4 pager button label (tintInk on tint)', p.tintInk, p.tint, 4.5);
      add('4 pager button tint vs sheet (card), component', p.tint, card, 3.0);
      final chip = _over(p.highlight, card);
      add('5 amber chip text (ink on highlight)', p.ink, chip, 4.5);
      add('5 amber chip fill vs card (info, text is inside), report only', chip, card, 3.0, only: true);
      add('6 disabled Delete (mutedInk on track), report only', p.mutedInk, p.track, 4.5, only: true);
    }

    final b = StringBuffer('\nF7 CONTRAST TABLE\n');
    b.writeln('theme | pair | ratio | need | result | smallest lightness fix (info)');
    final fails = <String, int>{};
    for (final r in rows) {
      final res = r.reportOnly ? 'REPORT' : (r.pass ? 'PASS' : 'FAIL');
      if (res == 'FAIL') fails[r.theme] = (fails[r.theme] ?? 0) + 1;
      final fix = res == 'FAIL' ? _fix(r.fg, r.bg, r.need) : '';
      b.writeln('${r.theme} | ${r.pair} | ${r.ratio.toStringAsFixed(2)} | ${r.need} | $res | $fix');
    }
    b.writeln('FAIL counts: $fails');
    // ignore: avoid_print
    print(b);
    expect(rows.length, 6 * 15);
  });
}
