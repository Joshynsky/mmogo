// 0.1.2 S4b (DS-1, CB3, EP1): the seven type colours of the three palettes in
// both themes, read from the REAL tokens in lib/ (not copies).
//   * the 24 colours that shipped in 0.1.1 are byte-identical (pinned);
//   * the new colours and text-use shades are exactly the PM-approved values;
//   * every palette x theme x type: chart colour vs card >= 3:1 and pill text
//     vs pill fill >= 4.5:1; the table is printed and any value within 0.1 of
//     a limit is listed as (thin), never hidden;
//   * the 28 hand-worked cells of the CB3 proposal (Leaf and Indigo, light
//     and dark, seven types) agree with the Flutter numbers;
//   * the error token (EP1) clears 4.5:1 on its card and background.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/format/source_types.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

final _sets = <String, AppPalette>{
  'ocean light': AppPalette.light,
  'ocean dark': AppPalette.dark,
  'leaf light': AppPalette.leafLight,
  'leaf dark': AppPalette.leafDark,
  'indigo light': AppPalette.indigoLight,
  'indigo dark': AppPalette.indigoDark,
};

const _codes = [
  'SEND_MONEY',
  'PAYBILL',
  'BUY_GOODS',
  'CASH',
  'POCHI_LA_BIASHARA',
  'AGENT_WITHDRAWAL',
  'AIRTIME',
];

/// The expected chart colour of every cell: [set][code]. The first four are
/// the 0.1.1 values (pinned), the last three the CB3 values (Ocean & Sun: the
/// signed mock's --c5..--c7).
const _chart = <String, List<String>>{
  'ocean light': ['#1283A3', '#5B4FC4', '#C2366B', '#B07800', '#1B6E2A', '#5F6F77', '#CC461C'],
  'ocean dark': ['#2AA3C4', '#8479E8', '#E0628F', '#BF8A00', '#4DBF63', '#9AAAB1', '#F2784B'],
  'leaf light': ['#0E8A4A', '#3D6FD6', '#C2366B', '#B07800', '#6A3FB5', '#646B66', '#CC461C'],
  'leaf dark': ['#2FB36A', '#7FA2F0', '#E0628F', '#BF8A00', '#9D70E6', '#A0A8A2', '#F2784B'],
  'indigo light': ['#5B54E8', '#0C77A6', '#C0397F', '#9A5B06', '#14532A', '#666677', '#E2603A'],
  'indigo dark': ['#8F89FF', '#3FA9D9', '#E0628F', '#C98A3A', '#6FD58A', '#A5A5BA', '#FF9272'],
};

/// CB3 proposal cells (hand-worked, +/-0.05): [set] -> per type (graphic vs
/// card, text vs fill).
const _proposal = <String, List<(double, double)>>{
  'leaf light': [(4.42, 5.08), (4.73, 4.73), (5.21, 5.21), (3.80, 5.49), (7.0, 7.0), (5.5, 5.5), (4.71, 4.71)],
  'leaf dark': [(5.45, 6.60), (5.84, 7.07), (4.42, 5.36), (4.80, 5.82), (4.13, 5.0), (6.04, 7.3), (5.30, 6.4)],
  'indigo light': [(5.41, 5.41), (5.0, 5.0), (5.1, 5.1), (5.41, 5.41), (9.1, 9.1), (5.63, 5.63), (3.52, 4.69)],
  'indigo dark': [(5.61, 6.39), (6.15, 7.0), (4.92, 5.61), (5.60, 6.38), (9.25, 10.5), (6.78, 7.72), (7.49, 8.5)],
};

