// §AUTOREAD.HARD_RULE_DECISION and §AUTOREAD.HARD_RULE_PAUSE (0.2.2 item 2, S-2).
// Dormant code: pure decision, pause switch, dormancy pin. Invented data only.
//
// ignore_for_file: depend_on_referenced_packages
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/autoread_wipe.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/rules/hard_rule_decision.dart';
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/reading_fakes.dart';

final _t0 = DateTime(2026, 11, 25);

ReceiverRule _rule({
  ReceiverType type = ReceiverType.sendMoney,
  RuleLevel level = RuleLevel.autoRecord,
  int? ceil,
}) =>
    ReceiverRule(type: type, key: 'k', name: 'Ann', level: level, categoryId: 3, created: _t0, changed: _t0, ceilingCents: ceil);

HardRuleDecision _d(
  ReceiverRule? r, {
  ReceiverType? kind = ReceiverType.sendMoney,
  int amount = 10000,
  bool paused = false,
  bool detailsOn = true,
}) =>
    decideHardRule(rule: r, kind: kind, amountCents: amount, paused: paused, detailsOn: detailsOn);

void main() {
  test('autoRecordLive is pinned true (live since the 0.2.2 flip)', () {
    expect(autoRecordLive, isTrue);
  });

  group('decideHardRule', () {
    test('no ceiling records, whatever the amount', () {
      expect(_d(_rule(), amount: 1), HardRuleDecision.record);
      expect(_d(_rule(), amount: 99999999999), HardRuleDecision.record);
    });

    test('ceiling boundary: below and equal record, +1 cent asks first', () {
      final r = _rule(ceil: 50000);
      expect(_d(r, amount: 49999), HardRuleDecision.record);
      expect(_d(r, amount: 50000), HardRuleDecision.record);
      expect(_d(r, amount: 50001), HardRuleDecision.askFirst);
    });

    test('ceiling extremes', () {
      expect(_d(_rule(ceil: 1), amount: 1), HardRuleDecision.record);
      expect(_d(_rule(ceil: 1), amount: 2), HardRuleDecision.askFirst);
      expect(_d(_rule(ceil: kCeilingMaxCents), amount: kCeilingMaxCents), HardRuleDecision.record);
      expect(_d(_rule(ceil: kCeilingMaxCents), amount: kCeilingMaxCents + 1), HardRuleDecision.askFirst);
    });

    test('an invalid ceiling in memory is doubt: askFirst', () {
      expect(_d(_rule(ceil: 0)), HardRuleDecision.askFirst);
      expect(_d(_rule(ceil: -5)), HardRuleDecision.askFirst);
      expect(_d(_rule(ceil: kCeilingMaxCents + 1)), HardRuleDecision.askFirst);
    });

    test('the fee is not an input: the signature has only the amount', () {
      // Ksh 500.00 ceiling, Ksh 500.00 sent (a fee on top is never passed in): records.
      expect(_d(_rule(ceil: 50000), amount: 50000), HardRuleDecision.record);
    });

    test('zero or negative amount is doubt: askFirst', () {
      expect(_d(_rule(), amount: 0), HardRuleDecision.askFirst);
      expect(_d(_rule(), amount: -1), HardRuleDecision.askFirst);
    });

    test('levels: Suggested not applicable, Ask first asks, no rule not applicable', () {
      expect(_d(_rule(level: RuleLevel.suggested)), HardRuleDecision.notApplicable);
      expect(_d(_rule(level: RuleLevel.askFirst)), HardRuleDecision.askFirst);
      expect(_d(null), HardRuleDecision.notApplicable);
    });

    test('paused: every Auto-record rule asks first, the rule is untouched', () {
      for (final t in [ReceiverType.sendMoney, ReceiverType.pochi, ReceiverType.buyGoods]) {
        final r = _rule(type: t, ceil: 50000);
        expect(_d(r, kind: t, paused: true), HardRuleDecision.askFirst, reason: '$t');
        expect(r.level, RuleLevel.autoRecord);
        expect(r.ceilingCents, 50000);
        expect(_d(r, kind: t, paused: false), HardRuleDecision.record, reason: '$t');
      }
      // pausing does not turn other levels into something else
      expect(_d(_rule(level: RuleLevel.suggested), paused: true), HardRuleDecision.notApplicable);
    });

    test('details OFF: askFirst', () {
      expect(_d(_rule(), detailsOn: false), HardRuleDecision.askFirst);
    });

    test('kinds: send money, pochi and till record; paybill level 2 in storage asks first', () {
      for (final t in [ReceiverType.sendMoney, ReceiverType.pochi, ReceiverType.buyGoods]) {
        expect(_d(_rule(type: t), kind: t), HardRuleDecision.record, reason: '$t');
      }
      expect(_d(_rule(type: ReceiverType.payBill), kind: ReceiverType.payBill), HardRuleDecision.askFirst);
    });

    test('withdrawal and airtime (no kind) are not applicable, even with a rule passed', () {
      expect(_d(_rule(), kind: null), HardRuleDecision.notApplicable);
      expect(_d(null, kind: null), HardRuleDecision.notApplicable);
    });

    test('a rule of another kind than the message asks first', () {
      expect(_d(_rule(type: ReceiverType.sendMoney), kind: ReceiverType.pochi), HardRuleDecision.askFirst);
    });
  });

  group('PrefsHardRulePause', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('default not paused; set, read back, resume', () async {
      final p = PrefsHardRulePause();
      expect(await p.isPaused(), isFalse);
      expect(await p.setPaused(true), isTrue);
      expect(await p.isPaused(), isTrue);
      expect(await p.setPaused(false), isTrue);
      expect(await p.isPaused(), isFalse);
      expect((await SharedPreferences.getInstance()).containsKey(kHardPausedPrefsKey), isFalse);
    });

    test('survives a restart: a fresh instance and fresh prefs read the stored value', () async {
      expect(await PrefsHardRulePause().setPaused(true), isTrue);
      final stored = (await SharedPreferences.getInstance()).getBool(kHardPausedPrefsKey);
      expect(stored, isTrue);
      SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: true}); // new process
      expect(await PrefsHardRulePause().isPaused(), isTrue);
    });

    test('pausing leaves stored rules untouched', () async {
      final store = PrefsRuleStore();
      expect(await store.setLevel(ReceiverType.sendMoney, 'k', name: 'Ann', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 5000, at: _t0), isTrue);
      await PrefsHardRulePause().setPaused(true);
      final r = (await store.get(ReceiverType.sendMoney, 'k'))!;
      expect(r.level, RuleLevel.autoRecord);
      expect(r.ceilingCents, 5000);
    });

    test('doubt reads as paused: a wrong-typed value and a failing prefs', () async {
      SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: 'yes'});
      expect(await PrefsHardRulePause().isPaused(), isTrue);
      final broken = PrefsHardRulePause(prefs: () async => throw StateError('no prefs'));
      expect(await broken.isPaused(), isTrue);
      expect(await broken.setPaused(true), isFalse);
    });

    test('the key is not a rule key (the rule wipe on a restore cannot clear it)', () {
      expect(kHardPausedPrefsKey, 'autoread_hard_paused');
    });
  });

  group('Delete data clears the pause (AutoReadWipe)', () {
    test('pause key removed with the rest', () async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 0);
      final p = FakeReadingPrefs();
      p.data[kHardPausedPrefsKey] = true;
      final c = ReadingController(bridge: b, store: FakeGenerationStore(), prefs: p);
      final w = AutoReadWipe(controller: () => c, prefs: p);
      expect(await w.run(), isTrue);
      expect(p.data.containsKey(kHardPausedPrefsKey), isFalse);
    });

    test('a pause key that will not go: false (fail closed)', () async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 0);
      final p = FakeReadingPrefs();
      p.data[kHardPausedPrefsKey] = true;
      final c = ReadingController(bridge: b, store: FakeGenerationStore(), prefs: p);
      final w = AutoReadWipe(controller: () => c, prefs: p);
      p.failRemove = true;
      expect(await w.run(), isFalse);
    });
  });
}
