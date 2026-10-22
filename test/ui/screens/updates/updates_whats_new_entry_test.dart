// 0.1.2 S11a (A2, A5, A6, A7): the one synthetic "What's new in mmogo 0.1.2"
// entry on the Updates page. Fake update client and service, a fake storage
// bridge, injected seen read / write / installed version, stub Settings and
// Backup routes; prefs are the mock store. The real Settings and Backup pages
// are never built and nothing touches a network.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/release_info.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/screens/updates/updates_screen.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/updates/fake_update_check_client.dart';
import '../../../support/fake_storage_bridge.dart';

const _entry = Key('whatsNewEntry');
const _entryButton = Key('whatsNewEntryButton');
const _pill = Key('whatsNewEntryPill');
const _pager = Key('whatsNewPager');

class _Rig {
  _Rig({this.seen, this.stored = const []});
  final String? seen;
  final List<Map<String, Object?>> stored;
  final written = <String>[];
  final opened = <String>[];
  late final UpdatesInbox inbox = UpdatesInbox(installedVersion: () => '0.1.1');
  late final FakeUpdateCheckClient client = FakeUpdateCheckClient(result: const ReleaseInfo(tag: 'v0.1.1', notes: ''));
  late final UpdateCheckService service = UpdateCheckService(
    clientFactory: () => client,
    inbox: inbox,
    installedVersion: () => '0.1.1',
  );
}

Future<_Rig> _pump(WidgetTester tester, {String? seen, List<Map<String, Object?>> stored = const [], bool reset = true}) async {
  SharedPreferences.setMockInitialValues({if (stored.isNotEmpty) 'updates_inbox_v1': jsonEncode(stored)});
  if (reset) WhatsNewProcess.resetForTest();
  StorageBridge.instance = FakeStorageBridge();
  final rig = _Rig(seen: seen, stored: stored);
  await rig.inbox.load();
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(rig));
  await tester.pumpAndSettle();
  return rig;
}

Widget _app(_Rig rig) => MaterialApp(
  routes: {
    '/settings': (_) => Scaffold(appBar: AppBar(title: const Text('SETTINGS STUB'))),
    '/backup': (_) => Scaffold(appBar: AppBar(title: const Text('BACKUP STUB'))),
    '/updates': (ctx) => UpdatesScreen(
      inbox: rig.inbox,
      service: rig.service,
      readSeenVersion: () async => rig.seen,
      writeSeenVersion: (v) async => rig.written.add(v),
      installedVersionName: '0.1.1',
      openSettings: () {
        rig.opened.add('settings');
        Navigator.of(ctx).pushNamed('/settings');
      },
      openBackup: () {
        rig.opened.add('backup');
        Navigator.of(ctx).pushNamed('/backup');
      },
    ),
  },
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('goUpdates'),
          onPressed: () => Navigator.of(context).pushNamed('/updates'),
          child: const Text('HOME'),
        ),
      ),
    ),
  ),
);

Future<void> _openUpdates(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('goUpdates')));
  await tester.pumpAndSettle();
}

Future<void> _openPager(WidgetTester tester) async {
  await tester.tap(find.byKey(_entryButton));
  await tester.pumpAndSettle();
}

Map<String, Object?> _notice(String tag, {bool read = false}) => {
  'tag': tag,
  'notes': 'Notes.',
  'receivedAt': DateTime(2026, 10, 2).millisecondsSinceEpoch,
  'read': read,
};

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('whatsNewBack')));
  await tester.pumpAndSettle();
}

