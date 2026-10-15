// B32: the static Privacy and your data page, the Settings "Privacy and
// security" row, the link row on the Backup page, and B33: the Send feedback
// row (opens the issues constant through the bridge only).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_constants.dart';
import 'package:mmogo/data/backup/backup_counts.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/privacy_copy.dart';
import 'package:mmogo/ui/screens/backup/backup_screen.dart';
import 'package:mmogo/ui/screens/backup/backup_widgets.dart';
import 'package:mmogo/ui/screens/privacy/privacy_screen.dart';
import 'package:mmogo/ui/screens/settings/privacy_section.dart';
import 'package:mmogo/ui/screens/settings/settings_widgets.dart';
import 'package:mmogo/ui/screens/settings/updates_section.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_storage_bridge.dart';

late FakeStorageBridge _bridge;

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .followedBy(tester.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()))
    .join('\n');

Future<void> _pumpPage(WidgetTester tester, Widget home, {Size size = const Size(400, 3200)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        Routes.privacy: (_) => const PrivacyScreen(),
        Routes.backup: (_) => BackupScreen(
          loadCounts: () async => const BackupCounts(transactions: 1, userClassifications: 0, receivers: 0, deletedLeftOut: 0),
        ),
      },
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _bridge = FakeStorageBridge();
    StorageBridge.instance = _bridge;
  });

  group('Privacy and your data page', () {
    testWidgets('privacy_page_contains_backup_warning_cloud_notice_and_network_disclosure_verbatim', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      expect(find.text(kPrivacyTitle), findsOneWidget);
      final text = _allText(tester);
      expect(text, contains(kBackupFileWarning));
      expect(text, contains(kCloudSyncNotice));
      expect(text, contains(kNetworkSentence));
      expect(text, contains(kNetworkDisclosure));
      expect(text, contains(kUninstallErasesNotice));
      expect(text, contains(kPhoneTransferNotice));
    });

    testWidgets('has the four card titles, what is stored, and how to turn the check off', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      for (final t in [kPrivacyStoredTitle, kPrivacyLeavesTitle, kPrivacyBackupFilesTitle, kPrivacyCloudTitle]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      final text = _allText(tester);
      expect(text, contains(kPrivacyStoredBody));
      expect(text, contains('transactions'));
      expect(text, contains('learned'));
      expect(text, contains('Android does not copy your data to Google'));
      expect(text, contains('That is the only thing mmogo sends'));
      expect(text, contains('turn the update check off on the Updates page'));
      expect(text, contains(kPrivacyBackupFilesBody));
    });

    testWidgets('privacy_page_has_no_banned_phrases', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      // 0.1.2: the canonical sentence is the one allowed "No permissions ..." form (C12).
      final text = _allText(tester).replaceAll(kPrivacySentenceStandard, '').toLowerCase();
      expect(text, isNot(contains('nothing is sent anywhere')));
      expect(text, isNot(contains('no permissions')));
      expect(text, isNot(contains('never leaves')));
      expect(text, isNot(contains('classification')));
      expect(text, isNot(contains('no request at all')));
      expect(text, isNot(contains('not even internet')));
      expect(text, isNot(contains('zero permissions')));
    });

    testWidgets('S1 P-Privacy-08: canonical sentence is first, exact, once; independence full sentence present', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      expect(kPrivacySentenceStandard, 'No permissions except internet, used only to check for updates (switchable off).');
      expect(find.text(kPrivacySentenceStandard), findsOneWidget);
      expect(find.byKey(const Key('privacySentenceStandard')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('privacySentenceStandard'))).dy,
        lessThan(tester.getTopLeft(find.text(kPrivacyStoredTitle)).dy),
      );
      expect(find.text(kIndependenceFull), findsOneWidget);
      expect(kIndependenceFull, contains('not made, approved or checked by Safaricom'));
    });

    testWidgets('S1 P-Privacy-01 (C-B12): stored card says categories and names what is stored', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      final text = _allText(tester);
      expect(text, contains('your categories'));
      expect(text, contains(kPrivacyStoredReceiverDetails));
      expect(text, contains('learned'));
      expect(text, contains(kPrivacyStoredAgentNumber));
      expect(text, contains(kPrivacyStoredRememberedAnswers));
      expect(kPrivacyStoredRememberedAnswers, contains('not in backups and not shared'));
      expect(kPrivacyStoredRememberedAnswers, contains('only when the tick is on'));
      expect(kPrivacyStoredReceiverDetails, contains('names and phone numbers'));
    });

    test('COPY AHEAD OF FEATURE: only the S3 agent-number sentence is left; the S8 remembered-answers sentence went live in S8c-2', () {
      // S8c-2 (F4): the remembered answers ship now, so that sentence left the list (it still shows on the page).
      // QA gate: do not release 0.1.2 unless slice S3 shipped, or this one is removed.
      expect(kPrivacyCopyAheadOfFeature, [kPrivacyStoredAgentNumber]);
      expect(kPrivacyCopyAheadOfFeature, isNot(contains(kPrivacyStoredRememberedAnswers)));
      expect(kPrivacyStoredAgentNumber, contains('agent number'));
    });

    testWidgets('S1 P-Privacy-03: "no automatic request" and the once-online sentence stay visible', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      expect(kPrivacyLeavesBody, contains('no automatic request'));
      expect(kPrivacyLeavesBody, isNot(contains('no request at all')));
      expect(find.text(kPrivacyCheckNowOnce), findsOneWidget);
      expect(kPrivacyCheckNowOnce, 'Even with automatic checks off, Check for updates now goes online once when you tap it.');
      expect(_allText(tester), contains(kPrivacyLeavesBody));
    });

    testWidgets('S1 P-Privacy-05/02 STAYS: the not-encrypted box and the phone-transfer paragraph are still there', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      expect(find.text(kBackupFileWarning), findsOneWidget);
      expect(find.byType(BackupWarning), findsOneWidget); // only the not-encrypted box
      expect(_allText(tester), contains(kUninstallErasesNotice));
      expect(_allText(tester), contains(kPhoneTransferNotice));
    });

    testWidgets('S1 P-Privacy-06: the cloud-folder notice is a plain card, not a warning box', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      final cloud = find.text(kCloudSyncNotice);
      expect(cloud, findsOneWidget);
      expect(find.ancestor(of: cloud, matching: find.byType(BackupWarning)), findsNothing);
      expect(find.ancestor(of: cloud, matching: find.byType(BackupCard)), findsOneWidget);
    });

    testWidgets('is static: it makes no network request and opens no URL', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      expect(_bridge.calls, isEmpty);
    });

    testWidgets('the link row opens Backup and restore', (tester) async {
      await _pumpPage(tester, const PrivacyScreen());
      expect(find.text(kPrivacyBackupRowTitle), findsOneWidget);
      await tester.tap(find.text(kPrivacyBackupRowTitle));
      await tester.pumpAndSettle();
      expect(find.byType(BackupScreen), findsOneWidget);
    });
  });

  group('Settings: Privacy and security group', () {
    testWidgets('one row, "Privacy and your data", that opens the page', (tester) async {
      await _pumpPage(tester, const Scaffold(body: PrivacySection(palette: AppPalette.light)));
      expect(find.text(kSettingsPrivacyGroup.toUpperCase()), findsOneWidget);
      expect(find.text(kPrivacyTitle), findsOneWidget);
      expect(find.text(kSettingsPrivacySubtitle), findsOneWidget);
      await tester.tap(find.text(kPrivacyTitle));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsOneWidget);
    });
  });

  group('Backup page: Privacy and your data link row', () {
    testWidgets('shows the row and opens the Privacy page', (tester) async {
      await _pumpPage(
        tester,
        BackupScreen(
          loadCounts: () async => const BackupCounts(transactions: 1, userClassifications: 0, receivers: 0, deletedLeftOut: 0),
        ),
        size: const Size(400, 3000),
      );
      expect(find.text(kPrivacyTitle), findsOneWidget);
      expect(find.text(kBackupPrivacyRowSubtitle), findsOneWidget);
      await tester.tap(find.text(kPrivacyTitle));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsOneWidget);
    });
  });

  group('Settings: Send feedback row (B33)', () {
    Future<void> pumpUpdates(WidgetTester tester) =>
        _pumpPage(tester, const Scaffold(body: UpdatesSection(palette: AppPalette.light)));

    testWidgets('shows the label and the full hint under it', (tester) async {
      await pumpUpdates(tester);
      expect(find.text('Send feedback'), findsOneWidget);
      expect(
        find.text(
          'Opens the mmogo issues page on GitHub in your browser. '
          'Do not paste M-Pesa messages, names or phone numbers into a public issue.',
        ),
        findsOneWidget,
      );
      expect(kSendFeedbackSubtitle, contains(kFeedbackHint));
    });

    testWidgets('B33b: Send feedback ends in the open-in-new arrow, Updates keeps the chevron', (tester) async {
      await pumpUpdates(tester);
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Send feedback'), matching: find.byType(SettingsLink)),
          matching: find.byIcon(Icons.open_in_new_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Send feedback'), matching: find.byType(SettingsLink)),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Updates'), matching: find.byType(SettingsLink)),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );
    });

    testWidgets('feedback_row_shows_hint_and_opens_issues_constant', (tester) async {
      await pumpUpdates(tester);
      await tester.tap(find.text('Send feedback'));
      await tester.pumpAndSettle();
      expect(_bridge.calls.where((c) => c.startsWith('openUrl')), ['openUrl:https://github.com/Joshynsky/mmogo/issues']);
      expect(_bridge.openedUrls, [AppConstants.issuesUrl]);
      expect(find.text(kSendFeedbackCouldNotOpen), findsNothing);
    });

    testWidgets('a browser that cannot open it shows a short message', (tester) async {
      StorageBridge.instance = _Refusing();
      await pumpUpdates(tester);
      await tester.tap(find.text('Send feedback'));
      await tester.pumpAndSettle();
      expect(find.text(kSendFeedbackCouldNotOpen), findsOneWidget);
    });

    testWidgets('nothing opens until the row is tapped', (tester) async {
      await pumpUpdates(tester);
      expect(_bridge.calls.where((c) => c.startsWith('openUrl')), isEmpty);
    });
  });
}

class _Refusing extends FakeStorageBridge {
  @override
  Future<bool> openUrl(String url) async => false;
}
