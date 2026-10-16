// 0.1.2 S10b (BP2, A2, A9d, A10, A14, item 6, item 7): the step list and the
// slow line, the busy rules (the sheet cannot be dismissed), the Replace
// result with its lost list, the Undo result (never "back" when rows were
// lost; the safety copy that stayed), the settings labels, and the refresh of
// Home and Analytics after a restore. FAKE service and bridge only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/backup/backup_screen.dart';
import 'package:mmogo/ui/shell/primary_shell.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/backup_page_harness.dart';
import '../../../support/fake_backup_ui.dart';
import '../../../support/fake_delete_data.dart';
import '../../../support/fake_restore_service.dart';

late FakeRestoreRig rig;

Future<void> pumpPage(WidgetTester t, {double scale = 1.0, Size size = const Size(420, 3200)}) =>
    pumpBackupPage(t, restoreFlow: rig.flow(), scale: scale, size: size);

Future<void> toMode(WidgetTester t) async {
  rig.file();
  await tapKey(t, 'restoreButton');
}

/// Replace chosen and confirmed (0 rows would be lost unless the test set some).
Future<void> replaceAndConfirm(WidgetTester t) async {
  await toMode(t);
  await tapKey(t, 'restoreOptionReplace');
  await tapKey(t, 'restoreContinue');
  if (find.byKey(const Key('replaceWarningSheet')).evaluate().isNotEmpty) {
    await tapKey(t, 'replaceTick');
    await tapKey(t, 'replaceWarnContinue');
  }
  await tapKey(t, 'restoreReplaceGo');
}

