// F3 (0.1.2 corrections): Backup and restore with the "?" help (mock
// backup-help.html), one not-encrypted warning (R42 / R46), "categories"
// everywhere visible (R41 / R44). Invented data only; every service is a fake.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/backup/restore_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/backup_page_harness.dart';
import '../../../support/fake_backup_ui.dart';
import '../../../support/fake_delete_data.dart';

String _allText(WidgetTester t) => [
  for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? '',
].join('\n');

void main() {
  setUp(() => useFakeDeleteData());
  setUp(() => useFakeBackupUi());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the "?" and its sheet', () {
    testWidgets('the round "?" (About this page, 44 px) opens "About backups": phone-to-phone and the file note, then Close', (t) async {
      final h = t.ensureSemantics();
      await pumpBackupPage(t);
      final button = find.byKey(const Key('helpButton'));
      expect(t.getSize(button), const Size(44, 44));
      expect(t.getSemantics(button).label, 'About this page');
      expect(find.text('About backups'), findsNothing);
      await t.tap(button);
      await t.pumpAndSettle();
      expect(find.text('About backups'), findsOneWidget);
      expect(
        find.text("Android's phone-to-phone transfer will not carry mmogo data. A backup file is the only way to move to a new phone."),
        findsOneWidget,
      );
      expect(
        find.text('A backup contains names and phone numbers; anyone who gets the file can read it. Keep it somewhere private.'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('helpSheetClose')));
      await t.pumpAndSettle();
      expect(find.text('About backups'), findsNothing);
      h.dispose();
    });

    testWidgets('the phone-to-phone sentence is written ONCE: in the sheet only, no "Show more" on Restore', (t) async {
      await pumpBackupPage(t);
      expect(find.text(kPhoneTransferNotice), findsNothing, reason: 'not on the page');
      expect(find.textContaining('Show more'), findsNothing);
      expect(find.textContaining('Moving to a new phone'), findsNothing);
      await t.tap(find.byKey(const Key('helpButton')));
      await t.pumpAndSettle();
      expect(find.text(kPhoneTransferNotice), findsOneWidget);
    });

    testWidgets('W3 stays VISIBLE in the page card, word for word, and is not repeated in the sheet', (t) async {
      await pumpBackupPage(t);
      expect(
        find.text('Uninstalling mmogo erases your data from this phone. Only a backup you saved can bring it back.'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('helpButton')));
      await t.pumpAndSettle();
      expect(find.textContaining('Uninstalling mmogo'), findsOneWidget, reason: 'still just the page copy');
    });
  });

  group('page order from the mock', () {
    testWidgets('D7 sits directly above the Restore button; the line under the button follows it', (t) async {
      await pumpBackupPage(t);
      final d7 = t.getRect(find.byKey(const Key('backupD7Line')));
      final button = t.getRect(find.byKey(const Key('restoreButton')));
      expect(d7.bottom, lessThanOrEqualTo(button.top));
      expect(button.top - d7.bottom, lessThan(16), reason: 'directly above');
      final intro = t.getRect(find.text(kRestoreIntro));
      expect(intro.top, greaterThanOrEqualTo(button.bottom));
    });

    testWidgets('the "Last backup" line stays in the first card', (t) async {
      await pumpBackupPage(t);
      expect(find.byKey(const Key('backupLastLine')), findsOneWidget);
      expect(t.getTopLeft(find.byKey(const Key('backupLastLine'))).dy,
          lessThan(t.getTopLeft(find.text('BACK UP NOW')).dy));
    });
  });

  group('R42 / R46: "not encrypted" is said once', () {
    testWidgets('only the short line on the Back up now card, wherever Auto-backup is on or off', (t) async {
      for (final auto in [false, true]) {
        SharedPreferences.setMockInitialValues(auto
            ? {'auto_backup_enabled': true, 'auto_backup_folder_uri': 'content://tree/x', 'auto_backup_folder_name': 'Folder'}
            : {});
        await pumpBackupPage(t);
        expect(find.text('Backups are not encrypted.'), findsOneWidget, reason: 'auto=$auto');
        expect(find.text(kBackupFileWarning), findsNothing, reason: 'auto=$auto');
        expect(find.textContaining('not encrypted'), findsOneWidget, reason: 'auto=$auto');
      }
    });

    testWidgets('the "Before you back up" dialog keeps only the share-sheet line', (t) async {
      await pumpBackupPage(t);
      await t.tap(find.byKey(const Key('backUpNowButton')));
      await t.pumpAndSettle();
      expect(find.text('Before you back up'), findsOneWidget);
      expect(find.text("The next screen is Android's share sheet. Pick where the file goes."), findsOneWidget);
      expect(find.textContaining('not encrypted'), findsOneWidget, reason: 'the card behind the dialog; the dialog adds none');
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Share backup'), findsOneWidget);
    });
  });

  group('R41 / R44: "categories", never "classifications"', () {
    test('the Restore dialog line reads "4 transactions, 18 categories, 0 saved receivers"', () {
      expect(restoreCountsLine(4, 18, 0), '4 transactions, 18 categories, 0 saved receivers');
      expect(restoreCountsLine(1, 1, 1), '1 transaction, 1 category, 1 saved receiver');
    });

    test('the Backup result reads "18 categories (1 you made)"; no bracket when the person made none', () {
      expect(backupSharedCountsLine(4, 18, 0, userCategories: 1),
          '4 transactions, 18 categories (1 you made) and 0 saved receivers went to the share sheet.');
      expect(backupSharedCountsLine(4, 18, 0, userCategories: 3),
          '4 transactions, 18 categories (3 you made) and 0 saved receivers went to the share sheet.');
      expect(backupSharedCountsLine(4, 18, 0),
          '4 transactions, 18 categories and 0 saved receivers went to the share sheet.');
      expect(backupSharedCountsLine(4, 18, 0, userCategories: 0), isNot(contains('you made')));
    });

    testWidgets('the shared sheet shows the total, then how many the person made, and no "classification"', (t) async {
      final rig = FakeExportRig(export: fakeExport(tx: 4, cats: 18, userCats: 1, receivers: 0));
      await pumpBackupPage(t, flow: rig.flow());
      await t.tap(find.byKey(const Key('backUpNowButton')));
      await t.pumpAndSettle();
      await t.tap(find.text('Share backup'));
      await t.pumpAndSettle();
      expect(find.text('4 transactions, 18 categories (1 you made) and 0 saved receivers went to the share sheet.'), findsOneWidget);
      expect(_allText(t).toLowerCase(), isNot(contains('classification')));
    });

    testWidgets('no visible text on the page or in the sheet says "classification"', (t) async {
      await pumpBackupPage(t);
      expect(_allText(t).toLowerCase(), isNot(contains('classification')));
      await t.tap(find.byKey(const Key('helpButton')));
      await t.pumpAndSettle();
      expect(_allText(t).toLowerCase(), isNot(contains('classification')));
    });
  });

  group('large text, 320 dp wide, dark', () {
    for (final scale in [1.3, 1.6]) {
      testWidgets('text $scale: page and sheet lay out without overflow, Close stays on screen', (t) async {
        await pumpBackupPage(t, scale: scale, dark: true, size: const Size(320, 640));
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('helpButton')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final close = t.getRect(find.byKey(const Key('helpSheetClose')));
        expect(close.bottom, lessThanOrEqualTo(640));
        expect(close.right, lessThanOrEqualTo(320));
      });
    }
  });
}