void main() {
  group('the entry is always there', () {
    testWidgets('with an EMPTY notice list the entry and the empty state show, and there is no footnote', (tester) async {
      final rig = await _pump(tester);
      await _openUpdates(tester);
      expect(rig.inbox.notices, isEmpty);
      expect(find.byKey(_entry), findsOneWidget);
      expect(find.text(kWhatsNewPagerTitle), findsOneWidget);
      expect(find.text(kWhatsNewEntryBody), findsOneWidget);
      expect(find.byKey(const Key('updatesEmpty')), findsOneWidget);
      expect(find.byKey(const Key('updatesFootnote')), findsNothing);
    });

    testWidgets('with a release notice the entry sits under it and ends the page (no footnote after it)', (tester) async {
      await _pump(tester, stored: [_notice('v0.1.3')]);
      await _openUpdates(tester);
      expect(find.byKey(const Key('notice-v0.1.3')), findsOneWidget);
      expect(find.byKey(const Key('updatesEmpty')), findsNothing);
      final noticeY = tester.getTopLeft(find.byKey(const Key('notice-v0.1.3'))).dy;
      final entryY = tester.getTopLeft(find.byKey(_entry)).dy;
      expect(find.byKey(const Key('updatesFootnote')), findsNothing);
      expect(noticeY, lessThan(entryY));
    });

    testWidgets('the entry button has its own key and label, apart from the "See what\'s new" browser buttons', (tester) async {
      await _pump(tester, stored: [_notice('v0.1.3')]);
      await _openUpdates(tester);
      expect(find.byKey(_entryButton), findsOneWidget);
      expect(find.byKey(const Key('noticeSeeWhatsNew')), findsOneWidget);
      expect(kWhatsNewEntryButton, isNot(kUpdatesSeeWhatsNew));
      expect(find.text(kUpdatesSeeWhatsNew), findsOneWidget);
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.byKey(_entryButton));
      expect(node.label, kWhatsNewPagerTitle);
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('the entry is synthetic: not in the inbox, not counted as unread', (tester) async {
      final rig = await _pump(tester);
      await _openUpdates(tester);
      expect(rig.inbox.notices, isEmpty);
      expect(rig.inbox.unreadCount.value, 0);
      await _openPager(tester);
      expect(rig.inbox.notices, isEmpty);
      expect(rig.inbox.unreadCount.value, 0);
    });

    testWidgets('the entry button does not open the browser', (tester) async {
      await _pump(tester);
      await _openUpdates(tester);
      final bridge = StorageBridge.instance as FakeStorageBridge;
      await _openPager(tester);
      expect(find.byKey(_pager), findsOneWidget);
      expect(bridge.openedUrls, isEmpty);
    });
  });

  group('the NEW pill', () {
    testWidgets('shown while the seen version is not 0.1.2', (tester) async {
      await _pump(tester, seen: '0.1.1');
      await _openUpdates(tester);
      expect(find.byKey(_pill), findsOneWidget);
    });

    testWidgets('not shown once 0.1.2 is stored as seen', (tester) async {
      await _pump(tester, seen: '0.1.2');
      await _openUpdates(tester);
      expect(find.byKey(_pill), findsNothing);
      expect(find.byKey(_entry), findsOneWidget);
    });

    testWidgets('opening Updates does not clear it; opening the pages does (Back or the system Back key)', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await _openUpdates(tester);
      expect(find.byKey(_pill), findsOneWidget);
      expect(WhatsNewProcess.pillCleared, isFalse);
      await _openPager(tester);
      expect(WhatsNewProcess.pillCleared, isTrue);
      await tester.binding.handlePopRoute(); // the system Back key: closed
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(find.byKey(_pill), findsNothing);
      expect(rig.written, ['0.1.1']);
    });

    testWidgets('leaving Updates clears it for this process: it is gone when the page is opened again', (tester) async {
      await _pump(tester, seen: '0.1.1');
      await _openUpdates(tester);
      expect(find.byKey(_pill), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(WhatsNewProcess.pillCleared, isTrue);
      await _openUpdates(tester);
      expect(find.byKey(_pill), findsNothing);
    });

    testWidgets('a cold start brings it back (no key stored): a fresh process state shows it again', (tester) async {
      await _pump(tester, seen: '0.1.1');
      await _openUpdates(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      WhatsNewProcess.resetForTest();
      await _openUpdates(tester);
      expect(find.byKey(_pill), findsOneWidget);
    });
  });

  group('the pages opened from the Updates entry (read only)', () {
    testWidgets('there is no Got it, only Back; Back returns to Updates, the version is stored, the pill is gone', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await _openUpdates(tester);
      await _openPager(tester);
      expect(find.byKey(const Key('whatsNewGotIt')), findsNothing);
      expect(find.byKey(const Key('whatsNewBack')), findsOneWidget);
      await _back(tester);
      expect(find.byKey(_pager), findsNothing);
      expect(find.byKey(_entry), findsOneWidget);
      expect(find.byKey(_pill), findsNothing);
      expect(rig.written, ['0.1.1']);
    });

    testWidgets('Change in Settings pushes the stub route over the page; Back returns to the open Weeks row; nothing more is marked', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await _openUpdates(tester);
      await _openPager(tester);
      await tester.tap(find.byKey(const Key('whatsNewItemHead-weeks')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
      await tester.pumpAndSettle();
      expect(find.text('SETTINGS STUB'), findsOneWidget);
      expect(rig.opened, ['settings']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(find.byKey(const Key('whatsNewItemBody-weeks')), findsOneWidget);
      expect(rig.written, ['0.1.1']); // opening the pages is what counted as seen, once
      expect(WhatsNewProcess.pillCleared, isTrue);
    });

    testWidgets('Open Backup and restore pushes the stub Backup route and marks nothing', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await _openUpdates(tester);
      await _openPager(tester);
      await tester.ensureVisible(find.byKey(const Key('whatsNewItemHead-backups')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whatsNewItemHead-backups')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whatsNewOpenBackup')));
      await tester.pumpAndSettle();
      expect(find.text('BACKUP STUB'), findsOneWidget);
      expect(rig.opened, ['backup']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whatsNewItemBody-backups')), findsOneWidget);
      expect(rig.written, ['0.1.1']);
    });
  });
}