/// A frame pair that lets a route animate in without waiting for a spinner.
Future<void> settleBusy(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> dismissAttempts(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await settleBusy(t);
  await t.tapAt(const Offset(10, 10));
  await settleBusy(t);
  await t.fling(find.byKey(const Key('backupSheetTitle')), const Offset(0, 800), 1500);
  await settleBusy(t);
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

  group('progress: the step list and the slow line', () {
    testWidgets('Replace shows the three steps, fed by the real step events, as a live region', (t) async {
      final h = t.ensureSemantics();
      rig.service.restoreGate = Completer<void>();
      rig.service.steps = const [
        RestoreStepEvent(RestoreStep.validating, RestoreStepPhase.started),
        RestoreStepEvent(RestoreStep.validating, RestoreStepPhase.done),
        RestoreStepEvent(RestoreStep.safetyCopy, RestoreStepPhase.started),
      ];
      await pumpPage(t);
      await toMode(t);
      await tapKey(t, 'restoreOptionReplace');
      await tapKey(t, 'restoreContinue');
      await t.tap(find.byKey(const Key('restoreReplaceGo')));
      await settleBusy(t);
      expect(find.text(kReplaceProgressTitle), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Checking the file, done')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Saving a safety copy, in progress')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Replacing your data, waiting')), findsOneWidget);
      expect(find.text(kStepValidating), findsOneWidget);
      expect(find.text(kStepSafetyCopy), findsOneWidget);
      expect(find.text(kStepWriting), findsOneWidget);
      expect(t.getSemantics(find.byKey(const Key('restoreStepList'))).flagsCollection.isLiveRegion, isTrue);
      // The next events move the list on.
      rig.service.onStepSink!(const RestoreStepEvent(RestoreStep.safetyCopy, RestoreStepPhase.done));
      rig.service.onStepSink!(const RestoreStepEvent(RestoreStep.writing, RestoreStepPhase.started));
      await t.pump();
      expect(find.bySemanticsLabel(RegExp('Saving a safety copy, done')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Replacing your data, in progress')), findsOneWidget);
      rig.service.restoreGate!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoreResultSheet')), findsOneWidget);
      h.dispose();
    });

    testWidgets('the slow line appears only when a slow event arrives (no UI timer), and is a live region', (t) async {
      final h = t.ensureSemantics();
      rig.service.restoreGate = Completer<void>();
      await pumpPage(t);
      await toMode(t);
      await tapKey(t, 'restoreOptionReplace');
      await tapKey(t, 'restoreContinue');
      await t.tap(find.byKey(const Key('restoreReplaceGo')));
      await settleBusy(t);
      await t.pump(const Duration(seconds: 30)); // time alone never shows it
      expect(find.byKey(const Key('restoreSlowLine')), findsNothing);
      rig.service.onStepSink!(const RestoreStepEvent(RestoreStep.safetyCopy, RestoreStepPhase.slow));
      await t.pump();
      expect(text(t, 'restoreSlowLine'), kRestoreSlow);
      expect(kRestoreSlow, 'This is taking longer than usual. Keep mmogo open.');
      expect(t.getSemantics(find.byKey(const Key('restoreSlowLine'))).flagsCollection.isLiveRegion, isTrue);
      rig.service.restoreGate!.complete();
      await t.pumpAndSettle();
      h.dispose();
    });

    testWidgets('Merge shows its one label (no step list) and the slow line on a slow event', (t) async {
      rig.service.restoreGate = Completer<void>();
      await pumpPage(t);
      await toMode(t);
      await t.tap(find.byKey(const Key('restoreContinue')));
      await settleBusy(t);
      expect(find.text(kRestoreRestoring), findsOneWidget);
      expect(find.byKey(const Key('restoreStepList')), findsNothing);
      rig.service.onStepSink!(const RestoreStepEvent(RestoreStep.writing, RestoreStepPhase.slow));
      await t.pump();
      expect(find.byKey(const Key('restoreSlowLine')), findsOneWidget);
      rig.service.restoreGate!.complete();
      await t.pumpAndSettle();
    });

    testWidgets('a failed phase leaves the sheet to the failure path (the confirm with its red box)', (t) async {
      rig.service.steps = const [
        RestoreStepEvent(RestoreStep.validating, RestoreStepPhase.started),
        RestoreStepEvent(RestoreStep.validating, RestoreStepPhase.failed),
      ];
      rig.service.restoreError = const RestoreFailed(RestoreFailReason.safetyCopyFailed);
      await pumpPage(t);
      await replaceAndConfirm(t);
      expect(find.byKey(const Key('restoreProgressSheet')), findsNothing);
      expect(find.byKey(const Key('replaceConfirmError')), findsOneWidget);
    });
  });

  group('busy: the sheet cannot be dismissed', () {
    testWidgets('Replace running: Back, outside tap and swipe do nothing; it ends when the work does', (t) async {
      rig.service.restoreGate = Completer<void>();
      await pumpPage(t);
      await toMode(t);
      await tapKey(t, 'restoreOptionReplace');
      await tapKey(t, 'restoreContinue');
      await t.tap(find.byKey(const Key('restoreReplaceGo')));
      await settleBusy(t);
      await dismissAttempts(t);
      expect(find.byKey(const Key('restoreProgressSheet')), findsOneWidget);
      expect(rig.service.calls.where((c) => c.startsWith('restore')).length, 1);
      rig.service.restoreGate!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoreProgressSheet')), findsNothing);
      expect(find.byKey(const Key('restoreResultSheet')), findsOneWidget);
    });

    testWidgets('Merge running: the same', (t) async {
      rig.service.restoreGate = Completer<void>();
      await pumpPage(t);
      await toMode(t);
      await t.tap(find.byKey(const Key('restoreContinue')));
      await settleBusy(t);
      await dismissAttempts(t);
      expect(find.byKey(const Key('restoreProgressSheet')), findsOneWidget);
      rig.service.restoreGate!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoreResultSheet')), findsOneWidget);
    });

    testWidgets('Undo running: the same, and "Undoing..." is its label', (t) async {
      rig.service.undoGate = Completer<void>();
      await pumpPage(t);
      await replaceAndConfirm(t);
      await t.tap(find.byKey(const Key('restoreUndoButton')));
      await settleBusy(t);
      expect(find.text(kRestoreUndoing), findsOneWidget);
      // Undo is fed by onStep too: a slow event shows the slow line.
      expect(find.byKey(const Key('restoreSlowLine')), findsNothing);
      rig.service.onStepSink!(const RestoreStepEvent(RestoreStep.writing, RestoreStepPhase.slow));
      await t.pump();
      expect(find.byKey(const Key('restoreSlowLine')), findsOneWidget);
      await dismissAttempts(t);
      expect(find.byKey(const Key('restoreProgressSheet')), findsOneWidget);
      rig.service.undoGate!.complete();
      await t.pumpAndSettle();
      expect(text(t, 'restoreResultTitle'), kResultUndoneTitle);
    });
  });

  group('the Replace result', () {
    testWidgets('"187 entries restored." with nothing lost: no "lost" word, the usual Undo line', (t) async {
      await pumpPage(t);
      await replaceAndConfirm(t);
      expect(text(t, 'replaceRestoredLine'), '187 entries restored.');
      expect(find.byKey(const Key('showWhichButton')), findsNothing);
      expect(text(t, 'restoreResultSafetyNote'), kResultSafetyCopyNote);
    });

    testWidgets('3 lost: "187 entries restored. 3 lost.", Show which, "Entries that were lost (3)", the Undo line', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 3);
      rig.service.resultLost = SkippedSummary.of(fakeSkippedEntries(3));
      await pumpPage(t);
      await replaceAndConfirm(t);
      expect(text(t, 'replaceRestoredLine'), '187 entries restored. 3 lost.');
      expect(find.byKey(const Key('skippedRowsList')), findsNothing);
      await tapKey(t, 'showWhichButton');
      expect(find.text('Entries that were lost (3)'), findsOneWidget);
      expect(find.text('01-09-2026, Send Money'), findsOneWidget);
      expect(find.textContaining('required detail'), findsNothing, reason: 'Replace lists show no reason');
      expect(text(t, 'restoreResultSafetyNote'), 'Undo brings back everything except those 3 entries.');
      expect(find.byKey(const Key('restoreUndoButton')), findsOneWidget);
    });

    testWidgets('200 lost: 20 rows, "and 180 more not shown", the exact 200, no Show all; buttons on screen at 1.3', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 200);
      rig.service.resultLost = SkippedSummary.of(fakeSkippedEntries(200));
      await pumpPage(t, scale: 1.3, size: const Size(420, 900));
      await t.dragUntilVisible(find.byKey(const Key('restoreButton')), find.byKey(const Key('backupScroll')), const Offset(0, -300));
      await t.pumpAndSettle();
      rig.file();
      await tapKey(t, 'restoreButton');
      await t.ensureVisible(find.byKey(const Key('restoreOptionReplace')));
      await tapKey(t, 'restoreOptionReplace');
      await t.ensureVisible(find.byKey(const Key('restoreContinue')));
      await tapKey(t, 'restoreContinue');
      await t.ensureVisible(find.byKey(const Key('replaceTick')));
      await tapKey(t, 'replaceTick');
      await tapKey(t, 'replaceWarnContinue');
      await tapKey(t, 'restoreReplaceGo');
      expect(text(t, 'replaceRestoredLine'), '187 entries restored. 200 lost.');
      await tapKey(t, 'showWhichButton');
      expect(find.text('Entries that were lost (200)'), findsOneWidget);
      expect(find.text('and 180 more not shown'), findsOneWidget);
      expect(find.byKey(const Key('skippedShowAll')), findsNothing);
      final h = t.view.physicalSize.height / t.view.devicePixelRatio;
      for (final k in ['restoreUndoButton', 'restoreDoneButton']) {
        expect(t.getRect(find.byKey(Key(k))).bottom, lessThanOrEqualTo(h), reason: k);
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('Done is the default with the focus; Undo is 44 high', (t) async {
      await pumpPage(t);
      await replaceAndConfirm(t);
      expect(hasFocusKey(t, 'restoreDoneButton'), isTrue);
      expect(t.getSize(find.byKey(const Key('restoreUndoButton'))).height, greaterThanOrEqualTo(44));
    });

    for (final how in ['Done', 'Back', 'outside tap', 'swipe']) {
      testWidgets('$how closes the result as Done: no Undo, nothing else', (t) async {
        await pumpPage(t);
        await replaceAndConfirm(t);
        switch (how) {
          case 'Done':
            await t.tap(find.byKey(const Key('restoreDoneButton')));
          case 'Back':
            await t.binding.handlePopRoute();
          case 'outside tap':
            await t.tapAt(const Offset(10, 10));
          default:
            await t.fling(find.byKey(const Key('restoreResultTitle')), const Offset(0, 800), 1500);
        }
        await t.pumpAndSettle();
        expect(find.byKey(const Key('restoreResultSheet')), findsNothing);
        expect(rig.service.calls, ['inspect', 'previewReplace', 'restore:replace']);
      });
    }

    testWidgets('the settings that were restored are listed by fixed labels, never values', (t) async {
      rig.service.appliedSettings = const ['palette_id', 'first_day_of_week', 'user_display_name', 'not_a_known_key'];
      await pumpPage(t);
      await replaceAndConfirm(t);
      expect(text(t, 'restoreResultSettings'), 'Settings restored: Display name, Colour palette, First day of the week.');
      expect(find.textContaining('not_a_known_key'), findsNothing);
    });

    testWidgets('no settings applied: no settings line (CB13)', (t) async {
      await pumpPage(t);
      await toMode(t);
      await tapKey(t, 'restoreContinue'); // merge
      expect(find.byKey(const Key('restoreResultSettings')), findsNothing);
    });

    test('every fixed setting label is a plain label with no digits, name or value', () {
      for (final l in kRestoredSettingLabels.values) {
        expect(RegExp(r'\d{3,}').hasMatch(l), isFalse);
        expect(l.toLowerCase().contains('classification'), isFalse, reason: l);
      }
      expect(kRestoredSettingLabels.length, 11, reason: 'one label per allowlisted setting');
    });
  });

  group('the Undo result (A2)', () {
    Future<void> undo(WidgetTester t) async {
      await tapKey(t, 'restoreUndoButton');
    }

    testWidgets('after a Replace that lost 3: "Everything except those 3 entries is back", never "The data from before the replace is back"', (
      t,
    ) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 3);
      rig.service.resultLost = SkippedSummary.of(fakeSkippedEntries(3));
      await pumpPage(t);
      await replaceAndConfirm(t);
      await undo(t);
      expect(text(t, 'restoreResultTitle'), kResultUndoneTitle);
      expect(text(t, 'restoreResultNote'), 'Everything except those 3 entries is back. Entries added after the replace were not kept.');
      expect(find.textContaining('The data from before the replace is back'), findsNothing);
      expect(find.byKey(const Key('restoreUndoButton')), findsNothing, reason: 'the UI never offers a second Undo');
    });

    test('one lost entry reads "that entry", not "those 1 entry"', () {
      expect(resultUndoneLostNote(1), 'Everything except that entry is back. Entries added after the replace were not kept.');
      expect(resultUndoneLostNote(4), 'Everything except those 4 entries is back. Entries added after the replace were not kept.');
    });

    testWidgets('after a Replace that lost nothing: the usual "The data from before the replace is back"', (t) async {
      await pumpPage(t);
      await replaceAndConfirm(t);
      await undo(t);
      expect(text(t, 'restoreResultNote'), kResultUndoneNote);
      expect(find.byKey(const Key('restoreSafetyCopyStillThere')), findsNothing);
    });

    testWidgets('the safety copy could not be removed: the line is on screen, still no second Undo', (t) async {
      rig.service.undoStillThere = true;
      await pumpPage(t);
      await replaceAndConfirm(t);
      await undo(t);
      expect(text(t, 'restoreSafetyCopyStillThere'), kResultSafetyCopyStillThere);
      expect(find.byKey(const Key('restoreUndoButton')), findsNothing);
      expect(find.byKey(const Key('restoreDoneButton')), findsOneWidget);
    });

    testWidgets('a new Replace after an Undo uses its own lost count, not the old one', (t) async {
      rig.service.replacePreview = fakeReplacePreview(lost: 3);
      rig.service.resultLost = SkippedSummary.of(fakeSkippedEntries(3));
      await pumpPage(t);
      await replaceAndConfirm(t);
      await undo(t);
      await tapKey(t, 'restoreDoneButton');
      rig.service.replacePreview = fakeReplacePreview();
      rig.service.resultLost = SkippedSummary.empty;
      await replaceAndConfirm(t);
      await undo(t);
      expect(text(t, 'restoreResultNote'), kResultUndoneNote);
    });

    testWidgets('a failing Undo shows the one failure message and a busy Undo its own text', (t) async {
      rig.service.undoError = const RestoreFailed(RestoreFailReason.busy);
      await pumpPage(t);
      await replaceAndConfirm(t);
      await undo(t);
      expect(text(t, 'restoreFailedMessage'), 'Another change is in progress, try again');
    });
  });

  group('Home and Analytics refresh after a restore (item 6)', () {
    testWidgets('Merge, Replace and Undo each bump the shell data revision (PrimaryShell.active.dataChanged)', (t) async {
      t.view.physicalSize = const Size(420, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      // The real wiring: BackupScreen builds its own RestoreFlow around the FAKE service.
      await t.pumpWidget(
        AppPaletteScope(
          controller: AppPaletteController(),
          child: MaterialApp(home: PrimaryShell(pages: const {0: SizedBox(), 1: SizedBox(), 3: SizedBox(), 4: SizedBox()})),
        ),
      );
      await t.pumpAndSettle();
      final shell = PrimaryShell.active!;
      Navigator.of(t.element(find.byType(PrimaryShell))).push(
        MaterialPageRoute<void>(
          builder: (_) => BackupScreen(loadCounts: () async => kPageCounts, restoreService: () => rig.service),
        ),
      );
      await t.pumpAndSettle();
      final start = shell.dataRevision.value;

      rig.file();
      await tapKey(t, 'restoreButton');
      await tapKey(t, 'restoreContinue'); // merge
      expect(shell.dataRevision.value, start + 1);
      await tapKey(t, 'restoreDoneButton');

      await replaceAndConfirm(t);
      expect(shell.dataRevision.value, start + 2);
      await tapKey(t, 'restoreUndoButton');
      expect(shell.dataRevision.value, start + 3);
    });

    testWidgets('a refused restore refreshes nothing', (t) async {
      rig.service.restoreError = const RestoreFailed(RestoreFailReason.databaseError);
      await pumpPage(t);
      await toMode(t);
      await tapKey(t, 'restoreContinue');
      expect(rig.refreshes, 0);
    });
  });

  group('words on the phone side', () {
    testWidgets('no sheet from the warning to the Undo result says skipped, erase, wipe or classification', (t) async {
      rig.service.replacePreview = fakeReplacePreview(
        rows: [
          ...fakeSkippedEntries(3),
          const SkippedRowInfo(kind: SkipKind.category, reason: SkipReason.cascaded),
          const SkippedRowInfo(kind: SkipKind.savedReceiver, reason: SkipReason.notAllowed),
        ],
      );
      rig.service.resultLost = SkippedSummary.of(rig.service.replacePreview.skipped.shown);
      rig.service.undoStillThere = true;
      rig.service.appliedSettings = const ['palette_id'];
      await pumpPage(t);
      final seen = <String>[];
      void grab() => seen.addAll(sheetTexts(t));
      await toMode(t);
      await tapKey(t, 'restoreOptionReplace');
      await tapKey(t, 'restoreContinue');
      await tapKey(t, 'showWhichButton');
      grab(); // warning with the list open
      await tapKey(t, 'replaceTick');
      await tapKey(t, 'replaceWarnContinue');
      grab(); // confirm
      await tapKey(t, 'restoreReplaceGo');
      await tapKey(t, 'showWhichButton');
      grab(); // result with the list open
      await tapKey(t, 'restoreUndoButton');
      grab(); // undo result
      expect(seen, isNotEmpty);
      for (final s in seen) {
        final l = s.toLowerCase();
        for (final banned in ['skipped', 'erase', 'wipe', 'classification']) {
          expect(l.contains(banned), isFalse, reason: '"$banned" in "$s"');
        }
        // No value: no long digit run (phone, code, amount) and no money or phone pattern.
        expect(RegExp(r'\d{6,}').hasMatch(s), isFalse, reason: s);
        expect(RegExp(r'ksh|\+254', caseSensitive: false).hasMatch(s), isFalse, reason: s);
      }
    });
  });
}
