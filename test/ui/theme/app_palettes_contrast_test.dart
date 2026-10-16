// T23 cheap contrast check: onPrimary text/icons on the primary button
// colour must clear WCAG's 4.5:1 (AA, normal text) bar in every one of the
// 6 shipped token sets (3 palettes x light/dark) — the orchestrator's own
// pre-build check, kept here as a
// permanent unit test so a future palette edit can't silently regress it.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

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
  pillContrastMain();
  typeColourOnCardMain();
  unselectedPillMain();
  selectedShortTextMain();
  chromePillsMain();
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

// S11b AX1a (A1 pill contrast): every pill/chip text on its fill, via the
// real accessors `typePillFill` / `typePillText`, for all seven stored types
// in all six token sets. Bar: WCAG 4.5:1 for normal text (the pills are small
// bold text, not "large"), so 4.5 is the bar here, not the relaxed 3.0.
// The tag on the Remembered screen is ink on a 15% tint of the pill fill over
// the card; it is checked at the same 4.5 bar.
const _pillTypes = <String>[
  'SEND_MONEY',
  'PAYBILL',
  'BUY_GOODS',
  'CASH',
  'POCHI_LA_BIASHARA',
  'AGENT_WITHDRAWAL',
  'AIRTIME',
];

Color _over(Color top, double alpha, Color under) => Color.alphaBlend(top.withValues(alpha: alpha), under);

/// The ratio table (also printed so the deviations file can quote it).
List<(String set, String type, double pill, double tag)> pillContrastTable() {
  final sets = <String, AppPalette>{
    'ocean light': AppPalette.light,
    'ocean dark': AppPalette.dark,
    'leaf light': AppPalette.leafLight,
    'leaf dark': AppPalette.leafDark,
    'indigo light': AppPalette.indigoLight,
    'indigo dark': AppPalette.indigoDark,
  };
  return [
    for (final e in sets.entries)
      for (final t in _pillTypes)
        (
          e.key,
          t,
          _contrastRatio(e.value.typePillText(t), e.value.typePillFill(t)),
          _contrastRatio(e.value.ink, _over(e.value.typePillFill(t), 0.15, e.value.card)),
        ),
  ];
}

void pillContrastMain() {
  group('S11b AX1a pill contrast (typePillText on typePillFill, 7 types x 6 sets)', () {
    final rows = pillContrastTable();
    test('table is complete (42 rows)', () {
      expect(rows.length, 42);
    });
    for (final r in rows) {
      test('${r.$1} ${r.$2}: pill text >= 4.5:1, Remembered tag ink >= 4.5:1', () {
        // ignore: avoid_print
        print('PILL ${r.$1} | ${r.$2} | pill ${r.$3.toStringAsFixed(2)} | tag ${r.$4.toStringAsFixed(2)}');
        expect(r.$3, greaterThanOrEqualTo(4.5), reason: 'pill ${r.$3.toStringAsFixed(2)}:1');
        expect(r.$4, greaterThanOrEqualTo(4.5), reason: 'tag ${r.$4.toStringAsFixed(2)}:1');
      });
    }
  });
}

/// S11b AX1a, non-text half: the type colour (chart segment, dot) against the
/// card it sits on, WCAG 1.4.11 bar 3:1. The name always sits beside the colour
/// (H7), so this is the secondary bar; printed for the deviations table.
void typeColourOnCardMain() {
  final sets = <String, AppPalette>{
    'ocean light': AppPalette.light,
    'ocean dark': AppPalette.dark,
    'leaf light': AppPalette.leafLight,
    'leaf dark': AppPalette.leafDark,
    'indigo light': AppPalette.indigoLight,
    'indigo dark': AppPalette.indigoDark,
  };
  group('S11b AX1a type colour vs card (non-text 3:1)', () {
    for (final e in sets.entries) {
      for (final t in _pillTypes) {
        test('${e.key} $t', () {
          final r = _contrastRatio(e.value.typeColor(t), e.value.card);
          // ignore: avoid_print
          print('NONTEXT ${e.key} | $t | ${r.toStringAsFixed(2)}');
          expect(r, greaterThanOrEqualTo(3.0), reason: '${r.toStringAsFixed(2)}:1');
        });
      }
    }
  });
}

