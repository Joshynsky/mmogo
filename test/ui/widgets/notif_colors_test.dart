import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/widgets/notif_colors.dart';
import 'package:mmogo/ui/widgets/notif_shape_icon.dart';

// Same WCAG formula as test/ui/theme/app_palettes_contrast_test.dart (that
// test's helpers are file-private, so the few lines are repeated here).
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
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

  for (final e in sets.entries) {
    final p = e.value;
    // The bell header sits on background and the mock's rows on surface (card is not used: see hand-back).
    final backs = {'background': p.background, 'surface': p.surface};
    for (final shape in NotifShape.values) {
      final fill = notifShapeColor(p, shape);
      for (final b in backs.entries) {
        test('${e.key}: $shape fill on ${b.key} >= 4.5:1', () {
          final r = _ratio(fill, b.value);
          expect(r, greaterThanOrEqualTo(4.5), reason: '${r.toStringAsFixed(2)}:1');
        });
      }
      test('${e.key}: $shape ink on fill >= 4.5:1', () {
        final r = _ratio(notifShapeInk(p, shape), fill);
        expect(r, greaterThanOrEqualTo(4.5), reason: '${r.toStringAsFixed(2)}:1');
      });
    }
  }

  test('signed mock values are reproduced', () {
    expect(notifBadgeColors(AppPalette.light).notice, const Color(0xFF5B4FC4));
    expect(notifBadgeColors(AppPalette.leafLight).notice, const Color(0xFF1F6F8B));
    expect(notifBadgeColors(AppPalette.indigoDark).notice, const Color(0xFF4FD1C5));
    expect(notifShapeColor(AppPalette.light, NotifShape.arrow), const Color(0xFF0A6E8A));
  });

  test('colour file carries no auto-read words', () {
    final src = File('lib/ui/widgets/notif_colors.dart').readAsStringSync();
    expect(RegExp('pars|waiting|sms', caseSensitive: false).hasMatch(src), isFalse);
  });
}
