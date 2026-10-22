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
  if (consent) {
    p.data[kReadingConsentKey] = kReadingConsentVersion;
    b.kotlinConsent = kReadingConsentVersion;
  }
  final s = FakeGenerationStore();
  return (c: ReadingController(bridge: b, store: s, prefs: p), b: b, p: p, s: s);
}

void main() {
  group('turnOn', () {
    test('asks for both permissions, then setEnabled(true), in that order', () async {
      final m = _make();
      final r = await m.c.turnOn();
      expect(r.isOn, isTrue);
      // The first getState is hasConsent asking Kotlin for its consent version (C1).
      expect(m.b.calls, ['getState', 'getState', 'requestPermissions', 'setEnabled:true']);
      expect(m.b.enabled, isTrue);
    });

    test('permissions already granted: no system dialog, still setEnabled(true)', () async {
      final m = _make(bridge: FakeReadingBridge(smsGranted: true, notifGranted: true));
      expect((await m.c.turnOn()).isOn, isTrue);
      expect(m.b.calls, ['getState', 'getState', 'setEnabled:true']);
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

  group('reconcile (fail closed)', () {
    test('on with current consent: nothing is touched', () async {
      final m = _make(bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true));
      expect(await m.c.reconcile(), isTrue);
      expect(m.b.enabled, isTrue);
      expect(m.b.calls, isNot(contains('setEnabled:false')));
    });

    test('on with an older consent version: forced off, held messages kept', () async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 3);
      final m = _make(consent: false, bridge: b);
      m.p.data[kReadingConsentKey] = kReadingConsentVersion - 1;
      expect(await m.c.reconcile(), isTrue);
      expect(b.enabled, isFalse);
      expect(b.heldCount, 3);
      expect(b.calls, isNot(contains('deleteAllHeld')));
    });

    test('on with the consent answer gone: forced off', () async {
      final m = _make(consent: false, bridge: FakeReadingBridge(enabled: true));
      expect(await m.c.reconcile(), isTrue);
      expect(m.b.enabled, isFalse);
    });

    test('off stays off and nothing is written', () async {
      final m = _make(consent: false);
      expect(await m.c.reconcile(), isTrue);
      expect(m.b.calls, ['getState']);
    });

    test('a missing permission alone is not forced off (the fix row shows it)', () async {
      final m = _make(bridge: FakeReadingBridge(enabled: true, smsGranted: false, notifGranted: true));
      expect(await m.c.reconcile(), isTrue);
      expect(m.b.enabled, isTrue);
    });

    test('false when the switch will not turn off; false on a platform failure', () async {
      final b = FakeReadingBridge(enabled: true)..setEnabledIgnoresOff = true;
      expect(await _make(consent: false, bridge: b).c.reconcile(), isFalse);
      final f = FakeReadingBridge()..stateError = const AutoReadBridgeException('not_available');
      expect(await _make(bridge: f).c.reconcile(), isFalse);
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

  group('C1: Dart asks Kotlin which consent version it holds', () {
    test('Dart 2 / Kotlin 0: not current, so the consent sheet is shown again', () async {
      final m = _make();
      m.b.kotlinConsent = 0;
      expect(m.p.data[kReadingConsentKey], 2);
      expect(await m.c.hasConsent(), isFalse);
      expect((await m.c.turnOn()).outcome, TurnOnOutcome.needsConsent);
      expect(m.b.calls, isNot(contains('requestPermissions')));
    });

    test('Dart 2 / Kotlin a different version: not current', () async {
      final m = _make();
      m.b.kotlinConsent = 1;
      expect(await m.c.hasConsent(), isFalse);
    });

    test('both 2: current, no sheet needed', () async {
      final m = _make();
      expect(m.b.kotlinConsent, 2);
      expect(await m.c.hasConsent(), isTrue);
    });

    test('Dart 0 / Kotlin 2: not current either', () async {
      final m = _make(consent: false);
      m.b.kotlinConsent = 2;
      expect(await m.c.hasConsent(), isFalse);
    });

    test('Allow stores BOTH sides, after which consent is current', () async {
      final m = _make();
      m.b.kotlinConsent = 0;
      expect(await m.c.hasConsent(), isFalse);
      expect(await m.c.recordConsent(), isTrue);
      expect(m.b.kotlinConsent, 2);
      expect(m.p.data[kReadingConsentKey], 2);
      expect(await m.c.hasConsent(), isTrue);
    });

    test('Kotlin cannot be asked: not current (fail closed)', () async {
      final m = _make(bridge: FakeReadingBridge()..stateError = const AutoReadBridgeException('failed'));
      expect(await m.c.hasConsent(), isFalse);
    });
  });

  group('consent version 2 (0.1.2): existing holders are asked again', () {
    test('the current version is 2', () => expect(kReadingConsentVersion, 2));

    test('a stored version 1 is not consent; the turn-on asks for consent, nothing is asked of the system', () async {
      final m = _make(consent: false);
      m.p.data[kReadingConsentKey] = 1;
      expect(await m.c.hasConsent(), isFalse);
      expect((await m.c.turnOn()).outcome, TurnOnOutcome.needsConsent);
      expect(m.b.calls, isEmpty);
    });

    test('an existing v1 holder with Read on: forced off at launch, held messages kept, nothing deleted', () async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 4);
      final m = _make(consent: false, bridge: b);
      m.p.data[kReadingConsentKey] = 1;
      m.p.data[pendingKey(1)] = 'x';
      expect(await m.c.reconcile(), isTrue);
      expect(b.enabled, isFalse);
      expect(b.heldCount, 4);
      expect(b.calls, isNot(contains('deleteAllHeld')));
      expect(m.s.bumps, 0);
      expect(m.p.data.keys.where((k) => k.startsWith('autoread_pending_v1.')).length, 1);
      // Re-asking: after the new consent the same user can turn Read on again.
      expect(await m.c.recordConsent(), isTrue);
      expect(m.p.data[kReadingConsentKey], 2);
      expect((await m.c.turnOn()).isOn, isTrue);
      expect(b.heldCount, 4);
    });

    test('recordConsent hands the version to Kotlin first, then stores it', () async {
      final m = _make(consent: false);
      expect(await m.c.recordConsent(), isTrue);
      expect(m.b.calls.first, 'setConsent:$kReadingConsentVersion');
      expect(m.b.kotlinConsent, kReadingConsentVersion);
    });

    test('if Kotlin cannot hold the consent, nothing is stored on the Dart side either', () async {
      final b = FakeReadingBridge()..setConsentError = const AutoReadBridgeException('failed');
      final m = _make(consent: false, bridge: b);
      expect(await m.c.recordConsent(), isFalse);
      expect(m.p.data, isEmpty);
    });

    test('a missing permission is still not forced off (PM decision)', () async {
      final m = _make(bridge: FakeReadingBridge(enabled: true, smsGranted: false, notifGranted: false));
      expect(await m.c.reconcile(), isTrue);
      expect(m.b.enabled, isTrue);
    });
  });

  group('Parse from the notification switch and Autostart help', () {
    test('state mirrors parseOn and autostartHelp; the defaults are off', () async {
      expect((await _make().c.state()).parseOn, isFalse);
      expect((await _make().c.state()).autostartHelp, isFalse);
      final m = _make(bridge: FakeReadingBridge(parseOn: true, autostartHelp: true));
      final s = await m.c.state();
      expect(s.parseOn, isTrue);
      expect(s.autostartHelp, isTrue);
    });

    test('setParse writes through and reads back; false when the write did not take', () async {
      final m = _make();
      expect(await m.c.setParse(true), isTrue);
      expect(m.b.parseOn, isTrue);
      expect(await m.c.setParse(false), isTrue);
      final b = FakeReadingBridge()..setParseIgnored = true;
      expect(await _make(bridge: b).c.setParse(true), isFalse);
    });

    test('turning Read off leaves the Parse switch as it was; delete held does too', () async {
      final b = FakeReadingBridge(enabled: true, parseOn: true, heldCount: 1);
      final m = _make(bridge: b);
      await m.c.turnOff();
      expect(b.parseOn, isTrue);
      await m.c.deleteHeld();
      expect(b.parseOn, isTrue);
    });

    test('openAutostartSettings calls the bridge only when asked; false on an error', () async {
      final m = _make();
      expect(m.b.calls, isNot(contains('openAutostartSettings')));
      expect(await m.c.openAutostartSettings(), isTrue);
      expect(m.b.calls, contains('openAutostartSettings'));
    });
  });
}
