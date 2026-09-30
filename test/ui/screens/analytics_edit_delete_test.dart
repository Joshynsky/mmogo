// T21 — edit / delete on Analytics rows (a rework of T13; T13's data
// behaviour is kept):
//  - swipe right reveals Edit, swipe left reveals Delete (mock `.bact`);
//  - Delete has no confirm sheet: it soft-deletes at once and shows
//    "<name> moved to Recently Deleted" with Undo for ~5 s (PM-approved
//    mock; replaces T13's _DeleteConfirmSheet — a behaviour change);
//  - the non-gesture path (WCAG 2.5.1) is inside the transaction: tapping
//    a row opens T13's edit form, which also has Delete (PM decision
//    2026-09-25; it replaces T13's always-visible edge buttons).
//
// Replaces analytics_screen_edit_delete_test.dart, whose edge-button,
// confirm-sheet and "Transaction updated" snackbar assertions describe
// removed behaviour. T13's field-set and classification-lock checks are
// carried over unchanged in substance.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/ui/screens/analytics_screen.dart';
import 'package:mpesa_tracker/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Future<FakeAnalyticsDb> _pump(WidgetTester tester, {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final db = FakeAnalyticsDb(analyticsSampleRows());
  await tester.pumpWidget(
    MaterialApp(
      home: AnalyticsScreen(db: db, clock: () => analyticsTestNow),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

String _total(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('analyticsTotal'))).data!;

Color? _rowColor(WidgetTester tester, String name) {
  final c = tester.widget<AnimatedContainer>(
    find.ancestor(of: find.text(name), matching: find.byType(AnimatedContainer)).first,
  );
  return (c.decoration as BoxDecoration?)?.color;
}

/// Lets the toast (5 s) and highlight (1.8 s) timers run out.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('no always-visible per-row buttons (T13 edge buttons removed, PM decision)', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('analyticsEditButton_1')), findsNothing);
    expect(find.byKey(const Key('analyticsDeleteButton_1')), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    // The swipe actions sit under the row content until it is swiped.
    final row = tester.getRect(find.byKey(const Key('analyticsRow-1')));
    final edit = tester.getRect(find.byKey(const Key('analyticsRowEdit-1')));
    expect(row.overlaps(edit), isTrue);
  });

  group('the non-gesture path: tap a row', () {
    testWidgets('tapping a non-Cash row opens the full T13 field set; the picker is locked to its type; '
        'Save runs the real update and lights the row', (tester) async {
      final db = await _pump(tester);
      await tester.tap(find.text('JOHN KAMAU'));
      await tester.pumpAndSettle();

      expect(find.text('Edit transaction'), findsOneWidget);
      expect(find.byKey(const Key('editAmountField')), findsOneWidget);
      expect(find.byKey(const Key('editDateTimeText')), findsOneWidget);
      expect(find.byKey(const Key('editLabelField')), findsOneWidget);
      expect(find.byKey(const Key('editPhoneField')), findsOneWidget);
      expect(find.byKey(const Key('editAccountField')), findsNothing);
      expect(find.byKey(const Key('editCostField')), findsOneWidget);
      expect(find.byKey(const Key('editDeleteButton')), findsOneWidget);
      expect(find.text('Classification: Family/Friends'), findsOneWidget);

      await tester.tap(find.byKey(const Key('editChooseClassificationButton')));
      await tester.pumpAndSettle();
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Rent Payment'), findsNothing, reason: 'locked to Send Money');
      await tester.tap(find.text('Rent'));
      await tester.pumpAndSettle();
      expect(find.text('Classification: Rent'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('editAmountField')), '2000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('editSaveButton')));
      await tester.pumpAndSettle();

      final row = db.byId(1);
      expect(row['amount_cents'], 200000);
      expect(row['classification_id'], 102);
      expect(row['source_type'], 'SEND_MONEY');
      expect(row['display_code'], 'CODE1');
      expect(find.text('Edit transaction'), findsNothing);
      expect(_total(tester), '4,550.00');
      expect(find.text('Rent · 09:00 · CODE1'), findsOneWidget);
      expect(_rowColor(tester, 'JOHN KAMAU'), AppPalette.light.highlight);
      await _drain(tester);
      expect(_rowColor(tester, 'JOHN KAMAU'), AppPalette.light.card);
    });

    testWidgets('a Cash row: Amount / Date / Classification only, with the flat cross-group picker', (tester) async {
      final db = await _pump(tester);
      await tester.tap(find.text('Cash — Groceries'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editAmountField')), findsOneWidget);
      expect(find.byKey(const Key('editDateTimeText')), findsOneWidget);
      expect(find.byKey(const Key('editLabelField')), findsNothing);
      expect(find.byKey(const Key('editPhoneField')), findsNothing);
      expect(find.byKey(const Key('editAccountField')), findsNothing);
      expect(find.byKey(const Key('editCostField')), findsNothing);

      await tester.tap(find.byKey(const Key('editChooseClassificationButton')));
      await tester.pumpAndSettle();
      expect(find.text('Family/Friends'), findsOneWidget);
      expect(find.text('Rent Payment'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editCancelButton')));
      await tester.pumpAndSettle();
      expect(db.byId(4)['amount_cents'], 50000);
      expect(find.text('Edit transaction'), findsNothing);
    });

    testWidgets('Delete inside the form: soft-deletes, closes the form, toast; Undo restores and lights it', (
      tester,
    ) async {
      final db = await _pump(tester);
      await tester.tap(find.text('DSTV KENYA'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editDeleteButton')));
      await tester.pumpAndSettle();

      expect(find.text('Edit transaction'), findsNothing);
      expect(db.byId(3)['deleted_at'], isNotNull);
      expect(find.text('DSTV KENYA'), findsNothing);
      expect(_total(tester), '2,850.00');
      expect(find.text('DSTV KENYA moved to Recently Deleted'), findsOneWidget);

      await tester.tap(find.byKey(const Key('analyticsUndo')));
      await tester.pumpAndSettle();
      expect(db.byId(3)['deleted_at'], isNull);
      expect(find.byKey(const Key('analyticsToast')), findsNothing);
      expect(_total(tester), '4,050.00');
      expect(_rowColor(tester, 'DSTV KENYA'), AppPalette.light.highlight);
      await _drain(tester);
    });
  });

  group('swipe', () {
    testWidgets('swipe left past the threshold reveals Delete; tapping it deletes at once (no confirm), '
        'the row leaves every total, and Undo brings it back', (tester) async {
      final db = await _pump(tester);
      await tester.drag(find.byKey(const Key('analyticsRow-1')), const Offset(-90, 0));
      await tester.pumpAndSettle();
      // Settled open at -84: the row's right edge meets the Delete action.
      final row = tester.getRect(find.byKey(const Key('analyticsRow-1')));
      final action = tester.getRect(find.byKey(const Key('analyticsRowDelete-1')));
      expect(row.right, closeTo(action.left, 0.5));
      await tester.tap(find.byKey(const Key('analyticsRowDelete-1')));
      await tester.pumpAndSettle();

      expect(find.text('Delete this transaction?'), findsNothing);
      expect(db.byId(1)['deleted_at'], isNotNull);
      expect(find.text('JOHN KAMAU'), findsNothing);
      expect(_total(tester), '2,550.00');
      expect(find.text('JOHN KAMAU moved to Recently Deleted'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byKey(const Key('analyticsUndo'))).style!.foregroundColor!.resolve({}),
        AppPalette.light.toastAction,
      );

      await tester.tap(find.byKey(const Key('analyticsUndo')));
      await tester.pumpAndSettle();
      expect(db.byId(1)['deleted_at'], isNull);
      expect(_total(tester), '4,050.00');
      expect(find.text('JOHN KAMAU'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('the toast goes away by itself after about 5 s; the delete stays', (tester) async {
      final db = await _pump(tester);
      await tester.drag(find.byKey(const Key('analyticsRow-2')), const Offset(-90, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsRowDelete-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsToast')), findsOneWidget);
      // pumpAndSettle above already ran the row animations (< 1 s).
      await tester.pump(const Duration(milliseconds: 3500));
      expect(find.byKey(const Key('analyticsToast')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.byKey(const Key('analyticsToast')), findsNothing);
      expect(db.byId(2)['deleted_at'], isNotNull);
    });

    testWidgets('swipe right past the threshold reveals Edit; tapping it opens the form', (tester) async {
      await _pump(tester);
      await tester.drag(find.byKey(const Key('analyticsRow-1')), const Offset(90, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsRowEdit-1')));
      await tester.pumpAndSettle();
      expect(find.text('Edit transaction'), findsOneWidget);
    });

    testWidgets('a short drag snaps back; nothing opens, nothing is deleted', (tester) async {
      final db = await _pump(tester);
      final before = tester.getRect(find.text('JOHN KAMAU'));
      await tester.drag(find.byKey(const Key('analyticsRow-1')), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('JOHN KAMAU')), before);
      expect(find.text('Edit transaction'), findsNothing);
      expect(db.byId(1)['deleted_at'], isNull);
    });

    testWidgets('dark: Delete on the dark up-red with dark text (#2A0E0C); Edit on primary', (tester) async {
      await _pump(tester, brightness: Brightness.dark);
      const p = AppPalette.dark;
      final del = tester.widget<Material>(
        find.ancestor(of: find.byKey(const Key('analyticsRowDelete-1')), matching: find.byType(Material)).first,
      );
      expect(del.color, p.diffUp);
      final label = tester.widget<Text>(
        find.descendant(of: find.byKey(const Key('analyticsRowDelete-1')), matching: find.text('Delete')),
      );
      expect(label.style!.color, const Color(0xFF2A0E0C));
      final edit = tester.widget<Material>(
        find.ancestor(of: find.byKey(const Key('analyticsRowEdit-1')), matching: find.byType(Material)).first,
      );
      expect(edit.color, p.primary);
    });

    testWidgets('dark: the classification picker sheet follows the dark palette', (tester) async {
      await _pump(tester, brightness: Brightness.dark);
      const p = AppPalette.dark;
      await tester.tap(find.text('JOHN KAMAU'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editChooseClassificationButton')));
      await tester.pumpAndSettle();

      final sheet = tester.widget<Container>(
        find.ancestor(of: find.text('Choose a classification'), matching: find.byType(Container)).first,
      );
      expect((sheet.decoration as BoxDecoration).color, p.card);
      final item = tester.widget<Text>(find.text('Rent'));
      expect(item.style!.color, p.ink);
      expect(item.style!.color, isNot(AppPalette.light.ink));
    });
  });
}
