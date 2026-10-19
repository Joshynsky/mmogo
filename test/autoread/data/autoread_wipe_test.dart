// §AUTOREAD.WIPE (I2): what Delete data does for auto-read, over the fakes, then
// through the real Delete data service and the real waiting repository. Invented
// data only.
//
// ignore_for_file: depend_on_referenced_packages
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/bridge/method_channel_autoread_bridge.dart';
import 'package:mmogo/autoread/data/autoread_wipe.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/data/maintenance/device_keys.dart';
import 'package:mmogo/data/maintenance/reset_resume.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/data_op_env.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;
import '../logic/reading_fakes.dart';

void main() {
  test('the consent key string equals the standard build copy', () {
    expect(kReadingConsentKey, kReadingConsentPrefsKey);
  });

  group('AutoReadWipe.run over the fakes', () {
    ({AutoReadWipe w, FakeReadingBridge b, FakeReadingPrefs p, List<String> refreshed}) make({
      bool nullController = false,
      Future<void> Function()? refresh,
    }) {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 3);
      final p = FakeReadingPrefs();
      p.data[kReadingConsentKey] = kReadingConsentVersion;
      p.data[pendingKey(1)] = 'x';
      p.data[pendingKey(2)] = 'y';
      final c = ReadingController(bridge: b, store: FakeGenerationStore(), prefs: p);
      final refreshed = <String>[];
      final w = AutoReadWipe(
        controller: () => nullController ? null : c,
        prefs: p,
        refresh: refresh ?? () async => refreshed.add('refresh'),
      );
      return (w: w, b: b, p: p, refreshed: refreshed);
    }

    test('off, held emptied, waiting keys and consent gone, then the refresh; Off comes before the wipe', () async {
      final m = make();
      expect(await m.w.run(), isTrue);
      expect(m.b.enabled, isFalse);
      expect(m.b.heldCount, 0);
      expect(m.p.data.keys.where((k) => k.startsWith(kPendingItemKeyPrefix)), isEmpty);
      expect(m.p.data.containsKey(kReadingConsentKey), isFalse);
      expect(m.refreshed, ['refresh']);
      expect(m.b.calls.indexOf('setEnabled:false'), lessThan(m.b.calls.indexOf('deleteAllHeld')));
    });

    test('Read will not turn off: false, no refresh', () async {
      final m = make();
      m.b.setEnabledIgnoresOff = true;
      expect(await m.w.run(), isFalse);
      expect(m.refreshed, isEmpty);
    });

    test('held messages that will not go: false', () async {
      final m = make();
      m.b.deleteHeldKeepsMessages = true;
      expect(await m.w.run(), isFalse);
      expect(m.refreshed, isEmpty);
    });

    test('a consent key that will not go: false', () async {
      final m = make();
      m.p.failRemove = true;
      expect(await m.w.run(), isFalse);
    });

    test('the platform cannot be asked: false', () async {
      final m = make();
      m.b.setEnabledError = const AutoReadBridgeException('failed');
      expect(await m.w.run(), isFalse);
      final n = make();
      n.b.stateError = const AutoReadBridgeException('not_available');
      expect(await n.w.run(), isFalse, reason: 'cannot read back: not proven');
    });

    test('no controller yet: false (fail closed)', () async {
      expect(await make(nullController: true).w.run(), isFalse);
    });

    test('a refresh that throws does not undo a verified wipe', () async {
      final m = make(refresh: () async => throw StateError('ui'));
      expect(await m.w.run(), isTrue);
    });
  });

  group('through Delete data', () {
    late DataOpEnv env;
    late FakeReadingBridge bridge;

    setUp(() async {
      env = await DataOpEnv.create();
      await env.populateAll();
      bridge = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 2);
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(kReadingConsentKey, kReadingConsentVersion);
      await sp.setString(pendingKey(7), '{}');
    });
    tearDown(() async {
      ResetEnv.defaultDeviceWipe = null;
      await env.dispose();
    });

    ResetEnv hooked({Future<void> Function()? refresh}) {
      final c = ReadingController(bridge: bridge, store: FakeGenerationStore(), prefs: SharedReadingPrefs());
      final wipe = AutoReadWipe(controller: () => c, refresh: refresh);
      final base = env.resetEnv();
      return ResetEnv(
        db: env.db,
        dbFactory: base.dbFactory,
        safety: env.safety,
        prefs: env.prefs,
        bridge: () => env.bridge,
        fs: env.fs,
        nowMs: () => env.clockMs,
        deviceWipe: wipe.run,
        grantTimeout: const Duration(milliseconds: 300),
        flagReadTimeout: const Duration(milliseconds: 500),
      );
    }

    DeleteDataServiceImpl svc(ResetEnv e) =>
        DeleteDataServiceImpl(env: e, memory: env.memory(), gate: env.gate, quiesceBound: const Duration(milliseconds: 400));

    test('Level 1: switch off, held store emptied, consent gone, waiting keys gone, generation bumped, rows refreshed', () async {
      var refreshed = 0;
      final r = await svc(hooked(refresh: () async => refreshed++)).deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(bridge.enabled, isFalse);
      expect(bridge.heldCount, 0);
      final m = await env.prefsMap();
      expect(m.containsKey(kReadingConsentKey), isFalse);
      expect(m.keys.where((k) => k.startsWith(kPendingItemKeyPrefix)), isEmpty);
      expect(m[kPendingGenerationPrefsKey], 1, reason: 'bumped from absent');
      expect(refreshed, 1);
    });

    test('Level 1: a held store that will not empty is "did not finish"; fixing it and retrying completes', () async {
      bridge.deleteHeldKeepsMessages = true;
      final s = svc(hooked());
      final first = await s.deleteMyTransactions();
      expect(first.outcome, DeleteDataOutcome.notFinished);
      expect(first.failedStep, DeleteDataStep.queue);
      bridge.deleteHeldKeepsMessages = false;
      expect((await s.deleteMyTransactions()).outcome, DeleteDataOutcome.done);
      expect(bridge.heldCount, 0);
    });

    test('Level 2 cut short, then resumed at start-up: the wipe runs again and finishes', () async {
      bridge.deleteHeldKeepsMessages = true;
      final r = await svc(hooked()).resetApp();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect((await env.prefsMap()).containsKey(kResetPendingKey), isTrue);
      bridge.deleteHeldKeepsMessages = false;
      expect(await ResetResume.runIfPending(env: hooked()), isTrue);
      expect(bridge.enabled, isFalse);
      expect(bridge.heldCount, 0);
      expect(await env.prefsMap(), isEmpty);
    });
  });

  group('the on-screen rows refresh', () {
    test('after the wipe the real waiting repository shows nothing', () async {
      final now = DateTime(2026, 10, 19, 8);
      final fake = FakeAutoReadBridge(now: () => now);
      fake.hold(heldIdFor(1), kSampleSendMoney, now.subtract(const Duration(hours: 1)));
      fake.hold(heldIdFor(2), 'not a payment message', now.subtract(const Duration(hours: 2)));
      final store = InMemoryPendingStore();
      final repo = RealWaitingRepository(
        bridge: fake,
        store: store,
        service: AutoReadService(bridge: fake, store: store, savedCodes: _NoCodes(), now: () => now),
        now: () => now,
        timer: (a, f) => Timer(const Duration(days: 365), () {}), // never fires by itself
      );
      await repo.ingest();
      expect(await repo.watch().first, hasLength(2));

      final p = FakeReadingPrefs();
      final c = ReadingController(bridge: _OverFake(fake), store: store, prefs: p);
      final w = AutoReadWipe(controller: () => c, prefs: p, refresh: repo.ingest);
      expect(await w.run(), isTrue);
      expect(await repo.watch().first, isEmpty);
      repo.dispose();
    });
  });
}

class _NoCodes implements CodeLookup {
  @override
  Future<bool> contains(String displayCode) async => false;
}

/// The reading bridge over the held-store fake: delete-all acks every id.
class _OverFake implements ReadingBridge {
  _OverFake(this._f);
  final FakeAutoReadBridge _f;
  bool enabled = true;

  @override
  Future<AutoReadState> getState() async => AutoReadState(
      enabled: enabled, smsGranted: true, notifGranted: true, heldCount: (await _f.listHeldIds()).length);
  @override
  Future<bool> setEnabled(bool e) async => enabled = e;
  @override
  Future<void> deleteAllHeld() async {
    for (final id in await _f.listHeldIds()) {
      await _f.ackHeld(id, generation: await _f.readGeneration());
    }
  }

  @override
  Future<AutoReadPermissions> requestPermissions() => throw UnimplementedError();
  @override
  Future<void> openAppSettings() => throw UnimplementedError();
}
