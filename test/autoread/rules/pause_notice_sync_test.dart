@Tags(['autoread'])
library;

// 0.2.2 item 2 slice B-PAUSE: the pinned "Auto-record is paused" notice sync.
//  - the rule table (paused / not x 0 / 1+ people, details, unreadable count, dormant);
//  - PM Q1: the last person leaves Auto-record while paused -> Pause switches itself off (through the port);
//  - Resume from the shade (a fake bridge that runs the Dart mirror of PauseActionReceiver) -> on resume the
//    port fires so every pause control re-reads; a wrong-typed value is kept (fail closed);
//  - survives restart (a new port + sync over the same preferences re-posts); dispose never removes it;
//  - Delete data (key removed + recheck) and Read off (Kotlin refuses + removes) remove it;
//  - swiped away (Android 14+) -> back on resume.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/pause_notice_bridge.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/pause_notice_sync.dart';
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/hard_rule_fakes.dart';

/// Stands in for PauseNotice.kt + PauseActionReceiver.kt. [readOn] models Kotlin's CaptureGuard: while Read is
/// off, show() refuses and removes the notice. [tapResume] runs the Dart mirror of the receiver against the
/// preferences the app reads (the same key, the same decision).
class FakePauseNoticeBridge implements PauseNoticeBridge {
  bool visible = false;
  bool readOn = true;
  int shows = 0;
  int cancels = 0;
  String? title;
  String? resume;
  String? channelName;

  @override
  Future<bool> show({required String title, required String resume, required String channelName}) async {
    shows++;
    if (!readOn) {
      visible = false;
      return false;
    }
    this.title = title;
    this.resume = resume;
    this.channelName = channelName;
    visible = true;
    return true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    visible = false;
  }

  /// The user swipes the notice away (Android 14+).
  void swipe() => visible = false;

  /// The Resume button with mmogo closed: what PauseActionReceiver.kt does, through [pauseResumeStep].
  Future<PauseResumeStep> tapResume({bool unreadable = false}) async {
    final p = await SharedPreferences.getInstance();
    final step = pauseResumeStep(p.get(kHardPausedPrefsKey), unreadable: unreadable);
    switch (step) {
      case PauseResumeStep.resume:
        await p.setBool(kHardPausedPrefsKey, false);
        if (p.get(kHardPausedPrefsKey) == false) visible = false;
      case PauseResumeStep.already:
        visible = false;
      case PauseResumeStep.keep:
        break;
    }
    return step;
  }
}

Future<void> _auto(FakeRuleStore s, String key) async {
  final ok = await s.setLevel(ReceiverType.sendMoney, key,
      name: 'P $key', level: RuleLevel.autoRecord, categoryId: 1, at: DateTime.utc(2026, 11, 26));
  expect(ok, isTrue);
}

Future<void> _level(FakeRuleStore s, String key, RuleLevel level) async {
  final ok = await s.setLevel(ReceiverType.sendMoney, key,
      name: 'P $key', level: level, categoryId: level == RuleLevel.suggested ? null : 1, at: DateTime.utc(2026, 11, 26));
  expect(ok, isTrue);
}

