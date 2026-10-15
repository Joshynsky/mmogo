// 0.1.2 S9b-2: the Delete data row and sheet (DD2 + CB6 + addendum A5-A8).
// FAKE service, FAKE Back up now flow, FAKE restart: nothing real is touched.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/ui/copy/delete_data_copy.dart';
import 'package:mmogo/ui/screens/backup/backup_export_flow.dart';
import 'package:mmogo/ui/screens/settings/settings_widgets.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/delete_data_harness.dart';
import '../../../support/fake_delete_data.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the row', () {
    testWidgets('is the LAST row of Your data, with a red Permanent tag and the default subtitle', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      expect(find.text(kDeleteDataTitle), findsOneWidget);
      expect(find.text(kDeleteRowSubtitle), findsOneWidget);
      expect(find.text(kDeletePermanentTag), findsOneWidget);
      final y = tester.getTopLeft(find.text(kDeleteDataTitle)).dy;
      for (final t in ['Backup and restore', 'Recently deleted', 'Export CSV']) {
        expect(tester.getTopLeft(find.text(t)).dy, lessThan(y), reason: '$t is above Delete data');
      }
      expect(tester.getTopLeft(find.text('ABOUT')).dy, greaterThan(y));
      final links = tester.widgetList<SettingsLink>(find.byType(SettingsLink)).toList();
      final i = links.indexWhere((l) => l.label == kDeleteDataTitle);
      expect(links[i + 1].label, 'Privacy and your data', reason: 'the next link is in ABOUT');
    });

    testWidgets('Level 1 empty: "Transactions deleted. You can still reset the app." and still opens', (tester) async {
      final fake = useFakeDeleteData(FakeDeleteDataService(peekValue: kFakePeekLevel1Empty));
      await pumpSettings(tester, fake);
      expect(find.text(kDeleteRowSubtitleLevel1Done), findsOneWidget);
      await openDeleteSheet(tester);
      expect(find.byKey(const Key('deleteWordField')), findsOneWidget);
    });

    testWidgets('nothing left at Level 2: "Nothing to delete", no arrow, no sheet', (tester) async {
      final fake = useFakeDeleteData(FakeDeleteDataService(peekValue: kFakePeekNothing));
      await pumpSettings(tester, fake);
      expect(find.text(kDeleteRowSubtitleNothing), findsOneWidget);
      final link = find.ancestor(of: find.text(kDeleteDataTitle), matching: find.byType(SettingsLink));
      expect(find.descendant(of: link, matching: find.byIcon(Icons.chevron_right)), findsNothing);
      await tester.tap(deleteRow);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteWordField')), findsNothing);
    });

    testWidgets('a failed peek keeps the default subtitle and does not crash', (tester) async {
      final fake = useFakeDeleteData(FakeDeleteDataService()..peekError = StateError('read failed'));
      await pumpSettings(tester, fake);
      expect(tester.takeException(), isNull);
      expect(find.text(kDeleteRowSubtitle), findsOneWidget);
      await openDeleteSheet(tester);
      expect(find.byKey(const Key('deleteWordField')), findsOneWidget, reason: 'the sheet still opens');
    });

    testWidgets('the Permanent tag reads in dark and light: palette.diffUp with palette.onDelete', (tester) async {
      for (final dark in [false, true]) {
        final fake = useFakeDeleteData();
        await pumpSettings(tester, fake, dark: dark);
        final p = dark ? AppPalette.dark : AppPalette.light;
        final tag = tester.widget<Container>(find.byKey(const Key('settingsRowRedTag')));
        expect((tag.decoration! as BoxDecoration).color, p.diffUp);
        final text = tester.widget<Text>(find.text(kDeletePermanentTag));
        expect(text.style!.color, p.onDelete);
        expect(_contrast(p.diffUp, p.onDelete), greaterThanOrEqualTo(4.5), reason: dark ? 'dark' : 'light');
      }
    });
  });

  group('the sheet', () {
    testWidgets('opens with the title, intro, Back up now, two cards with aggregate counts, the word field, red button off', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      expect(find.text(kDeleteDataTitle), findsNWidgets(2), reason: 'the row and the sheet title');
      expect(find.text(kDeleteIntro), findsOneWidget);
      expect(find.byKey(const Key('deleteBackUpNow')), findsOneWidget);
      expect(find.text(kDeleteLevel1Title), findsOneWidget);
      expect(find.text(kDeleteLevel2Title), findsOneWidget);
      expect(
        find.textContaining('12 transactions, 2 recently deleted, 3 learned receivers, 2 remembered recipients'),
        findsOneWidget,
      );
      expect(find.text(kDeleteWordLabel), findsOneWidget);
      expect(goEnabled(tester), isFalse);
      expect(find.text(kDeleteButtonLevel1), findsOneWidget);
      expect(fake.deleteCalls + fake.resetCalls, 0);
    });

    test('counts: zeros left out, singular and plural', () {
      expect(
        deleteCountsText(live: 1, recentlyDeleted: 0, learnedReceivers: 1, rememberedRecipients: 0),
        '1 transaction, 1 learned receiver',
      );
      expect(deleteCountsText(live: 0, recentlyDeleted: 0, learnedReceivers: 0, rememberedRecipients: 0), '');
      expect(
        deleteCountsText(live: 0, recentlyDeleted: 4, learnedReceivers: 0, rememberedRecipients: 1),
        '4 recently deleted, 1 remembered recipient',
      );
    });

    testWidgets('Cancel, outside tap, Back and swipe down: nothing deleted, service never asked to delete', (tester) async {
      for (final path in ['cancel', 'outside', 'back', 'swipe']) {
        final fake = useFakeDeleteData();
        await pumpSettings(tester, fake);
        await openDeleteSheet(tester);
        switch (path) {
          case 'cancel':
            await tester.tap(find.byKey(const Key('deleteCancel')));
          case 'outside':
            await tester.tapAt(const Offset(200, 10));
          case 'back':
            await tester.binding.handlePopRoute();
          case 'swipe':
            await tester.fling(find.byKey(const Key('deleteCancel')), const Offset(0, 800), 3000);
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deleteWordField')), findsNothing, reason: '$path closes the sheet');
        expect(fake.deleteCalls, 0, reason: path);
        expect(fake.resetCalls, 0, reason: path);
      }
    });

    testWidgets('after the sheet closes the row asks again, so the subtitle is current', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      final before = fake.peekCalls;
      await openDeleteSheet(tester);
      fake.peekValue = kFakePeekLevel1Empty;
      await tester.tap(find.byKey(const Key('deleteCancel')));
      await tester.pumpAndSettle();
      expect(fake.peekCalls, greaterThan(before + 1));
      expect(find.text(kDeleteRowSubtitleLevel1Done), findsOneWidget);
    });

    testWidgets('typed word: wrong stays off; lower case with spaces turns on; the label follows the level', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      await typeWord(tester, 'DELET');
      expect(goEnabled(tester), isFalse);
      await typeWord(tester, 'DELETEX');
      expect(goEnabled(tester), isFalse);
      await typeWord(tester, '  delete ');
      expect(goEnabled(tester), isTrue);
      expect(find.text(kDeleteButtonLevel1), findsOneWidget);
      // Switching level clears the typed word and changes the label.
      await tester.tap(find.byKey(const Key('deleteLevel2')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('deleteWordField'))).controller!.text, isEmpty);
      expect(goEnabled(tester), isFalse);
      expect(find.text(kDeleteButtonLevel2), findsOneWidget);
      expect(find.text(kDeleteButtonLevel1), findsNothing);
    });

    testWidgets('the word field asks for capitals and the keyboard Done key never deletes', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      final field = tester.widget<TextField>(find.byKey(const Key('deleteWordField')));
      expect(field.textCapitalization, TextCapitalization.characters);
      await tester.showKeyboard(find.byKey(const Key('deleteWordField')));
      await typeWord(tester, 'DELETE');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(fake.deleteCalls + fake.resetCalls, 0);
      expect(find.byKey(const Key('deleteWordField')), findsOneWidget, reason: 'the sheet is still open');
    });

    testWidgets('Level 1 disabled: "Nothing left to delete here.", Reset preselected, the card ignores taps', (tester) async {
      final fake = useFakeDeleteData(FakeDeleteDataService(peekValue: kFakePeekLevel1Empty));
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      expect(find.text(kDeleteLevel1Nothing), findsOneWidget);
      await typeWord(tester, 'delete');
      expect(find.text(kDeleteButtonLevel2), findsOneWidget, reason: 'Reset is preselected');
      await tester.tap(find.byKey(const Key('deleteLevel1')));
      await tester.pump();
      expect(find.text(kDeleteButtonLevel2), findsOneWidget, reason: 'still Reset');
      final handle = tester.ensureSemantics();
      final l1 = tester.getSemantics(find.byKey(const Key('deleteLevel1')));
      expect(l1.flagsCollection.isEnabled, Tristate.isFalse);
      final l2 = tester.getSemantics(find.byKey(const Key('deleteLevel2')));
      expect(l2.flagsCollection.isSelected, Tristate.isTrue);
      expect(l2.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      handle.dispose();
    });

    testWidgets('an incomplete peek shows no numbers and keeps Level 1 enabled (never "Nothing left")', (tester) async {
      final fake = useFakeDeleteData(
        FakeDeleteDataService(
          peekValue: const DeleteDataPeek(
            liveTransactions: 0,
            softDeletedTransactions: 0,
            learnedReceivers: 0,
            safetyCopyPresent: false,
            rememberedRecipientsPresent: false,
            queuePresent: false,
            incomplete: true,
          ),
        ),
      );
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      expect(find.text(kDeleteLevel1Nothing), findsNothing);
      expect(find.text(kDeleteCountsUnknown), findsOneWidget);
      await typeWord(tester, 'delete');
      expect(find.text(kDeleteButtonLevel1), findsOneWidget, reason: 'Level 1 is the preselected, enabled level');
      expect(goEnabled(tester), isTrue);
    });

    testWidgets('CB6: the sheet says backups stay, SMS stay, the safety copy goes, categories stay', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      expect(find.textContaining('Backup files you saved earlier are not touched'), findsOneWidget);
      expect(find.textContaining(kDeleteStayBackups), findsOneWidget);
      expect(find.textContaining(kDeleteStayAutoList), findsOneWidget);
      expect(find.text(kDeleteStaySms), findsNWidgets(2), reason: 'on both cards');
      expect(find.text(kDeleteLevel1SafetyGone), findsOneWidget);
      expect(find.text(kDeleteLevel1CategoriesStay), findsOneWidget);
      expect(find.textContaining('Deleted from this phone'), findsWidgets);
    });
  });

  group('Reset app: the second sheet', () {
    testWidgets('red goes to a confirm sheet; Cancel is focused and calls nothing; the service is not asked', (tester) async {
      final fake = useFakeDeleteData();
      final restart = FakeRestart();
      await pumpSettings(tester, fake, restart: restart);
      await openDeleteSheet(tester);
      await tester.tap(find.byKey(const Key('deleteLevel2')));
      await typeWord(tester, 'delete');
      await tapGo(tester);
      await tester.pumpAndSettle();
      expect(find.text(kDeleteConfirmTitle), findsOneWidget);
      expect(find.text(kDeleteConfirmBody), findsOneWidget);
      final cancel = tester.widget<FilledButton>(find.byKey(const Key('resetConfirmCancel')));
      expect(cancel.autofocus, isTrue);
      expect(primaryFocusIsIn(const Key('resetConfirmCancel')), isTrue, reason: 'Cancel has the focus');
      expect(fake.resetCalls, 0);
      await tester.tap(find.byKey(const Key('resetConfirmCancel')));
      await tester.pumpAndSettle();
      expect(find.text(kDeleteConfirmTitle), findsNothing);
      expect(find.byKey(const Key('deleteWordField')), findsOneWidget, reason: 'back on the first sheet, state kept');
      expect(fake.resetCalls, 0);
      expect(restart.calls, 0);
    });

    for (final path in ['outside', 'back', 'swipe']) {
      testWidgets('$path on the confirm sheet is Cancel: nothing is called', (tester) async {
        final fake = useFakeDeleteData();
        await pumpSettings(tester, fake);
        await openDeleteSheet(tester);
        await tester.tap(find.byKey(const Key('deleteLevel2')));
        await typeWord(tester, 'delete');
        await tapGo(tester);
        await tester.pumpAndSettle();
        expect(find.text(kDeleteConfirmTitle), findsOneWidget);
        switch (path) {
          case 'outside':
            await tester.tapAt(const Offset(200, 10));
          case 'back':
            await tester.binding.handlePopRoute();
          case 'swipe':
            await tester.fling(find.byKey(const Key('resetConfirmCancel')), const Offset(0, 800), 3000);
        }
        await tester.pumpAndSettle();
        expect(find.text(kDeleteConfirmTitle), findsNothing, reason: path);
        expect(fake.resetCalls, 0, reason: path);
        expect(fake.deleteCalls, 0, reason: path);
      });
    }

    testWidgets('the red Reset app ignores taps for the first moments: a double tap calls resetApp zero times', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake, restart: FakeRestart());
      await openDeleteSheet(tester);
      await tester.tap(find.byKey(const Key('deleteLevel2')));
      await typeWord(tester, 'delete');
      await tapGo(tester); // the first tap of the double tap
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350)); // the confirm sheet is up
      await tester.tap(find.byKey(const Key('resetConfirmGo'))); // the second tap, same spot
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(fake.resetCalls, 0, reason: 'too early: ignored');
      expect(find.text(kDeleteConfirmTitle), findsOneWidget, reason: 'the confirm sheet is still there');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byKey(const Key('resetConfirmGo')));
      await tester.pump(const Duration(milliseconds: 400)); // the run sheet spins; do not wait for it to settle
      expect(fake.resetCalls, 1, reason: 'a later tap goes through');
    });
  });

  group('Back up now (fake flow)', () {
    testWidgets('a closed share sheet changes nothing: sheet open, level and word kept, Delete still works', (tester) async {
      final fake = useFakeDeleteData();
      final flow = FakeBackupFlow(const BackupNotShared());
      await pumpSettings(tester, fake, flow: flow);
      await openDeleteSheet(tester);
      await tester.tap(find.byKey(const Key('deleteLevel2')));
      await typeWord(tester, 'delete');
      await tester.tap(find.byKey(const Key('deleteBackUpNow')));
      await tester.pumpAndSettle();
      expect(find.text('Before you back up'), findsOneWidget);
      await tester.tap(find.text('Share backup'));
      await tester.pumpAndSettle();
      expect(flow.runs, 1);
      expect(find.byKey(const Key('deleteWordField')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('deleteWordField'))).controller!.text, 'delete');
      expect(find.text(kDeleteButtonLevel2), findsOneWidget, reason: 'the level is kept');
      expect(goEnabled(tester), isTrue, reason: 'a closed share sheet does not block Delete');
      expect(fake.deleteCalls + fake.resetCalls, 0, reason: 'and it is never forced');
    });

    testWidgets('a failure shows the same dialog as the Backup page; a cancelled warning never runs the flow', (tester) async {
      final fake = useFakeDeleteData();
      final flow = FakeBackupFlow(const BackupFailed());
      await pumpSettings(tester, fake, flow: flow);
      await openDeleteSheet(tester);
      await tester.tap(find.byKey(const Key('deleteBackUpNow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share backup'));
      await tester.pumpAndSettle();
      expect(find.text('Could not create the backup'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteWordField')), findsOneWidget);
      await tester.tap(find.byKey(const Key('deleteBackUpNow')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(flow.runs, 1);
      expect(find.byKey(const Key('deleteWordField')), findsOneWidget);
    });
  });

  group('accessibility: 44 px, 1.3 scale, dark, focus, semantics', () {
    testWidgets('every control is at least 44 high and wide', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      for (final k in ['deleteBackUpNow', 'deleteLevel1', 'deleteLevel2', 'deleteCancel', 'deleteGo']) {
        final s = tester.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(44), reason: '$k height');
        expect(s.width, greaterThanOrEqualTo(44), reason: '$k width');
      }
      final row = tester.getSize(find.ancestor(of: find.text(kDeleteDataTitle), matching: find.byType(InkWell)).first);
      expect(row.height, greaterThanOrEqualTo(44));
    });

    testWidgets('initial focus: Back up now on the main sheet; the row gets focus back on close', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      expect(primaryFocusIsIn(const Key('deleteBackUpNow')), isTrue);
      await tester.tap(find.byKey(const Key('deleteCancel')));
      await tester.pumpAndSettle();
      final rowInk = tester.widget<InkWell>(find.ancestor(of: find.text(kDeleteDataTitle), matching: find.byType(InkWell)).first);
      expect(rowInk.focusNode!.hasPrimaryFocus, isTrue, reason: 'focus returned to the row');
    });

    testWidgets('the red button says it turns on when the word matches, and only while it is off', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      await openDeleteSheet(tester);
      final handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.byKey(const Key('deleteGo'))).hint, contains(kDeleteButtonSemanticsHint));
      await typeWord(tester, 'delete');
      expect(tester.getSemantics(find.byKey(const Key('deleteGo'))).hint, isNot(contains(kDeleteButtonSemanticsHint)));
      handle.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets('1.3 text scale, ${dark ? 'dark' : 'light'}, keyboard open: no overflow, every control reachable', (tester) async {
        final fake = useFakeDeleteData();
        await pumpSettings(tester, fake, scale: 1.3, dark: dark, size: const Size(400, 800));
        await openDeleteSheet(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await typeWord(tester, 'delete');
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('deleteGo')));
        await tester.pumpAndSettle();
        expect(goEnabled(tester), isTrue);
        await tester.ensureVisible(find.byKey(const Key('deleteLevel2')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final p = dark ? AppPalette.dark : AppPalette.light;
        final go = tester.widget<FilledButton>(find.byKey(const Key('deleteGo')));
        expect(go.style!.backgroundColor!.resolve({}), p.diffUp);
        expect(go.style!.foregroundColor!.resolve({}), p.onDelete);
      });
    }
  });
}
