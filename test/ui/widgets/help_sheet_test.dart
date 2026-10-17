// F3 (0.1.2 corrections): the shared "?" help pattern. One round "?" button in
// the app bar (44 x 44, spoken name "About this page") opens a bottom sheet
// with a title, scrolling text and a pinned Close button. Invented text only.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/shell/secondary_scaffold.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/help_sheet.dart';

const _title = 'About this invented page';
final _paras = [for (var i = 1; i <= 14; i++) 'Invented paragraph number $i says something rather long so that it wraps over a few lines.'];

Future<void> _pump(
  WidgetTester tester, {
  double scale = 1.0,
  bool dark = false,
  Size size = const Size(360, 780),
  List<String>? paragraphs,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', dark ? 'dark' : 'light'),
      child: MaterialApp(
        builder: (c, child) =>
            MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: SecondaryScaffold(
          title: 'Remembered recipients',
          followPalette: true,
          actions: [HelpPageButton(title: _title, paragraphs: paragraphs ?? _paras)],
          body: const SizedBox.expand(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('the "?" button', () {
    testWidgets('exists, is spoken as "About this page" (a button) and is 44 x 44', (t) async {
      final h = t.ensureSemantics();
      await _pump(t);
      final button = find.byKey(const Key('helpButton'));
      expect(button, findsOneWidget);
      expect(t.getSize(button), const Size(44, 44));
      final node = t.getSemantics(button);
      expect(node.label, 'About this page');
      expect(node.flagsCollection.isButton, isTrue);
      expect(kAboutThisPage, 'About this page');
      h.dispose();
    });

    testWidgets('is at the top right of the app bar, beside the title, and the Back button stays', (t) async {
      await _pump(t);
      final r = t.getRect(find.byKey(const Key('helpButton')));
      expect(r.right, greaterThan(300), reason: 'top right');
      expect(r.top, lessThan(60));
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('a tap opens the sheet: title, text and a Close button', (t) async {
      await _pump(t);
      expect(find.byKey(const Key('helpSheetTitle')), findsNothing);
      await t.tap(find.byKey(const Key('helpButton')));
      await t.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(find.text('Invented paragraph number 1 says something rather long so that it wraps over a few lines.'), findsOneWidget);
      expect(find.byKey(const Key('helpSheetClose')), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('helpSheetClose'))).height, greaterThanOrEqualTo(44));
    });
  });

  group('closing the sheet (three ways)', () {
    Future<void> open(WidgetTester t) async {
      await _pump(t);
      await t.tap(find.byKey(const Key('helpButton')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('helpSheetTitle')), findsOneWidget);
    }

    testWidgets('the Close button', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('helpSheetClose')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('helpSheetTitle')), findsNothing);
    });

    testWidgets('a tap on the dimmed area', (t) async {
      await open(t);
      await t.tapAt(const Offset(180, 40));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('helpSheetTitle')), findsNothing);
    });

    testWidgets('the Back key closes the sheet and stays on the page', (t) async {
      await open(t);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('helpSheetTitle')), findsNothing);
      expect(find.byKey(const Key('helpButton')), findsOneWidget, reason: 'still on the page');
    });
  });

  group('large text and narrow screens', () {
    for (final scale in [1.3, 1.6]) {
      testWidgets('text $scale on a 320 dp wide phone: nothing clips, the body scrolls, Close stays on screen', (t) async {
        await _pump(t, scale: scale, size: const Size(320, 640));
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('helpButton')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final close = t.getRect(find.byKey(const Key('helpSheetClose')));
        expect(close.bottom, lessThanOrEqualTo(640));
        expect(close.left, greaterThanOrEqualTo(0));
        expect(close.right, lessThanOrEqualTo(320));
        final title = t.getRect(find.byKey(const Key('helpSheetTitle')));
        expect(title.right, lessThanOrEqualTo(320));
        // The 14 paragraphs do not fit: the middle scrolls, the Close button does not move.
        final scroll = t.state<ScrollableState>(find.descendant(of: find.byKey(const Key('helpSheetScroll')), matching: find.byType(Scrollable)));
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        await t.drag(find.byKey(const Key('helpSheetScroll')), const Offset(0, -300));
        await t.pumpAndSettle();
        expect(t.getRect(find.byKey(const Key('helpSheetClose'))), close);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('text 1.6 on 320 dp: the app bar title wraps beside the "?" instead of being cut', (t) async {
      await _pump(t, scale: 1.6, size: const Size(320, 640));
      expect(t.takeException(), isNull);
      final title = t.widget<Text>(find.text('Remembered recipients'));
      expect(title.maxLines, 2);
      expect(title.softWrap, isTrue);
      expect(t.getRect(find.byKey(const Key('helpButton'))).right, lessThanOrEqualTo(320));
    });
  });

  group('dark mode', () {
    testWidgets('the sheet and the button use the dark palette', (t) async {
      await _pump(t, dark: true);
      final dark = AppPalette.forId('ocean', Brightness.dark);
      await t.tap(find.byKey(const Key('helpButton')));
      await t.pumpAndSettle();
      final sheet = t.widget<Container>(
        find.descendant(of: find.byType(HelpSheetFrame), matching: find.byType(Container)).at(0),
      );
      expect((sheet.decoration! as BoxDecoration).color, dark.card);
      final close = t.widget<FilledButton>(find.byKey(const Key('helpSheetClose')));
      expect(close.style!.backgroundColor!.resolve({}), dark.primary);
      expect(t.takeException(), isNull);
    });
  });

  group('screen reader', () {
    testWidgets('opening the sheet names the route with its title, and the title is a heading', (t) async {
      final h = t.ensureSemantics();
      await _pump(t);
      await t.tap(find.byKey(const Key('helpButton')));
      await t.pumpAndSettle();
      final route = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.namesRoute == true && w.properties.label == _title,
      );
      expect(route, findsOneWidget);
      expect(t.getSemantics(find.byKey(const Key('helpSheetTitle'))).flagsCollection.isHeader, isTrue);
      expect(t.getSemantics(find.byKey(const Key('helpSheetClose'))).label, 'Close');
      h.dispose();
    });

    testWidgets('a disclosure "?" (Delete data) reports expanded or collapsed and keeps its own spoken name', (t) async {
      final h = t.ensureSemantics();
      var open = false;
      await t.pumpWidget(
        AppPaletteScope(
          controller: AppPaletteController('ocean', 'light'),
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (c, set) => Scaffold(
                body: HelpButton(
                  key: const Key('disc'),
                  label: 'About deleting data',
                  expanded: open,
                  onPressed: () => set(() => open = !open),
                ),
              ),
            ),
          ),
        ),
      );
      expect(t.getSemantics(find.byKey(const Key('disc'))).label, 'About deleting data');
      expect(t.getSemantics(find.byKey(const Key('disc'))).flagsCollection.isExpanded, Tristate.isFalse);
      await t.tap(find.byKey(const Key('disc')));
      await t.pump();
      expect(t.getSemantics(find.byKey(const Key('disc'))).flagsCollection.isExpanded, Tristate.isTrue);
      h.dispose();
    });
  });
}
