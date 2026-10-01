// T20 — the shared primary chrome (lib/ui/shell/primary_scaffold.dart):
//  - the seamless top bar on every primary page: no divider, the page background, and a
//    subtle tint + shadow only when content scrolls under it;
//  - Ocean & Sun chrome on every primary page, following dark mode only on
//    pages that opt in (Home); the rest stay pinned light.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/notifications_screen.dart';
import 'package:mmogo/ui/shell/chrome_widgets.dart';
import 'package:mmogo/ui/shell/primary_scaffold.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

/// Finds the [IconCircleButton] with a given tooltip — since T25 there are
/// two on the primary top bar (Notifications, Profile), so a bare
/// `find.byType` no longer resolves to a single widget.
Finder _iconCircleButton(String tooltip) =>
    find.byWidgetPredicate((w) => w is IconCircleButton && w.tooltip == tooltip);

void _setPhone(WidgetTester tester, Brightness brightness) {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// A non-Home primary page (Settings' slot) with a long scrolling body.
Widget _settingsLike({bool followPhoneTheme = false}) => MaterialApp(
  home: PrimaryScaffold(
    title: 'Settings',
    activeIndex: 4,
    followPhoneTheme: followPhoneTheme,
    body: ListView(
      key: const Key('body'),
      children: [for (var i = 0; i < 60; i++) ListTile(title: Text('Row $i'))],
    ),
  ),
);

Material _barMaterial(WidgetTester tester) =>
    tester.widget<Material>(find.descendant(of: find.byType(AppBar), matching: find.byType(Material)).first);

Color? _navColor(WidgetTester tester) =>
    (tester.widget<Container>(find.byKey(const Key('primaryBottomNav'))).decoration! as BoxDecoration).color;

Color? _navLabelColor(WidgetTester tester, String label) => tester
    .widget<Text>(find.descendant(of: find.byKey(const Key('primaryBottomNav')), matching: find.text(label)))
    .style
    ?.color;

/// The page-level region the system reads the gesture/nav bar colour from
/// (T21 system-bar fix).
SystemUiOverlayStyle _bottomOverlay(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.ancestor(of: find.byType(Scaffold), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)).first,
    )
    .value;

