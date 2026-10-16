// 0.1.2 S10b (LF1, A4b, CB9, A11): the ONE sheet for leftover automatic backup
// files and the old-folder question, the toasts, the cancel paths, switch-off,
// the busy state. The auto-backup service is the real class on a
// FakeStorageBridge with mock prefs (useFakeBackupUi): no real folder, prefs or
// file. Invented names and dates only.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_leftovers.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/delete_data_copy.dart';
import 'package:mmogo/ui/screens/backup/auto_backup_card.dart';
import 'package:mmogo/ui/screens/backup/auto_backup_flow.dart';
import 'package:mmogo/ui/screens/backup/auto_backup_state.dart';
import 'package:mmogo/ui/screens/backup/leftover_dialog.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/backup_page_harness.dart';
import '../../../support/fake_backup_ui.dart';
import '../../../support/fake_delete_data.dart';

const _old = 'content://tree/old';
const _new = 'content://tree/new';
const _newFolder = PickedFolder(uri: _new, name: 'Fresh folder');

const _a1 = 'mmogo-auto-20260901-101500.json';
const _a2 = 'mmogo-auto-20260903-081000.json';
const _a3 = 'mmogo-auto-20260902-090000.json';
const _manual = 'mmogo-backup-20260901-101500.json';
const _notes = 'notes.txt';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

late FakeBackupUi ui;
final uris = <String, String>{};

/// The page with auto-backup working in the old folder, which holds [names].
Future<void> pumpWith(
  WidgetTester t,
  List<String> names, {
  double scale = 1.0,
  bool dark = false,
  Size size = const Size(420, 3200),
}) async {
  SharedPreferences.setMockInitialValues({
    'auto_backup_enabled': true,
    'auto_backup_folder_uri': _old,
    'auto_backup_folder_name': 'Old folder',
    'auto_backup_every_n': 10,
    'auto_backup_keep_k': 5,
  });
  ui.bridge.folders[_old] = {};
  ui.bridge.folders[_new] = {};
  uris.clear();
  for (final n in names) {
    uris[n] = ui.bridge.seed(_old, n, _b('x'));
  }
  ui.bridge.calls.clear();
  await pumpBackupPage(t, scale: scale, dark: dark, size: size);
}

/// Folder row, setup sheet, picker, cloud notice, "Use this folder".
Future<void> chooseNewFolder(WidgetTester t) async {
  ui.bridge.folderPicks.add(_newFolder);
  await tapKey(t, 'autoBackupFolderRow');
  await tapKey(t, 'setupChooseFolder');
  await tapKey(t, 'cloudUseFolder');
}

List<String> get deletes => ui.bridge.calls.where((c) => c.startsWith('deleteFile')).toList();
List<String> get releases => ui.bridge.calls.where((c) => c.startsWith('releaseGrant')).toList();

Iterable<String> sheetTexts(WidgetTester t) =>
    t.widgetList<Text>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Text))).map((w) => w.data ?? '');

