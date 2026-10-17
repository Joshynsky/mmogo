// F3 (0.1.2 corrections): the Delete data sheet with the "?" in its header
// (mock delete-data-help.html) and the buttons pinned above the keyboard (R30).
// FAKE service, FAKE Back up now flow, FAKE restart: nothing real is touched.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/delete_data_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/delete_data_harness.dart';
import '../../../support/fake_delete_data.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the "?" in the sheet header', () {
    testWidgets('is spoken "About deleting data", 44 px, collapsed; a tap shows the extras and reports expanded; another tap hides them', (tester) async {
      final h = tester.ensureSemantics();
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake, size: const Size(400, 800));
      await openDeleteSheet(tester);
      final q = find.byKey(const Key('deleteHelpButton'));
      expect(tester.getSize(q), const Size(44, 44));
      expect(tester.getSemantics(q).label, kDeleteHelpLabel);
      expect(kDeleteHelpLabel, 'About deleting data');
      expect(tester.getSemantics(q).flagsCollection.isExpanded, Tristate.isFalse);
      expect(find.byKey(const Key('deleteExtras')), findsNothing);
      await tester.tap(q);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(q).flagsCollection.isExpanded, Tristate.isTrue);
      expect(find.byKey(const Key('deleteExtras')), findsOneWidget);
      for (final s in kDeleteExtras) {
        expect(find.text(s), findsOneWidget);
      }
      await tester.tap(q);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteExtras')), findsNothing);
      h.dispose();
    });

    testWidgets('always visible: "This cannot be undone.", Back up now, the counts line, the word field and the hint', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake, size: const Size(400, 800));
      await openDeleteSheet(tester);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      expect(find.text(kDeleteExtraBackups), findsNothing, reason: 'behind the "?"');
      expect(find.byKey(const Key('deleteBackUpNow')), findsOneWidget);
      expect(find.textContaining(kDeleteCountsPrefix), findsOneWidget);
      expect(find.text(kDeleteWordLabel), findsOneWidget);
      expect(find.text('The red button stays off until the word matches.'), findsOneWidget);
      expect(goEnabled(tester), isFalse);
    });

    testWidgets('the sheet title names the route for the screen reader', (tester) async {
      final h = tester.ensureSemantics();
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake, size: const Size(400, 800));
      await openDeleteSheet(tester);
      final route = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.namesRoute == true && w.properties.label == kDeleteDataTitle,
      );
      expect(route, findsOneWidget);
      h.dispose();
    });
  });

  group('R30: Cancel and the red button stay on screen above the keyboard', () {
    // The keyboard is 40 percent of the screen height, like the mock.
    for (final scale in [1.0, 1.3]) {
      testWidgets('text $scale: field focused with the keyboard up, both buttons visible and tappable, the hint whole', (tester) async {
        final fake = useFakeDeleteData();
        await pumpSettings(tester, fake, scale: scale, size: const Size(400, 800));
        await openDeleteSheet(tester);
        // At 1.3 the field is below the fold of the sheet: scroll the body to it, as a person would.
        await tester.ensureVisible(find.byKey(const Key('deleteWordField')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('deleteWordField')));
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(primaryFocusIsIn(const Key('deleteWordField')), isTrue);

        const keyboardTop = 800.0 - 320.0;
        final cancel = tester.getRect(find.byKey(const Key('deleteCancel')));
        final go = tester.getRect(find.byKey(const Key('deleteGo')));
        expect(cancel.bottom, lessThanOrEqualTo(keyboardTop), reason: 'Cancel above the keyboard');
        expect(go.bottom, lessThanOrEqualTo(keyboardTop), reason: 'the red button above the keyboard');
        expect(cancel.top, greaterThanOrEqualTo(0));
        expect(cancel.height, greaterThanOrEqualTo(44));
        expect(go.height, greaterThanOrEqualTo(44));

        // The hint is whole (not half under the buttons or the keyboard) and sits above the buttons.
        final hint = tester.getRect(find.text(kDeleteWordHint));
        expect(hint.bottom, lessThanOrEqualTo(cancel.top), reason: 'the hint is not under the pinned buttons');
        expect(hint.top, greaterThanOrEqualTo(0));
        final field = tester.getRect(find.byKey(const Key('deleteWordField')));
        expect(field.bottom, lessThanOrEqualTo(cancel.top));

        // Type the word: the red button turns on and can be tapped from here.
        await tester.enterText(find.byKey(const Key('deleteWordField')), 'DELETE');
        await tester.pump();
        expect(goEnabled(tester), isTrue);
        await tester.tapAt(go.center);
        await tester.pumpAndSettle();
        expect(fake.deleteCalls, 1, reason: 'the red button was tappable with the keyboard up');
        expect(fake.resetCalls, 0);
      });

      testWidgets('text $scale: with the keyboard up, Cancel closes the sheet and deletes nothing', (tester) async {
        final fake = useFakeDeleteData();
        await pumpSettings(tester, fake, scale: scale, size: const Size(400, 800));
        await openDeleteSheet(tester);
        // At 1.3 the field is below the fold of the sheet: scroll the body to it, as a person would.
        await tester.ensureVisible(find.byKey(const Key('deleteWordField')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('deleteWordField')));
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getRect(find.byKey(const Key('deleteCancel'))).center);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deleteWordField')), findsNothing);
        expect(fake.deleteCalls + fake.resetCalls, 0);
      });
    }

    testWidgets('text 1.6, 320 dp wide, dark, keyboard up, extras open: no overflow, both buttons above the keyboard', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake, scale: 1.6, dark: true, size: const Size(320, 700));
      await openDeleteSheet(tester);
      await tester.tap(find.byKey(const Key('deleteHelpButton')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('deleteWordField')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteWordField')));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final cancel = tester.getRect(find.byKey(const Key('deleteCancel')));
      final go = tester.getRect(find.byKey(const Key('deleteGo')));
      expect(cancel.bottom, lessThanOrEqualTo(700 - 280));
      expect(go.bottom, lessThanOrEqualTo(700 - 280));
      expect(go.right, lessThanOrEqualTo(320));
      expect(cancel.left, greaterThanOrEqualTo(0));
    });

    testWidgets('Reset app: the red button reads "Reset app…" and is also pinned above the keyboard', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake, size: const Size(400, 800));
      await openDeleteSheet(tester);
      await tester.tap(find.byKey(const Key('deleteLevel2')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('deleteWordField')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteWordField')));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.text(kDeleteButtonLevel2), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('deleteGo'))).bottom, lessThanOrEqualTo(480));
    });
  });
}