void main() {
  group('seamless top bar on a non-Home primary page', () {
    testWidgets('no divider, same colour as the page, flat until scrolled under', (tester) async {
      await tester.pumpWidget(_settingsLike());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.bg);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.shape, const Border(), reason: 'no bottom border line');
      expect(appBar.bottom, isNull);
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(Divider)), findsNothing);

      final flat = _barMaterial(tester);
      expect(flat.color, scaffold.backgroundColor, reason: 'bar background = page background');
      expect(flat.elevation, 0);

      // Content scrolls under the bar -> subtle tint + shadow.
      await tester.drag(find.byKey(const Key('body')), const Offset(0, -300));
      await tester.pumpAndSettle();
      final scrolled = _barMaterial(tester);
      expect(scrolled.color, Color.alphaBlend(AppPalette.light.primary.withValues(alpha: 0.07), AppColors.bg));
      expect(scrolled.color, isNot(AppColors.bg));
      expect(scrolled.elevation, 2);

      // Back at the top it is seamless again.
      await tester.drag(find.byKey(const Key('body')), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(_barMaterial(tester).color, AppColors.bg);
      expect(_barMaterial(tester).elevation, 0);
    });

    testWidgets('Ocean & Sun chrome: title ink, round Profile button in the card colour, Ocean nav + FAB', (
      tester,
    ) async {
      await tester.pumpWidget(_settingsLike());
      await tester.pumpAndSettle();
      const p = AppPalette.light;
      final title = tester.widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.text('Settings')));
      expect(title.style!.color, p.ink);
      expect(title.style!.fontSize, 18);
      expect(title.style!.fontWeight, FontWeight.w800);

      final profile = tester.widget<IconCircleButton>(_iconCircleButton('Profile'));
      expect(profile.background, p.card);
      expect(profile.size, 36);

      expect(_navColor(tester), p.card);
      expect(_navLabelColor(tester, 'Settings'), p.primary, reason: 'active item is Ocean');
      expect(_navLabelColor(tester, 'Home'), p.mutedInk);
      final fab = tester.widget<Material>(find.byKey(const Key('primaryFab')));
      expect(fab.color, p.primary);
      expect(fab.color, const Color(0xFF0A6E8A));
      final plus = tester.widget<Icon>(
        find.descendant(of: find.byKey(const Key('primaryFab')), matching: find.byIcon(Icons.add)),
      );
      expect(plus.color, p.onPrimary);
    });
  });

  group('pinned light vs following the phone', () {
    testWidgets('a non-Home page stays light on a dark phone (chrome and body)', (tester) async {
      _setPhone(tester, Brightness.dark);
      await tester.pumpWidget(_settingsLike());
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, AppColors.bg);
      expect(_barMaterial(tester).color, AppColors.bg);
      expect(_navColor(tester), AppPalette.light.card);
      expect(tester.widget<Material>(find.byKey(const Key('primaryFab'))).color, AppPalette.light.primary);
      expect(tester.widget<AppBar>(find.byType(AppBar)).systemOverlayStyle, AppPalette.light.systemOverlayStyle);
      expect(_bottomOverlay(tester), AppPalette.light.systemOverlayStyle);
    });

    testWidgets('followPhoneTheme (Home) goes dark on a dark phone', (tester) async {
      _setPhone(tester, Brightness.dark);
      await tester.pumpWidget(_settingsLike(followPhoneTheme: true));
      await tester.pumpAndSettle();
      const p = AppPalette.dark;
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, p.background);
      expect(_barMaterial(tester).color, p.background);
      expect(_navColor(tester), p.card);
      expect(tester.widget<Material>(find.byKey(const Key('primaryFab'))).color, p.primary);
      expect(tester.widget<AppBar>(find.byType(AppBar)).systemOverlayStyle, p.systemOverlayStyle);
      expect(_bottomOverlay(tester), p.systemOverlayStyle);
      expect(_bottomOverlay(tester).systemNavigationBarColor, p.card);
    });
  });

  group('FAB hit area (T21, backlog "FAB top edge outside its hit area")', () {
    Future<List<String>> pumpWithTappableBody(WidgetTester tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PrimaryScaffold(
            title: 'Home',
            activeIndex: 0,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => log.add('body'),
              child: const SizedBox.expand(),
            ),
          ),
          onGenerateRoute: (settings) {
            log.add('route ${settings.name}');
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('ADD')),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      return log;
    }

    testWidgets('a tap on the FAB top edge (above the nav box) opens Add, not the body beneath', (tester) async {
      final log = await pumpWithTappableBody(tester);
      final fab = tester.getRect(find.byKey(const Key('primaryFab')));
      final navBoxTop = tester.getRect(find.byKey(const Key('primaryBottomNav'))).top - 14;
      // The point really is above the nav's layout box, i.e. over the body.
      final point = Offset(fab.center.dx, fab.top + 3);
      expect(point.dy, lessThan(navBoxTop));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(log, ['route /add']);
      expect(find.text('ADD'), findsOneWidget);
    });

    testWidgets('a tap on the ring (outside the 54px button) also opens Add', (tester) async {
      final log = await pumpWithTappableBody(tester);
      final ring = tester.getRect(find.byKey(const Key('primaryFabRing')));
      await tester.tapAt(Offset(ring.center.dx, ring.top + 2));
      await tester.pumpAndSettle();
      expect(log, ['route /add']);
    });

    testWidgets('empty space beside the FAB, at the same height, still reaches the body', (tester) async {
      final log = await pumpWithTappableBody(tester);
      final fab = tester.getRect(find.byKey(const Key('primaryFab')));
      await tester.tapAt(Offset(20, fab.top + 3));
      await tester.pumpAndSettle();
      expect(log, ['body']);
    });
  });

  group('T25 — notifications bell', () {
    testWidgets('sits 8px left of Profile, same size/style; tapping it opens Notifications', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PrimaryScaffold(title: 'Settings', activeIndex: 4, body: const SizedBox.shrink()),
          routes: {Routes.notifications: (_) => const NotificationsComingSoonScreen()},
        ),
      );
      await tester.pumpAndSettle();

      const p = AppPalette.light;
      final bell = tester.widget<IconCircleButton>(_iconCircleButton('Notifications'));
      expect(bell.icon, Icons.notifications_none_rounded);
      expect(bell.size, 36);
      expect(bell.background, p.card);
      expect(bell.foreground, p.ink);

      final bellRect = tester.getRect(_iconCircleButton('Notifications'));
      final profileRect = tester.getRect(_iconCircleButton('Profile'));
      expect(bellRect.right, moreOrLessEquals(profileRect.left - 8, epsilon: 0.1));

      await tester.tap(_iconCircleButton('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget, reason: 'the secondary page title');
      expect(find.text('Coming soon'), findsOneWidget);
    });
  });
}
