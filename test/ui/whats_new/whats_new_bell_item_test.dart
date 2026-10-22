// 0.1.2 "What's new in mmogo X" bell item: added once per version when the
// pages are due (the hook), kept in the inbox, shown as a What's new row in
// Notifications, opened read-only (Back, no Got it) and marked read by
// opening. Real inbox and repository over in-memory prefs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/data/updates/whats_new_notice.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/shell/updates_news_repository.dart';
import 'package:mmogo/ui/whats_new/whats_new_hook.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _t0 = DateTime(2026, 10, 22, 9, 0);

UpdatesInbox _inbox() => UpdatesInbox(installedVersion: () => '0.1.2');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WhatsNewProcess.resetForTest();
  });

  group('the notice', () {
    test('is added once per version, unread, and lights the bell', () async {
      final box = _inbox();
      await box.load();
      expect(await WhatsNewNotice.addIfDue(box, '0.1.2', now: _t0), isTrue);
      expect(await WhatsNewNotice.addIfDue(box, '0.1.2', now: _t0), isFalse);
      expect(box.notices.single.whatsNew, isTrue);
      expect(box.notices.single.tag, 'WhatsNew:0.1.2');
      expect(box.unreadCount.value, 1);
    });

    test('a later version gets its own item next to the old one', () async {
      final box = _inbox();
      await box.load();
      await WhatsNewNotice.addIfDue(box, '0.1.2', now: _t0);
      expect(await WhatsNewNotice.addIfDue(box, '0.1.3', now: _t0), isTrue);
      expect(box.notices.where((n) => n.whatsNew), hasLength(2));
    });

    test('survives a restart at the installed version and keeps its read state', () async {
      final box = _inbox();
      await box.load();
      await WhatsNewNotice.addIfDue(box, '0.1.2', now: _t0);
      await box.markRead('WhatsNew:0.1.2');
      final later = _inbox();
      await later.load();
      expect(later.notices.single.whatsNew, isTrue);
      expect(later.notices.single.read, isTrue);
      expect(later.unreadCount.value, 0);
    });

    test('is not an update: a bad version in the tag or two kinds in one are refused', () {
      expect(Notice.tryFromJson({'tag': 'WhatsNew:bogus', 'notes': '', 'receivedAt': 1, 'whats_new': true}), isNull);
      expect(Notice.tryFromJson({'tag': 'Welcome', 'notes': '', 'receivedAt': 1, 'whats_new': true, 'welcome': true}), isNull);
      expect(Notice.tryFromJson({'tag': 'WhatsNew:0.1.2', 'notes': '', 'receivedAt': 1, 'whats_new': true}), isNotNull);
    });
  });

  group('the Notifications row', () {
    test('is a What\'s new row titled with the page title; reading it saves read', () async {
      final box = _inbox();
      await box.load();
      await WhatsNewNotice.addIfDue(box, '0.1.2', now: _t0);
      final repo = UpdatesNewsRepository(box);
      addTearDown(repo.dispose);
      final items = await repo.watchNews().first;
      expect(items.single.kind, NewsKind.whatsNew);
      expect(items.single.title, kWhatsNewPagerTitle);
      expect(items.single.isUnread, isTrue);
      await repo.markRead(items.single.id, _t0);
      final later = _inbox();
      await later.load();
      expect(later.unreadCount.value, 0); // saved at once, a restart does not light the bell
    });
  });

  group('opened to read', () {
    Future<void> pump(WidgetTester tester, UpdatesInbox box, List<String> written) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () => openWhatsNewToRead(
                context,
                installedVersionName: '0.1.2',
                writeSeenVersion: (v) async => written.add(v),
                openSettings: () {},
                openBackup: () {},
                inbox: box,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
    }

    testWidgets('shows Back and no Got it; opening marks the item read, stores the version, clears the pill', (tester) async {
      final box = _inbox();
      await box.load();
      await WhatsNewNotice.addIfDue(box, '0.1.2', now: _t0);
      final written = <String>[];
      await pump(tester, box, written);
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whatsNewPager')), findsOneWidget);
      expect(find.byKey(const Key('whatsNewGotIt')), findsNothing);
      expect(find.byKey(const Key('whatsNewBack')), findsOneWidget);
      expect(box.unreadCount.value, 0);
      expect(written, ['0.1.2']);
      expect(WhatsNewProcess.pillCleared, isTrue);
      await tester.tap(find.byKey(const Key('whatsNewBack')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whatsNewPager')), findsNothing);
    });

    testWidgets('the first-open page keeps its Got it, and Got it leaves the bell item unread', (tester) async {
      final box = _inbox();
      await box.load();
      final written = <String>[];
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              maybeShowWhatsNew(
                context,
                installedVersionName: '0.1.2',
                readSeenVersion: () async => '0.1.1',
                readOnboardingComplete: () async => true,
                writeSeenVersion: (v) async => written.add(v),
                startupNoticeShown: () => false,
                openSettings: () {},
                openBackup: () {},
                inbox: box,
              );
            });
            return const Scaffold(body: Text('HOME'));
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whatsNewGotIt')), findsOneWidget);
      expect(find.byKey(const Key('whatsNewBack')), findsNothing);
      expect(box.notices.single.whatsNew, isTrue); // added when the page was due
      expect(box.unreadCount.value, 1);
      await tester.tap(find.byKey(const Key('whatsNewGotIt')));
      await tester.pumpAndSettle();
      expect(box.unreadCount.value, 1); // the bell stays lit until it is opened from Notifications
      expect(written, ['0.1.2']);
    });

    testWidgets('closing the first-open page with Back keeps the bell item unread', (tester) async {
      final box = _inbox();
      await box.load();
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              maybeShowWhatsNew(
                context,
                installedVersionName: '0.1.2',
                readSeenVersion: () async => '0.1.1',
                readOnboardingComplete: () async => true,
                writeSeenVersion: (v) async {},
                startupNoticeShown: () => false,
                openSettings: () {},
                openBackup: () {},
                inbox: box,
              );
            });
            return const Scaffold(body: Text('HOME'));
          },
        ),
      ));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(box.notices.single.whatsNew, isTrue);
      expect(box.unreadCount.value, 1);
    });
  });
}