void main() {
  setUp(() {
    useFakeDeleteData();
    ui = useFakeBackupUi();
  });

  group('the one sheet', () {
    testWidgets('shows the count and the date range (dd-mm-yyyy) and never a file name, URI or folder name', (t) async {
      await pumpWith(t, [_a1, _a2, _a3, _manual, _notes]);
      await chooseNewFolder(t);
      expect(find.text(kLeftoverTitle), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('leftoverBody'))).data,
        'We found 3 automatic backup files from 01-09-2026 to 03-09-2026 in the old folder. '
        'Keep them, or delete them? Your own manual backups are never touched.',
      );
      for (final s in sheetTexts(t)) {
        if (s == kLeftoverCountedNote) continue;
        expect(s.contains('mmogo-'), isFalse, reason: s);
        expect(s.contains('.json'), isFalse, reason: s);
        expect(s.contains('content://'), isFalse, reason: s);
        expect(s.contains('Old folder'), isFalse, reason: s);
        expect(s.contains('Fresh folder'), isFalse, reason: s);
        expect(s.contains('notes'), isFalse, reason: s);
      }
    });

    testWidgets('the old-folder question is on the SAME sheet, with its explanation, before Continue (A4)', (t) async {
      await pumpWith(t, [_a1, _a2, _a3]);
      await chooseNewFolder(t);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'one sheet, no second dialog');
      expect(
        t.widget<Text>(find.byKey(const Key('oldFolderBody'))).data,
        'mmogo now saves backups in the new folder only. If you stop using the old one, mmogo gives up '
        'its permission to it. Files in it stay where they are.',
      );
      expect(find.text(kStopUsingIt), findsOneWidget);
      expect(find.text(kKeepAccess), findsOneWidget);
      expect(find.text(kOldFolderTitle), findsOneWidget);
      // The explanation sits ABOVE the Continue button.
      expect(
        t.getTopLeft(find.byKey(const Key('oldFolderBody'))).dy,
        lessThan(t.getTopLeft(find.byKey(const Key('leftoverContinue'))).dy),
      );
    });

    testWidgets('defaults: Keep is chosen, "Stop using it" is chosen AND has the initial focus (CB9)', (t) async {
      final h = t.ensureSemantics();
      await pumpWith(t, [_a1, _a2, _a3]);
      await chooseNewFolder(t);
      expect(hasFocusKey(t, 'grantRelease'), isTrue, reason: 'initial focus on "Stop using it"');
      final keep = t.getSemantics(find.byKey(const Key('leftoverKeep')));
      final del = t.getSemantics(find.byKey(const Key('leftoverDelete')));
      expect(keep.flagsCollection.isChecked.name, 'isTrue');
      expect(del.flagsCollection.isChecked.name, 'isFalse');
      expect(keep.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(t.getSemantics(find.byKey(const Key('grantRelease'))).flagsCollection.isSelected.name, 'isTrue');
      expect(t.getSemantics(find.byKey(const Key('grantKeep'))).flagsCollection.isSelected.name, 'isFalse');
      expect(find.descendant(of: find.byKey(const Key('leftoverContinue')), matching: find.text('Keep 3 files')), findsOneWidget);
      h.dispose();
    });

    testWidgets('Delete needs the explicit choice: the button turns red and says how many', (t) async {
      await pumpWith(t, [_a1, _a2, _a3]);
      await chooseNewFolder(t);
      FilledButton btn() => t.widget<FilledButton>(find.byKey(const Key('leftoverContinue')));
      final p = AppPalette.light;
      expect(btn().style!.backgroundColor!.resolve({}), p.primary);
      await tapKey(t, 'leftoverDelete');
      expect(find.descendant(of: find.byKey(const Key('leftoverContinue')), matching: find.text('Delete 3 files')), findsOneWidget);
      expect(btn().style!.backgroundColor!.resolve({}), p.diffUp);
      await tapKey(t, 'leftoverKeep');
      expect(find.descendant(of: find.byKey(const Key('leftoverContinue')), matching: find.text('Keep 3 files')), findsOneWidget);
      expect(btn().style!.backgroundColor!.resolve({}), p.primary);
    });

    for (final dark in [false, true]) {
      testWidgets('the red Delete button has 4.5:1 text contrast (${dark ? 'dark' : 'light'})', (t) async {
        await pumpWith(t, [_a1, _a2, _a3], dark: dark);
        await chooseNewFolder(t);
        await tapKey(t, 'leftoverDelete');
        final style = t.widget<FilledButton>(find.byKey(const Key('leftoverContinue'))).style!;
        expect(contrastRatio(style.backgroundColor!.resolve({})!, style.foregroundColor!.resolve({})!), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('every control is at least 44 high and nothing clips at text scale 1.3', (t) async {
      await pumpWith(t, [_a1, _a2, _a3], scale: 1.3, size: const Size(420, 900));
      await t.dragUntilVisible(find.byKey(const Key('autoBackupFolderRow')), find.byKey(const Key('backupScroll')), const Offset(0, -200));
      await t.pumpAndSettle();
      await chooseNewFolder(t);
      expect(t.takeException(), isNull);
      for (final k in ['leftoverKeep', 'leftoverDelete', 'grantRelease', 'grantKeep', 'leftoverContinue']) {
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
      final h = t.view.physicalSize.height / t.view.devicePixelRatio;
      expect(t.getRect(find.byKey(const Key('leftoverContinue'))).bottom, lessThanOrEqualTo(h), reason: 'Continue is pinned on screen');
    });
  });

  group('the decision', () {
    testWidgets('Continue with the defaults: files kept, old permission released, folder changed, "Kept 3 files."', (t) async {
      await pumpWith(t, [_a1, _a2, _a3, _manual]);
      await chooseNewFolder(t);
      await tapKey(t, 'leftoverContinue');
      expect(deletes, isEmpty);
      expect(releases, ['releaseGrant:$_old']);
      expect(await BackupPrefs.readFolderUri(), _new);
      expect(find.text('Kept 3 files.'), findsOneWidget);
      // The "Auto-backup is on" toast follows the leftover toast.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text(autoBackupIsOnToast(10)), findsOneWidget);
    });

    testWidgets('Delete 3 files: only the three mmogo-auto files go; "Deleted 3 files."', (t) async {
      await pumpWith(t, [_a1, _a2, _a3, _manual, _notes]);
      await chooseNewFolder(t);
      await tapKey(t, 'leftoverDelete');
      await tapKey(t, 'leftoverContinue');
      expect(deletes.length, 3);
      for (final n in [_manual, _notes]) {
        expect(deletes, isNot(contains('deleteFile:${uris[n]}')));
      }
      expect(find.text('Deleted 3 files.'), findsOneWidget);
      expect(await BackupPrefs.readFolderUri(), _new);
    });

    testWidgets('one file: "Kept 1 file." and "Deleted 1 file." (singular)', (t) async {
      await pumpWith(t, [_a1]);
      await chooseNewFolder(t);
      expect(find.descendant(of: find.byKey(const Key('leftoverContinue')), matching: find.text('Keep 1 file')), findsOneWidget);
      expect(find.text('Keep it'), findsOneWidget);
      await tapKey(t, 'leftoverContinue');
      expect(find.text('Kept 1 file.'), findsOneWidget);
      expect(keptToast(1), 'Kept 1 file.');
      expect(deletedToast(1), 'Deleted 1 file.');
    });

    testWidgets('one of three cannot be deleted: "Deleted 2. 1 could not be deleted."', (t) async {
      await pumpWith(t, [_a1, _a2, _a3]);
      ui.bridge.failDeleteFor.add(uris[_a2]!);
      await chooseNewFolder(t);
      await tapKey(t, 'leftoverDelete');
      await tapKey(t, 'leftoverContinue');
      expect(find.text('Deleted 2. 1 could not be deleted.'), findsOneWidget);
    });

    testWidgets('none can be deleted: "Deleted 0. 3 could not be deleted." (also when D is 0)', (t) async {
      await pumpWith(t, [_a1, _a2, _a3]);
      ui.bridge.failDeleteFor.addAll([for (final n in [_a1, _a2, _a3]) uris[n]!]);
      await chooseNewFolder(t);
      await tapKey(t, 'leftoverDelete');
      await tapKey(t, 'leftoverContinue');
      expect(find.text('Deleted 0. 3 could not be deleted.'), findsOneWidget);
    });

    testWidgets('Keep access: the old permission is NOT released', (t) async {
      await pumpWith(t, [_a1, _a2, _a3]);
      await chooseNewFolder(t);
      await tapKey(t, 'grantKeep');
      await tapKey(t, 'leftoverContinue');
      expect(releases, isEmpty);
      expect(await BackupPrefs.readFolderUri(), _new);
      expect(find.text('Kept 3 files.'), findsOneWidget);
    });

    for (final how in ['outside tap', 'Back', 'swipe']) {
      testWidgets('$how on the sheet = cancel: files kept, permission kept, and the folder change CONTINUES', (t) async {
        await pumpWith(t, [_a1, _a2, _a3]);
        await chooseNewFolder(t);
        switch (how) {
          case 'outside tap':
            await t.tapAt(const Offset(10, 10));
          case 'Back':
            await t.binding.handlePopRoute();
          default:
            await t.fling(find.byKey(const Key('backupSheetTitle')), const Offset(0, 800), 1500);
        }
        await t.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(deletes, isEmpty);
        expect(releases, isEmpty);
        expect(await BackupPrefs.readFolderUri(), _new, reason: 'the change still happened');
        expect(await BackupPrefs.readEnabled(), isTrue);
      });
    }

    testWidgets('the cancel decision is keep + keepAccess (the service default)', (t) async {
      expect(LeftoverDecision.cancel.leftover, LeftoverChoice.keep);
      expect(LeftoverDecision.cancel.grant, GrantChoice.keepAccess);
    });

    testWidgets('no automatic files in the old folder: only the old-folder question, "Stop using it" is the default', (t) async {
      await pumpWith(t, [_manual, _notes]);
      await chooseNewFolder(t);
      expect(find.text(kOldFolderTitle), findsOneWidget);
      expect(find.byKey(const Key('leftoverKeep')), findsNothing);
      expect(find.byKey(const Key('leftoverDelete')), findsNothing);
      expect(hasFocusKey(t, 'grantRelease'), isTrue);
      expect(find.descendant(of: find.byKey(const Key('leftoverContinue')), matching: find.text('Continue')), findsOneWidget);
      await tapKey(t, 'leftoverContinue');
      expect(releases, ['releaseGrant:$_old']);
      expect(deletes, isEmpty);
      expect(await BackupPrefs.readFolderUri(), _new);
      expect(find.textContaining('Kept'), findsNothing, reason: 'nothing was kept or deleted, so no toast about files');
    });

    testWidgets('the old folder cannot be listed (permission lost): no sheet, quiet switch, no files toast', (t) async {
      await pumpWith(t, [_a1, _a2]);
      ui.bridge.revokeGrant(_old);
      await chooseNewFolder(t);
      expect(find.byType(BottomSheet), findsNothing);
      expect(await BackupPrefs.readFolderUri(), _new);
      expect(find.textContaining('Kept'), findsNothing);
      expect(find.textContaining('Deleted'), findsNothing);
    });

    testWidgets('the SAME folder again asks nothing and deletes nothing', (t) async {
      await pumpWith(t, [_a1, _a2]);
      ui.bridge.folderPicks.add(const PickedFolder(uri: _old, name: 'Old folder'));
      await tapKey(t, 'autoBackupFolderRow');
      await tapKey(t, 'setupChooseFolder');
      await tapKey(t, 'cloudUseFolder');
      expect(find.byType(BottomSheet), findsNothing);
      expect(deletes, isEmpty);
      expect(releases, isEmpty);
    });
  });

  group('switch-off', () {
    testWidgets('asks the leftover question ONLY (no old-folder question); the focus starts on Continue', (t) async {
      await pumpWith(t, [_a1, _a2, _a3]);
      await tapKey(t, 'autoBackupSwitch');
      expect(find.text(kLeftoverTitle), findsOneWidget);
      expect(find.byKey(const Key('oldFolderBody')), findsNothing);
      expect(find.byKey(const Key('grantRelease')), findsNothing);
      expect(find.text(kOldFolderTitle), findsNothing);
      expect(hasFocusKey(t, 'leftoverContinue'), isTrue);
      await tapKey(t, 'leftoverContinue');
      expect(find.text('Kept 3 files.'), findsOneWidget);
      expect(deletes, isEmpty);
      expect(await BackupPrefs.readEnabled(), isFalse);
      expect(releases, ['releaseGrant:$_old'], reason: 'the grant is released as today');
    });

    testWidgets('Delete 3 files on switch-off', (t) async {
      await pumpWith(t, [_a1, _a2, _a3, _manual]);
      await tapKey(t, 'autoBackupSwitch');
      await tapKey(t, 'leftoverDelete');
      await tapKey(t, 'leftoverContinue');
      expect(deletes.length, 3);
      expect(find.text('Deleted 3 files.'), findsOneWidget);
      expect(await BackupPrefs.readEnabled(), isFalse);
    });

    testWidgets('Back on switch-off = keep, and it is still switched off', (t) async {
      await pumpWith(t, [_a1, _a2]);
      await tapKey(t, 'autoBackupSwitch');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(deletes, isEmpty);
      expect(await BackupPrefs.readEnabled(), isFalse);
      expect(await BackupPrefs.readFolderUri(), isNull);
    });

    testWidgets('no automatic files: switched off at once, no sheet, no toast', (t) async {
      await pumpWith(t, [_manual]);
      await tapKey(t, 'autoBackupSwitch');
      expect(find.byType(BottomSheet), findsNothing);
      expect(await BackupPrefs.readEnabled(), isFalse);
      expect(find.textContaining('Kept'), findsNothing);
    });
  });

  group('busy', () {
    testWidgets('while it runs after the decision: a non-dismissible "Working..." shows and the card ignores taps', (t) async {
      await pumpWith(t, [_a1, _a2]);
      await chooseNewFolder(t);
      await tapKey(t, 'leftoverDelete');
      ui.bridge.hangOn.add('deleteFile'); // the provider does not answer
      await t.tap(find.byKey(const Key('leftoverContinue')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('folderWorking')), findsOneWidget);
      expect(find.text(kFolderWorking), findsWidgets);
      // Back, outside tap and swipe do not close it.
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 400));
      await t.tapAt(const Offset(10, 10));
      await t.pump(const Duration(milliseconds: 400));
      await t.fling(find.byKey(const Key('folderWorking')), const Offset(0, 800), 1500);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('folderWorking')), findsOneWidget);
      // The switch ignores taps (no second sheet, still on).
      await t.tap(find.byKey(const Key('autoBackupSwitch')), warnIfMissed: false);
      await t.pump();
      expect(find.text(kLeftoverTitle), findsNothing);
      // The 30 s bridge timeout ends the hung delete; then everything settles.
      await t.pump(const Duration(seconds: 31));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('folderWorking')), findsNothing);
    });

    testWidgets('another data change holds the service: "Another change is in progress", nothing changed', (t) async {
      await pumpWith(t, [_a1, _a2]);
      await ui.auto.quiesce(); // as Delete data does
      await chooseNewFolder(t);
      await tapKey(t, 'leftoverContinue');
      expect(find.text(kDataOpBusy), findsOneWidget);
      expect(await BackupPrefs.readFolderUri(), _old);
      expect(deletes, isEmpty);
      // The "Auto-backup is on" toast would queue behind the busy one: let the first go, then look.
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.textContaining('Auto-backup is on'), findsNothing);
      expect(find.textContaining('Could not save the folder choice'), findsNothing, reason: 'busy says only that it is busy');
      ui.auto.resume();
    });

    testWidgets('the card (switch, folder row, Choose folder) ignores taps while a folder change runs', (t) async {
      var toggles = 0, folders = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoBackupCard(
                palette: AppPalette.light,
                state: const AutoBackupState(enabled: true, folderUri: _old, folderName: 'Old folder'),
                onToggle: (_) => toggles++,
                onChooseFolder: () => folders++,
                onEveryN: (_) {},
                onKeepK: (_) {},
                busy: true,
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('autoBackupSwitch')));
      await t.tap(find.byKey(const Key('autoBackupFolderRow')));
      await t.pump();
      expect(toggles, 0);
      expect(folders, 0);
    });

    testWidgets('the flow itself starts nothing while it is busy (no second switch-off, no second folder change)', (t) async {
      await pumpWith(t, [_a1]);
      final flow = AutoBackupFlow(onChanged: () {});
      flow.busy.value = true;
      late BuildContext ctx;
      await t.pumpWidget(
        MaterialApp(home: Builder(builder: (c) { ctx = c; return const SizedBox(); })),
      );
      await flow.toggle(ctx, false, hasFolder: true);
      await flow.chooseFolder(ctx);
      await t.pump();
      expect(ui.bridge.calls, isEmpty, reason: 'no listing, no release, no picker');
      expect(await BackupPrefs.readEnabled(), isTrue);
      flow.busy.value = false;
    });
  });

  group('toast text', () {
    FolderChangeResult r({
      bool busy = false,
      bool asked = true,
      int found = 0,
      LeftoverDeleteResult? deleted,
    }) => FolderChangeResult(ok: true, busy: busy, asked: asked, found: found, deleted: deleted);

    test('every case', () {
      expect(folderChangeToast(r(found: 6)), 'Kept 6 files.');
      expect(folderChangeToast(r(found: 1)), 'Kept 1 file.');
      expect(folderChangeToast(r(found: 6, deleted: const LeftoverDeleteResult(deleted: 6))), 'Deleted 6 files.');
      expect(folderChangeToast(r(found: 6, deleted: const LeftoverDeleteResult(deleted: 4, failed: 2))), 'Deleted 4. 2 could not be deleted.');
      expect(folderChangeToast(r(found: 6, deleted: const LeftoverDeleteResult(deleted: 0, failed: 6))), 'Deleted 0. 6 could not be deleted.');
      expect(folderChangeToast(r(found: 6, deleted: const LeftoverDeleteResult(listingFailed: true))), isNull);
      expect(folderChangeToast(r(asked: false)), isNull);
      expect(folderChangeToast(r()), isNull, reason: 'only the old-folder question was asked');
      expect(folderChangeToast(r(busy: true)), kDataOpBusy);
    });
  });
}
