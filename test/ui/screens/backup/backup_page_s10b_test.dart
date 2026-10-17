// 0.1.2 S10b (BP2, A3, A5, A6, A7): the Backup page order, the D7 line, the flat
// W1 box and stuck line, the Back up now result states and the "Backup shared"
// sheet. FAKES only (useFakeBackupUi): no service, no file, no pref of the app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/skipped_row_describer.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/backup/auto_backup_card.dart';
import 'package:mmogo/ui/screens/backup/auto_backup_state.dart';
import 'package:mmogo/ui/screens/privacy/privacy_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/widgets/palette_alert_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/backup_page_harness.dart';
import '../../../support/fake_backup_ui.dart';
import '../../../support/fake_delete_data.dart';
import '../../../support/fake_restore_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useFakeDeleteData();
    useFakeBackupUi();
  });

  /// The Show which button INSIDE the open sheet (the card behind has one too).
  Finder sheetShowWhich() =>
      find.descendant(of: find.byType(BottomSheet), matching: find.byKey(const Key('showWhichButton')));

  Future<void> backUp(WidgetTester t) async {
    await t.ensureVisible(find.byKey(const Key('backUpNowButton')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('backUpNowButton')));
    await t.pumpAndSettle();
    await t.tap(find.text('Share backup'));
    await t.pumpAndSettle();
  }

  group('page order and fixed lines', () {
    testWidgets('top to bottom: header, Back up now, Auto-backup, Restore (D7 line directly above its button), Privacy link (F3 order)', (t) async {
      await pumpBackupPage(t);
      double y(Finder f) => t.getTopLeft(f.first).dy;
      final order = [
        y(find.text('Your data lives only on this phone')),
        y(find.text('BACK UP NOW')),
        y(find.byKey(const Key('autoBackupSwitch'))),
        y(find.text('RESTORE')),
        y(find.byKey(const Key('backupD7Line'))),
        y(find.byKey(const Key('restoreButton'))),
        y(find.text('Privacy and your data')),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]), reason: 'item $i is below item ${i - 1}');
      }
    });

    testWidgets('D7: "A backup made with 0.1.2 cannot be restored by 0.1.1 or older." is on the Backup page', (t) async {
      await pumpBackupPage(t);
      expect(kBackupNotRestorableByOlder, 'A backup made with 0.1.2 cannot be restored by 0.1.1 or older.');
      expect(find.text(kBackupNotRestorableByOlder), findsOneWidget);
    });

    testWidgets('D7 is not on the Privacy page', (t) async {
      await t.pumpWidget(const MaterialApp(home: PrivacyScreen()));
      await t.pumpAndSettle();
      expect(find.text(kBackupNotRestorableByOlder), findsNothing);
    });

    testWidgets('the counts sentence says "categories you made", and no "classification" shows on the page', (t) async {
      await pumpBackupPage(t);
      expect(
        find.text('A backup holds your 120 transactions, 3 categories you made, 8 saved receivers and your settings.'),
        findsOneWidget,
      );
      expect(find.textContaining('lassification'), findsNothing);
    });
  });

  group('A5 / A6: flat boxes', () {
    bool striped(WidgetTester t, Finder text) {
      final box = find.ancestor(of: text, matching: find.byType(Container)).evaluate().map((e) => e.widget as Container).firstWhere(
        (c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).color == AppPalette.light.highlight,
      );
      return (box.decoration! as BoxDecoration).border != null;
    }

    testWidgets('the not-encrypted box on the Back up now card has no left stripe', (t) async {
      await pumpBackupPage(t);
      expect(striped(t, find.text(kBackupNotEncryptedShort)), isFalse);
    });

    testWidgets('R42 / R46: the not-encrypted warning appears ONCE (Back up now card), not on the Auto-backup card or in the "Before you back up" dialog', (t) async {
      SharedPreferences.setMockInitialValues({
        'auto_backup_enabled': true,
        'auto_backup_folder_uri': 'content://tree/x',
        'auto_backup_folder_name': 'Folder',
      });
      await pumpBackupPage(t);
      expect(find.text(kBackupNotEncryptedShort), findsOneWidget);
      expect(find.text(kBackupFileWarning), findsNothing);
      await t.tap(find.byKey(const Key('backUpNowButton')));
      await t.pumpAndSettle();
      expect(find.text('Before you back up'), findsOneWidget);
      // The dialog keeps only its own share-sheet line; the page behind it still shows the warning once.
      expect(find.text(kBackupNotEncryptedShort), findsOneWidget);
      expect(find.text(kBackupFileWarning), findsNothing);
      expect(find.descendant(of: find.byType(PaletteAlertDialog), matching: find.textContaining('encrypted')), findsNothing);
      expect(find.descendant(of: find.byType(PaletteAlertDialog), matching: find.textContaining('Android')), findsOneWidget);
    });

    testWidgets('the W1 box in the auto-backup setup sheet has no stripe', (t) async {
      await pumpBackupPage(t);
      await tapKey(t, 'autoBackupSwitch');
      expect(find.byKey(const Key('setupWarning')), findsOneWidget);
      final warn = find.descendant(of: find.byKey(const Key('setupWarning')), matching: find.text(kBackupFileWarning));
      expect(striped(t, warn), isFalse);
    });

    testWidgets('the stuck line replaces the old banner: new text, no button, no stripe', (t) async {
      SharedPreferences.setMockInitialValues({
        'auto_backup_enabled': true,
        'auto_backup_folder_uri': 'content://tree/x',
        'auto_backup_folder_name': 'Folder',
        'auto_backup_fail_count': 1,
      });
      await pumpBackupPage(t);
      expect(
        kAutoBackupStuckLine,
        'The last automatic backup did not finish and was stopped. It will try again after your next saved entry.',
      );
      final line = find.byKey(const Key('autoBackupFailedBanner'));
      expect(find.descendant(of: line, matching: find.text(kAutoBackupStuckLine)), findsOneWidget);
      expect(find.descendant(of: line, matching: find.byType(ButtonStyleButton)), findsNothing);
      expect(striped(t, find.descendant(of: line, matching: find.text(kAutoBackupStuckLine))), isFalse);
    });

    testWidgets('the paused and no-folder banners keep their stripe', (t) async {
      for (final st in [
        const AutoBackupState(enabled: true, paused: true, folderUri: 'content://tree/x', folderName: 'F'),
        const AutoBackupState(enabled: true),
      ]) {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AutoBackupCard(
                  palette: AppPalette.light,
                  state: st,
                  onToggle: (_) {},
                  onChooseFolder: () {},
                  onEveryN: (_) {},
                  onKeepK: (_) {},
                ),
              ),
            ),
          ),
        );
        final banner = st.paused ? 'autoBackupPausedBanner' : 'autoBackupNoFolderBanner';
        final box = find.descendant(of: find.byKey(Key(banner)), matching: find.byType(Container)).evaluate().first.widget as Container;
        expect((box.decoration! as BoxDecoration).border, isNotNull, reason: banner);
      }
    });
  });

  group('after Back up now', () {
    testWidgets('shared, nothing left out: the sheet shows counts and the Files-app sentence; no "Did you save it?"', (t) async {
      final rig = FakeExportRig();
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      expect(find.text(kBackupSharedTitle), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('backupSharedCounts'))).data,
        '120 transactions, 3 categories and 8 saved receivers went to the share sheet.',
      );
      expect(find.text(kBackupFilesApp), findsOneWidget);
      expect(kBackupFilesApp, 'mmogo cannot see where you saved it. Check your Files app.');
      expect(find.byKey(const Key('backupLeftOutNote')), findsNothing);
      expect(find.byKey(const Key('backupSharedTidied')), findsNothing);
      expect(find.byKey(const Key('showWhichButton')), findsNothing);
      expect(find.textContaining('Did you save'), findsNothing);
      expect(find.byKey(const Key('backupResult')), findsNothing, reason: 'no inline success text (A3)');
      expect(find.textContaining('Backup ready'), findsNothing);
      expect(hasFocusKey(t, 'backupSharedDone'), isTrue, reason: 'Done has the initial focus');
    });

    testWidgets('the sheet claims nothing about the file being saved except the one mandated sentence', (t) async {
      final rig = FakeExportRig(export: fakeExport(repaired: 2, rows: fakeSkippedEntries(3)));
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      await t.tap(sheetShowWhich());
      await t.pumpAndSettle();
      final texts = t
          .widgetList<Text>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Text)))
          .map((w) => w.data ?? '');
      for (final d in texts) {
        if (d == kBackupFilesApp) continue;
        // "saved receivers" is a noun, not a claim about the file.
        expect(d.toLowerCase().replaceAll('saved receiver', '').contains('saved'), isFalse, reason: d);
        expect(d.toLowerCase().contains('safe'), isFalse, reason: d);
      }
    });

    testWidgets('rows left out: sheet note, tidied line and Show which; the list has reasons and the closing line', (t) async {
      final rig = FakeExportRig(export: fakeExport(repaired: 2, rows: fakeSkippedEntries(3)));
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      expect(find.text(backupTidiedLine(2)), findsOneWidget);
      expect(
        t.widget<Text>(find.descendant(of: find.byType(BottomSheet), matching: find.byKey(const Key('backupLeftOutLine')))).data,
        '3 entries could not be made valid and were left out of the backup. Your data on this phone was not changed.',
      );
      expect(t.getSize(sheetShowWhich()).height, greaterThanOrEqualTo(44));
      await t.tap(sheetShowWhich());
      await t.pumpAndSettle();
      expect(find.text('Not included in this backup (3)'), findsOneWidget);
      expect(find.text('01-09-2026, Send Money: a required detail is missing'), findsOneWidget);
      expect(find.text(kStillInApp), findsOneWidget);
    });

    testWidgets('a category or saved receiver left out says "items", not "entries"', (t) async {
      final rows = [
        ...fakeSkippedEntries(1),
        const SkippedRowInfo(kind: SkipKind.category, reason: SkipReason.cascaded),
      ];
      final rig = FakeExportRig(export: fakeExport(rows: rows));
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      final line = t
          .widget<Text>(find.descendant(of: find.byType(BottomSheet), matching: find.byKey(const Key('backupLeftOutLine'))))
          .data!;
      expect(line, startsWith('2 items could not be made valid and were left out'));
      await t.tap(sheetShowWhich());
      await t.pumpAndSettle();
      expect(find.text('A category: it belonged to a category that was left out'), findsOneWidget);
    });

    testWidgets('200 rows: the sheet list shows 20, "and 180 more not shown", Show all gives all 200 (A1); Done stays on screen at 1.3', (
      t,
    ) async {
      final rig = FakeExportRig(export: fakeExport(rows: fakeSkippedEntries(200)));
      await pumpBackupPage(t, flow: rig.flow(), scale: 1.3, size: const Size(420, 900));
      await backUp(t);
      await t.tap(sheetShowWhich());
      await t.pumpAndSettle();
      expect(find.text('Not included in this backup (200)'), findsOneWidget);
      expect(find.text('and 180 more not shown'), findsOneWidget);
      await t.tap(find.byKey(const Key('skippedShowAll')));
      await t.pumpAndSettle();
      expect(find.text('and 180 more not shown'), findsNothing);
      final done = t.getRect(find.byKey(const Key('backupSharedDone')));
      final view = t.view.physicalSize / t.view.devicePixelRatio;
      expect(done.bottom, lessThanOrEqualTo(view.height), reason: 'Done is on screen');
      expect(done.height, greaterThanOrEqualTo(44));
      expect(t.takeException(), isNull);
    });

    for (final how in ['Done', 'Back', 'outside tap', 'swipe']) {
      testWidgets('$how closes the sheet; nothing else happens and the left-out note stays on the card', (t) async {
        final rig = FakeExportRig(export: fakeExport(rows: fakeSkippedEntries(2)));
        await pumpBackupPage(t, flow: rig.flow());
        await backUp(t);
        expect(find.text(kBackupSharedTitle), findsOneWidget);
        switch (how) {
          case 'Done':
            await t.tap(find.byKey(const Key('backupSharedDone')));
          case 'Back':
            await t.binding.handlePopRoute();
          case 'outside tap':
            await t.tapAt(const Offset(10, 10));
          default:
            await t.fling(find.byKey(const Key('backupSheetTitle')), const Offset(0, 800), 1500);
        }
        await t.pumpAndSettle();
        expect(find.text(kBackupSharedTitle), findsNothing);
        expect(rig.shares, 1);
        // A3: Done does not clear the left-out note on the Back up now card.
        expect(find.byKey(const Key('backupLeftOutNote')), findsOneWidget);
        expect(find.byKey(const Key('showWhichButton')), findsOneWidget);
      });
    }

    testWidgets('the card note lists the same rows ("Show which") and the next Back up now clears it', (t) async {
      final rig = FakeExportRig(export: fakeExport(rows: fakeSkippedEntries(2)));
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      await t.tap(find.byKey(const Key('backupSharedDone')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('showWhichButton')));
      await t.pumpAndSettle();
      expect(find.text('Not included in this backup (2)'), findsOneWidget);
      rig.export = fakeExport();
      await backUp(t);
      await t.tap(find.byKey(const Key('backupSharedDone')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('backupLeftOutNote')), findsNothing, reason: 'a clean backup replaces the note');
    });

    testWidgets('the next Back up now clears the kept note at once, whatever its outcome (here: the share sheet is closed)', (t) async {
      final rig = FakeExportRig(export: fakeExport(rows: fakeSkippedEntries(2)));
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      await t.tap(find.byKey(const Key('backupSharedDone')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('backupLeftOutNote')), findsOneWidget);
      rig.shared = false;
      await backUp(t);
      expect(find.byKey(const Key('backupLeftOutNote')), findsNothing, reason: 'cleared when the next Back up now began');
      expect(find.text(kBackupNotSharedLine), findsOneWidget);
    });

    testWidgets('the share sheet closed: only the short inline line, no sheet, no question', (t) async {
      final rig = FakeExportRig()..shared = false;
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      expect(find.text('The share sheet was closed. No backup was saved.'), findsOneWidget);
      expect(kBackupNotSharedLine, 'The share sheet was closed. No backup was saved.');
      expect(find.text(kBackupSharedTitle), findsNothing);
      expect(find.textContaining('Did you save'), findsNothing);
      expect(find.byKey(const Key('backupLeftOutNote')), findsNothing);
    });

    testWidgets('a failed backup still shows the failure dialog and no sheet', (t) async {
      final rig = FakeExportRig()..exportError = StateError('x');
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      expect(find.text('Could not create the backup'), findsOneWidget);
      expect(find.text(kBackupSharedTitle), findsNothing);
    });
  });

  group('looks', () {
    for (final dark in [false, true]) {
      testWidgets('the Backup page and the shared sheet at 1.3 (${dark ? 'dark' : 'light'}): no overflow', (t) async {
        final rig = FakeExportRig(export: fakeExport(repaired: 1, rows: fakeSkippedEntries(25)));
        await pumpBackupPage(t, flow: rig.flow(), scale: 1.3, dark: dark);
        await backUp(t);
        expect(t.takeException(), isNull);
        final h = t.ensureSemantics();
        expect(find.bySemanticsLabel(kBackupSharedTitle), findsWidgets);
        h.dispose();
      });
    }

    testWidgets('the sheet title names the route', (t) async {
      final h = t.ensureSemantics();
      final rig = FakeExportRig();
      await pumpBackupPage(t, flow: rig.flow());
      await backUp(t);
      expect(
        t.getSemantics(find.byKey(const Key('backupSheetTitle'))),
        matchesSemantics(label: kBackupSharedTitle, isHeader: true),
      );
      h.dispose();
    });
  });
}
