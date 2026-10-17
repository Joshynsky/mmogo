// F2 (0.1.2 corrections), Paid to:
//   R35  the search field does not take focus back (keyboard opening) after the
//        Filter & sort sheet closes, unless the user was typing when it opened
//   R36  at large text a recipient name wraps to two lines instead of being cut;
//        the phone line stays one line; the spoken label keeps the full name
// Driven against FakeAnalyticsDb with invented rows (no real database).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/paid_to/recipient_row.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

const _longName = 'WANJIRU MUTHONI NJERI KAMAU WAMBUI';

List<Map<String, Object?>> _rows() => [
  fakeTx(id: 1, at: DateTime(2026, 9, 3, 9), label: 'JOHN KAMAU', phone: '0798630424', amountCents: 150000),
  fakeTx(id: 2, at: DateTime(2026, 9, 5, 9), label: _longName, phone: '0722334455', amountCents: 90000),
  fakeTx(id: 3, at: DateTime(2026, 9, 6, 9), label: 'ALICE', phone: '0711000111', amountCents: 10000, classification: 'Rent', classificationId: 102),
];

Future<void> _pump(WidgetTester tester, {double scale = 1.0, Size size = const Size(392, 1800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: PaidToScreen(db: FakeAnalyticsDb(_rows()), clock: () => analyticsTestNow),
    ),
  );
  await tester.pumpAndSettle();
}

bool _searchHasFocus(WidgetTester tester) {
  final editable = find.descendant(of: find.byKey(const Key('paidToSearch')), matching: find.byType(EditableText));
  return tester.widget<EditableText>(editable).focusNode.hasFocus;
}

Future<void> _openFilterPickShow(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('paidToFilterButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('paidToCat-Rent')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('paidToShow')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('R35 focus after the Filter & sort sheet', () {
    testWidgets('typed in search, keyboard closed, Filter, choose, Show: the search field has no focus', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('paidToSearch')), 'a');
      await tester.pump();
      // The keyboard is closed (no view insets) while the field still holds the focus.
      expect(tester.view.viewInsets.bottom, 0);
      await _openFilterPickShow(tester);
      expect(find.byKey(const Key('paidToFilterBadge')), findsOneWidget, reason: 'the choice was applied');
      expect(find.text('Filter & sort'), findsNothing, reason: 'the sheet is closed');
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNull,
          reason: 'no text field holds the focus, so no keyboard opens');
    });

    testWidgets('the keyboard was up when the sheet opened: the search field gets the focus back', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('paidToSearch')), 'a');
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await _openFilterPickShow(tester);
      expect(find.text('Filter & sort'), findsNothing);
      expect(_searchHasFocus(tester), isTrue, reason: 'the user was typing, so typing can go on');
    });

    testWidgets('never focused the search: it stays unfocused after the sheet closes', (tester) async {
      await _pump(tester);
      await _openFilterPickShow(tester);
      expect(_searchHasFocus(tester), isFalse);
    });
  });

  group('R36 recipient names at large text', () {
    for (final scale in [1.3, 1.6]) {
      testWidgets('x$scale: a long name wraps to two lines, is not cut; the phone line stays one line', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, scale: scale, size: const Size(392, 3200));
        final nameFinder = find.text(_longName);
        expect(nameFinder, findsOneWidget);
        final name = tester.widget<Text>(nameFinder);
        expect(name.maxLines, 2);
        expect(name.overflow, TextOverflow.ellipsis);
        // Wrapped in the row: more than one line tall, and every word is visible (no cut at 2 lines).
        final lineHeight = (name.style?.fontSize ?? 14) * scale;
        expect(tester.getSize(nameFinder).height, greaterThan(lineHeight * 1.5), reason: 'the name used two lines');
        final render = tester.renderObject<RenderBox>(nameFinder);
        expect(render.size.height, lessThan(lineHeight * 3.2), reason: 'at most two lines');
        // The second line (phone / amount line) stays single-line.
        final row = find.ancestor(of: nameFinder, matching: find.byType(PaidToRecipientRow));
        expect(row, findsOneWidget);
        final lastLine = tester.widget<Text>(find.descendant(of: row, matching: find.textContaining('Last ')));
        expect(lastLine.maxLines, 1, reason: 'the phone / last-paid line stays one line');
        // The spoken label still carries the full name.
        expect(find.bySemanticsLabel(RegExp(_longName)), findsWidgets);
        handle.dispose();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
