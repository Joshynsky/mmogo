// B17: the Restore flow in every state and on every path, with fakes (no
// database, no files, no platform channels): picker cancelled / too large,
// "Checking file...", every rejection reason, merge-or-replace dialog, Replace
// confirmation, result sheet, Undo, failures, cancel at each step, and the
// refresh (data screens, palette, name) after a restore.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_counts.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/backup/backup_screen.dart';
import 'package:mmogo/ui/screens/backup/restore_flow.dart';
import 'package:mmogo/ui/screens/backup/restore_messages.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_restore_service.dart';
import '../../../support/fake_storage_bridge.dart';

const _counts = BackupCounts(transactions: 60, userClassifications: 3, receivers: 7, deletedLeftOut: 4);

class _Rig {
  final service = FakeRestoreService();
  final bridge = FakeStorageBridge();
  int refreshes = 0;
  Object? refreshError;
  RestoreFlowEnd? end;

  void file() => bridge.filePicks.add(PickedFile(name: 'b.json', bytes: Uint8List.fromList([1, 2, 3])));

  RestoreFlow flow() => RestoreFlow(
    service: () => service,
    bridge: bridge,
    onDataChanged: () async {
      refreshes++;
      if (refreshError != null) throw refreshError!;
    },
  );
}

Future<void> _pump(WidgetTester t, _Rig r) async {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: BackupScreen(loadCounts: () async => _counts, restoreFlow: r.flow()),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _tapRestore(WidgetTester t) async {
  await t.tap(find.byKey(const Key('restoreButton')));
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

/// Pick a good file and reach the merge-or-replace dialog.
Future<void> _toMergeDialog(WidgetTester t, _Rig r) async {
  r.file();
  await _tapRestore(t);
  expect(find.byKey(const Key('restoreMergeDialog')), findsOneWidget);
}

Future<void> _toReplaceConfirm(WidgetTester t, _Rig r) async {
  await _toMergeDialog(t, r);
  await _tap(t, 'restoreOptionReplace');
  await _tap(t, 'restoreContinue');
  expect(find.byKey(const Key('restoreReplaceDialog')), findsOneWidget);
}

/// The text of the widget with [key]: itself when it is a Text, else its last
/// Text (the value column of a label/value row).
String _text(WidgetTester t, String key) {
  final w = t.widget(find.byKey(Key(key)));
  if (w is Text) return w.data!;
  return t.widgetList<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text))).last.data!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('button and picker', () {
    testWidgets('the Restore button is on the page and enabled even when the phone is empty', (t) async {
      final r = _Rig();
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            loadCounts: () async => const BackupCounts(transactions: 0, userClassifications: 0, receivers: 0, deletedLeftOut: 0),
            restoreFlow: r.flow(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(kRestoreButtonLabel), findsOneWidget);
      expect(t.widget<OutlinedButton>(find.byKey(const Key('restoreButton'))).onPressed, isNotNull);
    });

    testWidgets('picker_cancelled_shows_nothing_and_changes_nothing', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _tapRestore(t); // empty queue = cancelled
      expect(r.bridge.calls, ['pickFile:$kBackupMaxBytes']);
      expect(r.service.calls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(r.refreshes, 0);
    });

    testWidgets('picker asks for at most 20 MB', (t) async {
      expect(kBackupMaxBytes, 20 * 1024 * 1024);
      final r = _Rig();
      await _pump(t, r);
      await _tapRestore(t);
      expect(r.bridge.calls.single, 'pickFile:${20 * 1024 * 1024}');
    });

    testWidgets('picker reports cancelled as an error: treated as cancel', (t) async {
      final r = _Rig();
      await _pump(t, r);
      r.bridge.nextPickError = const StorageException(StorageErrorCode.cancelled);
      await _tapRestore(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(r.service.calls, isEmpty);
    });

    testWidgets('picker too large: rejection dialog with the too-large reason', (t) async {
      final r = _Rig();
      await _pump(t, r);
      r.bridge.nextPickError = const StorageException(StorageErrorCode.tooLarge);
      await _tapRestore(t);
      expect(_text(t, 'restoreRejectReason'), kRejectTooLarge);
      expect(find.text(kRestoreNothingChanged), findsOneWidget);
      expect(r.service.calls, isEmpty);
    });

    testWidgets('picker failure: the one failure message', (t) async {
      final r = _Rig();
      await _pump(t, r);
      r.bridge.nextPickError = const StorageException(StorageErrorCode.io);
      await _tapRestore(t);
      expect(_text(t, 'restoreFailedMessage'), 'Could not restore. Nothing was changed.');
    });

    testWidgets('the same Restore button is off while a restore is running', (t) async {
      final r = _Rig();
      r.service.inspectGate = Completer<void>();
      await _pump(t, r);
      r.file();
      await t.tap(find.byKey(const Key('restoreButton')));
      await t.pump();
      await t.pump();
      expect(t.widget<OutlinedButton>(find.byKey(const Key('restoreButton'))).onPressed, isNull);
      r.service.inspectGate!.complete();
      await t.pumpAndSettle();
      await _tap(t, 'restoreContinue'); // merge
      await t.tap(find.byKey(const Key('restoreDoneButton')));
      await t.pumpAndSettle();
      expect(t.widget<OutlinedButton>(find.byKey(const Key('restoreButton'))).onPressed, isNotNull);
    });
  });

  group('checking', () {
    testWidgets('Checking file... is shown while the file is checked, then goes away', (t) async {
      final r = _Rig();
      r.service.inspectGate = Completer<void>();
      await _pump(t, r);
      r.file();
      await t.tap(find.byKey(const Key('restoreButton')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('restoreProgress')), findsOneWidget);
      expect(find.text(kRestoreCheckingFile), findsOneWidget);
      expect(r.service.lastBytes, [1, 2, 3]);
      r.service.inspectGate!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoreProgress')), findsNothing);
      expect(find.byKey(const Key('restoreMergeDialog')), findsOneWidget);
    });

    testWidgets('the check itself failing shows the one failure message', (t) async {
      final r = _Rig();
      r.service.inspectError = StateError('db gone');
      await _pump(t, r);
      r.file();
      await _tapRestore(t);
      expect(_text(t, 'restoreFailedMessage'), kRestoreFailedMessage);
      expect(find.byKey(const Key('restoreProgress')), findsNothing);
    });
  });

  group('rejection dialog', () {
    const reasons = {
      RestoreRejectReason.notMmogo: kRejectNotMmogo,
      RestoreRejectReason.newer: kRejectNewer,
      RestoreRejectReason.corrupt: kRejectDamaged,
      RestoreRejectReason.tooLarge: kRejectTooLarge,
      RestoreRejectReason.tooMany: kRejectTooLarge,
    };
    for (final e in reasons.entries) {
      testWidgets('restore_rejection_messages_per_reason: ${e.key.name}', (t) async {
        final r = _Rig();
        r.service.inspectError = RestoreRejected(e.key);
        await _pump(t, r);
        r.file();
        await _tapRestore(t);
        expect(_text(t, 'restoreRejectReason'), e.value);
        expect(find.text(kRestoreNothingChanged), findsOneWidget);
        expect(find.text(kRestoreRejectTitle), findsOneWidget);
        expect(r.service.calls, ['inspect']); // never reached restore
        expect(r.refreshes, 0);
      });
    }

    testWidgets('invalid entry names the table, row and field', (t) async {
      final r = _Rig();
      r.service.inspectError = const RestoreRejected(
        RestoreRejectReason.invalidRow,
        table: 'transactions',
        rowIndex: 11,
        field: 'amount_cents',
      );
      await _pump(t, r);
      r.file();
      await _tapRestore(t);
      expect(_text(t, 'restoreRejectReason'), 'This backup has an invalid entry (transactions, row 12, amount_cents).');
    });

    testWidgets('a field or table name that came from the file is never shown', (t) async {
      final r = _Rig();
      r.service.inspectError = const RestoreRejected(
        RestoreRejectReason.invalidRow,
        table: 'evil<script>',
        rowIndex: 3,
        field: 'DROP TABLE x',
      );
      await _pump(t, r);
      r.file();
      await _tapRestore(t);
      final shown = _text(t, 'restoreRejectReason');
      expect(shown, 'This backup has an invalid entry (row 4).');
      expect(shown.contains('evil'), isFalse);
      expect(shown.contains('DROP'), isFalse);
    });

    test('reason text for dangling reference and a bare invalid entry', () {
      expect(
        restoreRejectReasonText(const RestoreRejected(RestoreRejectReason.danglingRef)),
        'This backup has an invalid entry.',
      );
      expect(
        restoreRejectReasonText(
          const RestoreRejected(RestoreRejectReason.invalidRow, table: 'counterparty_map', rowIndex: 0, field: 'classification'),
        ),
        'This backup has an invalid entry (saved receivers, row 1, classification).',
      );
    });

    testWidgets('a rejection found at restore time shows the dialog and refreshes nothing', (t) async {
      final r = _Rig();
      r.service.restoreError = const RestoreRejected(RestoreRejectReason.corrupt);
      await _pump(t, r);
      await _toMergeDialog(t, r);
      await _tap(t, 'restoreContinue');
      expect(_text(t, 'restoreRejectReason'), kRejectDamaged);
      expect(r.refreshes, 0);
    });
  });

  group('merge or replace dialog', () {
    testWidgets('merge_or_replace_dialog_shows_why_text, the counts, and Merge is preselected', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toMergeDialog(t, r);
      expect(find.text(kMergeDialogTitle), findsOneWidget);
      expect(find.byKey(const Key('restoreWhyAsks')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('restoreWhyAsks'))).textSpan!.toPlainText(), contains(kWhyRestoreAsks));
      expect(_text(t, 'restoreFileDate'), '20 Sep 2026, 10:15');
      expect(_text(t, 'restoreInFile'), '187 transactions, 2 classifications, 15 saved receivers');
      expect(_text(t, 'restoreNewHere'), '142 transactions');
      expect(_text(t, 'restoreAlreadyHere'), '45 transactions');
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    testWidgets('a file with no entries says so', (t) async {
      final r = _Rig();
      r.service.preview = fakePreview(fileTx: 0, fileCls: 0, fileMap: 0, newTx: 0, dupTx: 0);
      await _pump(t, r);
      await _toMergeDialog(t, r);
      expect(_text(t, 'restoreInFile'), kBackupHasNoEntries);
    });

    testWidgets('cancel_changes_nothing: Cancel at the merge-or-replace dialog', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toMergeDialog(t, r);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(r.service.calls, ['inspect']);
      expect(r.refreshes, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('picking Replace moves the radio and Continue then asks again', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toMergeDialog(t, r);
      await _tap(t, 'restoreOptionReplace');
      await _tap(t, 'restoreContinue');
      expect(find.byKey(const Key('restoreReplaceDialog')), findsOneWidget);
      expect(r.service.calls, ['inspect']); // nothing restored yet
    });
  });

  group('merge', () {
    testWidgets('merge restores, refreshes once, and the sheet lists counts with no Undo', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toMergeDialog(t, r);
      await _tap(t, 'restoreContinue');
      expect(r.service.calls, ['inspect', 'restore:merge']);
      expect(r.refreshes, 1);
      expect(find.byKey(const Key('restoreResultSheet')), findsOneWidget);
      expect(_text(t, 'restoreResultTitle'), kResultMergedTitle);
      // result_sheet_lists_counts
      for (final s in ['142', '45', '11', '4', 'Transactions', 'Classifications', 'Saved receivers', 'Added', 'Skipped', 'Rejected']) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      expect(find.text(kResultMergeNote), findsOneWidget);
      expect(find.byKey(const Key('restoreUndoButton')), findsNothing);
      expect(find.text(kSettingsNotApplied), findsNothing);
      await _tap(t, 'restoreDoneButton');
      expect(find.byKey(const Key('restoreResultSheet')), findsNothing);
      expect(r.service.calls, isNot(contains('undo')));
    });

    testWidgets('merge shows Restoring... while it runs', (t) async {
      final r = _Rig();
      r.service.restoreGate = Completer<void>();
      await _pump(t, r);
      await _toMergeDialog(t, r);
      await t.tap(find.byKey(const Key('restoreContinue')));
      await t.pump();
      await t.pump();
      expect(find.text(kRestoreRestoring), findsOneWidget);
      expect(r.refreshes, 0);
      r.service.restoreGate!.complete();
      await t.pumpAndSettle();
      expect(find.text(kRestoreRestoring), findsNothing);
    });

    testWidgets('the settings note appears when some settings could not be applied', (t) async {
      final r = _Rig();
      r.service.settingsOk = false;
      await _pump(t, r);
      await _toMergeDialog(t, r);
      await _tap(t, 'restoreContinue');
      expect(find.text(kSettingsNotApplied), findsOneWidget);
      expect(r.refreshes, 1); // the data restore still stands
    });

    testWidgets('a refresh that throws does not turn a good restore into an error', (t) async {
      final r = _Rig();
      r.refreshError = StateError('boom');
      await _pump(t, r);
      await _toMergeDialog(t, r);
      await _tap(t, 'restoreContinue');
      expect(find.byKey(const Key('restoreResultSheet')), findsOneWidget);
      expect(find.byKey(const Key('restoreFailedDialog')), findsNothing);
    });
  });

  group('replace', () {
    testWidgets('replace_requires_second_confirm_with_counts', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      expect(r.service.calls, ['inspect']);
      expect(find.text(kReplaceConfirmTitle), findsOneWidget);
      // 60 live + 4 recently deleted = 64 transactions removed.
      expect(
        _text(t, 'restoreReplaceRemoves'),
        'Replace will remove 64 transactions, 3 classifications and 7 saved receivers from this phone, '
        "including recently deleted ones, and put the file's data in. "
        'A safety copy of the current data is saved first so you can undo.',
      );
      expect(_text(t, 'restoreReplacePhone'), '60 transactions, 3 classifications, 7 saved receivers');
      expect(_text(t, 'restoreReplaceFile'), '187 transactions, 2 classifications, 15 saved receivers');
      expect(find.text(kReplaceConfirmButton), findsOneWidget);
    });

    testWidgets('the confirmation says Undo is not exact', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      final shown = _text(t, 'restoreUndoNotExact');
      expect(shown, kUndoNotExactNotice);
      expect(shown, contains('Recently deleted entries are gone for good'));
      expect(shown, contains('Entries you add after Replacing are lost if you Undo'));
      expect(shown, contains('A setting that was not set before keeps the value Replace gave it'));
    });

    testWidgets('an empty file gets a strong note on the confirmation', (t) async {
      final r = _Rig();
      r.service.preview = fakePreview(fileTx: 0, fileCls: 0, fileMap: 0, newTx: 0, dupTx: 0);
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      expect(find.byKey(const Key('restoreReplaceEmptyNote')), findsOneWidget);
    });

    testWidgets('cancel at the Replace confirmation changes nothing', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(r.service.calls, ['inspect']);
      expect(r.refreshes, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirmed Replace shows the safety-copy progress, then the sheet with Undo', (t) async {
      final r = _Rig();
      r.service.restoreGate = Completer<void>();
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      await t.tap(find.byKey(const Key('restoreReplaceGo')));
      await t.pump();
      await t.pump();
      expect(find.text(kRestoreReplacing), findsOneWidget);
      r.service.restoreGate!.complete();
      await t.pumpAndSettle();
      expect(r.service.calls, ['inspect', 'restore:replace']);
      expect(_text(t, 'restoreResultTitle'), kResultReplacedTitle);
      expect(find.text(kResultReplaceNote), findsOneWidget);
      expect(find.byKey(const Key('restoreResultSafetyNote')), findsOneWidget);
      expect(find.byKey(const Key('restoreUndoButton')), findsOneWidget);
      expect(r.refreshes, 1);
    });

    testWidgets('Replace refused for an incomplete safety copy shows the Use Merge line', (t) async {
      final r = _Rig();
      r.service.restoreError = const RestoreFailed(RestoreFailReason.safetyCopyIncomplete);
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      await _tap(t, 'restoreReplaceGo');
      expect(_text(t, 'restoreFailedMessage'), kReplaceNeedsCompleteCopy);
      expect(
        kReplaceNeedsCompleteCopy,
        'Replace needs a complete safety copy and some entries cannot be saved in it. Use Merge instead.',
      );
      expect(r.refreshes, 0);
    });

    testWidgets('undo_after_replace restores the previous data and refreshes again', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      await _tap(t, 'restoreReplaceGo');
      await _tap(t, 'restoreUndoButton');
      expect(r.service.calls, ['inspect', 'restore:replace', 'undo']);
      expect(r.refreshes, 2);
      expect(_text(t, 'restoreResultTitle'), kResultUndoneTitle);
      expect(find.byKey(const Key('restoreUndoButton')), findsNothing); // Undo disappears
      await _tap(t, 'restoreDoneButton');
      expect(find.byKey(const Key('restoreResultSheet')), findsNothing);
    });

    testWidgets('Done on the Replace sheet keeps the replaced data (no undo call)', (t) async {
      final r = _Rig();
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      await _tap(t, 'restoreReplaceGo');
      await _tap(t, 'restoreDoneButton');
      expect(r.service.calls, ['inspect', 'restore:replace']);
    });

    testWidgets('a failing Undo shows the one failure message', (t) async {
      final r = _Rig();
      r.service.undoError = const RestoreFailed(RestoreFailReason.noSafetyCopy);
      await _pump(t, r);
      await _toReplaceConfirm(t, r);
      await _tap(t, 'restoreReplaceGo');
      await _tap(t, 'restoreUndoButton');
      expect(_text(t, 'restoreFailedMessage'), kRestoreFailedMessage);
      expect(r.refreshes, 1);
    });
  });

  group('failures', () {
    for (final reason in [
      RestoreFailReason.databaseError,
      RestoreFailReason.safetyCopyFailed,
      RestoreFailReason.dataChangedMeanwhile,
      RestoreFailReason.schemaTooOld,
    ]) {
      testWidgets('could_not_restore_nothing_changed for ${reason.name}', (t) async {
        final r = _Rig();
        r.service.restoreError = RestoreFailed(reason, StateError('secret detail'));
        await _pump(t, r);
        await _toMergeDialog(t, r);
        await _tap(t, 'restoreContinue');
        expect(find.text(kRestoreFailedTitle), findsOneWidget);
        expect(_text(t, 'restoreFailedMessage'), 'Could not restore. Nothing was changed.');
        expect(find.textContaining('secret'), findsNothing);
        expect(find.byKey(const Key('restoreResultSheet')), findsNothing);
        expect(r.refreshes, 0);
      });
    }

    testWidgets('an unexpected error at restore time is the same message', (t) async {
      final r = _Rig();
      r.service.restoreError = StateError('x');
      await _pump(t, r);
      await _toMergeDialog(t, r);
      await _tap(t, 'restoreContinue');
      expect(_text(t, 'restoreFailedMessage'), kRestoreFailedMessage);
      expect(r.refreshes, 0);
    });

    test('the copy constants match the service message', () {
      expect(kRestoreFailedMessage, RestoreFailed.userMessage);
    });
  });

  group('refresh after restore (default flow wiring)', () {
    testWidgets('the saved palette and name are applied live, without a restart', (t) async {
      SharedPreferences.setMockInitialValues({AppPrefs.keyPaletteId: 'leaf'});
      final service = FakeRestoreService();
      final bridge = FakeStorageBridge()..filePicks.add(PickedFile(name: 'b.json', bytes: Uint8List.fromList([1])));
      StorageBridge.instance = bridge;
      final controller = AppPaletteController(); // ocean until the restore says otherwise
      final nameRevision = AppPrefs.userDisplayNameRevision.value;
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        AppPaletteScope(
          controller: controller,
          child: MaterialApp(
            home: BackupScreen(loadCounts: () async => _counts, restoreService: () => service),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(controller.value, 'ocean');
      await _tapRestore(t);
      await _tap(t, 'restoreContinue');
      expect(controller.value, 'leaf');
      expect(AppPrefs.userDisplayNameRevision.value, greaterThan(nameRevision));
      expect(find.byKey(const Key('restoreResultSheet')), findsOneWidget);
    });
  });
}
