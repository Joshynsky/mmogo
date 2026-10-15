// 0.1.2 S9a: Settings regrouped (ST1), Appearance (AP1), First day of the week
// (CW2 control), the two chart switches, the Look note, secondary-page chrome.
// Same fake-Database approach as settings_screen_test.dart (a real sqflite
// Database hangs inside testWidgets here).
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_info.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/domain/analytics/chart_blocks.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/screens/welcome_screen.dart';
import 'package:mmogo/main.dart';
import 'package:mmogo/ui/shell/primary_shell.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/shell/secondary_scaffold.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/tap_target.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/fake_analytics_db.dart';
import '../../../support/fake_delete_data.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _tall(WidgetTester tester, {double height = 4600}) async {
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<AppPaletteController> _pump(
  WidgetTester tester, {
  AppPaletteController? controller,
  double textScale = 1.0,
  Map<String, WidgetBuilder> routes = const {},
}) async {
  await _tall(tester);
  final c = controller ?? AppPaletteController();
  await tester.pumpWidget(
    MaterialApp(
      routes: routes,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppPaletteScope(
        controller: c,
        child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

double _y(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

void main() {
  // S9b-2 (A1): nothing here may reach the real Delete data service.
  setUp(() => useFakeDeleteData());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ST1: sections and rows', () {
    testWidgets('every row is present, in the signed order', (tester) async {
      await _pump(tester);
      final order = [
        find.text('LOOK'),
        find.text('Colour palette'),
        find.text('Appearance'),
        find.text('First day of the week'),
        find.text('Month chart shows'),
        find.text('Year view amounts'),
        find.text('Show withdrawals in the chart'),
        find.text('Where it went style'),
        find.text('ADDING ENTRIES'),
        find.text('Auto-recognize categories'),
        find.text('Manage categories'),
        find.text('Remembered recipients'),
        find.text('YOUR DATA'),
        find.text('Backup and restore'),
        find.text('Recently deleted'),
        find.text('Export CSV'),
        find.text('Delete data'), // S9b-2: the LAST row of Your data
        find.text('ABOUT'),
        find.text('Privacy and your data'),
        find.text('Updates'),
        find.text('Send feedback'),
      ];
      final ys = <double>[];
      for (final f in order) {
        expect(f, findsOneWidget);
        ys.add(_y(tester, f));
      }
      expect([...ys]..sort(), ys, reason: 'top to bottom in the mock order');
      expect(ys.toSet().length, ys.length);
      expect(find.text('${AppInfo.name} ${AppInfo.versionName} · your data stays on this phone'), findsOneWidget);
      // The careful tag.
      expect(find.byKey(const Key('settingsCarefulTag')), findsOneWidget);
    });

    testWidgets('"Show tips again" is gone; "Manage classifications" is now "Manage categories"', (tester) async {
      await _pump(tester, routes: {Routes.manageClassifications: (_) => const Scaffold(body: Text('MANAGE PAGE'))});
      expect(find.text('Show tips again'), findsNothing);
      expect(find.text('Replay the guide on every page'), findsNothing);
      expect(find.text('Manage classifications'), findsNothing);
      expect(find.text('Auto-recognize classifications'), findsNothing);
      await tester.tap(find.text('Manage categories'));
      await tester.pumpAndSettle();
      expect(find.text('MANAGE PAGE'), findsOneWidget);
    });

    testWidgets('the Remembered recipients row opens its page, subtitle as in the mock', (tester) async {
      await _pump(tester, routes: {Routes.rememberedRecipients: (_) => const Scaffold(body: Text('REMEMBERED PAGE'))});
      expect(find.text('Name and type, kept on this phone'), findsOneWidget);
      await tester.tap(find.text('Remembered recipients'));
      await tester.pumpAndSettle();
      expect(find.text('REMEMBERED PAGE'), findsOneWidget);
    });

    testWidgets('the Look note says Appearance stays on the phone and the rest is in backups', (tester) async {
      await _pump(tester);
      expect(
        find.text('Appearance is saved on this phone only. The other choices here are kept in your backups.'),
        findsOneWidget,
      );
      expect(find.textContaining('Set again after restoring'), findsNothing, reason: 'the stale mock line');
      expect(find.text('Reset Look'), findsNothing, reason: 'a panel shortcut in the mock, not an app control');
    });

    testWidgets('Year view amounts is on the page (firm, not conditional)', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('yearView-quarters')), findsOneWidget);
      expect(find.byKey(const Key('yearView-months')), findsOneWidget);
    });
  });

  group('secondary page chrome', () {
    for (final legacy in [false, true]) {
      testWidgets('no Add (+) button on a secondary page (followPalette: ${!legacy})', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AppPaletteScope(
              controller: AppPaletteController(),
              child: SecondaryScaffold(title: 'T', followPalette: !legacy, body: const Text('BODY')),
            ),
          ),
        );
        expect(find.byIcon(Icons.add), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.text('BODY'), findsOneWidget);
      });
    }

    testWidgets('Settings itself has no Add button', (tester) async {
      await _pump(tester);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    for (final (id, bright) in [
      ('ocean', Brightness.light),
      ('ocean', Brightness.dark),
      ('leaf', Brightness.light),
      ('indigo', Brightness.dark),
    ]) {
      testWidgets('the round Back button is primary with an on-primary arrow ($id, $bright)', (tester) async {
        final c = AppPaletteController(id, bright == Brightness.dark ? 'dark' : 'light');
        await tester.pumpWidget(
          MaterialApp(
            home: AppPaletteScope(
              controller: c,
              child: const SecondaryScaffold(title: 'T', followPalette: true, body: SizedBox()),
            ),
          ),
        );
        final set = AppPalettes.byId(id).forBrightness(bright);
        final back = find.byTooltip('Back');
        final circle = tester.widget<Material>(find.descendant(of: back, matching: find.byType(Material)).first);
        expect(circle.color, set.primary);
        final icon = tester.widget<Icon>(find.descendant(of: back, matching: find.byIcon(Icons.arrow_back)));
        expect(icon.color, set.onPrimary);
        expect(tester.getSize(find.descendant(of: back, matching: find.byType(TapTarget))).shortestSide, greaterThanOrEqualTo(44));
      });
    }
  });

  group('AP1: Appearance (three icons on the row)', () {
    testWidgets('System is the default; the three icons are one radio group, each 44 x 44', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      for (final m in ['system', 'light', 'dark']) {
        final f = find.byKey(Key('appearance-$m'));
        expect(f, findsOneWidget);
        expect(tester.getSize(f).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(f).height, greaterThanOrEqualTo(44));
      }
      expect(tester.getSemantics(find.byKey(const Key('appearance-system'))).flagsCollection.isSelected, Tristate.isTrue);
      expect(tester.getSemantics(find.byKey(const Key('appearance-dark'))).flagsCollection.isSelected, Tristate.isFalse);
      expect(find.text('System follows your phone’s setting.'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('Dark then Light then System: the palette follows at once and device-only pref is stored', (tester) async {
      final c = await _pump(tester);
      final ctx = tester.element(find.byKey(const Key('appearance-dark')));
      expect(AppPalette.of(ctx).brightness, Brightness.light, reason: 'the test phone is light');

      await tester.tap(find.byKey(const Key('appearance-dark')));
      await tester.pumpAndSettle();
      expect(c.appearance, 'dark');
      expect(AppPalette.of(tester.element(find.byKey(const Key('appearance-dark')))).brightness, Brightness.dark);
      // The chosen icon is the filled one (primary circle), the others are not.
      Color? fill(String m) => tester
          .widget<Container>(find.descendant(of: find.byKey(Key('appearance-$m')), matching: find.byType(Container)).first)
          .decoration is BoxDecoration
          ? ((tester.widget<Container>(find.descendant(of: find.byKey(Key('appearance-$m')), matching: find.byType(Container)).first).decoration) as BoxDecoration).color
          : null;
      expect(fill('dark'), AppPalette.dark.primary);
      expect(fill('system'), Colors.transparent);
      expect(fill('light'), Colors.transparent);
      expect(await AppPrefs.readAppearanceMode(), 'dark');

      await tester.tap(find.byKey(const Key('appearance-light')));
      await tester.pumpAndSettle();
      expect(c.appearance, 'light');
      expect(await AppPrefs.readAppearanceMode(), 'light');
      expect(AppPalette.of(tester.element(find.byKey(const Key('appearance-light')))).brightness, Brightness.light);

      await tester.tap(find.byKey(const Key('appearance-system')));
      await tester.pumpAndSettle();
      expect(c.appearance, 'system');
      expect(await AppPrefs.readAppearanceMode(), 'system', reason: 'written explicitly even at the default');
    });

    testWidgets('System follows the phone: a dark phone gives the dark palette, Light overrides it', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final c = await _pump(tester);
      final key = find.byKey(const Key('appearance-light'));
      expect(AppPalette.of(tester.element(key)).brightness, Brightness.dark, reason: 'system on a dark phone');
      await tester.tap(key);
      await tester.pumpAndSettle();
      expect(c.appearance, 'light');
      expect(AppPalette.of(tester.element(key)).brightness, Brightness.light, reason: 'light wins over the phone');
    });

    testWidgets('the whole app switches: MaterialApp theme mode, dark theme and the page palette', (tester) async {
      final saved = welcomeFirstFramePresented;
      welcomeFirstFramePresented = waitForFrameBuilt;
      addTearDown(() => welcomeFirstFramePresented = saved);
      final c = AppPaletteController();
      await tester.pumpWidget(MpesaTrackerApp(controller: c));
      await tester.pump(const Duration(milliseconds: 50));
      BuildContext ctx() => tester.element(find.byType(WelcomeScreen));
      expect(Theme.of(ctx()).brightness, Brightness.light);
      expect(AppPalette.of(ctx()).brightness, Brightness.light);

      c.selectAppearance('dark');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // MaterialApp animates a theme change
      expect(Theme.of(ctx()).brightness, Brightness.dark, reason: 'dialogs, pickers and snackbars use the dark theme');
      expect(AppPalette.of(ctx()).brightness, Brightness.dark);
      expect(Theme.of(ctx()).scaffoldBackgroundColor, AppPalette.dark.background);

      c.selectAppearance('light');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(Theme.of(ctx()).brightness, Brightness.light);
      expect(Theme.of(ctx()).scaffoldBackgroundColor, AppPalette.light.background);

      await tester.pumpWidget(const SizedBox()); // cancels Welcome's timer
    });

    testWidgets('a stored dark choice is loaded before the first frame (no flash of light)', (tester) async {
      SharedPreferences.setMockInitialValues({'appearance_mode': 'dark', 'palette_id': 'leaf'});
      final c = AppPaletteController();
      await c.load(); // what main() awaits before runApp
      expect(c.appearance, 'dark');
      expect(c.value, 'leaf');
      final saved = welcomeFirstFramePresented;
      welcomeFirstFramePresented = waitForFrameBuilt;
      addTearDown(() => welcomeFirstFramePresented = saved);
      await tester.pumpWidget(MpesaTrackerApp(controller: c));
      // The very first frame already carries the dark theme and the leaf palette.
      final ctx = tester.element(find.byType(WelcomeScreen));
      expect(Theme.of(ctx).brightness, Brightness.dark);
      expect(AppPalette.of(ctx), AppPalettes.leaf.dark);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('appearance_mode is never in the backup allowlist keys written by the Look rows', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('appearance-dark')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance_mode'), 'dark');
    });
  });

  group('CW2: First day of the week', () {
    testWidgets('the row shows Monday by default; the dialog lists the seven days, Monday tagged Default', (tester) async {
      await _pump(tester);
      expect(find.descendant(of: find.byKey(const Key('settingsFirstDayRow')), matching: find.text('Monday')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      for (var d = 1; d <= 7; d++) {
        expect(find.byKey(Key('firstDay-$d')), findsOneWidget);
        expect(tester.getSize(find.byKey(Key('firstDay-$d'))).height, greaterThanOrEqualTo(44));
      }
      expect(find.text('Default'), findsOneWidget);
      expect(find.byKey(const Key('firstDayCancel')), findsOneWidget);
    });

    testWidgets('choosing Sunday stores 7, shows Sunday on the row and bumps the refresh notifier', (tester) async {
      await _tall(tester);
      final shell = await _pumpOverShell(tester);
      final before = shell.dataRevision.value;
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDay-7')));
      await tester.pumpAndSettle();
      expect(await AppPrefs.readFirstDayOfWeek(), 7);
      expect((await SharedPreferences.getInstance()).get('first_day_of_week'), 7);
      expect(find.descendant(of: find.byKey(const Key('settingsFirstDayRow')), matching: find.text('Sunday')), findsOneWidget);
      expect(shell.dataRevision.value, greaterThan(before), reason: 'Home and Analytics re-read without a restart');
    });

    testWidgets('choosing the default (Monday) still writes it explicitly', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDay-1')));
      await tester.pumpAndSettle();
      expect((await SharedPreferences.getInstance()).get('first_day_of_week'), 1);
    });

    testWidgets('Cancel, a tap outside and Back change nothing and write nothing', (tester) async {
      final shell = await _pumpOverShell(tester);
      final before = shell.dataRevision.value;
      // Cancel
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDayCancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firstDayDialog')), findsNothing);
      // Outside tap
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firstDayDialog')), findsNothing);
      // Back
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firstDayDialog')), findsNothing);
      expect(find.byKey(const Key('settingsFirstDayRow')), findsOneWidget, reason: 'still on Settings');
      expect((await SharedPreferences.getInstance()).containsKey('first_day_of_week'), isFalse);
      expect(shell.dataRevision.value, before);
    });

    testWidgets('a stored Wednesday is shown and marked in the dialog', (tester) async {
      SharedPreferences.setMockInitialValues({'first_day_of_week': 3});
      await _pump(tester);
      expect(find.descendant(of: find.byKey(const Key('settingsFirstDayRow')), matching: find.text('Wednesday')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      final selected = find.descendant(of: find.byKey(const Key('firstDay-3')), matching: find.byIcon(Icons.radio_button_checked));
      expect(selected, findsOneWidget);
    });
  });

  group('Look rows write the prefs explicitly and refresh', () {
    testWidgets('Month chart shows, Year view amounts, Show withdrawals, Where it went style', (tester) async {
      final shell = await _pumpOverShell(tester);
      var rev = shell.dataRevision.value;
      Future<void> tapKey(String k) async {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.tap(find.byKey(Key(k)));
        await tester.pumpAndSettle();
        expect(shell.dataRevision.value, greaterThan(rev), reason: '$k refreshes Home and Analytics');
        rev = shell.dataRevision.value;
      }

      final prefs = await SharedPreferences.getInstance();
      // Defaults are shown before anything is saved: Weeks, quarters, off, button.
      expect(await AppPrefs.readMonthChartStyle(), MonthChartStyle.weeks);

      await tapKey('monthChart-days');
      expect(prefs.get('month_chart_style'), 'days');
      await tapKey('monthChart-weeks');
      expect(prefs.get('month_chart_style'), 'weeks', reason: 'the default is written explicitly');

      await tapKey('yearView-months');
      expect(prefs.get('year_view_amounts'), 'months');
      await tapKey('yearView-quarters');
      expect(prefs.get('year_view_amounts'), 'quarters');

      await tapKey('whereStyle-strip');
      expect(prefs.get('where_it_went_style'), 'strip');
      await tapKey('whereStyle-button');
      expect(prefs.get('where_it_went_style'), 'button');

      await tapKey('settingsShowWithdrawals');
      expect(prefs.get('show_withdrawals_in_chart'), true);
      await tapKey('settingsShowWithdrawals');
      expect(prefs.get('show_withdrawals_in_chart'), false, reason: 'off is written, not removed');
    });

    testWidgets('stored values are shown as chosen on load', (tester) async {
      SharedPreferences.setMockInitialValues({
        'month_chart_style': 'days',
        'year_view_amounts': 'months',
        'show_withdrawals_in_chart': true,
        'where_it_went_style': 'strip',
      });
      await _pump(tester);
      Semantics sem(String key) => tester.widget<Semantics>(
        find.ancestor(of: find.byKey(Key(key)), matching: find.byType(Semantics)).first,
      );
      expect(sem('monthChart-days').properties.selected, isTrue);
      expect(sem('monthChart-weeks').properties.selected, isFalse);
      expect(sem('yearView-months').properties.selected, isTrue);
      expect(sem('whereStyle-strip').properties.selected, isTrue);
      final sw = tester.widget<Switch>(find.descendant(of: find.byKey(const Key('settingsShowWithdrawals')), matching: find.byType(Switch)));
      expect(sw.value, isTrue);
    });

    testWidgets('the segment buttons are at least 44 high', (tester) async {
      await _pump(tester);
      for (final k in ['monthChart-days', 'monthChart-weeks', 'yearView-quarters', 'yearView-months', 'whereStyle-button', 'whereStyle-strip']) {
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
    });

    testWidgets('Analytics follows live: Show withdrawals on draws the hatch without a restart', (tester) async {
      await _tall(tester, height: 2600);
      final db = FakeAnalyticsDb([
        fakeTx(id: 1, at: DateTime(2026, 9, 24, 9), amountCents: 150000, classification: 'Rent'),
        fakeTx(
          id: 5,
          at: DateTime(2026, 9, 23, 8),
          type: 'AGENT_WITHDRAWAL',
          amountCents: 500000,
          classification: 'Withdrawal',
          agentNumber: '123456',
        ),
      ]);
      await tester.pumpWidget(
        AppPaletteScope(
          controller: AppPaletteController(),
          child: MaterialApp(
            home: PrimaryShell(
              initialIndex: 1,
              pages: {1: AnalyticsScreen(db: db, clock: () => analyticsTestNow)},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      int hatchLines() {
        final cp = tester.widget<CustomPaint>(find.byKey(const Key('analyticsChartPaint')));
        final canvas = TestRecordingCanvas();
        cp.painter!.paint(canvas, const Size(320, 146));
        return canvas.invocations
            .where((i) => i.invocation.memberName == #drawLine && (i.invocation.positionalArguments[2] as Paint).strokeWidth == 2.0)
            .length;
      }

      expect(hatchLines(), 0);
      final nav = Navigator.of(tester.element(find.byType(PrimaryShell)));
      nav.push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {})));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settingsShowWithdrawals')));
      await tester.tap(find.byKey(const Key('settingsShowWithdrawals')));
      await tester.pumpAndSettle();
      nav.pop();
      await tester.pumpAndSettle();
      expect(hatchLines(), greaterThan(0), reason: 'the hatched withdrawal segment appears');
    });
  });

  group('dark theme and 1.3 text scale', () {
    for (final mode in ['light', 'dark']) {
      testWidgets('Settings draws without overflow at 1.3 text scale ($mode)', (tester) async {
        await _pump(tester, controller: AppPaletteController('ocean', mode), textScale: 1.3);
        expect(tester.takeException(), isNull);
        for (final k in ['appearance-system', 'appearance-light', 'appearance-dark']) {
          expect(tester.getSize(find.byKey(Key(k))).shortestSide, greaterThanOrEqualTo(44));
        }
        // The first-day dialog too.
        await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dark: the page uses the dark background, not the light one', (tester) async {
      await _pump(tester, controller: AppPaletteController('ocean', 'dark'));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, AppPalette.dark.background);
    });
  });
}

/// Settings pushed over a live [PrimaryShell] (as in the app), so the refresh
/// notifier `PrimaryShell.active` exists. Returns the shell controller.
Future<PrimaryShellController> _pumpOverShell(WidgetTester tester) async {
  await _tall(tester);
  await tester.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController(),
      child: MaterialApp(home: PrimaryShell(pages: const {0: SizedBox(), 1: SizedBox(), 3: SizedBox(), 4: SizedBox()})),
    ),
  );
  await tester.pumpAndSettle();
  final shell = PrimaryShell.active!;
  Navigator.of(tester.element(find.byType(PrimaryShell))).push(
    MaterialPageRoute<void>(builder: (_) => SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {})),
  );
  await tester.pumpAndSettle();
  return shell;
}
