// 0.2.2 item 2, B-HIDE (PM 25-11, reverses the 0.2.1 privacy wipe): "Record receiver details" OFF HIDES the
// rules and ON brings them back exactly as before. Forget all and Delete data still erase. Nothing reads a
// hidden rule while OFF (labeller, offers, chips, engine). The fake store and the real store agree.
// Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/autoread_wipe.dart';
import 'package:mmogo/autoread/data/suggested_chips_source.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/history/rule_labeler.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_rule_engine.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/receiver_key.dart';
import 'package:mmogo/autoread/rules/rule_backup_guard.dart';
import 'package:mmogo/autoread/rules/rule_backup_source.dart';
import 'package:mmogo/autoread/rules/rule_cleanup.dart';
import 'package:mmogo/autoread/rules/rule_codec.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_restore.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/data/backup/restore_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/waiting_fakes.dart';
import '../logic/reading_fakes.dart';

const _sm = ReceiverType.sendMoney;
const _bg = ReceiverType.buyGoods;
const _po = ReceiverType.pochi;
final _t0 = DateTime.utc(2026, 11, 25, 9);

/// One store plus its details switch, so the same table runs on the real and the fake store.
class _Side {
  _Side(this.name, this.store, this.setDetails);
  final String name;
  final RuleStore store;
  final Future<void> Function(bool on) setDetails;
}

_Side _prefsSide() => _Side('PrefsRuleStore', PrefsRuleStore(),
    (on) async => (await SharedPreferences.getInstance()).setBool(kReceiverDetailsPrefsKey, on));

_Side _fakeSide() {
  final s = FakeRuleStore();
  return _Side('FakeRuleStore', s, (on) async => s.detailsOn = on);
}

/// Jane: Auto-record, category 7, limit Ksh 500. Ann: Ask first, category 3, no limit. Sue: Suggested with the
/// chosen list [4, 7]. Bob: a Pochi on Ask first.
Future<void> _seed(RuleStore s) async {
  expect(await s.setLevel(_sm, '0712345678', name: 'Jane', level: RuleLevel.autoRecord, categoryId: 7, ceilingCents: 50000, at: _t0), isTrue);
  expect(await s.setLevel(_bg, 'MAMA MBOGA', name: 'Ann', level: RuleLevel.askFirst, categoryId: 3, at: _t0), isTrue);
  expect(await s.setLevel(_sm, '0799000111', name: 'Sue', level: RuleLevel.suggested, chosenCategoryIds: const [4, 7], at: _t0), isTrue);
  expect(await s.setLevel(_po, 'BOB', name: 'Bob', level: RuleLevel.askFirst, categoryId: 2, at: _t0), isTrue);
}

