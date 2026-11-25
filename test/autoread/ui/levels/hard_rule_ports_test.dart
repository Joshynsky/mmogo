@Tags(['autoread'])
library;

// 0.2.2 item 2, slice C0: the shared seams of the Auto-record screens. The pause port (persists, fails
// closed, fires on every set), the UI flag override, the page-wide rule operations (reset count, clears
// ceiling and pending mark, keeps rules, never raises a level), LevelsDeps defaults, and the hint field
// `fromAutoRecord` (default false, stored only when true).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/hard_rule_decision.dart';
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/hard_rule_fakes.dart';
import '../../../support/waiting_fakes.dart';

class _ThrowingPause extends PrefsHardRulePause {
  @override
  Future<bool> isPaused() => throw StateError('disk');
  @override
  Future<bool> setPaused(bool paused) => throw StateError('disk');
}

void main() {
  group('autoRecordUi', () {
    tearDown(() => debugAutoRecordUiOverride = null);

    test('follows autoRecordLive (false) unless a test overrides it', () {
      expect(autoRecordLive, isFalse);
      expect(autoRecordUi, isFalse);
      debugAutoRecordUiOverride = true;
      expect(autoRecordUi, isTrue);
      debugAutoRecordUiOverride = null;
      expect(autoRecordUi, isFalse);
    });
  });

  group('PrefsHardRulePausePort', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('default not paused; pause persists for a new port (restart); resume removes the key', () async {
      final a = PrefsHardRulePausePort();
      expect(await a.isPaused(), isFalse);
      expect(await a.setPaused(true), isTrue);
      expect(await PrefsHardRulePausePort().isPaused(), isTrue);
      SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: true}); // new process
      expect(await PrefsHardRulePausePort().isPaused(), isTrue);
      expect(await PrefsHardRulePausePort().setPaused(false), isTrue);
      expect((await SharedPreferences.getInstance()).containsKey(kHardPausedPrefsKey), isFalse);
    });

    test('fails closed: a wrong-typed value and a failing store both read as paused', () async {
      SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: 'yes'});
      expect(await PrefsHardRulePausePort().isPaused(), isTrue);
      final broken = PrefsHardRulePausePort(pause: _ThrowingPause());
      expect(await broken.isPaused(), isTrue);
      expect(await broken.setPaused(false), isFalse);
    });

    test('changes fires after every set, also a failed one (the switch re-reads and snaps back)', () async {
      var fired = 0;
      final ok = PrefsHardRulePausePort()..changes.addListener(() => fired++);
      await ok.setPaused(true);
      expect(fired, 1);
      final broken = PrefsHardRulePausePort(pause: _ThrowingPause())..changes.addListener(() => fired++);
      await broken.setPaused(true);
      expect(fired, 2);
    });
  });

  group('RuleBulkOps', () {
    Future<(RuleBulkOps, FakeRuleStore)> rig() async {
      final store = await hardTestStore([
        hardTestRule('tim', level: RuleLevel.autoRecord, categoryId: 2, ceilingCents: 200000),
        hardTestRule('amina', type: ReceiverType.pochi, level: RuleLevel.autoRecord, categoryId: 1),
        hardTestRule('gary', level: RuleLevel.askFirst, categoryId: 2),
        hardTestRule('kplc', type: ReceiverType.payBill, level: RuleLevel.askFirst, categoryId: 3),
        hardTestRule('back', level: RuleLevel.askFirst, categoryId: 2, ceilingCents: 50000, autoPending: true),
        hardTestRule('grace'),
        hardTestRule('walt'),
      ]);
      return (RuleBulkOps(store, now: () => kHardTestNow), store);
    }

    test('countByLevel counts every stored level, zero when none', () async {
      final (ops, _) = await rig();
      expect(await ops.countByLevel(), {RuleLevel.suggested: 2, RuleLevel.askFirst: 3, RuleLevel.autoRecord: 2});
      expect(await RuleBulkOps(await hardTestStore([])).countByLevel(), {RuleLevel.suggested: 0, RuleLevel.askFirst: 0, RuleLevel.autoRecord: 0});
    });

    test('pendingAutoPeople comes only from the autoPending mark', () async {
      final (ops, _) = await rig();
      expect([for (final r in await ops.pendingAutoPeople()) r.key], ['back']);
    });

    test('reset: count matches the dialog, clears ceilings and marks, keeps every rule, raises nobody', () async {
      final (ops, store) = await rig();
      expect(await ops.resetCount(), 5);
      expect(await ops.resetAllToSuggested(), 5);
      final after = await store.all();
      expect(after, hasLength(7), reason: 'rules stay: people stay remembered');
      for (final r in after) {
        expect(r.level, RuleLevel.suggested);
        expect(r.ceilingCents, isNull);
        expect(r.autoPending, isFalse);
      }
      expect(await ops.resetCount(), 0);
      expect(await ops.resetAllToSuggested(), 0);
    });

    test('reset never touches the pause switch', () async {
      SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: true});
      final (ops, _) = await rig();
      await ops.resetAllToSuggested();
      expect(await PrefsHardRulePausePort().isPaused(), isTrue);
    });

    test('a refused write (details OFF) is not counted', () async {
      final (ops, store) = await rig();
      store.detailsOn = false;
      expect(await ops.resetAllToSuggested(), 0);
    });

    test('works over the real preferences store too', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsRuleStore();
      final at = DateTime.utc(2026, 11, 25);
      expect(
          await store.setLevel(ReceiverType.sendMoney, '0712345678',
              name: 'Ann', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 5000, at: at),
          isTrue);
      final ops = RuleBulkOps(store, now: () => at);
      expect(await ops.resetAllToSuggested(), 1);
      final r = await store.get(ReceiverType.sendMoney, '0712345678');
      expect(r, isNotNull);
      expect(r!.level, RuleLevel.suggested);
      expect(r.ceilingCents, isNull);
    });
  });

  group('LevelsDeps', () {
    test('bulk is built over the store; notice and pause are passed through', () async {
      final pause = FakeHardRulePausePort(paused: true);
      final notice = FakeRuleChangeNotice();
      final store = await hardTestStore([hardTestRule('tim', level: RuleLevel.askFirst, categoryId: 1)]);
      final d = hardTestDeps(store: store, pause: pause, notice: notice);
      expect(await d.bulk.resetCount(), 1);
      expect(await d.pause!.isPaused(), isTrue);
      d.notice.show('Tim', RuleLevel.autoRecord, null, null);
      expect(notice.calls.single.level, RuleLevel.autoRecord);
    });
  });

  group('RuleHint.fromAutoRecord', () {
    WaitingItem item(RuleHint h) => WaitingItem(
          id: heldIdFor(1),
          kind: WaitingKind.waitingCategory,
          heldAt: DateTime.utc(2026, 11, 25),
          parsed: sampleFields(1, DateTime.utc(2026, 11, 25)),
          hint: h,
        );

    test('defaults to false and is not written then (old items unchanged)', () {
      const h = RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: 'k', suggested: [1]);
      expect(h.fromAutoRecord, isFalse);
      final json = encodePendingItem(item(h));
      expect(json.contains('"fa"'), isFalse);
      expect(decodePendingItem(json)!.hint, h);
    });

    test('round-trips when true and takes part in equality', () {
      const h = RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: 'k', fromAutoRecord: true);
      final back = decodePendingItem(encodePendingItem(item(h)))!.hint!;
      expect(back.fromAutoRecord, isTrue);
      expect(back, h);
      expect(back == const RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: 'k'), isFalse);
    });
  });
}
