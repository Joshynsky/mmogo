// 0.1.2 S10b (A2c, RS1, CB8, A9): the Replace flow up to the write: the
// preview before the confirm, the loss warning (only when rows would be lost,
// tick before Continue, Cancel the default), the confirm with
// "included + lost = live", failures inside the confirm, and the "this changed,
// look again" path. FAKE restore service, fake bridge: nothing real is touched.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/delete_data_copy.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/backup_page_harness.dart';
import '../../../support/fake_backup_ui.dart';
import '../../../support/fake_delete_data.dart';
import '../../../support/fake_restore_service.dart';

late FakeRestoreRig rig;

Future<void> pumpPage(WidgetTester t, {double scale = 1.0, bool dark = false, Size size = const Size(420, 3200)}) =>
    pumpBackupPage(t, restoreFlow: rig.flow(), scale: scale, dark: dark, size: size);

/// File picked, Replace chosen: ends on the warning or the confirm.
Future<void> toReplace(WidgetTester t) async {
  rig.file();
  await tapKey(t, 'restoreButton');
  await tapKey(t, 'restoreOptionReplace');
  await tapKey(t, 'restoreContinue');
}

Future<void> tickAndContinue(WidgetTester t) async {
  await tapKey(t, 'replaceTick');
  await tapKey(t, 'replaceWarnContinue');
}