void main() {
  test('the seven codes are the app\'s sourceTypeOrder', () {
    expect([for (final (c, _) in sourceTypeOrder) c], _codes);
  });

  test('chart colours: the 24 colours of 0.1.1 are unchanged, the 18 new ones are the approved values', () {
    for (final e in _sets.entries) {
      final got = [for (final c in _codes) _hex(e.value.typeColor(c))];
      expect(got, _chart[e.key], reason: e.key);
    }
  });

  test('text-use shades: only where white/ink on the chart colour fails 4.5:1', () {
    expect(_hex(AppPalette.light.typePillFill('SEND_MONEY')), '#0F7C9B'); // chosen here: #1283A3 gives 4.37
    expect(_hex(AppPalette.light.typePillFill('CASH')), '#8C6100');
    expect(_hex(AppPalette.leafLight.typePillFill('SEND_MONEY')), '#0B7F44');
    expect(_hex(AppPalette.leafLight.typePillFill('CASH')), '#8C6100');
    expect(_hex(AppPalette.indigoLight.typePillText('AIRTIME')), '#1E1B3A');
    // Everything else: fill = chart colour, text = onTypeColor.
    for (final e in _sets.entries) {
      for (final c in _codes) {
        final special = (e.key == 'ocean light' || e.key == 'leaf light') && (c == 'SEND_MONEY' || c == 'CASH');
        if (!special) expect(e.value.typePillFill(c), e.value.typeColor(c), reason: '${e.key} $c fill');
        final ink = e.key == 'indigo light' && c == 'AIRTIME';
        if (!ink) expect(e.value.typePillText(c), e.value.onTypeColor, reason: '${e.key} $c text');
      }
    }
  });

  test('contrast table: graphic >= 3:1 on the card, pill text >= 4.5:1 on its fill (thin cells listed)', () {
    final failures = <String>[];
    final thin = <String>[];
    final rows = StringBuffer()
      ..writeln('palette/theme    type               chart   card    graphic  pill fill  pill text  text')
      ..writeln('-' * 84);
    for (final e in _sets.entries) {
      final p = e.value;
      for (final c in _codes) {
        final chart = p.typeColor(c);
        final g = _ratio(chart, p.card);
        final fill = p.typePillFill(c), txt = p.typePillText(c);
        final t = _ratio(txt, fill);
        rows.writeln(
          '${e.key.padRight(16)} ${c.padRight(18)} ${_hex(chart)} ${_hex(p.card)} ${g.toStringAsFixed(2).padLeft(5)}    '
          '${_hex(fill)}  ${_hex(txt)}  ${t.toStringAsFixed(2).padLeft(5)}',
        );
        if (g < 3.0) failures.add('${e.key} $c graphic ${g.toStringAsFixed(2)} < 3');
        if (t < 4.5) failures.add('${e.key} $c text ${t.toStringAsFixed(2)} < 4.5');
        if ((g - 3.0).abs() < 0.1) thin.add('${e.key} $c graphic ${g.toStringAsFixed(2)} (thin)');
        if ((t - 4.5).abs() < 0.1) thin.add('${e.key} $c text ${t.toStringAsFixed(2)} (thin)');
      }
    }
    // ignore: avoid_print
    print('$rows\nTHIN (within 0.1 of a limit): ${thin.isEmpty ? 'none' : '\n  ${thin.join('\n  ')}'}');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('the 28 hand-worked proposal cells (Leaf and Indigo) agree with Flutter within 0.1', () {
    var cells = 0;
    final off = <String>[];
    for (final e in _proposal.entries) {
      final p = _sets[e.key]!;
      for (var i = 0; i < _codes.length; i++) {
        final (g, t) = e.value[i];
        final gr = _ratio(p.typeColor(_codes[i]), p.card);
        final tr = _ratio(p.typePillText(_codes[i]), p.typePillFill(_codes[i]));
        cells++;
        if ((gr - g).abs() > 0.1) off.add('${e.key} ${_codes[i]} graphic proposal $g vs ${gr.toStringAsFixed(2)}');
        if ((tr - t).abs() > 0.1) off.add('${e.key} ${_codes[i]} text proposal $t vs ${tr.toStringAsFixed(2)}');
      }
    }
    expect(cells, 28);
    // KNOWN: the proposal's hand figures for Indigo dark Pochi (9.25 / 10.5)
    // were off by 0.23; Flutter says 9.02 / 10.27. Both pass their limits by a
    // wide margin, so the colour #6FD58A stands. Any OTHER disagreement fails.
    expect(off, [
      'indigo dark POCHI_LA_BIASHARA graphic proposal 9.25 vs 9.02',
      'indigo dark POCHI_LA_BIASHARA text proposal 10.5 vs 10.27',
    ]);
  });

  test('the shade chosen for Ocean Send Money reaches 4.5:1 with white; the old chart colour does not', () {
    expect(_ratio(Colors.white, AppPalette.light.typePillFill('SEND_MONEY')), greaterThanOrEqualTo(4.5));
    expect(_ratio(Colors.white, AppPalette.light.typeSendMoney), lessThan(4.5)); // 4.37
  });

  test('error token (EP1): #B3261E light, #FF8A8E dark; >= 4.5:1 on the card and the page background', () {
    for (final e in _sets.entries) {
      final p = e.value;
      expect(_hex(p.error), p.brightness == Brightness.dark ? '#FF8A8E' : '#B3261E', reason: e.key);
      for (final (name, bg) in [('card', p.card), ('background', p.background), ('textCard', p.textCard)]) {
        final r = _ratio(p.error, bg);
        expect(r, greaterThanOrEqualTo(4.5), reason: '${e.key} error on $name ${r.toStringAsFixed(2)}');
      }
    }
    expect(_ratio(AppPalette.light.error, Colors.white), closeTo(6.53, 0.02));
  });

  test('the old fixed red #E5484D is gone from lib/', () {
    final hits = <String>[
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && f.readAsStringSync().toUpperCase().contains('E5484D')) f.path,
    ];
    expect(hits, isEmpty, reason: 'use palette.error: $hits');
  });
}
