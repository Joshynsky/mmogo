// 0.2.2 item 2, slice S-1: rule ceiling, autoPending marker, kinds that may
// hold Auto-record, privacy refusal. Dormant: nothing here makes the app record.
// Invented data only.
@Tags(['autoread'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_codec.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Object _absent = Object();

void main() {
  final t0 = DateTime.utc(2026, 11, 25, 10);
  const sm = ReceiverType.sendMoney;
  ReceiverRule rule({int? ceil, bool ap = false}) => ReceiverRule(
      type: sm, key: '0712', name: 'Ann', level: RuleLevel.autoRecord, categoryId: 3, created: t0, changed: t0, ceilingCents: ceil, autoPending: ap);
  String json({Object? ceil = _absent, Object? ap = _absent}) {
    final m = <String, Object?>{'v': 1, 't': 'SM', 'k': 'a', 'name': 'n', 'lv': 2, 'run': 0, 'created': 1, 'changed': 1};
    if (!identical(ceil, _absent)) m['ceil'] = ceil;
    if (!identical(ap, _absent)) m['ap'] = ap;
    return jsonEncode(m);
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('codec', () {
    test('ceiling and autoPending round-trip', () {
      final r = decodeRule(encodeRule(rule(ceil: 150000, ap: true)))!;
      expect(r.ceilingCents, 150000);
      expect(r.autoPending, isTrue);
      expect(r.created, t0);
      expect(decodeRule(encodeRule(rule()))!.ceilingCents, isNull);
      expect(decodeRule(encodeRule(rule()))!.autoPending, isFalse);
    });
    test('a 0.2.1 rule (no ceil, no ap) still decodes; no ceiling, not pending', () {
      final r = decodeRule(json())!;
      expect(r.ceilingCents, isNull);
      expect(r.autoPending, isFalse);
      expect(
          decodeRule('{"v":1,"t":"SM","k":"a","name":"n","lv":1,"cat":4,"run":2,"runCat":4,"created":1,"changed":2,"lastRecorded":null}')!.level,
          RuleLevel.askFirst);
    });
    test('ceiling boundaries: 1 and 100,000,000 valid; 0, negative, 100,000,001, non-int are corrupt', () {
      expect(decodeRule(json(ceil: 1))!.ceilingCents, 1);
      expect(decodeRule(json(ceil: 100000000))!.ceilingCents, 100000000);
      for (final bad in <Object?>[0, -1, 100000001, 1.5, '100', true]) {
        expect(decodeRule(json(ceil: bad)), isNull, reason: '$bad');
      }
      expect(decodeRule(json(ceil: null))!.ceilingCents, isNull);
    });
    test('a non-bool ap is corrupt', () {
      expect(decodeRule(json(ap: 1)), isNull);
      expect(decodeRule(json(ap: 'true')), isNull);
      expect(decodeRule(json(ap: true))!.autoPending, isTrue);
    });
    test('Kotlin-facing keys unchanged: v stays 1 and lv is still written', () {
      final m = jsonDecode(encodeRule(rule(ceil: 5))) as Map;
      expect(m['v'], 1);
      expect(m['lv'], 2);
    });
  });

  group('copyWith', () {
    test('can set, keep and clear the ceiling and the marker', () {
      final r = rule(ceil: 100, ap: true);
      expect(r.copyWith(name: 'B').ceilingCents, 100);
      expect(r.copyWith(ceilingCents: 200).ceilingCents, 200);
      expect(r.copyWith(clearCeiling: true).ceilingCents, isNull);
      expect(r.copyWith(autoPending: false).autoPending, isFalse);
      expect(r.copyWith(name: 'B').autoPending, isTrue);
    });
  });

  test('canHoldAutoRecord: Send Money, Pochi, Till yes; Paybill no', () {
    expect(canHoldAutoRecord(ReceiverType.sendMoney), isTrue);
    expect(canHoldAutoRecord(ReceiverType.pochi), isTrue);
    expect(canHoldAutoRecord(ReceiverType.buyGoods), isTrue);
    expect(canHoldAutoRecord(ReceiverType.payBill), isFalse);
  });

  // The same behaviour must hold for the real store and the fake.
  for (final real in [true, false]) {
    group(real ? 'PrefsRuleStore' : 'FakeRuleStore', () {
      late RuleStore s;
      void detailsOff() {
        if (real) {
          SharedPreferences.setMockInitialValues({kReceiverDetailsPrefsKey: false});
        } else {
          (s as FakeRuleStore).detailsOn = false;
        }
      }

      setUp(() => s = real ? PrefsRuleStore() : FakeRuleStore());

      test('Auto-record accepted for Send Money, Pochi, Till; refused for Paybill; Ask first for Paybill fine', () async {
        for (final t in [ReceiverType.sendMoney, ReceiverType.pochi, ReceiverType.buyGoods]) {
          expect(await s.setLevel(t, 'k', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, at: t0), isTrue, reason: '$t');
          expect((await s.get(t, 'k'))!.level, RuleLevel.autoRecord);
        }
        expect(await s.setLevel(ReceiverType.payBill, 'B#1', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, at: t0), isFalse);
        expect(await s.get(ReceiverType.payBill, 'B#1'), isNull);
        expect(await s.setLevel(ReceiverType.payBill, 'B#1', name: 'n', level: RuleLevel.askFirst, categoryId: 1, at: t0), isTrue);
        expect(await s.setLevel(ReceiverType.payBill, 'B#1', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, at: t0), isFalse);
        expect((await s.get(ReceiverType.payBill, 'B#1'))!.level, RuleLevel.askFirst);
      });

      test('ceiling stored, replaced and cleared; invalid ceilings refused and change nothing', () async {
        expect(await s.setLevel(sm, 'k', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 50000, at: t0), isTrue);
        expect((await s.get(sm, 'k'))!.ceilingCents, 50000);
        expect(await s.setLevel(sm, 'k', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 1, at: t0), isTrue);
        expect((await s.get(sm, 'k'))!.ceilingCents, 1);
        expect(await s.setLevel(sm, 'k', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 100000000, at: t0), isTrue);
        for (final bad in [0, -5, 100000001]) {
          expect(await s.setLevel(sm, 'k', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: bad, at: t0), isFalse,
              reason: '$bad');
        }
        expect((await s.get(sm, 'k'))!.ceilingCents, 100000000);
        expect(await s.setLevel(sm, 'k', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, at: t0), isTrue);
        expect((await s.get(sm, 'k'))!.ceilingCents, isNull, reason: 'null clears it');
      });

      test('setLevel is refused with receiver details OFF', () async {
        detailsOff();
        expect(await s.setLevel(sm, 'k', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, at: t0), isFalse);
        expect(await s.setLevel(sm, 'k', name: 'n', level: RuleLevel.askFirst, categoryId: 1, at: t0), isFalse);
        expect(await s.get(sm, 'k'), isNull);
        expect(await s.all(), isEmpty);
      });

      test('cap 300 is untouched', () async {
        for (var i = 0; i < kRuleCap; i++) {
          expect(await s.setLevel(sm, 'k$i', name: 'n', level: RuleLevel.askFirst, categoryId: 1, at: t0), isTrue);
        }
        expect(await s.setLevel(sm, 'extra', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, at: t0), isFalse);
        expect(await s.setLevel(sm, 'k0', name: 'n', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 9, at: t0), isTrue);
      });
    });
  }

  group('PrefsRuleStore autoPending', () {
    test('saveRule keeps the marker; setLevel for that person clears it; ceiling kept', () async {
      final s = PrefsRuleStore();
      await s.saveRule(rule(ceil: 7000, ap: true).copyWith(level: RuleLevel.askFirst));
      final r = (await s.get(sm, '0712'))!;
      expect(r.autoPending, isTrue);
      expect(r.ceilingCents, 7000);
      expect(r.level, RuleLevel.askFirst);
      await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.askFirst, categoryId: 3, ceilingCents: 7000, at: t0);
      final r2 = (await s.get(sm, '0712'))!;
      expect(r2.autoPending, isFalse);
      expect(r2.ceilingCents, 7000);
    });
    test('a stored rule with a bad ceiling is ignored like any corrupt rule', () async {
      final s = PrefsRuleStore();
      await s.setLevel(sm, 'good', name: 'G', level: RuleLevel.askFirst, categoryId: 1, at: t0);
      final p = await SharedPreferences.getInstance();
      await p.setString(ruleStorageKey(sm, 'bad'), json(ceil: 0));
      expect((await s.all()).map((e) => e.key), ['good']);
      expect(await s.get(sm, 'bad'), isNull);
    });
  });
}