Set<ReceiverRule> _set(List<ReceiverRule> l) => l.toSet();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final make in [_prefsSide, _fakeSide]) {
    group(make().name, () {
      test('OFF hides everyone (all empty, get null) and ON brings back level, category, limit and chosen list', () async {
        final side = make();
        final s = side.store;
        await _seed(s);
        final before = _set(await s.all());
        expect(before.length, 4);
        await side.setDetails(false);
        expect(await s.all(), isEmpty);
        for (final r in before) {
          expect(await s.get(r.type, r.key), isNull, reason: r.name);
        }
        expect(await s.countEveryone(), 4, reason: 'hidden, not erased');
        await side.setDetails(true);
        expect(_set(await s.all()), before);
        final jane = (await s.get(_sm, '0712345678'))!;
        expect((jane.level, jane.categoryId, jane.ceilingCents), (RuleLevel.autoRecord, 7, 50000));
        final ann = (await s.get(_bg, 'MAMA MBOGA'))!;
        expect((ann.level, ann.categoryId, ann.ceilingCents), (RuleLevel.askFirst, 3, null));
        final sue = (await s.get(_sm, '0799000111'))!;
        expect(sue.level, RuleLevel.suggested);
        expect(sue.chosenCategoryIds, [4, 7]);
      });

      test('OFF refuses setLevel and saveRule; the hidden rule is unchanged at ON', () async {
        final side = make();
        final s = side.store;
        await _seed(s);
        final before = _set(await s.all());
        await side.setDetails(false);
        expect(await s.setLevel(_sm, '0712345678', name: 'Jane', level: RuleLevel.suggested, at: _t0.add(const Duration(days: 1))), isFalse);
        expect(await s.setLevel(_sm, '0700999888', name: 'New', level: RuleLevel.askFirst, categoryId: 1, at: _t0), isFalse);
        expect(await s.saveRule(ReceiverRule(type: _sm, key: '0712345678', name: 'Jane', created: _t0, changed: _t0)), isFalse);
        await side.setDetails(true);
        expect(_set(await s.all()), before);
      });

      test('Forget all while OFF erases the hidden rules (forgetEveryone); ON brings nobody back', () async {
        final side = make();
        final s = side.store;
        await _seed(s);
        await side.setDetails(false);
        expect(await s.forgetEveryone(), 4);
        expect(await s.countEveryone(), 0);
        await side.setDetails(true);
        expect(await s.all(), isEmpty);
      });

      test('Forget one person while OFF erases that hidden rule', () async {
        final side = make();
        final s = side.store;
        await _seed(s);
        await side.setDetails(false);
        await s.forget(_sm, '0712345678');
        await side.setDetails(true);
        expect(await s.get(_sm, '0712345678'), isNull);
        expect((await s.all()).length, 3);
      });

      test('backup export while OFF carries no rules (hidden = not used)', () async {
        final side = make();
        await _seed(side.store);
        expect((await backupRulesFrom(side.store)).length, 4);
        await side.setDetails(false);
        expect(await backupRulesFrom(side.store), isEmpty);
      });

      const fileRow = RestoredRule(type: 'SM', key: '0711222333', name: 'Kim', level: 1, categoryId: 5);

      test('DECISION: a Replace restore while OFF also clears the hidden rules (file rows left out)', () async {
        final side = make();
        await _seed(side.store);
        await side.setDetails(false);
        final out = await RuleRestoreApplier(store: side.store, detailsOn: () async => false)
            .apply(const RulesRestorePlan(replace: true, hasSection: true, rows: [fileRow]));
        expect(out.phoneRulesCleared, isTrue);
        expect(out.droppedForPrivacy, 1);
        expect(await side.store.countEveryone(), 0);
        await side.setDetails(true);
        expect(await side.store.all(), isEmpty, reason: 'ON does not bring back the pre-restore settings');
      });

      test('DECISION: a Merge restore while OFF leaves the hidden rules (file rows left out)', () async {
        final side = make();
        await _seed(side.store);
        final before = _set(await side.store.all());
        await side.setDetails(false);
        final out = await RuleRestoreApplier(store: side.store, detailsOn: () async => false)
            .apply(const RulesRestorePlan(replace: false, hasSection: true, rows: [fileRow]));
        expect(out.phoneRulesCleared, isFalse);
        expect(out.droppedForPrivacy, 1);
        await side.setDetails(true);
        expect(_set(await side.store.all()), before);
      });

      test('chips: a hidden Ask first rule is not read (same chips as with no rule at all)', () async {
        final side = make();
        final key = receiverKey(_sm, phone: '0700000000')!;
        final history = FakeHistoryReader(history: {'SM.$key': [1, 2]});
        final src = SuggestedChipsSource(rules: side.store, history: history, recordReceiverDetails: () async => true);
        final item = WaitingItem(
          id: heldIdFor(1),
          kind: WaitingKind.waitingCategory,
          heldAt: _t0,
          parsed: sampleFields(0, _t0),
          hint: RuleHint(level: RuleLevel.suggested, type: _sm, key: key, suggested: const [1, 2]),
        );
        final noRule = await src.chipsFor(item, _cats);
        expect(noRule, isNotEmpty);
        await side.store.setLevel(_sm, key, name: 'Shop', level: RuleLevel.askFirst, categoryId: 1, at: _t0);
        expect(await src.chipsFor(item, _cats), isEmpty, reason: 'ON: Ask first keeps its own flow');
        await side.setDetails(false);
        expect([for (final c in await src.chipsFor(item, _cats)) c.id], [for (final c in noRule) c.id]);
      });

      test('labeller: a hidden Ask first rule gives no Ask first hint', () async {
        final side = make();
        final key = receiverKey(_sm, phone: '0700000000')!;
        await side.store.setLevel(_sm, key, name: 'Shop', level: RuleLevel.askFirst, categoryId: 1, at: _t0);
        // The store alone is tested here: the labeller is told details are ON, the store is OFF.
        final lab = RuleLabeler(rules: side.store, history: FakeHistoryReader(), recordReceiverDetails: () async => true);
        expect((await lab.label(sampleFields(0, _t0)))?.level, RuleLevel.askFirst);
        await side.setDetails(false);
        expect(await lab.label(sampleFields(0, _t0)), isNull);
        // And the real wiring (details OFF on both): no hint either.
        final real = RuleLabeler(rules: side.store, history: FakeHistoryReader(), recordReceiverDetails: () async => false);
        expect(await real.label(sampleFields(0, _t0)), isNull);
      });
    });
  }

  group('the fake and the real store agree', () {
    test('the same steps give the same answers on both', () async {
      Future<List<Object?>> run(_Side side) async {
        final s = side.store;
        final out = <Object?>[];
        await _seed(s);
        await side.setDetails(false);
        out.add((await s.all()).length);
        out.add(await s.get(_sm, '0712345678'));
        out.add(await s.setLevel(_sm, '0712345678', name: 'J', level: RuleLevel.askFirst, categoryId: 1, at: _t0));
        out.add(await s.countEveryone());
        await s.forget(_po, 'BOB');
        await side.setDetails(true);
        out.add([for (final r in await s.all()) '${r.type.code}.${r.key}.${r.level.name}.${r.categoryId}.${r.ceilingCents}.${r.chosenCategoryIds}']..sort());
        await side.setDetails(false);
        out.add(await s.forgetEveryone());
        await side.setDetails(true);
        out.add((await s.all()).length);
        return out;
      }

      final real = await run(_prefsSide());
      final fake = await run(_fakeSide());
      expect(fake, real);
      expect(real.first, 0);
    });
  });

  test('FakeRuleStore.refuseWrites refuses writes but keeps the rules readable (unlike details OFF)', () async {
    final s = FakeRuleStore();
    await _seed(s);
    s.refuseWrites = true;
    expect(await s.setLevel(_sm, '0700999888', name: 'New', level: RuleLevel.askFirst, categoryId: 1, at: _t0), isFalse);
    expect(await s.saveRule(ReceiverRule(type: _sm, key: '0712345678', name: 'Jane', created: _t0, changed: _t0)), isFalse);
    expect((await s.all()).length, 4);
    expect(await s.get(_sm, '0712345678'), isNotNull);
  });

  group('PrefsRuleStore and the guard', () {
    test('OFF reads never erase and never fire changes', () async {
      final s = PrefsRuleStore();
      await _seed(s);
      var fired = 0;
      final sub = s.changes.listen((_) => fired++);
      await (await SharedPreferences.getInstance()).setBool(kReceiverDetailsPrefsKey, false);
      expect(await s.all(), isEmpty);
      expect(await s.get(_sm, '0712345678'), isNull);
      expect(fired, 0);
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys().where((k) => k.startsWith(kRuleKeyPrefix)).length, 4);
      await sub.cancel();
    });

    test('clearDetailsOffData clears only the undone codes and the summary; wipe still clears everything', () async {
      final p = FakeReadingPrefs();
      p.data['${kRuleKeyPrefix}SM.x'] = 'v';
      p.data[kUndoneCodesKey] = 'v';
      p.data[kHistorySummaryKey] = 'v';
      p.data['other'] = 'keep';
      final g = RuleBackupGuard(prefs: p);
      expect(await g.clearDetailsOffData(), isTrue);
      expect(p.data.keys.toSet(), {'${kRuleKeyPrefix}SM.x', 'other'});
      expect(await g.wipe(), isTrue);
      expect(p.data.keys.toList(), ['other']);
      expect(kDetailsOffClearedPrefixes, [kUndoneCodesKey, kHistorySummaryKey]);
    });

    test('clearDetailsOffData fails closed when a key stays', () async {
      final p = FakeReadingPrefs();
      p.data[kUndoneCodesKey] = 'v';
      p.failRemove = true;
      expect(await RuleBackupGuard(prefs: p).clearDetailsOffData(), isFalse);
    });

    test('Delete data while OFF erases the hidden rules (AutoReadWipe -> guard.wipe)', () async {
      final s = PrefsRuleStore();
      await _seed(s);
      await PrefsUndoneCodes().add('CODE000001', now: DateTime.now());
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kReceiverDetailsPrefsKey, false);
      final prefs = SharedReadingPrefs();
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 0);
      final c = ReadingController(bridge: b, store: FakeGenerationStore(), prefs: prefs);
      expect(await AutoReadWipe(controller: () => c, prefs: prefs, rules: RuleBackupGuard(prefs: prefs)).run(), isTrue);
      await sp.reload();
      expect(sp.getKeys().where((k) => kRuleKeyPrefixes.any(k.startsWith)), isEmpty);
      await sp.setBool(kReceiverDetailsPrefsKey, true);
      expect(await s.all(), isEmpty, reason: 'ON brings nobody back after Delete data');
    });

    test('a Replace restore guard while OFF erases the hidden rules too', () async {
      final s = PrefsRuleStore();
      await _seed(s);
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kReceiverDetailsPrefsKey, false);
      expect(await RuleBackupGuard().afterReplaceRestore(), isTrue);
      await sp.setBool(kReceiverDetailsPrefsKey, true);
      expect(await s.all(), isEmpty);
    });

    test('launch/resume with details OFF keeps the rules and clears the undone codes and summary', () async {
      final s = PrefsRuleStore();
      await _seed(s);
      final before = _set(await s.all());
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kUndoneCodesKey, '{}');
      await sp.setString(kHistorySummaryKey, '{}');
      await sp.setBool(kReceiverDetailsPrefsKey, false);
      await RuleCleanup(s, guard: RuleBackupGuard(prefs: SharedReadingPrefs())).enforceDetailsOff();
      await sp.reload();
      expect(sp.containsKey(kUndoneCodesKey), isFalse);
      expect(sp.containsKey(kHistorySummaryKey), isFalse);
      await sp.setBool(kReceiverDetailsPrefsKey, true);
      expect(_set(await s.all()), before);
    });

    test('Forget all remembered names while OFF erases the hidden Pochi rules only', () async {
      final s = PrefsRuleStore();
      await _seed(s);
      await s.setLevel(_po, 'AMY', name: 'Amy', level: RuleLevel.suggested, at: _t0);
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kReceiverDetailsPrefsKey, false);
      await RuleCleanup(s, guard: RuleBackupGuard(prefs: FakeReadingPrefs())).onAllNamesForgotten();
      await sp.setBool(kReceiverDetailsPrefsKey, true);
      expect(await s.get(_po, 'BOB'), isNull);
      expect(await s.get(_po, 'AMY'), isNull);
      expect((await s.all()).map((r) => r.name).toSet(), {'Jane', 'Ann', 'Sue'});
    });

    test('engine while OFF: offers are empty and a record does not overwrite the hidden rule', () async {
      final s = PrefsRuleStore();
      final e = PrefsRuleEngine(s);
      // Sue becomes due for an offer (3 in a row in category 4, default Suggest after = 3).
      for (var i = 0; i < 3; i++) {
        await e.onRecorded(_sm, '0799000111', name: 'Sue', categoryId: 4, at: _t0.add(Duration(minutes: i)));
      }
      await s.setLevel(_bg, 'MAMA MBOGA', name: 'Ann', level: RuleLevel.askFirst, categoryId: 3, at: _t0);
      expect((await e.pendingOffers()).map((o) => o.name), ['Sue']);
      final before = _set(await s.all());
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kReceiverDetailsPrefsKey, false);
      expect(await e.pendingOffers(), isEmpty);
      await e.onRecorded(_bg, 'MAMA MBOGA', name: 'Ann', categoryId: 9, at: _t0.add(const Duration(days: 1)));
      await e.onRecorded(_sm, '0799000111', name: 'Sue', categoryId: 4, at: _t0.add(const Duration(days: 1)));
      await e.notNow(_sm, '0799000111');
      await sp.setBool(kReceiverDetailsPrefsKey, true);
      expect(_set(await s.all()), before);
      expect((await e.pendingOffers()).map((o) => o.name), ['Sue']);
    });
  });
}

class _Choices implements CategoryChoices {
  _Choices(this.cats);
  final List<CategoryChoice> cats;
  @override
  Future<List<CategoryChoice>> categories() async => cats;
  @override
  Future<CategoryChoice> create(String name) async => throw UnimplementedError();
}

final _cats = _Choices(const [
  CategoryChoice(id: '1', name: 'Family and friends'),
  CategoryChoice(id: '2', name: 'Debts'),
]);