String text(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data!;

Iterable<String> sheetTexts(WidgetTester t) =>
    t.widgetList<Text>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Text))).map((w) => w.data ?? '');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useFakeDeleteData();
    rig = FakeRestoreRig(useFakeBackupUi());
  });

  group('the preview comes first', () {
    testWidgets('previewReplace runs BEFORE the Replace confirm, and nothing is restored yet', (t) async {
      await pumpPage(t);
      await toReplace(t);
      expect(rig.service.calls, ['inspect', 'previewReplace']);
      expect(find.byKey(const Key('restoreReplaceDialog')), findsOneWidget);
    });

    testWidgets('while it runs a non-dismissible "Checking" shows; Back does not close it', (t) async {
      rig.service.previewGate = Completer<void>();
      await pumpPage(t);
      rig.file();
      await tapKey(t, 'restoreButton');
      await tapKey(t, 'restoreOptionReplace');
      await t.tap(find.byKey(const Key('restoreContinue')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(kReplaceChecking), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(kReplaceChecking), findsOneWidget, reason: 'Back does not dismiss it');
      rig.service.previewGate!.complete();
      await t.pumpAndSettle();
      expect(find.text(kReplaceChecking), findsNothing);
      expect(find.byKey(const Key('restoreReplaceDialog')), findsOneWidget);
    });

    for (final c in <(String, Object)>[
      ('a restore failure', const RestoreFailed(RestoreFailReason.safetyCopyFailed)),
      ('an unexpected error', StateError('x')),
    ]) {
      testWidgets('${c.$1} in the preview: the failure is shown, the confirm never opens, nothing is replaced', (t) async {
        rig.service.previewReplaceError = c.$2;
        await pumpPage(t);
        await toReplace(t);
        expect(find.byKey(const Key('restoreFailedDialog')), findsOneWidget);
        expect(text(t, 'restoreFailedMessage'), 'Could not restore. Nothing was changed.');
        expect(find.byKey(const Key('restoreReplaceDialog')), findsNothing);
        expect(rig.service.calls, ['inspect', 'previewReplace']);
        expect(rig.refreshes, 0);
      });
    }

    testWidgets('busy in the preview maps to its own text', (t) async {
      rig.service.previewReplaceError = const RestoreFailed(RestoreFailReason.busy);
      await pumpPage(t);
      await toReplace(t);
      expect(text(t, 'restoreFailedMessage'), kDataOpBusy);
    });
  });

  group('the loss warning', () {
    testWidgets('0 rows would be lost: no warning at all, the confirm shows no "lost" line', (t) async {
      await pumpPage(t);
      await toReplace(t);
      expect(find.byKey(const Key('replaceWarningSheet')), findsNothing);
      expect(find.byKey(const Key('replaceIdentity')), findsNothing);
      expect(sheetTexts(t).where((s) => s.contains('lost for good')), isEmpty);
    });

    testWidgets('rows would be lost: the warning comes FIRST, before the confirm', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 3);
      await pumpPage(t);
      await toReplace(t);
      expect(find.byKey(const Key('replaceWarningSheet')), findsOneWidget);
      expect(find.byKey(const Key('restoreReplaceDialog')), findsNothing);
      expect(find.text(kLostWarningTitle), findsOneWidget);
      expect(
        text(t, 'replaceWarningBody'),
        'Replace swaps everything on this phone for what is in the file. '
        "3 entries on this phone cannot be kept in the safety copy because they break the app's rules. "
        'If you continue, they are lost for good. Undo cannot bring them back.',
      );
      expect(rig.service.calls, ['inspect', 'previewReplace'], reason: 'nothing restored yet');
    });

    testWidgets('one row: singular wording; a category among them says "items"', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 1);
      await pumpPage(t);
      await toReplace(t);
      expect(text(t, 'replaceWarningBody'), contains('1 entry on this phone cannot be kept in the safety copy because it breaks'));
      expect(text(t, 'replaceWarningBody'), contains('it is lost for good. Undo cannot bring it back.'));
      await tapKey(t, 'replaceWarnCancel');
      rig.service.replacePreview = fakeReplacePreview(
        rows: [...fakeSkippedEntries(1), const SkippedRowInfo(kind: SkipKind.category, reason: SkipReason.cascaded)],
      );
      await toReplace(t);
      expect(text(t, 'replaceWarningBody'), contains('2 items on this phone cannot be kept'));
    });

    testWidgets('the list is behind "Show which": date and type only, title with the exact N, closing line', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 3);
      await pumpPage(t);
      await toReplace(t);
      expect(find.byKey(const Key('skippedRowsList')), findsNothing);
      await tapKey(t, 'showWhichButton');
      expect(find.text('Entries that will be lost (3)'), findsOneWidget);
      expect(find.text('01-09-2026, Send Money'), findsOneWidget);
      expect(find.text(kOnlyDateAndType), findsOneWidget);
      expect(find.textContaining('required detail'), findsNothing, reason: 'Replace lists show no reason');
    });

    testWidgets('200 rows: first 20, "and 180 more not shown", the exact 200, and NO Show all (A1)', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 200);
      await pumpPage(t);
      await toReplace(t);
      await tapKey(t, 'showWhichButton');
      expect(find.text('Entries that will be lost (200)'), findsOneWidget);
      expect(find.text('and 180 more not shown'), findsOneWidget);
      expect(find.byKey(const Key('skippedShowAll')), findsNothing);
      expect(find.text(lostWarningBody(200, allEntries: true)), findsOneWidget);
    });

    testWidgets('the tick gates Continue; the tick is a checked Semantics node', (t) async {
      final h = t.ensureSemantics();
      rig.service.replacePreview = fakeReplacePreview(lost: 2);
      await pumpPage(t);
      await toReplace(t);
      expect(t.widget<OutlinedButton>(find.byKey(const Key('replaceWarnContinue'))).onPressed, isNull);
      var tick = t.getSemantics(find.byKey(const Key('replaceTick')));
      expect(tick.label, kLostTickLabel);
      expect(tick.flagsCollection.isChecked.name, 'isFalse');
      await tapKey(t, 'replaceTick');
      tick = t.getSemantics(find.byKey(const Key('replaceTick')));
      expect(tick.flagsCollection.isChecked.name, 'isTrue');
      expect(t.widget<OutlinedButton>(find.byKey(const Key('replaceWarnContinue'))).onPressed, isNotNull);
      await tapKey(t, 'replaceTick');
      expect(t.widget<OutlinedButton>(find.byKey(const Key('replaceWarnContinue'))).onPressed, isNull, reason: 'untick turns it off');
      h.dispose();
    });

    testWidgets('Cancel is the large filled default with the initial focus; Continue is quieter', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 2);
      await pumpPage(t);
      await toReplace(t);
      expect(hasFocusKey(t, 'replaceWarnCancel'), isTrue);
      expect(t.widget(find.byKey(const Key('replaceWarnCancel'))), isA<FilledButton>());
      expect(t.widget(find.byKey(const Key('replaceWarnContinue'))), isA<OutlinedButton>());
      for (final k in ['replaceWarnCancel', 'replaceWarnContinue', 'replaceTick']) {
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
    });

    for (final how in ['Cancel', 'Back', 'outside tap', 'swipe']) {
      testWidgets('$how on the warning cancels: nothing restored, nothing refreshed', (t) async {
        rig.service.replacePreview = fakeReplacePreview(lost: 2);
        await pumpPage(t);
        await toReplace(t);
        switch (how) {
          case 'Cancel':
            await t.tap(find.byKey(const Key('replaceWarnCancel')));
          case 'Back':
            await t.binding.handlePopRoute();
          case 'outside tap':
            await t.tapAt(const Offset(10, 10));
          default:
            await t.fling(find.byKey(const Key('backupSheetTitle')), const Offset(0, 800), 1500);
        }
        await t.pumpAndSettle();
        expect(find.byKey(const Key('replaceWarningSheet')), findsNothing);
        expect(find.byKey(const Key('restoreReplaceDialog')), findsNothing);
        expect(rig.service.calls, ['inspect', 'previewReplace']);
        expect(rig.refreshes, 0);
      });
    }

    testWidgets('after the tick, Continue opens the confirm (the warning is not asked again)', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 2);
      await pumpPage(t);
      await toReplace(t);
      await tickAndContinue(t);
      expect(find.byKey(const Key('replaceWarningSheet')), findsNothing);
      expect(find.byKey(const Key('restoreReplaceDialog')), findsOneWidget);
    });
  });

  group('the confirm', () {
    testWidgets('"included + lost = live" for the transactions, from the preview identity', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 3);
      await pumpPage(t);
      await toReplace(t);
      await tickAndContinue(t);
      expect(
        text(t, 'replaceIdentity'),
        'Of the 60 transactions on this phone, 57 go into the safety copy and 3 are lost for good (57 + 3 = 60).',
      );
      expect(find.byKey(const Key('replaceLostCategories')), findsNothing, reason: 'only when above 0');
      expect(find.byKey(const Key('replaceLostReceivers')), findsNothing);
      expect(find.text(kUndoRestoresRest), findsOneWidget);
    });

    testWidgets('category and receiver lost lines appear only when above 0', (t) async {
      rig.service.replacePreview = fakeReplacePreview(
        rows: [
          ...fakeSkippedEntries(2),
          const SkippedRowInfo(kind: SkipKind.category, reason: SkipReason.cascaded),
          const SkippedRowInfo(kind: SkipKind.savedReceiver, reason: SkipReason.notAllowed),
          const SkippedRowInfo(kind: SkipKind.savedReceiver, reason: SkipReason.notAllowed),
        ],
      );
      await pumpPage(t);
      await toReplace(t);
      await tickAndContinue(t);
      expect(text(t, 'replaceLostCategories'), '1 category is lost for good.');
      expect(text(t, 'replaceLostReceivers'), '2 saved receivers are lost for good.');
    });

    testWidgets('the phone-side counts come from the Replace preview, not the earlier file preview', (t) async {
      rig.service.preview = fakePreview(phoneTx: 999, phoneCls: 99, phoneMap: 88, deleted: 77);
      rig.service.replacePreview = fakeReplacePreview(tx: 50, cls: 4, map: 6, deleted: 2);
      await pumpPage(t);
      await toReplace(t);
      expect(text(t, 'restoreReplacePhone'), '50 transactions, 4 categories, 6 saved receivers');
      expect(
        text(t, 'restoreReplaceRemoves'),
        startsWith('Replace will remove 52 transactions, 4 categories you made and 6 saved receivers from this phone'),
      );
      expect(text(t, 'restoreReplaceFile'), '187 transactions, 2 categories, 15 saved receivers');
    });

    testWidgets('the remembered-recipients sentence (F3) and "Undo is not exact" are on the confirm', (t) async {
      await pumpPage(t);
      await toReplace(t);
      expect(text(t, 'replaceRememberedNote'), kRememberedRecipientsNotInBackup);
      expect(text(t, 'restoreUndoNotExact'), kUndoNotExactNotice);
    });

    testWidgets('Cancel is the filled default with the focus; Replace everything is red; both are 44 high', (t) async {
      await pumpPage(t);
      await toReplace(t);
      expect(hasFocusKey(t, 'restoreReplaceCancel'), isTrue);
      expect(t.widget(find.byKey(const Key('restoreReplaceCancel'))), isA<FilledButton>());
      for (final k in ['restoreReplaceCancel', 'restoreReplaceGo']) {
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
    });

    for (final dark in [false, true]) {
      testWidgets('Replace everything: red with 4.5:1 text contrast (${dark ? 'dark' : 'light'})', (t) async {
        await pumpPage(t, dark: dark);
        await toReplace(t);
        final style = t.widget<FilledButton>(find.byKey(const Key('restoreReplaceGo'))).style!;
        final bg = style.backgroundColor!.resolve({})!;
        final fg = style.foregroundColor!.resolve({})!;
        final p = dark ? AppPalette.dark : AppPalette.light;
        expect(bg, p.diffUp);
        expect(contrastRatio(bg, fg), greaterThanOrEqualTo(4.5));
      });
    }

    for (final how in ['Cancel', 'Back', 'outside tap', 'swipe']) {
      testWidgets('$how on the confirm cancels: nothing restored', (t) async {
        await pumpPage(t);
        await toReplace(t);
        switch (how) {
          case 'Cancel':
            await t.tap(find.byKey(const Key('restoreReplaceCancel')));
          case 'Back':
            await t.binding.handlePopRoute();
          case 'outside tap':
            await t.tapAt(const Offset(10, 10));
          default:
            await t.fling(find.byKey(const Key('backupSheetTitle')), const Offset(0, 800), 1500);
        }
        await t.pumpAndSettle();
        expect(find.byKey(const Key('restoreReplaceDialog')), findsNothing);
        expect(rig.service.calls, ['inspect', 'previewReplace']);
        expect(rig.refreshes, 0);
      });
    }

    testWidgets('Replace everything passes acceptedSkipped = the previewed count', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 4);
      await pumpPage(t);
      await toReplace(t);
      await tickAndContinue(t);
      await tapKey(t, 'restoreReplaceGo');
      expect(rig.service.lastAcceptedSkipped, 4);
      rig.service.calls.clear();
    });

    testWidgets('with 0 to lose acceptedSkipped is 0 (not null)', (t) async {
      await pumpPage(t);
      await toReplace(t);
      await tapKey(t, 'restoreReplaceGo');
      expect(rig.service.lastAcceptedSkipped, 0);
    });
  });

  group('failures inside the confirm', () {
    testWidgets('safety copy could not be saved: red box in the confirm, buttons back, nothing replaced', (t) async {
      rig.service.restoreError = const RestoreFailed(RestoreFailReason.safetyCopyFailed);
      await pumpPage(t);
      await toReplace(t);
      await tapKey(t, 'restoreReplaceGo');
      expect(find.byKey(const Key('restoreReplaceDialog')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('replaceConfirmError')), matching: find.text(kReplaceSafetyCopyFailed)), findsOneWidget);
      expect(kReplaceSafetyCopyFailed, 'Could not save a safety copy, so nothing was replaced.');
      expect(find.byKey(const Key('restoreReplaceGo')), findsOneWidget);
      expect(find.byKey(const Key('restoreReplaceCancel')), findsOneWidget);
      expect(rig.refreshes, 0);
    });

    for (final c in <(String, Object, String)>[
      ('database error', const RestoreFailed(RestoreFailReason.databaseError), 'Could not restore. Nothing was changed.'),
      ('data changed', const RestoreFailed(RestoreFailReason.dataChangedMeanwhile), 'Could not restore. Nothing was changed.'),
      ('an unexpected error', StateError('x'), 'Could not restore. Nothing was changed.'),
      ('busy', const RestoreFailed(RestoreFailReason.busy), kDataOpBusy),
    ]) {
      testWidgets('${c.$1}: ${c.$3}', (t) async {
        rig.service.restoreError = c.$2;
        await pumpPage(t);
        await toReplace(t);
        await tapKey(t, 'restoreReplaceGo');
        expect(find.descendant(of: find.byKey(const Key('replaceConfirmError')), matching: find.text(c.$3)), findsOneWidget);
        expect(rig.refreshes, 0);
      });
    }

    testWidgets('after a failure the user can try again, and Cancel still changes nothing', (t) async {
      rig.service.restoreErrorQueue.add(const RestoreFailed(RestoreFailReason.safetyCopyFailed));
      await pumpPage(t);
      await toReplace(t);
      await tapKey(t, 'restoreReplaceGo');
      await tapKey(t, 'restoreReplaceGo'); // second try works
      expect(rig.service.calls, ['inspect', 'previewReplace', 'restore:replace', 'restore:replace']);
      expect(find.byKey(const Key('restoreResultSheet')), findsOneWidget);
      expect(rig.refreshes, 1);
    });

    testWidgets('after a failure, Cancel ends the flow with nothing changed', (t) async {
      rig.service.restoreError = const RestoreFailed(RestoreFailReason.databaseError);
      await pumpPage(t);
      await toReplace(t);
      await tapKey(t, 'restoreReplaceGo');
      await tapKey(t, 'restoreReplaceCancel');
      expect(find.byKey(const Key('restoreReplaceDialog')), findsNothing);
      expect(rig.refreshes, 0);
    });
  });

  group('"this changed" (skippedChanged)', () {
    testWidgets('the refusal shows the preview again with the changed line, the tick is reset, never silent', (t) async {
      rig.service.previewQueue.addAll([fakeReplacePreview(lost: 2), fakeReplacePreview(lost: 5)]);
      rig.service.restoreErrorQueue.add(const RestoreFailed(RestoreFailReason.skippedChanged));
      await pumpPage(t);
      await toReplace(t);
      expect(find.byKey(const Key('replaceChangedNote')), findsNothing, reason: 'not on the first look');
      await tickAndContinue(t);
      await tapKey(t, 'restoreReplaceGo');
      // Back on the warning with the new count, the line, and an unticked box.
      expect(find.byKey(const Key('replaceWarningSheet')), findsOneWidget);
      expect(text(t, 'replaceChangedNote'), 'This changed while you were checking. Please look again.');
      expect(text(t, 'replaceWarningBody'), contains('5 entries'));
      expect(t.widget<OutlinedButton>(find.byKey(const Key('replaceWarnContinue'))).onPressed, isNull, reason: 'tick reset');
      expect(rig.service.calls, ['inspect', 'previewReplace', 'restore:replace', 'previewReplace']);
      await tickAndContinue(t);
      await tapKey(t, 'restoreReplaceGo');
      expect(rig.service.lastAcceptedSkipped, 5);
      expect(find.byKey(const Key('restoreResultSheet')), findsOneWidget);
    });

    testWidgets('if the new count is 0 the confirm opens (no warning), with the new numbers', (t) async {
      rig.service.previewQueue.addAll([fakeReplacePreview(lost: 2), fakeReplacePreview()]);
      rig.service.restoreErrorQueue.add(const RestoreFailed(RestoreFailReason.skippedChanged));
      await pumpPage(t);
      await toReplace(t);
      await tickAndContinue(t);
      await tapKey(t, 'restoreReplaceGo');
      expect(find.byKey(const Key('replaceWarningSheet')), findsNothing);
      expect(find.byKey(const Key('restoreReplaceDialog')), findsOneWidget);
      expect(find.byKey(const Key('replaceIdentity')), findsNothing);
      expect(rig.refreshes, 0);
    });

    testWidgets('the changed text does not say "skipped"', (t) async {
      expect(kChangedWhileChecking.toLowerCase().contains('skipped'), isFalse);
    });
  });

  group('every phone-side sheet, scale 1.3, 200 rows: buttons stay on screen', () {
    testWidgets('warning and confirm', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 200);
      await pumpPage(t, scale: 1.3, size: const Size(420, 900));
      rig.file();
      await t.dragUntilVisible(find.byKey(const Key('restoreButton')), find.byKey(const Key('backupScroll')), const Offset(0, -300));
      await t.pumpAndSettle();
      await tapKey(t, 'restoreButton');
      await t.ensureVisible(find.byKey(const Key('restoreOptionReplace'))); // the 0.1.1 dialog scrolls
      await tapKey(t, 'restoreOptionReplace');
      await t.ensureVisible(find.byKey(const Key('restoreContinue')));
      await tapKey(t, 'restoreContinue');
      await tapKey(t, 'showWhichButton'); // worst case: the list is open
      final h = t.view.physicalSize.height / t.view.devicePixelRatio;
      for (final k in ['replaceWarnCancel', 'replaceWarnContinue']) {
        expect(t.getRect(find.byKey(Key(k))).bottom, lessThanOrEqualTo(h), reason: k);
        expect(t.getRect(find.byKey(Key(k))).top, greaterThanOrEqualTo(0), reason: k);
      }
      await t.ensureVisible(find.byKey(const Key('replaceTick'))); // the body scrolls; the buttons do not
      await tickAndContinue(t);
      for (final k in ['restoreReplaceCancel', 'restoreReplaceGo']) {
        expect(t.getRect(find.byKey(Key(k))).bottom, lessThanOrEqualTo(h), reason: k);
      }
      expect(t.takeException(), isNull);
    });
  });
}
