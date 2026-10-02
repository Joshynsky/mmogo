// ignore_for_file: text_direction_code_point_in_literal
// B26: UpdateCheckService policy against a fake client (no socket is ever
// opened). Prefs are in-memory shared_preferences.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/data/updates/release_info.dart';
import 'package:mmogo/data/updates/update_check_client.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_update_check_client.dart';

final t0 = DateTime(2026, 10, 2, 9, 0);
const newer = ReleaseInfo(tag: 'v0.2.0', notes: 'Shiny');

class _Rig {
  _Rig({ReleaseInfo? result, Object? error, String installed = '0.1.1'}) {
    fake = FakeUpdateCheckClient(result: result, error: error);
    inbox = UpdatesInbox(installedVersion: () => installed);
    service = UpdateCheckService(
      clientFactory: () {
        constructions++;
        return fake;
      },
      inbox: inbox,
      installedVersion: () => installed,
    );
  }
  late final FakeUpdateCheckClient fake;
  late final UpdatesInbox inbox;
  late final UpdateCheckService service;
  int constructions = 0;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('prefs defaults: switch on, never checked', () async {
    expect(UpdatePrefs.keyEnabled, 'update_check_enabled');
    expect(UpdatePrefs.keyLastCheckAt, 'update_last_check_at');
    expect(await UpdatePrefs.readEnabled(), isTrue);
    expect(await UpdatePrefs.readLastCheckAt(), isNull);
  });

  test('switch_off_makes_zero_client_calls (and builds no client)', () async {
    SharedPreferences.setMockInitialValues({'update_check_enabled': false});
    final r = _Rig(result: newer);
    expect(await r.service.maybeCheck(now: t0), isFalse);
    expect(r.constructions, 0);
    expect(r.fake.calls, 0);
    expect(r.inbox.notices, isEmpty);
    expect(await UpdatePrefs.readLastCheckAt(), isNull);
  });

  test('switch is read at call time (turned off after the service was built)', () async {
    final r = _Rig(result: newer);
    await UpdatePrefs.writeEnabled(false);
    await r.service.maybeCheck(now: t0);
    expect(r.constructions, 0);
    // Turning it back on lets a later call in the same process still check
    // because the off-call did not use up the launch's attempt.
    await UpdatePrefs.writeEnabled(true);
    expect(await r.service.maybeCheck(now: t0), isTrue);
    expect(r.fake.calls, 1);
  });

  test('first run: one request, notice added unread, timestamp written', () async {
    final r = _Rig(result: newer);
    expect(await r.service.maybeCheck(now: t0), isTrue);
    expect(r.fake.calls, 1);
    expect(r.inbox.notices.single.tag, 'v0.2.0');
    expect(r.inbox.notices.single.notes, 'Shiny');
    expect(r.inbox.notices.single.read, isFalse);
    expect(r.inbox.unreadCount.value, 1);
    expect(r.inbox.notices.single.receivedAt, t0);
    expect(await UpdatePrefs.readLastCheckAt(), t0);
  });

  test('success_resets_the_week', () async {
    final r = _Rig(result: newer);
    await UpdatePrefs.writeLastCheckAt(t0.subtract(const Duration(days: 30)));
    await r.service.maybeCheck(now: t0);
    expect(await UpdatePrefs.readLastCheckAt(), t0);
    // A fresh process one day later: not due.
    final r2 = _Rig(result: newer);
    expect(await r2.service.maybeCheck(now: t0.add(const Duration(days: 1))), isFalse);
    expect(r2.fake.calls, 0);
  });

  group('cap_boundary', () {
    test('6d23h59m: no request', () async {
      await UpdatePrefs.writeLastCheckAt(t0);
      final r = _Rig(result: newer);
      await r.service.maybeCheck(now: t0.add(const Duration(days: 6, hours: 23, minutes: 59)));
      expect(r.fake.calls, 0);
      expect(r.constructions, 0);
    });
    test('exactly 7d: request', () async {
      await UpdatePrefs.writeLastCheckAt(t0);
      final r = _Rig(result: newer);
      await r.service.maybeCheck(now: t0.add(const Duration(days: 7)));
      expect(r.fake.calls, 1);
    });
    test('7d and a second: request', () async {
      await UpdatePrefs.writeLastCheckAt(t0);
      final r = _Rig(result: newer);
      await r.service.maybeCheck(now: t0.add(const Duration(days: 7, seconds: 1)));
      expect(r.fake.calls, 1);
    });
  });

  test('clock_rollback_due_once', () async {
    await UpdatePrefs.writeLastCheckAt(t0.add(const Duration(days: 400))); // far future
    final r = _Rig(result: newer);
    expect(await r.service.maybeCheck(now: t0), isTrue);
    expect(r.fake.calls, 1);
    // The success rewrote the stamp to now, so the next launch is not due.
    expect(await UpdatePrefs.readLastCheckAt(), t0);
    final r2 = _Rig(result: newer);
    await r2.service.maybeCheck(now: t0.add(const Duration(hours: 1)));
    expect(r2.fake.calls, 0);
  });

