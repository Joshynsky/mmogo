// 0.1.2 S10b (A2c, A3, BP1): the shared "not included / lost" list. Invented
// rows only (a date and a type; never an amount, name, phone number or code).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/skipped_row_describer.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:mmogo/ui/screens/backup/skipped_rows_list.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

import '../../../support/fake_restore_service.dart';

Future<void> _pump(
  WidgetTester t,
  List<SkippedRowInfo> rows, {
  int? total,
  bool showAll = false,
  bool reasons = true,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = const Size(420, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SkippedRowsList(
            palette: dark ? AppPalette.dark : AppPalette.light,
            rows: rows,
            total: total ?? rows.length,
            title: notIncludedTitle(total ?? rows.length),
            footer: kStillInApp,
            allowShowAll: showAll,
            showReasons: reasons,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

int _rowCount() => find
    .byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('skippedRow-'))
    .evaluate()
    .length;

void main() {
  group('counts and the cap', () {
    testWidgets('0 rows: the exact title and the closing line, no row, no buttons', (t) async {
      await _pump(t, const []);
      expect(find.text('Not included in this backup (0)'), findsOneWidget);
      expect(_rowCount(), 0);
      expect(find.byKey(const Key('skippedShowAll')), findsNothing);
      expect(find.byKey(const Key('skippedRowsMore')), findsNothing);
    });

    testWidgets('1 row: one row, no Show all, no "more not shown"', (t) async {
      await _pump(t, fakeSkippedEntries(1), showAll: true);
      expect(find.text('Not included in this backup (1)'), findsOneWidget);
      expect(_rowCount(), 1);
      expect(find.byKey(const Key('skippedShowAll')), findsNothing);
      expect(find.byKey(const Key('skippedRowsMore')), findsNothing);
    });

    testWidgets('exactly 20 rows: all 20, nothing hidden, no Show all', (t) async {
      await _pump(t, fakeSkippedEntries(20), showAll: true);
      expect(_rowCount(), 20);
      expect(find.byKey(const Key('skippedShowAll')), findsNothing);
      expect(find.byKey(const Key('skippedRowsMore')), findsNothing);
    });

    testWidgets('200 rows: first 20, "and 180 more not shown", exact N 200 in the title, Show all reveals all', (t) async {
      await _pump(t, fakeSkippedEntries(200), showAll: true);
      expect(find.text('Not included in this backup (200)'), findsOneWidget);
      expect(_rowCount(), 20);
      expect(find.text('and 180 more not shown'), findsOneWidget);
      expect(find.text(kShowingFirst20), findsOneWidget);
      await t.tap(find.byKey(const Key('skippedShowAll')));
      await t.pumpAndSettle();
      expect(_rowCount(), 200);
      expect(find.byKey(const Key('skippedRowsMore')), findsNothing);
      expect(find.byKey(const Key('skippedShowAll')), findsNothing);
      expect(find.text('Not included in this backup (200)'), findsOneWidget, reason: 'N never changes');
    });

    testWidgets('a summary of 20 rows for N=200 (the Replace lists): no Show all, still "and 180 more not shown"', (
      t,
    ) async {
      final s = SkippedSummary.of(fakeSkippedEntries(200));
      await _pump(t, s.shown, total: s.count, showAll: false);
      expect(_rowCount(), 20);
      expect(find.byKey(const Key('skippedShowAll')), findsNothing);
      expect(find.text('and 180 more not shown'), findsOneWidget);
      expect(find.text('Not included in this backup (200)'), findsOneWidget);
    });

    testWidgets('the list box has a height cap and its own scroll', (t) async {
      await _pump(t, fakeSkippedEntries(200), showAll: true);
      await t.tap(find.byKey(const Key('skippedShowAll')));
      await t.pumpAndSettle();
      expect(t.getSize(find.byKey(const Key('skippedRowsScroll'))).height, lessThanOrEqualTo(240));
    });

    testWidgets('Show all and the toggle are at least 44 high', (t) async {
      await _pump(t, fakeSkippedEntries(30), showAll: true);
      expect(t.getSize(find.byKey(const Key('skippedShowAll'))).height, greaterThanOrEqualTo(44));
    });
  });

  group('row text', () {
    testWidgets('an entry reads dd-mm-yyyy, its type and the reason', (t) async {
      final row = SkippedRowInfo(
        kind: SkipKind.entry,
        reason: SkipReason.missingDetail,
        date: DateTime(2026, 9, 3, 14, 5),
        type: 'SEND_MONEY',
      );
      await _pump(t, [row]);
      expect(find.text('03-09-2026, Send Money: a required detail is missing'), findsOneWidget);
    });

    test('every kind and reason has its own plain wording', () {
      const e = SkippedRowInfo(kind: SkipKind.category, reason: SkipReason.cascaded);
      expect(skippedRowText(e, showReason: true), 'A category: it belonged to a category that was left out');
      expect(
        skippedRowText(const SkippedRowInfo(kind: SkipKind.savedReceiver, reason: SkipReason.notAllowed), showReason: true),
        'A saved receiver: a value is not allowed',
      );
      expect(
        skippedRowText(const SkippedRowInfo(kind: SkipKind.savedReceiver, reason: SkipReason.couldNotRead), showReason: true),
        'A saved receiver: it could not be read',
      );
      final unread = const SkippedRowInfo(kind: SkipKind.entry, reason: SkipReason.couldNotRead);
      expect(skippedRowText(unread, showReason: true), 'An entry that could not be read');
      final unreadMissing = const SkippedRowInfo(kind: SkipKind.entry, reason: SkipReason.missingDetail);
      expect(skippedRowText(unreadMissing, showReason: true), 'An entry that could not be read: a required detail is missing');
    });

    testWidgets('showReasons false (the Replace lists) is the row alone', (t) async {
      await _pump(t, fakeSkippedEntries(3), reasons: false);
      expect(find.textContaining('required detail'), findsNothing);
      expect(find.textContaining('not allowed'), findsNothing);
      expect(find.text('01-09-2026, Send Money'), findsOneWidget);
    });

    testWidgets('no row, title or line carries an amount, a name, a phone number or a code', (t) async {
      await _pump(t, fakeSkippedEntries(40), showAll: true);
      final texts = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join('\n');
      expect(RegExp(r'\d{6,}').hasMatch(texts), isFalse, reason: 'no long digit run (phone, code, amount)');
      expect(RegExp(r'ksh|\+254|07\d', caseSensitive: false).hasMatch(texts), isFalse);
      // Dates are the only digits in a row, and only as dd-mm-yyyy.
      final rowTexts = t
          .widgetList<Text>(find.descendant(of: find.byKey(const Key('skippedRowsScroll')), matching: find.byType(Text)))
          .map((w) => w.data ?? '');
      var checked = 0;
      for (final d in rowTexts) {
        if (d.startsWith('and ') || d.startsWith('Showing') || !RegExp(r'\d').hasMatch(d)) continue;
        checked++;
        expect(RegExp(r'^\d{2}-\d{2}-\d{4}, [A-Za-z ]+: ').hasMatch(d), isTrue, reason: d);
      }
      expect(checked, greaterThan(0));
    });
  });

  group('looks', () {
    for (final dark in [false, true]) {
      testWidgets('20 rows at text scale 1.3 (${dark ? 'dark' : 'light'}): no overflow, nothing clipped', (t) async {
        await _pump(t, fakeSkippedEntries(20), scale: 1.3, dark: dark);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('skippedRowsFooter')), findsOneWidget);
      });
    }

    testWidgets('the title is a screen-reader header', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, fakeSkippedEntries(2));
      expect(
        t.getSemantics(find.byKey(const Key('skippedRowsTitle'))),
        matchesSemantics(label: 'Not included in this backup (2)', isHeader: true),
      );
      h.dispose();
    });
  });
}
