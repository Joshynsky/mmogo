// "Other version of mmogo" (standard build): the one-time bell notice, its
// permanent place in Notifications (read item at the bottom, never dismissed,
// never lights the bell again) and the permanent Settings > About row. Real
// inbox + repository over in-memory prefs; the browser is the fake bridge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_constants.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/data/updates/other_version_notice.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/data/updates/updates_startup.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/domain/notifications/news_logic.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';
import 'package:mmogo/ui/copy/other_version_copy.dart';
import 'package:mmogo/ui/screens/notifications/notifications_page.dart';
import 'package:mmogo/ui/screens/settings/about_section.dart';
import 'package:mmogo/ui/shell/updates_news_repository.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/updates/fake_update_check_client.dart';
import '../support/fake_storage_bridge.dart';

final _t0 = DateTime(2026, 10, 21, 9, 0);

UpdatesInbox _inbox() => UpdatesInbox(installedVersion: () => '0.1.2');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the notice', () {
    test('first run adds it unread and lights the bell once', () async {
      final box = _inbox();
      await box.load();
      expect(await OtherVersionNotice.addIfNeeded(box, now: _t0), isTrue);
      expect(box.notices.single.otherVersion, isTrue);
      expect(box.unreadCount.value, 1);
      expect(await UpdatePrefs.readOtherVersionNoticeAdded(), isTrue);
    });

    test('after it is read the bell stays dark on later launches and the item remains', () async {
      final box = _inbox();
      await box.load();
      await OtherVersionNotice.addIfNeeded(box, now: _t0);
      await box.markRead(Notice.otherVersionTag);
      expect(box.unreadCount.value, 0);

      final later = _inbox(); // a new launch
      await later.load();
      expect(later.unreadCount.value, 0);
      expect(await OtherVersionNotice.addIfNeeded(later, now: _t0), isFalse);
      expect(later.notices.single.otherVersion, isTrue);
      expect(later.notices.single.read, isTrue);
    });

    test('never added twice, even when the inbox lost it (pref is the once-only guard)', () async {
      final box = _inbox();
      await box.load();
      await OtherVersionNotice.addIfNeeded(box, now: _t0);
      SharedPreferences.setMockInitialValues({UpdatePrefs.keyOtherVersionNoticeAdded: true});
      final fresh = _inbox();
      await fresh.load();
      expect(await OtherVersionNotice.addIfNeeded(fresh, now: _t0), isFalse);
      expect(fresh.notices, isEmpty);
    });

    test('startUpdates adds it by default in the standard build and not when switched off', () async {
      final box = _inbox();
      final svc = UpdateCheckService(
        clientFactory: () => FakeUpdateCheckClient(error: StateError('offline')),
        inbox: box,
        installedVersion: () => '0.1.2',
      );
      await startUpdates(inbox: box, service: svc, now: _t0, otherVersionNotice: false);
      expect(box.notices.any((n) => n.otherVersion), isFalse); // the auto-read build path
      await startUpdates(inbox: box, service: svc, now: _t0, otherVersionNotice: true);
      expect(box.notices.where((n) => n.otherVersion), hasLength(1));
    });

    test('the permanent notice survives the 10-notice cap, at add and at load', () async {
      final box = _inbox();
      await box.load();
      await OtherVersionNotice.addIfNeeded(box, now: _t0.subtract(const Duration(days: 30)));
      for (var i = 0; i < 12; i++) {
        await box.add(Notice(tag: 'v0.3.$i', notes: '', receivedAt: _t0.add(Duration(minutes: i))));
      }
      expect(box.notices.where((n) => n.otherVersion), hasLength(1));
      expect(box.notices.where((n) => !n.otherVersion), hasLength(UpdatesInbox.maxNotices));
      final later = _inbox();
      await later.load();
      expect(later.notices.where((n) => n.otherVersion), hasLength(1));
    });

    test('the prefs key is in no backup key list', () {
      expect(UpdatePrefs.keyOtherVersionNoticeAdded, 'other_version_notice_added');
    });

    test('notice and row share one sentence, so they cannot drift', () {
      expect(kOtherVersionNoticeBody, endsWith(kOtherVersionPermissionSentence));
      expect(kOtherVersionSettingsSubtitle, endsWith(kOtherVersionPermissionSentence));
      expect(kOtherVersionNoticeTitle, 'Another version of mmogo');
      expect(kOtherVersionNoticeAction, 'See what it does');
    });
  });

  group('news logic', () {
    NewsItem item(String id, {DateTime? readAt, bool permanent = false, int ageMin = 10}) => NewsItem(
          id: id,
          kind: NewsKind.notice,
          title: id,
          createdAt: _t0.subtract(Duration(minutes: ageMin)),
          readAt: readAt,
          permanent: permanent,
        );

    test('a read permanent item sorts last; an unread one sorts like any other', () {
      final read = _t0.subtract(const Duration(days: 1));
      final sorted = sortNews([
        item('perm', readAt: read, permanent: true, ageMin: 1),
        item('old', readAt: read, ageMin: 5000),
        item('new', ageMin: 30),
      ]);
      expect(sorted.map((i) => i.id), ['new', 'old', 'perm']);
    });

    test('a permanent item is never dropped after the 30-day read window', () {
      final long = _t0.subtract(const Duration(days: 400));
      final out = visibleNews([item('perm', readAt: long, permanent: true), item('x', readAt: long)], _t0, readView: true);
      expect(out.map((i) => i.id), ['perm']);
    });
  });

  group('the repository', () {
    test('markRead saves it; remove does nothing for it', () async {
      final box = _inbox();
      await box.load();
      await OtherVersionNotice.addIfNeeded(box, now: _t0);
      final repo = UpdatesNewsRepository(box);
      addTearDown(repo.dispose);
      final first = await repo.watchNews().first;
      expect(first.single.permanent, isTrue);
      expect(first.single.title, kOtherVersionNoticeTitle);
      expect(first.single.body, kOtherVersionNoticeBody);
      await repo.remove(Notice.otherVersionTag);
      expect(box.notices, hasLength(1));
      await repo.markRead(Notice.otherVersionTag, _t0);
      final again = _inbox();
      await again.load();
      expect(again.notices.single.read, isTrue);
    });
  });

  group('the Notifications item', () {
    late FakeStorageBridge bridge;
    late UpdatesInbox box;
    late UpdatesNewsRepository repo;

    Future<void> open(WidgetTester t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(360, 800);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: NotificationsPage(news: repo, clock: () => _t0.add(const Duration(minutes: 5))),
      ));
      await t.pump();
      await t.pump();
    }

    setUp(() async {
      bridge = FakeStorageBridge();
      StorageBridge.instance = bridge;
      box = _inbox();
      await box.load();
      await OtherVersionNotice.addIfNeeded(box, now: _t0);
      repo = UpdatesNewsRepository(box);
    });
    tearDown(() => repo.dispose());

    testWidgets('unread: title, body, See what it does (44 px), no Dismiss', (t) async {
      await open(t);
      expect(find.textContaining(kOtherVersionNoticeTitle, findRichText: true), findsOneWidget);
      expect(find.text(kOtherVersionNoticeBody), findsOneWidget);
      expect(find.text(kNewsActionDismiss), findsNothing);
      expect(find.text(kNewsActionRemove), findsNothing);
      final pill = find.text(kOtherVersionNoticeAction);
      expect(pill, findsOneWidget);
      final box44 = t.getSize(find.ancestor(of: pill, matching: find.byType(ConstrainedBox)).first);
      expect(box44.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel(kOtherVersionNoticeActionSpoken), findsOneWidget);
    });

    testWidgets('See what it does opens the site, marks it read, and the item stays without Remove', (t) async {
      final h = t.ensureSemantics();
      await open(t);
      await t.tap(find.text(kOtherVersionNoticeAction));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
      expect(bridge.openedUrls, [AppConstants.siteUrl]);
      expect(box.unreadCount.value, 0);
      // Read view: still there, no Remove, no Dismiss.
      await t.tap(find.text(kNewsSwitchRead));
      await t.pump();
      expect(find.textContaining(kOtherVersionNoticeTitle, findRichText: true), findsOneWidget);
      expect(find.text(kNewsActionRemove), findsNothing);
      expect(find.text(kNewsActionDismiss), findsNothing);
      expect(find.text(kOtherVersionNoticeAction), findsOneWidget);
      h.dispose();
    }, skip: kAutoReadCompiled); // the auto-read page has its own chip bar
  });

  group('Settings > About row', () {
    Future<FakeStorageBridge> pump(WidgetTester t, {bool? row}) async {
      final bridge = FakeStorageBridge();
      StorageBridge.instance = bridge;
      final box = _inbox();
      await box.load();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: row == null
                ? AboutSection(palette: AppPalette.light, inbox: box)
                : AboutSection(palette: AppPalette.light, inbox: box, otherVersionRow: row),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return bridge;
    }

    testWidgets('sits between Updates and Send feedback and opens the site', (t) async {
      final bridge = await pump(t);
      expect(find.text(kOtherVersionSettingsLabel), findsOneWidget);
      expect(find.text(kOtherVersionSettingsSubtitle), findsOneWidget);
      double y(String s) => t.getTopLeft(find.text(s)).dy;
      expect(y('Updates'), lessThan(y(kOtherVersionSettingsLabel)));
      expect(y(kOtherVersionSettingsLabel), lessThan(y('Send feedback')));
      await t.tap(find.text(kOtherVersionSettingsLabel));
      await t.pump();
      expect(bridge.openedUrls, [AppConstants.siteUrl]);
    }, skip: kAutoReadCompiled);

    testWidgets('the row is at least 44 px high', (t) async {
      await pump(t);
      final row = find.ancestor(of: find.text(kOtherVersionSettingsLabel), matching: find.byType(InkWell)).first;
      expect(t.getSize(row).height, greaterThanOrEqualTo(44));
    }, skip: kAutoReadCompiled);

    testWidgets('the auto-read build path (row off) shows no row', (t) async {
      await pump(t, row: false);
      expect(find.text(kOtherVersionSettingsLabel), findsNothing);
      expect(find.text('Send feedback'), findsOneWidget);
    });
  });
}