  group('failure_does_not_use_up_the_week', () {
    final errors = <String, Object>{
      'SocketException': const SocketException('offline'),
      'HandshakeException': const HandshakeException('tls'),
      'TimeoutException': TimeoutException('slow'),
      'HttpException': const HttpException('status 500'),
      'FormatException': const FormatException('bad json'),
      'StateError': StateError('boom'),
      'ArgumentError': ArgumentError('x'),
      'plain String': 'a thrown string',
      'Error subclass': UnsupportedError('nope'),
    };
    errors.forEach((name, e) {
      test('silent_on_every_exception_type: $name', () async {
        await UpdatePrefs.writeLastCheckAt(t0.subtract(const Duration(days: 10)));
        final before = await UpdatePrefs.readLastCheckAt();
        final r = _Rig(error: e);
        expect(await r.service.maybeCheck(now: t0), isFalse); // returns, never throws
        expect(r.fake.calls, 1);
        expect(r.inbox.notices, isEmpty);
        expect(await UpdatePrefs.readLastCheckAt(), before); // no timestamp
        // The next launch (new process) tries again: the week was not used up.
        final r2 = _Rig(result: newer);
        expect(await r2.service.maybeCheck(now: t0.add(const Duration(minutes: 5))), isTrue);
        expect(r2.fake.calls, 1);
      });
    });

    test('never-checked user who was offline stays "never"', () async {
      final r = _Rig(error: const SocketException('offline'));
      await r.service.maybeCheck(now: t0);
      expect(await UpdatePrefs.readLastCheckAt(), isNull);
    });
  });

  test('failed_attempt_writes_no_timestamp_and_second_call_in_same_process_makes_zero_client_calls', () async {
    final r = _Rig(error: const SocketException('offline'));
    await r.service.maybeCheck(now: t0);
    expect(await UpdatePrefs.readLastCheckAt(), isNull);
    expect(r.fake.calls, 1);
    await r.service.maybeCheck(now: t0.add(const Duration(minutes: 1)));
    await r.service.maybeCheck(now: t0.add(const Duration(days: 30)));
    expect(r.fake.calls, 1);
    expect(r.constructions, 1);
  });

  test('two concurrent calls make one request', () async {
    final r = _Rig(result: newer);
    final a = r.service.maybeCheck(now: t0);
    final b = r.service.maybeCheck(now: t0);
    await Future.wait([a, b]);
    expect(r.fake.calls, 1);
  });

  test('a client factory that throws is silent too', () async {
    final service = UpdateCheckService(
      clientFactory: () => throw StateError('cannot build'),
      inbox: UpdatesInbox(installedVersion: () => '0.1.1'),
    );
    expect(await service.maybeCheck(now: t0), isFalse);
    expect(await UpdatePrefs.readLastCheckAt(), isNull);
  });

  group('newer_only_adds_notice', () {
    for (final tag in ['v0.1.1', '0.1.1', 'v0.1.0', '0.0.9']) {
      test('$tag is not newer than 0.1.1: no notice, but the check counts as done', () async {
        final r = _Rig(result: ReleaseInfo(tag: tag, notes: ''));
        expect(await r.service.maybeCheck(now: t0), isTrue);
        expect(r.inbox.notices, isEmpty);
        expect(await UpdatePrefs.readLastCheckAt(), t0);
      });
    }
    test('0.1.10 is newer than 0.1.9 (numeric)', () async {
      final r = _Rig(result: const ReleaseInfo(tag: '0.1.10', notes: ''), installed: '0.1.9');
      await r.service.maybeCheck(now: t0);
      expect(r.inbox.notices.single.tag, '0.1.10');
    });
  });

  test('duplicate_tag_not_readded (a later week, same release)', () async {
    final r = _Rig(result: newer);
    await r.service.maybeCheck(now: t0);
    await r.inbox.markAllRead();
    final r2 = _Rig(result: newer);
    await r2.service.maybeCheck(now: t0.add(const Duration(days: 8)));
    expect(r2.fake.calls, 1);
    expect(r2.inbox.notices, hasLength(1));
    expect(r2.inbox.notices.single.read, isTrue, reason: 'a re-seen release must not turn unread again');
    expect(r2.inbox.unreadCount.value, 0);
    expect(await UpdatePrefs.readLastCheckAt(), t0.add(const Duration(days: 8)));
  });

  test('hostile notes are clean in the inbox', () async {
    final r = _Rig(result: ReleaseInfo(tag: '0.2.0', notes: 'a‮b\u0000c'));
    await r.service.maybeCheck(now: t0);
    expect(r.inbox.notices.single.notes, 'abc');
  });

  test('a new release after an older notice: both kept, newest first', () async {
    final r = _Rig(result: newer);
    await r.service.maybeCheck(now: t0);
    final r2 = _Rig(result: const ReleaseInfo(tag: '0.3.0', notes: ''));
    await r2.service.maybeCheck(now: t0.add(const Duration(days: 8)));
    expect(r2.inbox.notices.map((x) => x.tag), ['0.3.0', 'v0.2.0']);
  });

  test('the request layer is the only thing the service can reach (type check)', () {
    expect(UpdateCheckClient(), isA<UpdateCheckSource>());
    expect(UpdateCheckService.interval, const Duration(days: 7));
  });

  test('maybeCheck returns without waiting on a slow client being awaited by startup', () async {
    // The caller does not await it: the call returns a Future immediately.
    final slow = Completer<ReleaseInfo>();
    final service = UpdateCheckService(
      clientFactory: () => _Slow(slow.future),
      inbox: UpdatesInbox(installedVersion: () => '0.1.1'),
    );
    var done = false;
    final f = service.maybeCheck(now: t0).then((_) => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(done, isFalse); // still waiting; nothing blocked the test body
    slow.complete(newer);
    await f;
    expect(done, isTrue);
  });
}

class _Slow implements UpdateCheckSource {
  _Slow(this.f);
  final Future<ReleaseInfo> f;
  @override
  Future<ReleaseInfo> fetchLatest() => f;
}
