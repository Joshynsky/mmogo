// 0.1.2 S9b-2: running Delete data and every result (DD2 + CB6 + addendum
// A3, A5, A9). FAKE service, FAKE restart: no real delete, no real reset.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/data/maintenance/reset_resume.dart';
import 'package:mmogo/main.dart';
import 'package:mmogo/ui/copy/delete_data_copy.dart';
import 'package:mmogo/ui/restart_scope.dart';
import 'package:mmogo/ui/screens/welcome_screen.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/startup_notice.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/error_notes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/delete_data_harness.dart';
import '../../../support/fake_delete_data.dart';

const _notFinished = DeleteDataResult(outcome: DeleteDataOutcome.notFinished, failedStep: DeleteDataStep.safetyCopy);

/// Opens the sheet, types the word, chooses [reset] or not, and taps through.
Future<void> _runIt(WidgetTester tester, {bool reset = false}) async {
  await openDeleteSheet(tester);
  if (reset) {
    await tester.ensureVisible(find.byKey(const Key('deleteLevel2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('deleteLevel2')));
  }
  await typeWord(tester, 'delete');
  await tapGo(tester);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (reset) {
    // The confirm sheet: wait out the arming delay, then the red button.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const Key('resetConfirmGo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('busy state', () {
    for (final reset in [false, true]) {
      for (final path in ['back', 'outside', 'swipe']) {
        testWidgets('${reset ? 'Reset app' : 'Level 1'}: $path while running does nothing, the run is not repeated', (tester) async {
          final fake = useFakeDeleteData()..hold = Completer<void>();
          await pumpSettings(tester, fake, restart: FakeRestart());
          await _runIt(tester, reset: reset);
          expect(find.byKey(const Key('deleteBusy')), findsOneWidget);
          expect(find.text(reset ? kDeleteBusyLevel2 : kDeleteBusyLevel1), findsOneWidget);
          switch (path) {
            case 'back':
              await tester.binding.handlePopRoute();
            case 'outside':
              await tester.tapAt(const Offset(200, 10));
            case 'swipe':
              await tester.fling(find.byKey(const Key('deleteBusy')), const Offset(0, 800), 3000);
          }
          // A popped route starts leaving on the NEXT frame and is gone ~300 ms later.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byKey(const Key('deleteBusy')), findsOneWidget, reason: '$path must not close the busy sheet');
          expect(fake.deleteCalls + fake.resetCalls, 1, reason: 'one run only');
          fake.hold!.complete();
          await tester.pump(const Duration(milliseconds: 400));
        });
      }
    }
  });

  group('Level 1 results', () {
    testWidgets('done: the result says deleted from this phone, what stays, and Done closes it; the row asks again', (tester) async {
      final fake = useFakeDeleteData();
      await pumpSettings(tester, fake);
      final peeksBefore = fake.peekCalls;
      await _runIt(tester);
      await tester.pumpAndSettle();
      expect(fake.deleteCalls, 1);
      expect(fake.resetCalls, 0);
      expect(find.text(kDeleteDoneTitle), findsOneWidget);
      expect(kDeleteDoneTitle, contains('deleted from this phone'));
      for (final line in [
        kDeleteStayBackups,
        kDeleteStayAutoList,
        kDeleteStaySms,
        kDeleteLevel1SafetyGone,
        kDeleteLevel1CategoriesStay,
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(primaryFocusIsIn(const Key('deleteDoneButton')), isTrue, reason: 'focus starts on Done');
      expect(tester.getSize(find.byKey(const Key('deleteDoneButton'))).height, greaterThanOrEqualTo(44));
      fake.peekValue = kFakePeekLevel1Empty;
      await tester.tap(find.byKey(const Key('deleteDoneButton')));
      await tester.pumpAndSettle();
      expect(find.text(kDeleteDoneTitle), findsNothing);
      expect(fake.peekCalls, greaterThan(peeksBefore), reason: 'the subtitle is read again');
      expect(find.text(kDeleteRowSubtitleLevel1Done), findsOneWidget);
    });

    testWidgets('nothingWasDeleted: "Nothing was deleted" with Done only', (tester) async {
      final fake = useFakeDeleteData(FakeDeleteDataService()..level1Results = [const DeleteDataResult(outcome: DeleteDataOutcome.nothingWasDeleted)]);
      await pumpSettings(tester, fake);
      await _runIt(tester);
      await tester.pumpAndSettle();
      expect(find.text(kDeleteNothingDeletedTitle), findsOneWidget);
      expect(find.byKey(const Key('deleteTryAgain')), findsNothing);
      await tester.tap(find.byKey(const Key('deleteDoneButton')));
      await tester.pumpAndSettle();
      expect(find.text(kDeleteNothingDeletedTitle), findsNothing);
    });

    testWidgets('notFinished: the plain wording only, in an error box; Try again re-calls the SAME method', (tester) async {
      final fake = useFakeDeleteData(FakeDeleteDataService()..level1Results = [_notFinished, kFakeDone]);
      await pumpSettings(tester, fake);
      await _runIt(tester);
      await tester.pumpAndSettle();
      expect(find.text(kDeleteDataNotFinished), findsOneWidget);
      expect(find.byType(ErrorBox), findsOneWidget, reason: 'error pattern A');
      expect(find.text(kDeleteLevel2NotFinishedExtra), findsNothing, reason: 'Level 1 never claims an undo or a later finish');
      expect(tester.getSize(find.byKey(const Key('deleteTryAgain'))).height, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const Key('deleteTryAgain')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(fake.deleteCalls, 2, reason: 'the same method again');
      expect(fake.resetCalls, 0);
      expect(find.text(kDeleteDoneTitle), findsOneWidget);
    });

    testWidgets('busy: "Another change is in progress, try again" with Try again', (tester) async {
      final fake = useFakeDeleteData(
        FakeDeleteDataService()..level1Results = [const DeleteDataResult(outcome: DeleteDataOutcome.busy), kFakeDone],
      );
      await pumpSettings(tester, fake);
      await _runIt(tester);
      await tester.pumpAndSettle();
      expect(find.text(kDataOpBusy), findsOneWidget);
      await tester.tap(find.byKey(const Key('deleteTryAgain')));
      await tester.pumpAndSettle();
      expect(fake.deleteCalls, 2);
      expect(find.text(kDeleteDoneTitle), findsOneWidget);
    });
  });

  group('Level 2 results', () {
    testWidgets('done: restart is called ONCE with the host context, resetApp once, deleteMyTransactions never; the sheet is left alone', (tester) async {
      final fake = useFakeDeleteData();
      final restart = FakeRestart();
      await pumpSettings(tester, fake, restart: restart);
      await _runIt(tester, reset: true);
      expect(fake.resetCalls, 1);
      expect(fake.deleteCalls, 0);
      expect(restart.calls, 1);
      // A9: after the restart answer the sheet does not pop or change itself.
      expect(find.byKey(const Key('deleteBusy')), findsOneWidget);
      expect(find.text(kDeleteResetDoneReopen), findsNothing);
    });

    testWidgets('done but no RestartScope (restart answers false): "Reset is done. Close mmogo and open it again."', (tester) async {
      final fake = useFakeDeleteData();
      final restart = FakeRestart(answer: false);
      await pumpSettings(tester, fake, restart: restart);
      await _runIt(tester, reset: true);
      await tester.pumpAndSettle();
      expect(restart.calls, 1);
      expect(find.text(kDeleteResetDoneReopen), findsOneWidget);
      await tester.tap(find.byKey(const Key('deleteDoneButton')));
      await tester.pumpAndSettle();
      expect(find.text(kDeleteResetDoneReopen), findsNothing);
    });

    testWidgets('notFinished: the plain wording PLUS the next-launch line; Try again calls resetApp again, not the Level 1 method', (tester) async {
      final fake = useFakeDeleteData(FakeDeleteDataService()..resetResults = [_notFinished, kFakeDone]);
      final restart = FakeRestart();
      await pumpSettings(tester, fake, restart: restart);
      await _runIt(tester, reset: true);
      await tester.pumpAndSettle();
      expect(find.text(kDeleteDataNotFinished), findsOneWidget);
      expect(find.text(kDeleteLevel2NotFinishedExtra), findsOneWidget);
      expect(restart.calls, 0, reason: 'no restart after a failed reset');
      await tester.tap(find.byKey(const Key('deleteTryAgain')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(fake.resetCalls, 2);
      expect(fake.deleteCalls, 0);
      expect(restart.calls, 1, reason: 'now it finished: the restart runs');
    });

    testWidgets('1.3 text scale and dark: the failure result fits and its buttons are 44 px', (tester) async {
      final fake = useFakeDeleteData(FakeDeleteDataService()..resetResults = [_notFinished]);
      await pumpSettings(tester, fake, restart: FakeRestart(), scale: 1.3, dark: true, size: const Size(400, 800));
      await _runIt(tester, reset: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final k in ['deleteTryAgain', 'deleteDoneButton']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
    });
  });

  group('the start-up notice (A4)', () {
    setUp(() {
      StartupNotice.resetForTest();
      addTearDown(() {
        StartupNotice.resetForTest();
        ResetResume.lastOutcome = ResetResumeOutcome.nothingPending;
      });
    });

    Future<AppPaletteController> pumpApp(WidgetTester tester) async {
      welcomeFirstFramePresented = waitForFrameBuilt;
      addTearDown(() => welcomeFirstFramePresented = waitForFirstFramePresented);
      final c = AppPaletteController();
      await tester.pumpWidget(RestartScope(controller: c, builder: (c) => MpesaTrackerApp(controller: c)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return c;
    }

    testWidgets('a start-up reset that did not finish shows the notice once; two restarts add none', (tester) async {
      ResetResume.lastOutcome = ResetResumeOutcome.notFinished;
      await pumpApp(tester);
      expect(find.byKey(const Key('startupNotice')), findsOneWidget);
      expect(find.text(kDeleteDataNotFinished), findsOneWidget);
      // The messenger key survives a restart (GlobalKey), so the shown notice is
      // dismissed first: whatever appears after is a NEW notice.
      appMessengerKey.currentState!.hideCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startupNotice')), findsNothing);
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() async {
          expect(await RestartScope.restart(tester.element(find.byType(WelcomeScreen))), isTrue);
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('startupNotice')), findsNothing, reason: 'restart ${i + 1}: no second notice');
      }
    });

    for (final o in [ResetResumeOutcome.completed, ResetResumeOutcome.flagUnreadable, ResetResumeOutcome.nothingPending]) {
      testWidgets('${o.name} shows nothing', (tester) async {
        ResetResume.lastOutcome = o;
        await pumpApp(tester);
        expect(find.byKey(const Key('startupNotice')), findsNothing);
      });
    }
  });
}
