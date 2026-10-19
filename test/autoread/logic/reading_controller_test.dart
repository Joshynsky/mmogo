@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/method_channel_autoread_bridge.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';

import 'reading_fakes.dart';

({ReadingController c, FakeReadingBridge b, FakeReadingPrefs p, FakeGenerationStore s}) _make({
  bool consent = true,
  FakeReadingBridge? bridge,
}) {
  final b = bridge ?? FakeReadingBridge();
  final p = FakeReadingPrefs();
  if (consent) p.data[kReadingConsentKey] = kReadingConsentVersion;
  final s = FakeGenerationStore();
  return (c: ReadingController(bridge: b, store: s, prefs: p), b: b, p: p, s: s);
}

void main() {
  group('turnOn', () {
    test('asks for both permissions, then setEnabled(true), in that order', () async {
      final m = _make();
      final r = await m.c.turnOn();
      expect(r.isOn, isTrue);
      expect(m.b.calls, ['getState', 'requestPermissions', 'setEnabled:true']);
      expect(m.b.enabled, isTrue);
    });

    test('permissions already granted: no system dialog, still setEnabled(true)', () async {
      final m = _make(bridge: FakeReadingBridge(smsGranted: true, notifGranted: true));
      expect((await m.c.turnOn()).isOn, isTrue);
      expect(m.b.calls, ['getState', 'setEnabled:true']);
    });

    test('without consent nothing is asked of the system', () async {
      final m = _make(consent: false);
      final r = await m.c.turnOn();
      expect(r.outcome, TurnOnOutcome.needsConsent);
      expect(m.b.calls, isEmpty);
    });

    test('a consent from an older text version is not consent', () async {
      final m = _make(consent: false);
      m.p.data[kReadingConsentKey] = kReadingConsentVersion - 1;
      expect(await m.c.hasConsent(), isFalse);
    });

    test('SMS denied: Denied.sms, Read stays off, setEnabled never called', () async {
      final b = FakeReadingBridge()..grantSms = false;
      final m = _make(bridge: b);
      final r = await m.c.turnOn();
      expect(r.outcome, TurnOnOutcome.denied);
      expect(r.denied, Denied.sms);
      expect(b.calls, isNot(contains('setEnabled:true')));
      expect(b.enabled, isFalse);
    });

    test('notifications denied: Denied.notifications, Read stays off', () async {
      final b = FakeReadingBridge()..grantNotif = false;
      final m = _make(bridge: b);
      final r = await m.c.turnOn();
      expect(r.denied, Denied.notifications);
      expect(b.enabled, isFalse);
      expect(b.calls, isNot(contains('setEnabled:true')));
    });

    test('both denied: Denied.blocked', () async {
      final b = FakeReadingBridge()
        ..grantSms = false
        ..grantNotif = false;
      final m = _make(bridge: b);
      expect((await m.c.turnOn()).denied, Denied.blocked);
      expect(b.enabled, isFalse);
    });

    test('a permission error from the platform maps to blocked; others to failed', () async {
      final b1 = FakeReadingBridge()..requestError = const AutoReadBridgeException('permission');
      expect((await _make(bridge: b1).c.turnOn()).denied, Denied.blocked);
      final b2 = FakeReadingBridge()..requestError = const AutoReadBridgeException('failed');
      expect((await _make(bridge: b2).c.turnOn()).outcome, TurnOnOutcome.failed);
      expect(b2.enabled, isFalse);
    });

    test('setEnabled throwing or answering false is a failure, not "on"', () async {
      final b1 = FakeReadingBridge()..setEnabledError = const AutoReadBridgeException('failed');
      expect((await _make(bridge: b1).c.turnOn()).outcome, TurnOnOutcome.failed);
    });
  });

  group('turnOff', () {
    test('only switches capture off: waiting and held messages are kept', () async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 3);
      final m = _make(bridge: b);
      m.p.data[pendingKey(1)] = 'x';
      m.p.data[pendingKey(2)] = 'y';
      m.p.data['autoread_generation_v1'] = 5;
      final r = await m.c.turnOff();
      expect(r, TurnOffResult.off);
      expect(m.s.bumps, 0);
      expect(m.p.data.keys.where((k) => k.startsWith('autoread_pending_v1.')).length, 2);
      expect(m.p.data['autoread_generation_v1'], 5);
      expect(m.p.data[kReadingConsentKey], kReadingConsentVersion); // consent stays
      expect(b.calls, ['setEnabled:false']);
      expect(b.enabled, isFalse);
      expect(b.heldCount, 3);
    });

    test('the switch cannot be turned off: stillOn, nothing cleared', () async {
      final b = FakeReadingBridge(enabled: true)..setEnabledIgnoresOff = true;
      final m = _make(bridge: b);
      m.p.data[pendingKey(1)] = 'x';
      expect(await m.c.turnOff(), TurnOffResult.stillOn);
      expect(m.p.data.keys.where((k) => k.startsWith('autoread_pending_v1.')).length, 1);
    });

    test('a bridge error is stillOn', () async {
      final b = FakeReadingBridge(enabled: true)..setEnabledError = StateError('x');
      expect(await _make(bridge: b).c.turnOff(), TurnOffResult.stillOn);
    });

    test('idempotent: a second call ends in the same state', () async {
      final m = _make(bridge: FakeReadingBridge(enabled: true, heldCount: 1));
      expect(await m.c.turnOff(), TurnOffResult.off);
      expect(await m.c.turnOff(), TurnOffResult.off);
      expect(m.b.enabled, isFalse);
    });
  });

  group('state and deleteHeld', () {
    test('state mirrors the bridge; broken only when on and a permission is missing', () async {
      final m = _make(bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: false, heldCount: 4));
      final s = await m.c.state();
      expect(s.on, isTrue);
      expect(s.smsAllowed, isTrue);
      expect(s.notificationsAllowed, isFalse);
      expect(s.heldCount, 4);
      expect(s.broken, isTrue);
      m.b.enabled = false;
      expect((await m.c.state()).broken, isFalse);
      m.b.enabled = true;
      m.b.notifGranted = true;
      expect((await m.c.state()).broken, isFalse);
    });

    test('a platform failure reads as not available, off, not broken', () async {
      final b = FakeReadingBridge()..stateError = const AutoReadBridgeException('not_available');
      final s = await _make(bridge: b).c.state();
      expect(s.available, isFalse);
      expect(s.on, isFalse);
      expect(s.broken, isFalse);
    });

    test('deleteHeld clears and reads back; false when messages remain', () async {
      final b = FakeReadingBridge(enabled: true, heldCount: 2);
      final m = _make(bridge: b);
      expect(await m.c.deleteHeld(), isTrue);
      expect(b.calls, contains('deleteAllHeld'));
      expect(m.s.bumps, 1); // waiting items are cleared too
      final b2 = FakeReadingBridge(enabled: true, heldCount: 2)..deleteHeldKeepsMessages = true;
      expect(await _make(bridge: b2).c.deleteHeld(), isFalse);
    });

    test('recordConsent stores the version and fails closed when it cannot', () async {
      final m = _make(consent: false);
      expect(await m.c.hasConsent(), isFalse);
      expect(await m.c.recordConsent(), isTrue);
      expect(await m.c.hasConsent(), isTrue);
      final n = _make(consent: false);
      n.p.failWrite = true;
      expect(await n.c.recordConsent(), isFalse);
      expect(await n.c.hasConsent(), isFalse);
    });

    test('the consent key name is the one handed to integration', () {
      expect(kReadingConsentKey, 'autoread_consent_version_v1');
    });
  });
}
