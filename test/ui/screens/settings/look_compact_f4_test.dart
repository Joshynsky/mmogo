// 0.1.2 F4 (finding R17 and the small Settings changes around it): the compact
// Look group (approved mock look-compact.html), the Appearance caption (R20),
// the First day row and dialog (R16, R21), the toast (R22), the Your data
// order (R19) and the dead copy that went with the old layout.
// Fake Database only (a real sqflite Database hangs inside testWidgets here).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/settings_copy.dart';
import 'package:mmogo/ui/screens/settings/compact_choice_row.dart';
import 'package:mmogo/ui/screens/settings/look_section.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/fake_delete_data.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _rowKeys = ['settingsMonthChartRow', 'settingsYearViewRow', 'settingsWhereStyleRow'];
const _optionKeys = [
  'monthChart-days',
  'monthChart-weeks',
  'yearView-quarters',
  'yearView-months',
  'whereStyle-button',
  'whereStyle-strip',
];

Future<void> _pump(
  WidgetTester tester, {
  double width = 400,
  double height = 3600,
  double scale = 1.0,
  String mode = 'system',
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AppPaletteScope(
        controller: AppPaletteController('ocean', mode),
        child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _in(String rowKey, String childKey) =>
    find.descendant(of: find.byKey(Key(rowKey)), matching: find.byKey(Key(childKey)));

bool _stacked(WidgetTester t, String rowKey) => _in(rowKey, 'compactStacked').evaluate().isNotEmpty;

void main() {
  setUp(() => useFakeDeleteData());

  group('A1/A2: one compact row each, one column, equal controls (text 1.0, a wide card)', () {
    testWidgets('Month chart, Year view and Where it went style are rows with the control beside the title', (tester) async {
      await _pump(tester, width: 800);
      for (final r in _rowKeys) {
        expect(_in(r, 'compactBeside'), findsOneWidget, reason: r);
        expect(_in(r, 'compactStacked'), findsNothing, reason: r);
      }
      expect(find.text('Month chart'), findsOneWidget);
      expect(find.text('One bar per day or week.'), findsOneWidget);
      expect(find.text('Year view'), findsOneWidget);
      expect(find.text('Quarter or month totals.'), findsOneWidget);
      expect(find.text('Where it went style'), findsOneWidget);
      expect(find.text('Buttons or a strip.'), findsOneWidget);
      // The old long titles and two-line explanations are gone.
      expect(find.text('Month chart shows'), findsNothing);
      expect(find.text('Year view amounts'), findsNothing);
      expect(find.textContaining('one bar for every day of the month'), findsNothing);
      expect(find.textContaining('ranked category cards'), findsNothing);
      // Options are words.
      for (final w in ['Days', 'Weeks', 'Quarter', 'Monthly', 'Button', 'Strip']) {
        expect(find.text(w), findsOneWidget, reason: w);
      }
    });

    testWidgets('the three controls have the same width and height and sit in one right-aligned column', (tester) async {
      await _pump(tester, width: 800);
      final rects = [
        for (final p in ['monthChart', 'yearView', 'whereStyle']) tester.getRect(find.byKey(Key('$p-control'))),
      ];
      for (final r in rects) {
        expect(r.width, rects.first.width);
        expect(r.height, 48);
        expect(r.left, rects.first.left);
        expect(r.right, rects.first.right);
      }
      // Right-aligned: the right edge is the row's content edge (14 px padding).
      final card = tester.getRect(find.byKey(const Key('settingsMonthChartRow')));
      expect(rects.first.right, card.right - 14);
    });

    testWidgets('every option is at least 44 x 44', (tester) async {
      await _pump(tester, width: 800);
      for (final k in _optionKeys) {
        final s = tester.getSize(find.byKey(Key(k)));
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
      }
    });

    testWidgets('the chosen option is filled with the primary colour AND set in heavier type', (tester) async {
      await _pump(tester, width: 800, prefs: {'year_view_amounts': 'months'});
      final p = AppPalettes.ocean.light;
      Material material(String key) => tester.widget<Material>(
        find.ancestor(of: find.byKey(Key(key)), matching: find.byType(Material)).first,
      );
      FontWeight? weight(String key, String word) =>
          tester.widget<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.text(word))).style!.fontWeight;
      expect(material('yearView-months').color, p.primary);
      expect(material('yearView-quarters').color, Colors.transparent);
      expect(weight('yearView-months', 'Monthly'), FontWeight.w800);
      expect(weight('yearView-quarters', 'Quarter'), FontWeight.w700);
    });

    testWidgets('a tap chooses the option and writes the same stored values as before', (tester) async {
      await _pump(tester, width: 800);
      final prefs = await SharedPreferences.getInstance();
      await tester.tap(find.byKey(const Key('monthChart-days')));
      await tester.pumpAndSettle();
      expect(prefs.get('month_chart_style'), 'days');
      await tester.tap(find.byKey(const Key('yearView-months')));
      await tester.pumpAndSettle();
      expect(prefs.get('year_view_amounts'), 'months');
      await tester.tap(find.byKey(const Key('whereStyle-strip')));
      await tester.pumpAndSettle();
      expect(prefs.get('where_it_went_style'), 'strip');
    });

    testWidgets('each control is one radio group named by its title, options are buttons with a selected state', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, width: 800);
      final days = tester.getSemantics(find.byKey(const Key('monthChart-days')));
      expect(days.label, 'Days');
      expect(days.flagsCollection.isButton, isTrue);
      expect(days.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(find.bySemanticsLabel('Month chart'), findsWidgets);
      h.dispose();
    });
  });

  group('A3: the fallback (real measured text)', () {
    testWidgets('the rule is the mock\'s: 128 + 186.4 x text, with the equal control width', (tester) async {
      // Roboto-like widths: the mock's minimum control width (8.8 em + 38) dominates.
      for (final (scale, limit) in [(1.0, 314.4), (1.3, 370.3), (1.6, 426.2)]) {
        final control = 8.8 * 13 * scale + 38;
        expect(compactStacks(cardWidth: limit - 0.5, textFactor: scale, controlWidth: control), isTrue, reason: '$scale');
        expect(compactStacks(cardWidth: limit + 0.5, textFactor: scale, controlWidth: control), isFalse, reason: '$scale');
      }
      // Appearance: 86 + 72 x text + 140 + 4.
      expect(compactStacks(cardWidth: 301.9, textFactor: 1.0, controlWidth: 140), isTrue);
      expect(compactStacks(cardWidth: 302.1, textFactor: 1.0, controlWidth: 140), isFalse);
    });

    for (final width in [320.0, 360.0, 412.0, 600.0, 800.0]) {
      for (final scale in [1.0, 1.3, 1.6]) {
        testWidgets('${width.toInt()} dp wide, text $scale: every row follows the rule and nothing clips', (tester) async {
          await _pump(tester, width: width, scale: scale);
          expect(tester.takeException(), isNull);
          final card = width - 28;
          final ctx = tester.element(find.byKey(const Key('settingsMonthChartRow')));
          final choice = compactChoiceWidth(ctx, ['Days', 'Weeks']);
          for (final r in _rowKeys) {
            expect(
              _stacked(tester, r),
              compactStacks(cardWidth: card, textFactor: scale, controlWidth: choice),
              reason: '$r at $width / $scale',
            );
          }
          expect(
            _stacked(tester, 'settingsAppearanceRow'),
            compactStacks(cardWidth: card, textFactor: scale, controlWidth: AppearanceModeControl.sideWidth),
            reason: 'Appearance at $width / $scale',
          );
          // No option below 44 and no control past the card edge, either way.
          for (final k in _optionKeys) {
            final s = tester.getSize(find.byKey(Key(k)));
            expect(s.height, greaterThanOrEqualTo(44), reason: k);
            expect(s.width, greaterThanOrEqualTo(44), reason: k);
            expect(tester.getRect(find.byKey(Key(k))).right, lessThanOrEqualTo(width - 14 + 0.5), reason: k);
          }
          for (final m in ['system', 'light', 'dark']) {
            expect(tester.getSize(find.byKey(Key('appearance-$m'))).shortestSide, greaterThanOrEqualTo(44));
          }
        });
      }
    }

    testWidgets('stacked at 320 dp, text 1.6: the control fills its own line under the title, the icon stays beside the title', (tester) async {
      await _pump(tester, width: 320, scale: 1.6);
      for (final r in _rowKeys) {
        expect(_stacked(tester, r), isTrue, reason: r);
      }
      final row = tester.getRect(find.byKey(const Key('settingsYearViewRow')));
      final control = tester.getRect(find.byKey(const Key('yearView-control')));
      final title = tester.getRect(find.text('Year view'));
      expect(control.top, greaterThanOrEqualTo(title.bottom), reason: 'under the title');
      expect(control.left, row.left + 14);
      expect(control.right, row.right - 14, reason: 'full width');
      // The icon tile is beside the title (same line), not on its own line.
      final icon = tester.getRect(find.descendant(of: find.byKey(const Key('settingsYearViewRow')), matching: find.byIcon(Icons.bar_chart_outlined)));
      expect(icon.left, lessThan(title.left));
      expect(icon.top, lessThan(title.bottom));
      expect(icon.bottom, greaterThan(title.top));
    });

    testWidgets('Appearance stacked: the icons carry the small labels System, Light, Dark', (tester) async {
      await _pump(tester, width: 320, scale: 1.3);
      expect(_stacked(tester, 'settingsAppearanceRow'), isTrue);
      for (final w in ['System', 'Light', 'Dark']) {
        expect(find.descendant(of: find.byKey(const Key('settingsAppearanceRow')), matching: find.text(w)), findsOneWidget, reason: w);
      }
    });

    testWidgets('Appearance beside: icons only (no labels), a 140 dp control of three 44 x 44 buttons', (tester) async {
      await _pump(tester, width: 800);
      expect(_stacked(tester, 'settingsAppearanceRow'), isFalse);
      for (final w in ['System', 'Light', 'Dark']) {
        expect(find.descendant(of: find.byKey(const Key('settingsAppearanceRow')), matching: find.text(w)), findsNothing, reason: w);
      }
      for (final m in ['system', 'light', 'dark']) {
        expect(tester.getSize(find.byKey(Key('appearance-$m'))), const Size(44, 44));
      }
      final control = find.ancestor(of: find.byKey(const Key('appearance-system')), matching: find.byType(Semantics)).evaluate().isNotEmpty;
      expect(control, isTrue);
    });

    testWidgets('the palette names still wrap at 320 dp and text 1.6 (R37 kept)', (tester) async {
      await _pump(tester, width: 320, scale: 1.6);
      expect(tester.takeException(), isNull);
      expect(find.text('Ocean & Sun'), findsOneWidget);
    });

    for (final mode in ['light', 'dark']) {
      testWidgets('the whole page draws at 320 dp and text 1.6 without overflow ($mode)', (tester) async {
        await _pump(tester, width: 320, scale: 1.6, mode: mode);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('A4: Appearance', () {
    testWidgets('three icon buttons with the spoken names System, Light, Dark and a selected state', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, width: 800);
      for (final (id, name, on) in [('system', 'System', true), ('light', 'Light', false), ('dark', 'Dark', false)]) {
        final s = tester.getSemantics(find.byKey(Key('appearance-$id')));
        expect(s.label, name);
        expect(s.flagsCollection.isButton, isTrue);
        expect(s.flagsCollection.isSelected.name, on ? 'isTrue' : 'isFalse', reason: name);
      }
      h.dispose();
    });

    testWidgets('the caption changes with the choice: exact texts', (tester) async {
      await _pump(tester, width: 800);
      final caption = find.byKey(const Key('settingsAppearanceCaption'));
      expect(tester.widget<Text>(caption).data, 'Follows your phone’s setting.');
      await tester.tap(find.byKey(const Key('appearance-light')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(caption).data, 'Always light.');
      await tester.tap(find.byKey(const Key('appearance-dark')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(caption).data, 'Always dark.');
      await tester.tap(find.byKey(const Key('appearance-system')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(caption).data, 'Follows your phone’s setting.');
      expect(kAppearanceCaptionLight, 'Always light.');
      expect(kAppearanceCaptionDark, 'Always dark.');
      expect(appearanceCaption('nonsense'), 'Follows your phone’s setting.');
    });
  });

  group('A5/A6: First day of the week', () {
    testWidgets('the row is title, current day, chevron: the regrouped line is NOT on the page', (tester) async {
      await _pump(tester, width: 800);
      expect(find.text('First day of the week'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('settingsFirstDayRow')), matching: find.text('Monday')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('settingsFirstDayRow')), matching: find.byIcon(Icons.chevron_right)), findsOneWidget);
      expect(find.text(kFirstDayRegrouped), findsNothing);
      expect(find.textContaining('Weeks in Analytics and on Home run from this day'), findsNothing);
      // One line: the day sits on the title's line.
      final title = tester.getRect(find.text('First day of the week'));
      final day = tester.getRect(find.byKey(const Key('settingsRowValue')));
      expect(day.top, lessThan(title.bottom));
      expect(day.left, greaterThan(title.right));
      expect(tester.getSize(find.byKey(const Key('settingsFirstDayRow'))).height, greaterThanOrEqualTo(44));
    });

    testWidgets('narrow row: the day moves under the title', (tester) async {
      await _pump(tester, width: 320, scale: 1.6);
      expect(find.byKey(const Key('firstDayStacked')), findsOneWidget);
      final title = tester.getRect(find.text('First day of the week'));
      final day = tester.getRect(find.byKey(const Key('settingsRowValue')));
      expect(day.top, greaterThanOrEqualTo(title.bottom));
      expect(day.left, title.left);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dialog shows the regrouped line once, in light weight (not bold)', (tester) async {
      await _pump(tester, width: 800);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      expect(find.text(kFirstDayRegrouped), findsOneWidget);
      final style = tester.widget<Text>(find.byKey(const Key('firstDayRegrouped'))).style!;
      expect(style.fontWeight, FontWeight.w400);
      expect(find.byKey(const Key('firstDayCancel')), findsOneWidget);
    });

    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('R21: the dialog on a 320 x 568 phone at text $scale: Cancel stays visible and nothing is wasted above it', (tester) async {
        await _pump(tester, width: 320, height: 568, scale: scale);
        await tester.ensureVisible(find.byKey(const Key('settingsFirstDayRow')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final dialog = find.byKey(const Key('firstDayDialog'));
        final scroll = find.descendant(of: dialog, matching: find.byType(SingleChildScrollView));
        final cancel = tester.getRect(find.byKey(const Key('firstDayCancel')));
        final view = tester.getRect(scroll);
        expect(cancel.bottom, lessThanOrEqualTo(568), reason: 'Cancel is on screen');
        expect(cancel.top, greaterThanOrEqualTo(view.bottom), reason: 'Cancel is below the list');
        // The Cancel button's tap area is 48; the gap between the list and its top edge is small.
        expect(cancel.top - view.bottom, lessThanOrEqualTo(12), reason: 'no empty band above Cancel');
        expect(cancel.height, greaterThanOrEqualTo(44));
        // Sunday is reachable (the list scrolls only when it must).
        await tester.ensureVisible(find.byKey(const Key('firstDay-7')));
        expect(tester.getRect(find.byKey(const Key('firstDay-7'))).bottom, lessThanOrEqualTo(568));
        for (var d = 1; d <= 7; d++) {
          expect(tester.getSize(find.byKey(Key('firstDay-$d'))).height, greaterThanOrEqualTo(44), reason: 'day $d');
        }
      });
    }

    testWidgets('R21: on a tall screen at text 1.0 nothing scrolls (the list scrolls only when it must)', (tester) async {
      await _pump(tester, width: 400, height: 900);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const Key('firstDayDialog')), matching: find.byType(Scrollable)),
      );
      expect(scroll.position.maxScrollExtent, 0);
    });

    testWidgets('the dialog still closes with Cancel, outside tap and Back, and returns the day', (tester) async {
      await _pump(tester, width: 800);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDayCancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firstDayDialog')), findsNothing);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDay-3')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('settingsFirstDayRow')), matching: find.text('Wednesday')), findsOneWidget);
    });
  });

  group('A7: the toast after the day changes (R22)', () {
    testWidgets('a changed day shows "Weeks now start on Sunday." for about 2 seconds, no spinner', (tester) async {
      await _pump(tester, width: 800);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDay-7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Weeks now start on Sunday.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, const Duration(seconds: 2));
      expect(kWeeksToastDuration, const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Weeks now start on Sunday.'), findsNothing, reason: 'gone after about 2 seconds');
    });

    testWidgets('the toast names the chosen day (Wednesday)', (tester) async {
      await _pump(tester, width: 800);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDay-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Weeks now start on Wednesday.'), findsOneWidget);
      expect(weeksNowStartOnText('Monday'), 'Weeks now start on Monday.');
    });

    testWidgets('picking the same day again shows no toast (and still writes it)', (tester) async {
      await _pump(tester, width: 800);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDay-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SnackBar), findsNothing);
      expect((await SharedPreferences.getInstance()).get('first_day_of_week'), 1);
    });

    testWidgets('Cancel shows no toast', (tester) async {
      await _pump(tester, width: 800);
      await tester.tap(find.byKey(const Key('settingsFirstDayRow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('firstDayCancel')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('A8: Your data order (R19)', () {
    testWidgets('Backup and restore, Export CSV, Recently deleted, Delete data', (tester) async {
      await _pump(tester, width: 800);
      final ys = [
        for (final t in ['Backup and restore', 'Export CSV', 'Recently deleted', 'Delete data']) tester.getTopLeft(find.text(t)).dy,
      ];
      expect([...ys]..sort(), ys);
      expect(ys.toSet().length, 4);
    });
  });

  group('A11: dead copy is gone', () {
    test('the constants and widgets that only served the old layout no longer exist in lib/', () {
      final src = [
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart')) f.readAsStringSync(),
      ].join('\n');
      for (final dead in [
        'kMonthChartHelp',
        'kYearViewHelp',
        'kWhereStyleHelp',
        'kFirstDaySubtitle',
        'kAppearanceSubtitle',
        'class SettingsSegment',
        'class SettingsHeadRow',
        'class SettingsHelp',
        'Year view amounts',
      ]) {
        expect(src.contains(dead), isFalse, reason: dead);
      }
    });
  });
}
