// B27 / B49: a 404 counts as a successful check, "Check for updates now"
// (CheckNowResult), the welcome notice rules, and the startup order. Fake
// client only; no socket is ever opened. Prefs are in-memory.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/data/updates/release_info.dart';
import 'package:mmogo/data/updates/update_check_client.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/data/updates/updates_startup.dart';
import 'package:mmogo/data/updates/welcome_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_update_check_client.dart';

final t0 = DateTime(2026, 10, 2, 9, 0);
const newer = ReleaseInfo(tag: 'v0.2.0', notes: 'Shiny');

class _Rig {
  _Rig({ReleaseInfo? result, Object? error}) {
    fake = FakeUpdateCheckClient(result: result, error: error);
    inbox = UpdatesInbox(installedVersion: () => '0.1.1');
    service = UpdateCheckService(
      clientFactory: () => fake,
      inbox: inbox,
      installedVersion: () => '0.1.1',
    );
  }
  late final FakeUpdateCheckClient fake;
  late final UpdatesInbox inbox;
  late final UpdateCheckService service;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a 404 (no release yet)', () {
    test('maybeCheck counts it as a successful check: timestamp written, nothing added, no error', () async {
      final r = _Rig(error: const NoReleaseYetException());
      expect(await r.service.maybeCheck(now: t0), isTrue);
      expect(await UpdatePrefs.readLastCheckAt(), t0);
      expect(r.inbox.notices, isEmpty);
    });

    test('so the next launch within the week makes no request', () async {
      final r = _Rig(error: const NoReleaseYetException());
      await r.service.maybeCheck(now: t0);
      final second = _Rig(error: const NoReleaseYetException());
      expect(await second.service.maybeCheck(now: t0.add(const Duration(days: 3))), isFalse);
      expect(second.fake.calls, 0);
    });