class _ThrowingStore extends FakeRuleStore {
  bool fail = false;
  @override
  Future<List<ReceiverRule>> all() => fail ? Future.error(StateError('disk')) : super.all();
}

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() => debugAutoRecordUiOverride = null);

  group('pauseNoticeStep (the rule)', () {
    final cases = <(bool enabled, bool paused, int? n, bool details, PauseNoticeStep want)>[
      (true, false, 0, true, PauseNoticeStep.cancel),
      (true, false, 1, true, PauseNoticeStep.cancel),
      (true, false, 3, true, PauseNoticeStep.cancel),
      (true, true, 1, true, PauseNoticeStep.show),
      (true, true, 3, true, PauseNoticeStep.show),
      (true, true, 0, true, PauseNoticeStep.autoOff), // PM Q1
      (true, true, 0, false, PauseNoticeStep.cancel), // details OFF hides rules: pause kept
      (true, true, null, true, PauseNoticeStep.keep), // could not count: change nothing
      (true, false, null, true, PauseNoticeStep.cancel),
      (false, true, 2, true, PauseNoticeStep.cancel), // Auto-record screens off (dormant)
      (false, true, 0, true, PauseNoticeStep.cancel), // dormant: never Q1
    ];
    for (final c in cases) {
      test('enabled=${c.$1} paused=${c.$2} people=${c.$3} details=${c.$4} -> ${c.$5.name}', () {
        expect(pauseNoticeStep(enabled: c.$1, paused: c.$2, autoPeople: c.$3, detailsOn: c.$4), c.$5);
      });
    }
  });

  group('PauseNoticeSync with fakes', () {
    late FakeHardRulePausePort pause;
    late FakeRuleStore store;
    late FakePauseNoticeBridge bridge;
    late bool details;
    late PauseNoticeSync sync;

    setUp(() {
      pause = FakeHardRulePausePort();
      store = FakeRuleStore();
      bridge = FakePauseNoticeBridge();
      details = true;
      sync = PauseNoticeSync(pause: pause, store: store, bridge: bridge, detailsOn: () async => details);
    });
    tearDown(() => sync.dispose());

    test('table on the real sync: not paused x 0 / 1+ people -> no notice', () async {
      await sync.start();
      expect(bridge.visible, isFalse);
      await _auto(store, 'a');
      await sync.recheck();
      expect(bridge.visible, isFalse);
      expect(bridge.shows, 0);
    });

    test('paused + 1 person -> notice with the signed words; paused + 2 -> still shown', () async {
      await _auto(store, 'a');
      await sync.start();
      await pause.setPaused(true);
      await sync.recheck();
      expect(bridge.visible, isTrue);
      expect(bridge.title, kHardPausedNoticeTitle);
      expect(bridge.title, 'Auto-record is paused');
      expect(bridge.resume, kHardResume);
      expect(bridge.resume, 'Resume');
      expect(bridge.channelName, startsWith('[PM to write:'), reason: 'WORDING-MISSING -> W2');
      await _auto(store, 'b');
      await sync.recheck();
      expect(bridge.visible, isTrue);
    });

    test('paused + 0 people (details ON): Pause switches itself off at once (PM Q1), no notice', () async {
      pause.paused = true;
      await sync.start();
      expect(pause.paused, isFalse);
      expect(pause.setCalls, 1);
      expect(bridge.visible, isFalse);
    });

    test('PM Q1: the LAST person leaves Auto-record while paused -> Pause off through the port, notice gone', () async {
      await _auto(store, 'a');
      await _auto(store, 'b');
      await sync.start();
      await pause.setPaused(true);
      await sync.recheck();
      expect(bridge.visible, isTrue);
      var fired = 0;
      void l() => fired++;
      pause.changes.addListener(l);

      await _level(store, 'a', RuleLevel.askFirst); // one left on Auto-record: still paused
      await sync.recheck();
      expect(pause.paused, isTrue);
      expect(bridge.visible, isTrue);

      await _level(store, 'b', RuleLevel.suggested); // the last one leaves (store change triggers the sync)
      await sync.recheck();
      expect(pause.paused, isFalse);
      expect(fired, greaterThanOrEqualTo(1), reason: 'every pause control hears it through the port');
      expect(bridge.visible, isFalse);
      pause.changes.removeListener(l);
    });

    test('PM Q1 also after Forget all people', () async {
      await _auto(store, 'a');
      await sync.start();
      await pause.setPaused(true);
      await sync.recheck();
      expect(bridge.visible, isTrue);
      await store.forgetEveryone();
      await sync.recheck();
      expect(pause.paused, isFalse);
      expect(bridge.visible, isFalse);
    });

    test('details OFF hides the rules: the pause is KEPT (not Q1), the notice goes; ON again -> back', () async {
      await _auto(store, 'a');
      await sync.start();
      await pause.setPaused(true);
      await sync.recheck();
      expect(bridge.visible, isTrue);
      details = false;
      store.detailsOn = false;
      await sync.recheck();
      expect(pause.paused, isTrue);
      expect(bridge.visible, isFalse);
      details = true;
      store.detailsOn = true;
      await sync.recheck();
      expect(pause.paused, isTrue);
      expect(bridge.visible, isTrue);
    });

    test('details flips while counting -> nothing changes (no Q1 on a half read)', () async {
      pause.paused = true;
      var calls = 0;
      final s2 = PauseNoticeSync(
          pause: pause, store: store, bridge: bridge, detailsOn: () async => (calls++).isEven); // ON then OFF
      await s2.recheck();
      s2.dispose();
      expect(pause.paused, isTrue);
      expect(pause.setCalls, 0);
      expect(bridge.shows + bridge.cancels, 0);
    });

    test('the store cannot be read -> nothing changes (fail closed: no Q1, notice left as it is)', () async {
      final bad = _ThrowingStore();
      await _auto(bad, 'a');
      final s2 = PauseNoticeSync(pause: pause, store: bad, bridge: bridge, detailsOn: () async => true);
      await pause.setPaused(true);
      await s2.recheck();
      expect(bridge.visible, isTrue);
      bad.fail = true;
      await s2.recheck();
      expect(pause.paused, isTrue);
      expect(bridge.visible, isTrue);
      s2.dispose();
    });

    test('a failed pause read counts as paused (fail closed): the notice shows while people are on Auto-record', () async {
      await _auto(store, 'a');
      pause.failReads = true;
      await sync.start();
      expect(bridge.visible, isTrue);
    });

    test('the pause port change alone triggers the sync (no recheck call)', () async {
      await _auto(store, 'a');
      await sync.start();
      await pause.setPaused(true);
      await pumpEventQueue();
      expect(bridge.visible, isTrue);
      await pause.setPaused(false);
      await pumpEventQueue();
      expect(bridge.visible, isFalse);
    });

    test('a rule store change alone triggers the sync', () async {
      await sync.start();
      pause.paused = true; // set without a signal
      await _auto(store, 'a'); // store change
      await pumpEventQueue();
      expect(bridge.visible, isTrue);
    });

    test('swiped away (Android 14+) -> posted again on resume', () async {
      await _auto(store, 'a');
      await sync.start();
      await pause.setPaused(true);
      await sync.recheck();
      bridge.swipe();
      expect(bridge.visible, isFalse);
      await sync.resumed();
      expect(bridge.visible, isTrue);
    });

    test('Read off: Kotlin refuses to post and removes it; Read on again + resume -> back', () async {
      await _auto(store, 'a');
      await sync.start();
      await pause.setPaused(true);
      await sync.recheck();
      expect(bridge.visible, isTrue);
      bridge.readOn = false;
      bridge.visible = false; // FeatureHooks cancels on setEnabled(false)
      await sync.resumed();
      expect(bridge.visible, isFalse);
      bridge.readOn = true;
      await sync.resumed();
      expect(bridge.visible, isTrue);
    });

    test('Auto-record screens off (dormant flag): the notice is removed, the pause is never touched', () async {
      debugAutoRecordUiOverride = false;
      pause.paused = true;
      await sync.start();
      expect(bridge.cancels, greaterThanOrEqualTo(1));
      expect(bridge.shows, 0);
      expect(pause.setCalls, 0);
      expect(pause.paused, isTrue);
    });

    test('dispose stops listening and never removes the notice', () async {
      await _auto(store, 'a');
      await sync.start();
      await pause.setPaused(true);
      await sync.recheck();
      final cancels = bridge.cancels;
      sync.dispose();
      expect(bridge.visible, isTrue);
      expect(bridge.cancels, cancels);
      await pause.setPaused(false);
      await pumpEventQueue();
      expect(bridge.visible, isTrue, reason: 'no longer listening');
    });

    test('start twice listens once', () async {
      await sync.start();
      await sync.start();
      await _auto(store, 'a');
      pause.paused = true;
      await pumpEventQueue();
      final before = bridge.shows;
      await pause.setPaused(true);
      await pumpEventQueue();
      expect(bridge.shows - before, 1);
    });
  });

  group('PauseNoticeSync over the real preferences (restart, shade Resume, Delete data)', () {
    late FakeRuleStore store;
    late FakePauseNoticeBridge bridge;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      store = FakeRuleStore();
      bridge = FakePauseNoticeBridge();
    });

    PauseNoticeSync newSync(HardRulePausePort port) =>
        PauseNoticeSync(pause: port, store: store, bridge: bridge, detailsOn: () async => true);

    test('survives restart: a new port and sync over the same preferences re-post the notice on open', () async {
      await _auto(store, 'a');
      final port1 = PrefsHardRulePausePort();
      final s1 = newSync(port1);
      await s1.start();
      await port1.setPaused(true);
      await s1.recheck();
      expect(bridge.visible, isTrue);
      s1.dispose();
      bridge.visible = false; // the phone restarted: the notice is gone

      final port2 = PrefsHardRulePausePort(); // the app opens again
      final s2 = newSync(port2);
      await s2.start();
      expect(await port2.isPaused(), isTrue);
      expect(bridge.visible, isTrue);
      s2.dispose();
    });

    test('Resume from the shade (mmogo in the background) -> on resume the port fires and reads not paused', () async {
      await _auto(store, 'a');
      final port = PrefsHardRulePausePort();
      final s = newSync(port);
      await s.start();
      await port.setPaused(true);
      await s.recheck();
      expect(bridge.visible, isTrue);

      expect(await bridge.tapResume(), PauseResumeStep.resume);
      expect(bridge.visible, isFalse);
      expect((await SharedPreferences.getInstance()).get(kHardPausedPrefsKey), isFalse);

      var fired = 0;
      void l() => fired++;
      port.changes.addListener(l);
      await s.resumed();
      expect(fired, greaterThanOrEqualTo(1), reason: 'the switch, rows and banners re-read');
      expect(await port.isPaused(), isFalse);
      expect(bridge.visible, isFalse);
      port.changes.removeListener(l);
      s.dispose();
    });

    test('Resume from the shade with a wrong-typed stored value: nothing happens (fail closed)', () async {
      SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: 'yes'});
      await _auto(store, 'a');
      final port = PrefsHardRulePausePort();
      final s = newSync(port);
      await s.start();
      expect(await port.isPaused(), isTrue, reason: 'a wrong type reads as paused');
      expect(bridge.visible, isTrue);
      expect(await bridge.tapResume(), PauseResumeStep.keep);
      expect(bridge.visible, isTrue);
      expect((await SharedPreferences.getInstance()).get(kHardPausedPrefsKey), 'yes');
      await s.resumed();
      expect(await port.isPaused(), isTrue);
      expect(bridge.visible, isTrue);
      s.dispose();
    });

    test('Resume from the shade on an unreadable file: nothing happens (fail closed)', () async {
      await _auto(store, 'a');
      final port = PrefsHardRulePausePort();
      final s = newSync(port);
      await s.start();
      await port.setPaused(true);
      await s.recheck();
      expect(await bridge.tapResume(unreadable: true), PauseResumeStep.keep);
      expect(bridge.visible, isTrue);
      expect(await port.isPaused(), isTrue);
      s.dispose();
    });

    test('a stale notice (already not paused) -> Resume only removes it', () async {
      bridge.visible = true;
      expect(await bridge.tapResume(), PauseResumeStep.already);
      expect(bridge.visible, isFalse);
      expect((await SharedPreferences.getInstance()).get(kHardPausedPrefsKey), isNull);
    });

    test('Delete data (the pause key removed, then recheck) removes the notice', () async {
      await _auto(store, 'a');
      final port = PrefsHardRulePausePort();
      final s = newSync(port);
      await s.start();
      await port.setPaused(true);
      await s.recheck();
      expect(bridge.visible, isTrue);
      // AutoReadWipe removes the key directly (not through the port), and the rules with it.
      await (await SharedPreferences.getInstance()).remove(kHardPausedPrefsKey);
      await store.wipeAll();
      await s.recheck();
      expect(bridge.visible, isFalse);
      expect(await port.isPaused(), isFalse);
      s.dispose();
    });
  });

  test('the sync passes the signed words only (C1 keys), and the channel name is marked missing', () {
    expect(kHardPausedNoticeTitle, 'Auto-record is paused');
    expect(kHardResume, 'Resume');
    expect(kHardPausedToast, 'Auto-record paused. Your settings are kept.', reason: 'the short pill on Pause stays');
  });

  test('FakeHardRulePausePort is a Listenable the sync can follow', () {
    expect(FakeHardRulePausePort().changes, isA<Listenable>());
  });
}
