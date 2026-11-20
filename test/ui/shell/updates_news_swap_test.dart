// 0.2.1 #3: before install the News has the Update row and the Updates page the Update button;
// after install (installed version >= notice) both are gone and the What's new item takes their place.
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/debug_release_seed.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/ui/screens/updates/updates_screen.dart';
import 'package:mmogo/ui/shell/updates_news_repository.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _release(String tag) => {
  'tag': tag,
  'notes': 'Notes.',
  'receivedAt': DateTime(2026, 11, 1).millisecondsSinceEpoch,
  'read': false,
};

void _stored(List<Map<String, Object?>> l) => SharedPreferences.setMockInitialValues({'updates_inbox_v1': jsonEncode(l)});

/// The news list once the repository has loaded the inbox and run the swap (its last emission).
Future<List<NewsItem>> _news(UpdatesInbox inbox, String installed, {bool content = true}) async {
  final repo = UpdatesNewsRepository(inbox, installedVersion: () => installed, hasContentFor: (_) => content);
  List<NewsItem> last = const [];
  final sub = repo.watchNews().listen((l) => last = l);
  await inbox.ensureLoaded();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await sub.cancel();
  repo.dispose();
  return last;
}

void main() {
  test('before install: the Update row is there and no What\'s new item is added', () async {
    _stored([_release('v0.2.1')]);
    final inbox = UpdatesInbox(installedVersion: () => '0.2.0');
    final items = await _news(inbox, '0.2.0');
    expect(inbox.updateAvailable, isTrue);
    expect(items.where((n) => n.kind == NewsKind.update), hasLength(1));
    expect(items.where((n) => n.kind == NewsKind.whatsNew), isEmpty);
    expect(inbox.prunedReleaseTags, isEmpty);
  });

  test('after install: the Update row is gone and the What\'s new item is in its place', () async {
    _stored([_release('v0.2.1')]);
    final inbox = UpdatesInbox(installedVersion: () => '0.2.1');
    final items = await _news(inbox, '0.2.1');
    expect(inbox.updateAvailable, isFalse);
    expect(inbox.prunedReleaseTags, ['v0.2.1']);
    expect(items.where((n) => n.kind == NewsKind.update), isEmpty);
    expect(items.where((n) => n.kind == NewsKind.whatsNew).map((n) => n.id), [Notice.whatsNewTagFor('0.2.1')]);
  });

  test('after install with no pages for that version: the row is gone and nothing is added', () async {
    _stored([_release('v0.2.1')]);
    final inbox = UpdatesInbox(installedVersion: () => '0.2.1');
    final items = await _news(inbox, '0.2.1', content: false);
    expect(items, isEmpty);
  });

  test('the swap is not repeated: only one What\'s new item', () async {
    _stored([_release('v0.2.1')]);
    final inbox = UpdatesInbox(installedVersion: () => '0.2.1');
    await _news(inbox, '0.2.1');
    await _news(inbox, '0.2.1');
    expect(inbox.notices.where((n) => n.whatsNew), hasLength(1));
  });

  testWidgets('Updates page: Update button before install, none after; the entry stays', (tester) async {
    Future<void> pump(String installed) async {
      WhatsNewProcess.resetForTest();
      final inbox = UpdatesInbox(installedVersion: () => installed);
      await tester.pumpWidget(
        MaterialApp(home: UpdatesScreen(key: UniqueKey(), inbox: inbox, installedVersionName: installed, readSeenVersion: () async => null)),
      );
      await tester.pumpAndSettle();
    }

    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _stored([_release('v0.2.1')]);
    await pump('0.2.0');
    expect(find.text('Update'), findsOneWidget);
    _stored([_release('v0.2.1')]);
    await pump('0.2.1');
    expect(find.text('Update'), findsNothing);
    expect(find.byKey(const Key('whatsNewEntry')), findsOneWidget);
  });

  test('debug seed: adds a notice one patch newer than installed (debug only)', () async {
    SharedPreferences.setMockInitialValues({});
    final inbox = UpdatesInbox(installedVersion: () => '0.2.0');
    final tag = await seedNewerReleaseNotice(inbox, installedVersionName: '0.2.0');
    expect(kDebugMode, isTrue);
    expect(tag, '0.2.1');
    expect(inbox.updateAvailable, isTrue);
    expect(await seedNewerReleaseNotice(inbox, installedVersionName: '0.2.0'), isNull, reason: 'one per release');
  });
}
