// 0.2.2 item 2 redesign, slice C2: chosen Suggest categories on the rule (model, codec `sc`, setLevel),
// and forgetEveryone / countEveryone in the real and the fake store. Dormant: nothing here records.
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
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Object _absent = Object();

void main() {
  final t0 = DateTime.utc(2026, 11, 25, 10);
  final t1 = DateTime.utc(2026, 11, 25, 11);
  const sm = ReceiverType.sendMoney;

  ReceiverRule rule({RuleLevel level = RuleLevel.suggested, List<int> sc = const []}) => ReceiverRule(
      type: sm, key: '0712', name: 'Ann', level: level, categoryId: 3, created: t0, changed: t0, chosenCategoryIds: sc);

  String json({Object? sc = _absent, int lv = 0}) {
    final m = <String, Object?>{'v': 1, 't': 'SM', 'k': 'a', 'name': 'n', 'lv': lv, 'run': 0, 'created': 1, 'changed': 1};
    if (!identical(sc, _absent)) m['sc'] = sc;
    return jsonEncode(m);
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('model', () {
    test('default is empty (Last 10 payments); max is 2', () {
      expect(rule().chosenCategoryIds, isEmpty);
      expect(kMaxChosenCategories, 2);
    });
    test('copyWith keeps the list on null and replaces it when given', () {
      final r = rule(sc: [4, 7]);
      expect(r.copyWith(run: 2).chosenCategoryIds, [4, 7]);
      expect(r.copyWith(chosenCategoryIds: const [9]).chosenCategoryIds, [9]);
      expect(r.copyWith(chosenCategoryIds: const []).chosenCategoryIds, isEmpty);
    });
    test('== and hashCode follow the list (order counts); a copy of the list is equal', () {
      expect(rule(sc: [4, 7]), rule(sc: [4, 7]));
      expect(rule(sc: [4, 7]).hashCode, rule(sc: List<int>.of([4, 7])).hashCode);
      expect(rule(sc: [4, 7]) == rule(sc: [7, 4]), isFalse);
      expect(rule(sc: [4]) == rule(), isFalse);
    });
    test('valid list: at most 2, no id twice', () {
      expect(isValidChosenCategoryIds(const []), isTrue);
      expect(isValidChosenCategoryIds(const [1, 2]), isTrue);
      expect(isValidChosenCategoryIds(const [1, 2, 3]), isFalse);
      expect(isValidChosenCategoryIds(const [5, 5]), isFalse);
    });
    test('clamp: duplicates dropped, first 2 kept, order kept', () {
      expect(clampChosenCategoryIds(const [3, 3, 8, 9]), [3, 8]);
      expect(clampChosenCategoryIds(const [9, 1, 2]), [9, 1]);
      expect(clampChosenCategoryIds(const []), isEmpty);
      expect(() => clampChosenCategoryIds(const [1]).add(2), throwsUnsupportedError);
    });
  });

  group('codec sc', () {
    test('round trip with 1 and 2 ids', () {
      expect(decodeRule(encodeRule(rule(sc: [4])))!.chosenCategoryIds, [4]);
      final r = rule(sc: [7, 4]);
      expect(decodeRule(encodeRule(r)), r);
    });
    test('an empty list is not written (old shape kept)', () {
      expect((jsonDecode(encodeRule(rule())) as Map).containsKey('sc'), isFalse);
      expect((jsonDecode(encodeRule(rule(sc: [4]))) as Map)['sc'], [4]);
    });
    test('an old 0.2.1 rule (no sc) reads as empty', () {
      final r = decodeRule(json())!;
      expect(r.chosenCategoryIds, isEmpty);
      expect(decodeRule('{"v":1,"t":"SM","k":"a","name":"n","lv":1,"cat":4,"run":2,"runCat":4,"created":1,"changed":2,"lastRecorded":null}')!
          .chosenCategoryIds, isEmpty);
    });
    test('a bad sc drops the field, never the rule', () {
      for (final bad in <Object?>[
        null,
        [1, 2, 3],
        [1, 'x'],
        [1.5],
        ['3'],
        [4, 4],
        'not a list',
        7,
        {'a': 1},
        [null],
      ]) {
        final r = decodeRule(json(sc: bad));
        expect(r, isNotNull, reason: '$bad');
        expect(r!.chosenCategoryIds, isEmpty, reason: '$bad');
        expect(r.key, 'a');
      }
    });
    test('decodeChosenCategoryIds returns an unmodifiable list', () {
      expect(() => decodeChosenCategoryIds([1]).add(2), throwsUnsupportedError);
    });
  });

  // Both stores must behave the same: every case runs on each.
  final stores = <String, Future<RuleStore> Function()>{
    'PrefsRuleStore': () async => PrefsRuleStore(),
    'FakeRuleStore': () async => FakeRuleStore(),
  };

  for (final e in stores.entries) {
    group('${e.key} setLevel chosen list', () {
      test('stored at Suggested exactly as passed', () async {
        final s = await e.value();
        expect(await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, chosenCategoryIds: const [7, 4], at: t0), isTrue);
        expect((await s.get(sm, '0712'))!.chosenCategoryIds, [7, 4]);
      });
      test('the default (not passed) stores empty, so a caller that keeps a list passes it', () async {
        final s = await e.value();
        await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, chosenCategoryIds: const [7], at: t0);
        await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, chosenCategoryIds: const [7], at: t1);
        expect((await s.get(sm, '0712'))!.chosenCategoryIds, [7]);
        await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, at: t1);
        expect((await s.get(sm, '0712'))!.chosenCategoryIds, isEmpty);
      });
      test('Ask first clears it, even when a list is passed', () async {
        final s = await e.value();
        await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, chosenCategoryIds: const [7, 4], at: t0);
        expect(
            await s.setLevel(sm, '0712',
                name: 'Ann', level: RuleLevel.askFirst, categoryId: 7, chosenCategoryIds: const [7, 4], at: t1),
            isTrue);
        final r = (await s.get(sm, '0712'))!;
        expect(r.level, RuleLevel.askFirst);
        expect(r.categoryId, 7);
        expect(r.chosenCategoryIds, isEmpty);
      });
      test('Auto-record clears it', () async {
        final s = await e.value();
        await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, chosenCategoryIds: const [7], at: t0);
        expect(await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.autoRecord, categoryId: 7, at: t1), isTrue);
        expect((await s.get(sm, '0712'))!.chosenCategoryIds, isEmpty);
      });
      test('a list over 2 or with an id twice is refused at Suggested (nothing written)', () async {
        final s = await e.value();
        expect(await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, chosenCategoryIds: const [1, 2, 3], at: t0),
            isFalse);
        expect(await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, chosenCategoryIds: const [5, 5], at: t0),
            isFalse);
        expect(await s.get(sm, '0712'), isNull);
      });
      test('an existing caller (no chosen list) still compiles and stores empty at Ask first', () async {
        final s = await e.value();
        expect(await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.askFirst, categoryId: 2, at: t0), isTrue);
        expect((await s.get(sm, '0712'))!.chosenCategoryIds, isEmpty);
      });
      test('saveRule keeps the list (engine counters do not lose it)', () async {
        final s = await e.value();
        await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.suggested, chosenCategoryIds: const [4], at: t0);
        final r = (await s.get(sm, '0712'))!;
        await s.saveRule(r.copyWith(run: 3));
        expect((await s.get(sm, '0712'))!.chosenCategoryIds, [4]);
      });
    });

    group('${e.key} Reset everyone to Suggested (PM 25-11 Q2: keeps the chosen list)', () {
      test('a Suggested rule with a ceiling and 2 chosen ids: ceiling gone, list kept', () async {
        final s = await e.value();
        await s.saveRule(ReceiverRule(
            type: sm,
            key: '0712',
            name: 'Ann',
            level: RuleLevel.suggested,
            ceilingCents: 150000,
            chosenCategoryIds: const [7, 4],
            created: t0,
            changed: t0));
        await s.setLevel(sm, 'b', name: 'B', level: RuleLevel.askFirst, categoryId: 2, at: t0);
        final ops = RuleBulkOps(s, now: () => t1);
        expect(await ops.resetCount(), 2);
        expect(await ops.resetAllToSuggested(), 2);
        final r = (await s.get(sm, '0712'))!;
        expect(r.level, RuleLevel.suggested);
        expect(r.ceilingCents, isNull);
        expect(r.chosenCategoryIds, [7, 4]);
        final b = (await s.get(sm, 'b'))!;
        expect(b.level, RuleLevel.suggested);
        expect(b.chosenCategoryIds, isEmpty);
        expect(await ops.resetCount(), 0);
      });
    });

    group('${e.key} forgetEveryone / countEveryone', () {
      test('count and erase every rule; changes fires once; a second call is 0 and silent', () async {
        final s = await e.value();
        await s.setLevel(sm, 'a', name: 'A', level: RuleLevel.suggested, chosenCategoryIds: const [1], at: t0);
        await s.setLevel(sm, 'b', name: 'B', level: RuleLevel.askFirst, categoryId: 2, at: t0);
        await s.setLevel(ReceiverType.buyGoods, 'c', name: 'C', level: RuleLevel.autoRecord, categoryId: 2, at: t0);
        expect(await s.countEveryone(), 3);
        var fired = 0;
        final sub = s.changes.listen((_) => fired++);
        expect(await s.forgetEveryone(), 3);
        expect(fired, 1);
        expect(await s.countEveryone(), 0);
        expect(await s.all(), isEmpty);
        expect(await s.forgetEveryone(), 0);
        expect(fired, 1);
        await sub.cancel();
      });
    });
  }

  group('details OFF with hidden rule keys present', () {
    test('PrefsRuleStore: countEveryone counts them and forgetEveryone erases them, never through all()', () async {
      final a = encodeRule(rule(sc: [4, 7]));
      final b = encodeRule(ReceiverRule(
          type: ReceiverType.payBill, key: '888', name: 'Pay', level: RuleLevel.askFirst, categoryId: 2, created: t0, changed: t0));
      SharedPreferences.setMockInitialValues({
        kReceiverDetailsPrefsKey: false,
        ruleStorageKey(sm, '0712'): a,
        ruleStorageKey(ReceiverType.payBill, '888'): b,
        'some_other_pref': 'kept',
      });
      final s = PrefsRuleStore();
      expect(await s.countEveryone(), 2);
      expect(await s.forgetEveryone(), 2);
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys().where((k) => k.startsWith(kRuleKeyPrefix)), isEmpty);
      expect(p.getString('some_other_pref'), 'kept');
      expect(p.getBool(kReceiverDetailsPrefsKey), isFalse, reason: 'the switch itself is not touched');
      expect(await s.countEveryone(), 0);
    });
    test('PrefsRuleStore: a corrupt rule value is counted and erased too (every rule key)', () async {
      SharedPreferences.setMockInitialValues({ruleStorageKey(sm, 'x'): 'not json'});
      final s = PrefsRuleStore();
      expect(await s.countEveryone(), 1);
      expect(await s.forgetEveryone(), 1);
      expect(await s.countEveryone(), 0);
    });
    test('FakeRuleStore matches: rules held while detailsOn is false are counted and erased', () async {
      final s = FakeRuleStore();
      await s.setLevel(sm, 'a', name: 'A', level: RuleLevel.suggested, chosenCategoryIds: const [1], at: t0);
      await s.setLevel(sm, 'b', name: 'B', level: RuleLevel.askFirst, categoryId: 2, at: t0);
      s.detailsOn = false;
      expect(await s.countEveryone(), 2);
      expect(await s.forgetEveryone(), 2);
      s.detailsOn = true;
      expect(await s.countEveryone(), 0);
      expect(await s.all(), isEmpty);
    });
    test('setLevel with a chosen list is refused while OFF (both stores)', () async {
      SharedPreferences.setMockInitialValues({kReceiverDetailsPrefsKey: false});
      expect(
          await PrefsRuleStore()
              .setLevel(sm, 'a', name: 'A', level: RuleLevel.suggested, chosenCategoryIds: const [1], at: t0),
          isFalse);
      final f = FakeRuleStore()..detailsOn = false;
      expect(await f.setLevel(sm, 'a', name: 'A', level: RuleLevel.suggested, chosenCategoryIds: const [1], at: t0), isFalse);
    });
  });
}