    test('other failures still write no timestamp (5xx, bad JSON, offline stay failures)', () async {
      for (final e in [
        const HttpExceptionLike(),
        const FormatException('bad json'),
        StateError('offline'),
      ]) {
        final r = _Rig(error: e);
        expect(await r.service.maybeCheck(now: t0), isFalse, reason: '$e');
        expect(await UpdatePrefs.readLastCheckAt(), isNull, reason: '$e');
      }
    });
  });

  group('checkNow', () {
    test('switch off: says off, no client call, no timestamp', () async {
      SharedPreferences.setMockInitialValues({'update_check_enabled': false});
      final r = _Rig(result: newer);
      expect(await r.service.checkNow(now: t0), CheckNowResult.off);
      expect(r.fake.calls, 0);
      expect(await UpdatePrefs.readLastCheckAt(), isNull);
    });

    test('newer release: newVersion, notice in the inbox, timestamp written', () async {
      final r = _Rig(result: newer);
      expect(await r.service.checkNow(now: t0), CheckNowResult.newVersion);
      expect(r.inbox.notices.single.tag, 'v0.2.0');
      expect(await UpdatePrefs.readLastCheckAt(), t0);
    });

    test('same version: upToDate, timestamp written, nothing added', () async {
      final r = _Rig(result: const ReleaseInfo(tag: 'v0.1.1', notes: ''));
      expect(await r.service.checkNow(now: t0), CheckNowResult.upToDate);
      expect(r.inbox.notices, isEmpty);
      expect(await UpdatePrefs.readLastCheckAt(), t0);
    });

    test('404: upToDate', () async {
      final r = _Rig(error: const NoReleaseYetException());
      expect(await r.service.checkNow(now: t0), CheckNowResult.upToDate);
    });

    test('failure: failed, and no timestamp', () async {
      final r = _Rig(error: StateError('offline'));
      expect(await r.service.checkNow(now: t0), CheckNowResult.failed);
      expect(await UpdatePrefs.readLastCheckAt(), isNull);
    });

    test('is not held back by the weekly cap or the once-per-launch flag', () async {
      await UpdatePrefs.writeLastCheckAt(t0);
      final r = _Rig(result: newer);
      expect(await r.service.maybeCheck(now: t0.add(const Duration(days: 1))), isFalse);
      expect(r.fake.calls, 0);
      expect(await r.service.checkNow(now: t0.add(const Duration(days: 1))), CheckNowResult.newVersion);
      expect(r.fake.calls, 1);
      expect(await r.service.checkNow(now: t0.add(const Duration(days: 1))), CheckNowResult.newVersion);
      expect(r.fake.calls, 2);
      expect(r.inbox.notices, hasLength(1), reason: 'the same release is not added twice');
    });
  });

  group('welcome notice (B49)', () {
    test('fresh install: added, unread, flagged welcome, tag Welcome', () async {
      final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
      await inbox.load();
      expect(await WelcomeNotice.addIfFirstLaunch(inbox, now: t0), isTrue);
      final n = inbox.notices.single;
      expect(n.tag, 'Welcome');
      expect(n.welcome, isTrue);
      expect(n.read, isFalse);
      expect(n.receivedAt, t0);
      expect(inbox.unreadCount.value, 1);
    });

    test('is stored: a later launch (new instance, same prefs) does not add it again', () async {
      final a = UpdatesInbox(installedVersion: () => '0.1.1');
      await a.load();
      await WelcomeNotice.addIfFirstLaunch(a, now: t0);
      final b = UpdatesInbox(installedVersion: () => '0.1.1');
      await b.load();
      expect(b.hadStoredValue, isTrue);
      expect(await WelcomeNotice.addIfFirstLaunch(b), isFalse);
      expect(b.notices.single.welcome, isTrue, reason: 'the welcome notice survives a reload');
    });

    test('stays once read: no second welcome after markAllRead', () async {
      final a = UpdatesInbox(installedVersion: () => '0.1.1');
      await a.load();
      await WelcomeNotice.addIfFirstLaunch(a);
      await a.markAllRead();
      final b = UpdatesInbox(installedVersion: () => '0.1.1');
      await b.load();
      expect(await WelcomeNotice.addIfFirstLaunch(b), isFalse);
      expect(b.notices.single.read, isTrue);
    });

    test('not added when an inbox is already stored (even an empty list)', () async {
      SharedPreferences.setMockInitialValues({'updates_inbox_v1': '[]'});
      final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
      await inbox.load();
      expect(await WelcomeNotice.addIfFirstLaunch(inbox), isFalse);
      expect(inbox.notices, isEmpty);
    });

    test('not added when the update check has already run', () async {
      await UpdatePrefs.writeLastCheckAt(t0);
      final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
      await inbox.load();
      expect(await WelcomeNotice.addIfFirstLaunch(inbox), isFalse);
    });

    test('not added when the switch is already off (the text says checks are on)', () async {
      SharedPreferences.setMockInitialValues({'update_check_enabled': false});
      final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
      await inbox.load();
      expect(await WelcomeNotice.addIfFirstLaunch(inbox), isFalse);
    });

    test('a welcome flag with a version tag, or a Welcome tag without the flag, is dropped at load', () async {
      SharedPreferences.setMockInitialValues({
        'updates_inbox_v1': jsonEncode([
          {'tag': 'v0.3.0', 'notes': '', 'receivedAt': 5, 'read': false, 'welcome': true},
          {'tag': 'Welcome', 'notes': '', 'receivedAt': 4, 'read': false},
        ]),
      });
      final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
      await inbox.load();
      expect(inbox.notices, isEmpty);
    });

    test('a release notice later sits above the welcome notice', () async {
      final r = _Rig(result: newer);
      await r.inbox.load();
      await WelcomeNotice.addIfFirstLaunch(r.inbox, now: t0);
      await r.service.maybeCheck(now: t0.add(const Duration(minutes: 1)));
      expect(r.inbox.notices.map((n) => n.tag), ['v0.2.0', 'Welcome']);
      expect(r.inbox.unreadCount.value, 2);
    });
  });

  group('startUpdates (what Home runs after its first load)', () {
    test('fresh install: loads, adds the welcome notice, then the check runs', () async {
      final r = _Rig(result: newer);
      await startUpdates(inbox: r.inbox, service: r.service, now: t0);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(r.inbox.notices.any((n) => n.welcome), isTrue);
      expect(r.fake.calls, 1);
    });

    test('returning user with the switch off: inbox loaded, no welcome, no request', () async {
      SharedPreferences.setMockInitialValues({
        'update_check_enabled': false,
        'updates_inbox_v1': jsonEncode([
          {'tag': 'v0.2.0', 'notes': 'x', 'receivedAt': 5, 'read': false},
        ]),
      });
      final r = _Rig(result: newer);
      await startUpdates(inbox: r.inbox, service: r.service, now: t0);
      await Future<void>.delayed(Duration.zero);
      expect(r.inbox.unreadCount.value, 1, reason: 'the bell dot comes from the loaded inbox');
      expect(r.fake.calls, 0);
      expect(r.inbox.notices.any((n) => n.welcome), isFalse);
    });
  });
}

class HttpExceptionLike implements Exception {
  const HttpExceptionLike();
}
