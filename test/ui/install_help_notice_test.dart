// "Install help" notice (auto-read build only): model, once-only add, startup
// wiring (opposite flavor of the other-version notice), the Updates page card and
// its button, the permanent Notifications row. Real inbox and prefs in memory;
// the browser is the fake bridge.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/app_constants.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/data/updates/install_help_notice.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/data/updates/updates_startup.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/install_help_copy.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';
import 'package:mmogo/ui/screens/notifications/notifications_page.dart';
import 'package:mmogo/ui/screens/updates/notice_card.dart';
import 'package:mmogo/ui/screens/updates/updates_screen.dart';
import 'package:mmogo/ui/shell/updates_news_repository.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/updates/fake_update_check_client.dart';
import '../support/fake_storage_bridge.dart';

final _t0 = DateTime(2026, 11, 20, 9, 0);

UpdatesInbox _inbox() => UpdatesInbox(installedVersion: () => '0.2.0');

Map<String, Object?> _json({String tag = 'InstallHelp', Map<String, Object?> extra = const {'install_help': true}}) =>
    {'tag': tag, 'notes': '', 'receivedAt': _t0.millisecondsSinceEpoch, 'read': false, ...extra};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the model', () {
    test('round trips and is not a release', () {
      final n = Notice(tag: Notice.installHelpTag, notes: '', receivedAt: _t0, installHelp: true);
      expect(n.isRelease, isFalse);
      final back = Notice.tryFromJson(jsonDecode(jsonEncode(n.toJson())));
      expect(back, isNotNull);
      expect(back!.installHelp, isTrue);
      expect(back.tag, 'InstallHelp');
      expect(back.copyWith(read: true).installHelp, isTrue);
    });

    test('bad data returns null: wrong tag, two special kinds, no flag, bad date', () {
      expect(Notice.tryFromJson(_json(tag: 'v1.2.3')), isNull);
      expect(Notice.tryFromJson(_json(tag: 'Welcome')), isNull);
      expect(Notice.tryFromJson(_json(extra: {'install_help': true, 'other_version': true})), isNull);
      expect(Notice.tryFromJson(_json(extra: {'install_help': true, 'welcome': true})), isNull);
      expect(Notice.tryFromJson(_json(extra: {})), isNull); // no flag: not a version either
      expect(Notice.tryFromJson(_json()..['receivedAt'] = 'x'), isNull);
    });

    test('the inbox refuses a wrong tag or two kinds and keeps it past the cap', () async {
      final box = _inbox();
      await box.load();
      expect(await box.add(Notice(tag: 'v9.9.9', notes: '', receivedAt: _t0, installHelp: true)), isFalse);
      expect(
        await box.add(Notice(tag: Notice.installHelpTag, notes: '', receivedAt: _t0, installHelp: true, otherVersion: true)),
        isFalse,
      );
      await InstallHelpNotice.addIfNeeded(box, now: _t0.subtract(const Duration(days: 30)));
      for (var i = 0; i < 12; i++) {
        await box.add(Notice(tag: 'v0.3.$i', notes: '', receivedAt: _t0.add(Duration(minutes: i))));
      }
      expect(box.notices.where((n) => n.installHelp), hasLength(1));
      final later = _inbox();
      await later.load();
      expect(later.notices.where((n) => n.installHelp), hasLength(1));
    });

    test('alone it is not an update', () async {
      final box = _inbox();
      await box.load();
      await InstallHelpNotice.addIfNeeded(box, now: _t0);
      expect(box.updateAvailable, isFalse);
    });
  });

  group('add once', () {
    test('first run adds it unread, sets the key; read stays read on later launches', () async {
      final box = _inbox();
      await box.load();
      expect(await InstallHelpNotice.addIfNeeded(box, now: _t0), isTrue);
      expect(box.unreadCount.value, 1);
      expect(await UpdatePrefs.readInstallHelpNoticeAdded(), isTrue);
      await box.markRead(Notice.installHelpTag);
      final later = _inbox();
      await later.load();
      expect(later.unreadCount.value, 0);
      expect(await InstallHelpNotice.addIfNeeded(later, now: _t0), isFalse);
      expect(later.notices.single.read, isTrue);
    });

    test('never added again once the key is set, even when the inbox lost it', () async {
      SharedPreferences.setMockInitialValues({UpdatePrefs.keyInstallHelpNoticeAdded: true});
      final box = _inbox();
      await box.load();
      expect(await InstallHelpNotice.addIfNeeded(box, now: _t0), isFalse);
      expect(box.notices, isEmpty);
    });

    test('a stored one sets the key without adding a second', () async {
      final box = _inbox();
      await box.load();
      await box.add(Notice(tag: Notice.installHelpTag, notes: '', receivedAt: _t0, installHelp: true));
      expect(await InstallHelpNotice.addIfNeeded(box, now: _t0), isFalse);
      expect(await UpdatePrefs.readInstallHelpNoticeAdded(), isTrue);
      expect(box.notices, hasLength(1));
    });

    test('the key name', () => expect(UpdatePrefs.keyInstallHelpNoticeAdded, 'install_help_notice_added'));
  });

  group('startup wiring', () {
    test('off by default (standard build); on only when the caller says (auto-read build)', () async {
      final box = _inbox();
      final svc = UpdateCheckService(
        clientFactory: () => FakeUpdateCheckClient(error: StateError('offline')),
        inbox: box,
        installedVersion: () => '0.2.0',
      );
      await startUpdates(inbox: box, service: svc, now: _t0);
      expect(box.notices.any((n) => n.installHelp), isFalse);
      await startUpdates(inbox: box, service: svc, now: _t0, otherVersionNotice: false, installHelpNotice: false);
      expect(box.notices.any((n) => n.installHelp), isFalse);
      await startUpdates(inbox: box, service: svc, now: _t0, otherVersionNotice: false, installHelpNotice: true);
      expect(box.notices.where((n) => n.installHelp), hasLength(1));
    });
  });

  group('copy and url', () {
    test('the words and the guide url', () {
      expect(kInstallHelpNoticeTitle, 'Trouble installing the auto-read version?');
      expect(kInstallHelpNoticeAction, 'Open the install guide');
      expect(kInstallHelpNoticeChip, 'Install help');
      expect(AppConstants.installHelpUrl, '${AppConstants.siteUrl}install-auto-read.html');
      expect(AppConstants.allowedUrls, contains(AppConstants.installHelpUrl));
    });
  });

  group('the Updates page card', () {
    late FakeStorageBridge bridge;
    setUp(() {
      bridge = FakeStorageBridge();
      StorageBridge.instance = bridge;
    });

    Future<void> pump(WidgetTester t, {bool withNotice = true}) async {
      SharedPreferences.setMockInitialValues({
        if (withNotice) 'updates_inbox_v1': jsonEncode([_json()]),
      });
      final box = _inbox();
      await box.load();
      final svc = UpdateCheckService(
        clientFactory: () => FakeUpdateCheckClient(error: StateError('offline')),
        inbox: box,
        installedVersion: () => '0.2.0',
      );
      t.view.physicalSize = const Size(400, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: UpdatesScreen(inbox: box, service: svc)));
      await t.pumpAndSettle();
    }

    testWidgets('shows title, body, chip and the button (44 px) and the button opens the guide', (t) async {
      final h = t.ensureSemantics();
      await pump(t);
      expect(find.text(kInstallHelpNoticeTitle), findsOneWidget);
      expect(find.text(kInstallHelpNoticeBody), findsOneWidget);
      expect(find.text(kInstallHelpNoticeChip), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('noticeInstallHelp'))).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(kInstallHelpNoticeActionSpoken))), findsWidgets);
      await t.tap(find.text(kInstallHelpNoticeAction));
      await t.pump();
      expect(bridge.openedUrls, [AppConstants.installHelpUrl]);
      h.dispose();
    });

    testWidgets('standard build: no notice stored, so no card', (t) async {
      await pump(t, withNotice: false);
      expect(find.text(kInstallHelpNoticeTitle), findsNothing);
      expect(find.byKey(const Key('noticeInstallHelp')), findsNothing);
    });

    testWidgets('the card respects a large text scale', (t) async {
      t.view.physicalSize = const Size(480, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: NoticeCard(
                notice: Notice(tag: Notice.installHelpTag, notes: '', receivedAt: _t0, installHelp: true, read: true),
                onSeeWhatsNew: () {},
                onOpenInstallHelp: () {},
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text(kInstallHelpNoticeAction), findsOneWidget);
    });
  });

  group('the Notifications row', () {
    late FakeStorageBridge bridge;
    late UpdatesInbox box;
    late UpdatesNewsRepository repo;

    setUp(() async {
      bridge = FakeStorageBridge();
      StorageBridge.instance = bridge;
      box = _inbox();
      await box.load();
      await InstallHelpNotice.addIfNeeded(box, now: _t0);
      repo = UpdatesNewsRepository(box);
    });
    tearDown(() => repo.dispose());

    test('it is permanent: remove does nothing, markRead is saved', () async {
      final first = await repo.watchNews().first;
      expect(first.single.permanent, isTrue);
      expect(first.single.title, kInstallHelpNoticeTitle);
      expect(first.single.body, kInstallHelpNoticeBody);
      await repo.remove(Notice.installHelpTag);
      expect(box.notices, hasLength(1));
      await repo.markRead(Notice.installHelpTag, _t0);
      final again = _inbox();
      await again.load();
      expect(again.notices.single.read, isTrue);
    });

    testWidgets('the row has no Dismiss and its link opens the install guide', (t) async {
      t.view.devicePixelRatio = 1.0;
      // Wider than a phone: the test font is wider than the real one (the link is a long label).
      t.view.physicalSize = const Size(480, 800);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: NotificationsPage(news: repo, initialChip: NotifChip.news, clock: () => _t0.add(const Duration(minutes: 5))),
      ));
      await t.pump();
      await t.pump();
      expect(find.text(kInstallHelpNoticeBody), findsOneWidget);
      expect(find.text(kNewsActionDismiss), findsNothing);
      expect(find.text(kNewsActionRemove), findsNothing);
      await t.tap(find.text(kInstallHelpNoticeAction));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
      expect(bridge.openedUrls, [AppConstants.installHelpUrl]);
      expect(box.unreadCount.value, 0);
    });
  });
}