/// S11b AX1a: the UNSELECTED pills (Add's type pills and Paid to's filter
/// pills): the type colour as text on a 10% tint of itself over the page. Add
/// writes the chart colour, Paid to the pill fill; the locked Add pill writes
/// mutedInk on the surface; Paid to "All" writes ink on a tint of primary.
void unselectedPillMain() {
  final sets = <String, AppPalette>{
    'ocean light': AppPalette.light,
    'ocean dark': AppPalette.dark,
    'leaf light': AppPalette.leafLight,
    'leaf dark': AppPalette.leafDark,
    'indigo light': AppPalette.indigoLight,
    'indigo dark': AppPalette.indigoDark,
  };
  group('S11b AX1a unselected pills (4.5:1)', () {
    for (final e in sets.entries) {
      final p = e.value;
      for (final t in _pillTypes) {
        test('${e.key} Add pill $t (typePillInk on its 10% tint over the surface)', () {
          final bg = _over(p.typePillFill(t), 0.10, p.surface);
          final r = _contrastRatio(p.typePillInk(t, page: p.surface), bg);
          // ignore: avoid_print
          print('UNSEL-ADD ${e.key} | $t | ${r.toStringAsFixed(2)}');
          expect(r, greaterThanOrEqualTo(4.5), reason: '${r.toStringAsFixed(2)}:1');
        });
        test('${e.key} Paid to pill $t (pill fill on its 10% tint over the card)', () {
          final fill = p.typePillFill(t);
          final r = _contrastRatio(p.typePillInk(t, page: p.card), _over(fill, 0.10, p.card));
          // ignore: avoid_print
          print('UNSEL-PAIDTO ${e.key} | $t | ${r.toStringAsFixed(2)}');
          expect(r, greaterThanOrEqualTo(4.5), reason: '${r.toStringAsFixed(2)}:1');
        });
      }
      test('${e.key} locked Add pill (mutedInk on surface) and Paid to All pill', () {
        expect(_contrastRatio(p.mutedInk, p.surface), greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(p.ink, _over(p.primary, 0.10, p.card)), greaterThanOrEqualTo(4.5));
      });
    }
  });
}

/// S11b AX1a: Paid to's SELECTED pill prints the short word after the label.
/// It used to be drawn at 80% of the pill text colour, which failed 4.5:1 on 25
/// of 42 pairs (down to 3.55:1). It now uses the full pill text colour (so the
/// "pill text >= 4.5:1" group above covers it); this pins that no alpha is
/// applied again.
void selectedShortTextMain() {
  test('S11b AX1a: the selected Paid to pill short text has no alpha (full pill text colour)', () {
    final src = File('lib/ui/screens/paid_to/type_pills.dart').readAsStringSync();
    expect(src.contains('fg.withValues'), isFalse);
    expect(src.contains('color: fg)'), isTrue);
  });
}

/// S11b AX1a: the chrome pills and chips (not type pills): the change pills
/// on Analytics (up / down tint of diffUp / diffDown over the card, flat =
/// mutedInk on track), the NEW pill and fee pill (tintInk on tint), the period
/// pill value (ink on track) and the removable chip (onPrimary on primary).
void chromePillsMain() {
  final sets = <String, AppPalette>{
    'ocean light': AppPalette.light,
    'ocean dark': AppPalette.dark,
    'leaf light': AppPalette.leafLight,
    'leaf dark': AppPalette.leafDark,
    'indigo light': AppPalette.indigoLight,
    'indigo dark': AppPalette.indigoDark,
  };
  group('S11b AX1a chrome pills (4.5:1)', () {
    for (final e in sets.entries) {
      final p = e.value;
      final pairs = <String, double>{
        'flat change pill (mutedInk on track)': _contrastRatio(p.mutedInk, p.track),
        'up change pill (diffUp on its 12% tint over card)': _contrastRatio(p.diffUp, _over(p.diffUp, 0.12, p.card)),
        'down change pill (diffDown on its 12% tint over card)': _contrastRatio(p.diffDown, _over(p.diffDown, 0.12, p.card)),
        'fee / selected pill (tintInk on tint)': _contrastRatio(p.tintInk, p.tint),
        'period pill value (ink on track)': _contrastRatio(p.ink, p.track),
        'removable chip (onPrimary on primary)': _contrastRatio(p.onPrimary, p.primary),
        'NEW pill (onPrimary on primary)': _contrastRatio(p.onPrimary, p.primary),
      };
      for (final x in pairs.entries) {
        test('${e.key}: ${x.key}', () {
          // ignore: avoid_print
          print('CHROME ${e.key} | ${x.key} | ${x.value.toStringAsFixed(2)}');
          expect(x.value, greaterThanOrEqualTo(4.5), reason: '${x.value.toStringAsFixed(2)}:1');
        });
      }
    }
  });
}
