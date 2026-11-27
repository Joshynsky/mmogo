// Item 4 (0.2.2): Black as dark level 2, and the Ocean 2 values.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('appearance_mode accepts black and still refuses unknown values', () async {
    expect(await AppPrefs.writeAppearanceMode('black'), isTrue);
    expect(await AppPrefs.readAppearanceMode(), 'black');
    expect(await AppPrefs.writeAppearanceMode('blackest'), isFalse);
    expect(await AppPrefs.readAppearanceMode(), 'black');
  });

  test('the controller: black draws dark, system never gives black', () {
    final c = AppPaletteController('ocean', 'system');
    expect(c.brightnessFor(Brightness.dark), Brightness.dark);
    expect(c.brightnessFor(Brightness.light), Brightness.light);
    c.selectAppearance('black');
    expect(c.appearance, 'black');
    expect(c.brightnessFor(Brightness.light), Brightness.dark);
    c.selectAppearance('nonsense');
    expect(c.appearance, 'black');
  });

  test('toBlack: true black page, same accents and type colours, every palette', () {
    for (final set in AppPalettes.all) {
      final d = set.dark, b = d.toBlack();
      expect(b.background, const Color(0xFF000000));
      expect(b.primary, d.primary);
      expect(b.ink, d.ink);
      expect(b.typeSendMoney, d.typeSendMoney);
      expect(b.addFill, d.addFill);
      expect(b.card, isNot(d.card));
      expect(_ratio(b.ink, b.card), greaterThan(12));
      expect(_ratio(b.softInk, b.card), greaterThan(7));
      expect(_ratio(b.primary, b.card), greaterThan(4.5));
      expect(_ratio(b.onPrimary, b.primary), greaterThan(4.5));
      expect(set.light.toBlack(), same(set.light));
    }
  });

  test('Ocean 2: the Add button is the Sun with dark ink; other palettes keep primary', () {
    for (final p in [AppPalette.light, AppPalette.dark]) {
      expect(p.addFill, AppColors.sun);
      expect(_ratio(p.addInk, p.addFill), greaterThan(8));
      expect(p.activeDot, AppColors.sun);
    }
    expect(AppPalette.leafLight.addFill, AppPalette.leafLight.primary);
    expect(AppPalette.indigoDark.activeDot, AppPalette.indigoDark.primary);
  });

  test('Ocean 2: Send Money is off the control teal and every text pair holds', () {
    for (final p in [AppPalette.light, AppPalette.dark]) {
      expect(p.typeSendMoney, isNot(p.primary));
      expect(_ratio(p.ink, p.card), greaterThan(12));
      expect(_ratio(p.softInk, p.card), greaterThan(6.5));
      expect(_ratio(p.mutedInk, p.background), greaterThan(4.5));
      expect(_ratio(p.primary, p.card), greaterThan(4.5));
      expect(_ratio(p.onPrimary, p.primary), greaterThan(4.5));
      expect(_ratio(p.typeSendMoney, p.card), greaterThan(4.5));
      expect(_ratio(p.typePillFill('SEND_MONEY'), p.typePillText('SEND_MONEY')), greaterThan(4.5));
    }
    expect(_ratio(AppPalette.light.track, AppPalette.light.card), greaterThan(1.25));
    expect(_ratio(AppPalette.dark.track, AppPalette.dark.card), greaterThan(1.6));
    expect(_ratio(AppPalette.dark.line, AppPalette.dark.card), greaterThan(1.8));
  });
}
