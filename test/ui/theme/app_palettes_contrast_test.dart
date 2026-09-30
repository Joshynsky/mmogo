// T23 cheap contrast check: onPrimary text/icons on the primary button
// colour must clear WCAG's 4.5:1 (AA, normal text) bar in every one of the
// 6 shipped token sets (3 palettes x light/dark) — the orchestrator's own
// pre-build check, kept here as a
// permanent unit test so a future palette edit can't silently regress it.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/ui/theme/app_colors.dart';

/// WCAG 2.x relative luminance (sRGB), per the spec's own formula.
double _relativeLuminance(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two colours (order-independent).
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final sets = <String, AppPalette>{
    'ocean light': AppPalette.light,
    'ocean dark': AppPalette.dark,
    'leaf light': AppPalette.leafLight,
    'leaf dark': AppPalette.leafDark,
    'indigo light': AppPalette.indigoLight,
    'indigo dark': AppPalette.indigoDark,
  };

  test('AppPalettes.all covers exactly these 6 sets', () {
    final fromRegistry = <AppPalette>{for (final s in AppPalettes.all) s.light, for (final s in AppPalettes.all) s.dark};
    expect(fromRegistry, sets.values.toSet());
  });

  for (final entry in sets.entries) {
    test('${entry.key}: onPrimary on primary is >= 4.5:1', () {
      final ratio = _contrastRatio(entry.value.onPrimary, entry.value.primary);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key} onPrimary/primary contrast was ${ratio.toStringAsFixed(2)}:1',
      );
    });
  }

  // T26 "yes switch them to dark initials": onTypeColor (the avatar
  // initials) must clear 3:1 against each of the 4 type colours in every
  // one of the 6 sets, not just the primary button.
  for (final entry in sets.entries) {
    final palette = entry.value;
    final types = <String, Color>{
      'typeSendMoney': palette.typeSendMoney,
      'typePaybill': palette.typePaybill,
      'typeBuyGoods': palette.typeBuyGoods,
      'typeCash': palette.typeCash,
    };
    for (final typeEntry in types.entries) {
      test('${entry.key}: onTypeColor on ${typeEntry.key} is >= 3:1', () {
        final ratio = _contrastRatio(palette.onTypeColor, typeEntry.value);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '${entry.key} onTypeColor/${typeEntry.key} contrast was ${ratio.toStringAsFixed(2)}:1',
        );
      });
    }
  }
}
