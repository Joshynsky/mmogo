// Ocean & Sun palette + dark mode (PM direct decisions, 2026-09-24;
// values from the approved mock v3's `:root` / `.phone.dark` CSS). Ocean is the default
// palette; T26 ("i think it should recolor the entire app") made the chosen
// palette apply app-wide, including Welcome and onboarding — see the
// "follow the chosen palette (T26)" group below.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/prefs/app_prefs.dart';
import 'package:mymog/main.dart';
import 'package:mymog/ui/screens/onboarding_screen.dart';
import 'package:mymog/ui/screens/welcome_screen.dart';
import 'package:mymog/ui/theme/app_colors.dart';
import 'package:mymog/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _setPhone(WidgetTester tester, Brightness brightness) {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

Color? _circleColor(WidgetTester tester) {
  final box = tester.widget<Container>(find.ancestor(of: find.text('Welcome'), matching: find.byType(Container)).first);
  return (box.decoration! as BoxDecoration).color;
}

SystemUiOverlayStyle _overlay(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first)
    .value;

Color? _textColor(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style?.color;

Color? _buttonBg(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).style!.backgroundColor!.resolve(<WidgetState>{});

Color? _buttonFg(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).style!.foregroundColor!.resolve(<WidgetState>{});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  // Welcome's timer waits for its first frame to be on screen; the
  // widget-test binding has no rasteriser, so treat "built" as "presented"
  // (see test/ui/screens/onboarding_flow_test.dart for the real gate).
  setUp(() => welcomeFirstFramePresented = waitForFrameBuilt);
  tearDown(() => welcomeFirstFramePresented = waitForFirstFramePresented);

  group('Tokens', () {
    test('light tokens are the mock v3 :root values', () {
      const p = AppPalette.light;
      expect(p.brightness, Brightness.light);
      expect(p.primary, const Color(0xFF0A6E8A));
      expect(p.onPrimary, const Color(0xFFFFFFFF));
      expect(p.deep, const Color(0xFF073B4C));
      expect(p.backBg, const Color(0xFF073B4C));
      expect(p.backInk, const Color(0xFFFFFFFF));
      expect(p.tint, const Color(0xFFE0F1F5));
      expect(p.tintInk, const Color(0xFF073B4C));
      expect(p.brightPill, const Color(0xFF1597B8));
      expect(p.dotIdle, const Color(0xFFC3CFD3));
      expect(p.ink, const Color(0xFF13262E));
      expect(p.softInk, const Color(0xFF3E5058));
      expect(p.mutedInk, const Color(0xFF5B6B72));
      expect(p.background, const Color(0xFFF4F8F9));
      expect(p.surface, const Color(0xFFFFFFFF));
      expect(p.textCard, const Color(0xFFE8F0F2));
      expect(p.line, const Color(0xFFD3DFE3));
      expect(p.frameLine, const Color(0xFFB5D6DF));
      expect(p.skipBg, const Color(0xD9FFFFFF));
      expect(p.skipInk, const Color(0xFF073B4C));
      expect(p.sun, const Color(0xFFFFB703));
      // T21: transparent status bar (no scrim), nav bar in the nav's card
      // colour, dark icons on light.
      expect(p.systemOverlayStyle.statusBarColor, const Color(0x00000000));
      expect(p.systemOverlayStyle.systemStatusBarContrastEnforced, isFalse);
      expect(p.systemOverlayStyle.statusBarIconBrightness, Brightness.dark);
      expect(p.systemOverlayStyle.systemNavigationBarColor, p.card);
      expect(p.systemOverlayStyle.systemNavigationBarIconBrightness, Brightness.dark);
      // T21 Analytics tokens (Analytics mock v4 `.phone`).
      expect(p.bar, const Color(0xFF9CC9D6));
      expect(p.barOn, const Color(0xFF0A6E8A));
      expect(p.highlight, const Color(0xFFFFF4D6));
      expect(p.toastAction, const Color(0xFF8FD3E6));
      expect(p.onDelete, const Color(0xFFFFFFFF));
    });

    test('dark tokens are the mock v3 .phone.dark values', () {
      const p = AppPalette.dark;
      expect(p.brightness, Brightness.dark);
      expect(p.primary, const Color(0xFF3FB6D4));
      expect(p.onPrimary, const Color(0xFF06212B));
      expect(p.deep, const Color(0xFFBFE4EE));
      expect(p.backBg, const Color(0xFFCFE9F0));
      expect(p.backInk, const Color(0xFF073B4C));
      expect(p.tint, const Color(0xFF133640));
      expect(p.tintInk, const Color(0xFFBFE4EE));
      expect(p.brightPill, const Color(0xFF3FB6D4));
      expect(p.dotIdle, const Color(0xFF3A4E56));
      expect(p.ink, const Color(0xFFE6F0F3));
      expect(p.softInk, const Color(0xFFA3B7BF));
      expect(p.mutedInk, const Color(0xFFA3B7BF));
      expect(p.background, const Color(0xFF0E1A1F));
      expect(p.surface, const Color(0xFF0E1A1F));
      expect(p.textCard, const Color(0xFF1A2C34));
      expect(p.line, const Color(0xFF2E444D));
      expect(p.frameLine, const Color(0xFF2E5561));
      expect(p.skipBg, const Color(0xEB1A2C34));
      expect(p.skipInk, const Color(0xFFBFE4EE));
      expect(p.sun, const Color(0xFFFFB703));
      expect(p.systemOverlayStyle.statusBarColor, const Color(0x00000000));
      expect(p.systemOverlayStyle.statusBarIconBrightness, Brightness.light);
      expect(p.systemOverlayStyle.systemNavigationBarColor, p.card);
      expect(p.systemOverlayStyle.systemNavigationBarColor, isNot(const Color(0xFF000000)));
      expect(p.systemOverlayStyle.systemNavigationBarIconBrightness, Brightness.light);
      // T21 Analytics tokens (Analytics mock v4 `.phone.dark`).
      expect(p.bar, const Color(0xFF2E5561));
      expect(p.barOn, const Color(0xFF3FB6D4));
      expect(p.highlight, const Color(0xFF3A3320));
      expect(p.toastAction, const Color(0xFF2E5561));
      expect(p.onDelete, const Color(0xFF2A0E0C));
    });

    test('forBrightness picks the matching set; type colours are per-theme tokens', () {
      expect(AppPalette.forBrightness(Brightness.light), same(AppPalette.light));
      expect(AppPalette.forBrightness(Brightness.dark), same(AppPalette.dark));
      expect(AppColors.sun, const Color(0xFFFFB703));
      // T20: the PM-approved chart colours (home-colours-mock v4 --c1..--c4).
      const l = AppPalette.light;
      expect(l.typeSendMoney, const Color(0xFF1283A3));
      expect(l.typePaybill, const Color(0xFF5B4FC4));
      expect(l.typeBuyGoods, const Color(0xFFC2366B));
      expect(l.typeCash, const Color(0xFFB07800));
      const d = AppPalette.dark;
      expect(d.typeSendMoney, const Color(0xFF2AA3C4));
      expect(d.typePaybill, const Color(0xFF8479E8));
      expect(d.typeBuyGoods, const Color(0xFFE0628F));
      expect(d.typeCash, const Color(0xFFBF8A00));
      expect(l.typeColor('SEND_MONEY'), l.typeSendMoney);
      expect(l.typeColor('PAYBILL'), l.typePaybill);
      expect(d.typeColor('BUY_GOODS'), d.typeBuyGoods);
      expect(d.typeColor('CASH'), d.typeCash);
      // Home tokens (mock .phone / .phone.dark).
      expect(l.card, const Color(0xFFFFFFFF));
      expect(d.card, const Color(0xFF1A2C34));
      expect(l.track, const Color(0xFFE8F0F2));
      expect(d.track, const Color(0xFF26404A));
      expect(d.track, isNot(d.background));
      expect(d.track, isNot(d.card));
      expect(l.diffUp, const Color(0xFFC62828));
      expect(d.diffUp, const Color(0xFFFF8A80));
      expect(l.diffDown, const Color(0xFF0A6E8A));
      expect(d.diffDown, const Color(0xFF3FB6D4));
      // Parties/Analytics' donut colours are untouched until their rework.
      expect(AppColors.sourceSendMoney, const Color(0xFF00A651));
      expect(AppColors.sourcePaybill, const Color(0xFF3D7FE0));
      expect(AppColors.sourceBuyGoods, const Color(0xFF8B5CF6));
      expect(AppColors.sourceCash, const Color(0xFFF5A623));
    });
  });

  group('Welcome follows the phone setting (default Ocean palette)', () {
    for (final (brightness, palette) in [(Brightness.light, AppPalette.light), (Brightness.dark, AppPalette.dark)]) {
      testWidgets('${brightness.name} phone -> ${brightness.name} palette', (tester) async {
        _setPhone(tester, brightness);
        await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
        await tester.pump();
        expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, palette.surface);
        expect(_circleColor(tester), palette.tint);
        expect(_textColor(tester, 'Welcome'), palette.tintInk);
        expect(_textColor(tester, 'Tap to continue'), palette.mutedInk);
        expect(_overlay(tester), palette.overlayStyleWithNavBar(palette.surface));
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('Onboarding follows the phone setting (default Ocean palette)', () {
    for (final (brightness, palette) in [(Brightness.light, AppPalette.light), (Brightness.dark, AppPalette.dark)]) {
      testWidgets('${brightness.name} phone -> ${brightness.name} palette', (tester) async {
        _setPhone(tester, brightness);
        await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
        await tester.pumpAndSettle();
        expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, palette.background);
        expect(tester.widget<ColoredBox>(find.byKey(const Key('onboarding-image-area'))).color, palette.tint);
        expect(_textColor(tester, 'Track every shilling'), palette.ink);
        expect(_textColor(tester, 'Your M-Pesa and cash spending, in one place.'), palette.softInk);
        expect(_buttonBg(tester, const Key('onboarding-next')), palette.primary);
        expect(_buttonFg(tester, const Key('onboarding-next')), palette.onPrimary);
        expect(_buttonBg(tester, const Key('onboarding-skip')), palette.skipBg);
        expect(_buttonFg(tester, const Key('onboarding-skip')), palette.skipInk);
        expect(_overlay(tester), palette.overlayStyleWithNavBar(palette.background));

        await tester.tap(find.byKey(const Key('onboarding-next')));
        await tester.pumpAndSettle();
        expect(_buttonBg(tester, const Key('onboarding-back')), palette.backBg);
        expect(_buttonFg(tester, const Key('onboarding-back')), palette.backInk);
      });
    }

    testWidgets('switching the phone to dark while open re-colours the screen', (tester) async {
      _setPhone(tester, Brightness.light);
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, AppPalette.light.background);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, AppPalette.dark.background);
    });
  });

  group('Welcome & onboarding follow the chosen palette (T26)', () {
    // T26 "i think it should recolor the entire app" supersedes T23's
    // "only reworked pages" rule: Welcome and onboarding now call
    // AppPalette.of (not the removed AppPalette.oceanOf), so a non-Ocean
    // chosen palette recolours them too, not just Home/Analytics/Paid
    // to/Settings.
    testWidgets('Welcome under Leaf renders Leaf, not Ocean', (tester) async {
      _setPhone(tester, Brightness.light);
      await tester.pumpWidget(
        AppPaletteScope(
          controller: AppPaletteController('leaf'),
          child: const MaterialApp(home: WelcomeScreen()),
        ),
      );
      await tester.pump();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, AppPalette.leafLight.surface);
      expect(_circleColor(tester), AppPalette.leafLight.tint);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Onboarding under Leaf + a dark phone renders Leaf dark', (tester) async {
      _setPhone(tester, Brightness.dark);
      await tester.pumpWidget(
        AppPaletteScope(
          controller: AppPaletteController('leaf'),
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, AppPalette.leafDark.background);
      expect(_buttonBg(tester, const Key('onboarding-next')), AppPalette.leafDark.primary);
    });
  });

  group('Other screens stay light on a dark phone', () {
    Future<ThemeData> homeTheme(WidgetTester tester, Brightness brightness) async {
      SharedPreferences.setMockInitialValues({AppPrefs.keyOnboardingComplete: true});
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      await tester.pumpWidget(const MpesaTrackerApp());
      await tester.pump();
      // Welcome in the real app follows the phone.
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppPalette.forBrightness(brightness).surface,
      );
      await tester.pump(welcomeDuration);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final parties = find.text('Paid to');
      expect(parties, findsOneWidget, reason: 'on Home');
      final context = tester.element(parties);
      expect(MediaQuery.platformBrightnessOf(context), brightness);
      final theme = Theme.of(context);
      await tester.pumpWidget(const SizedBox());
      return theme;
    }

    testWidgets('Home in the real app gets the same light ThemeData on a dark phone', (tester) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final light = await homeTheme(tester, Brightness.light);
      final dark = await homeTheme(tester, Brightness.dark);
      expect(dark.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.light);
      expect(dark.scaffoldBackgroundColor, AppColors.bg);
      expect(dark.colorScheme, light.colorScheme);
      expect(dark.scaffoldBackgroundColor, light.scaffoldBackgroundColor);
      expect(dark.appBarTheme, light.appBarTheme);
      expect(dark.textTheme, light.textTheme);
    });
  });
}
