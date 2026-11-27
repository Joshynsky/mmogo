// 0.2.2 restore keeps rules (Option B, PM 26-11): Auto-record people come back at level 2 with the
// pending marker (`ap`), the engine acts as Ask first meanwhile, Merge replaces only a phone Suggested
// rule, Keep / Turn off through RestoredAutoRecord, schema 8 files, the Rules-line counts.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/hard_rule_decision.dart';
import 'package:mmogo/autoread/rules/restored_auto_record.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_restore.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

final _at = DateTime.utc(2026, 11, 26);
const _sm = ReceiverType.sendMoney;

RestoreService _svc(Database db, RuleStore store) => RestoreService(
      db: () async => db,
      backup: backupOf(db),
      safety: FakeSafetyCopyStore([]),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      validateInIsolate: false,
      afterReplace: () async {},
      rules: RuleRestoreApplier(store: store, detailsOn: () async => true, now: () => _at),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late Database db;
  setUp(() async => db = await openTestDb());

  Uint8List bytes(List<Map<String, Object?>> rules, {int schema = 9}) =>
      fileBytes(fileJson(classes: seedRowsV5(), txs: const [], rules: rules, schemaVersion: schema));

  Future<ReceiverRule> add(FakeRuleStore s, String k, String name, RuleLevel lv) async {
    await s.saveRule(ReceiverRule(type: _sm, key: k, name: name, level: lv, categoryId: lv == RuleLevel.suggested ? null : 4, created: _at, changed: _at));
    return (await s.get(_sm, k))!;
  }

  group('restored Auto-record is pending and acts as Ask first', () {
    test('level 2 + ap stored; the Dart engine decides Ask first, not record', () async {
      final store = FakeRuleStore();
      await _svc(db, store).restore(bytes([ruleRow('SM', '1', name: 'Mama', lv: 2, catSeed: 'SEND_MONEY:rent', ceil: 9000)]), RestoreMode.replace);
      final r = (await store.get(_sm, '1'))!;
      expect([r.level, r.autoPending, r.ceilingCents], [RuleLevel.autoRecord, true, 9000]);
      HardRuleDecision decide(ReceiverRule x) => decideHardRule(rule: x, kind: _sm, amountCents: 100, paused: false, detailsOn: true);
      expect(decide(r), HardRuleDecision.askFirst);
      expect(decide(r.copyWith(autoPending: false)), HardRuleDecision.record, reason: 'after Keep it records');
    });

    test('file Auto-record with ap already 1 stays level 2 pending; Paybill lv 2 is Ask first without the marker', () async {
      final store = FakeRuleStore();
      await _svc(db, store).restore(
          bytes([ruleRow('SM', '1', lv: 2, ap: 1, catSeed: 'SEND_MONEY:rent'), ruleRow('PB', '888', lv: 2, ap: 0)]), RestoreMode.replace);
      expect((await store.get(_sm, '1'))!.autoPending, isTrue);
      final pb = (await store.get(ReceiverType.payBill, '888'))!;
      expect([pb.level, pb.autoPending], [RuleLevel.askFirst, false]);
    });

    test('schema 8 file (no rules): Replace leaves none, Merge leaves the phone alone', () async {
      final store = FakeRuleStore();
      await add(store, '1', 'Phone', RuleLevel.autoRecord);
      await _svc(db, store).restore(bytes(const [], schema: 8), RestoreMode.merge);
      expect(await store.all(), hasLength(1));
      await _svc(db, store).restore(bytes(const [], schema: 8), RestoreMode.replace);
      expect(await store.all(), isEmpty);
    });
  });

  group('Merge rule', () {
    test('Suggest replaced; Ask first and Auto-record stay and are named; counts for the Rules line', () async {
      final store = FakeRuleStore();
      await add(store, 'sug', 'Sue', RuleLevel.suggested);
      await add(store, 'ask', 'Ann', RuleLevel.askFirst);
      final auto = await add(store, 'aut', 'Auto Al', RuleLevel.autoRecord);
      final out = (await _svc(db, store).restore(
              bytes([
                ruleRow('SM', 'sug', name: 'Sue F', lv: 2, catSeed: 'SEND_MONEY:rent'),
                ruleRow('SM', 'ask', name: 'Ann F', lv: 0),
                ruleRow('SM', 'aut', name: 'Al F', lv: 1),
                ruleRow('SM', 'new', name: 'New', lv: 1),
              ]),
              RestoreMode.merge))
          .rules!;
      expect([out.added, out.replaced, out.keptPhone], [1, 1, 2]);
      expect(out.keptLocalNames, ['Ann', 'Auto Al']);
      final sue = (await store.get(_sm, 'sug'))!;
      expect([sue.name, sue.level, sue.autoPending], ['Sue F', RuleLevel.autoRecord, true]);
      expect((await store.get(_sm, 'ask'))!.level, RuleLevel.askFirst);
      expect(await store.get(_sm, 'aut'), auto, reason: 'untouched, byte for byte');
      expect(restoreRulesLine(added: out.added, replaced: out.replaced, keptPhone: out.keptPhone),
          'Rules: 1 added, 1 replaced, 2 kept from this phone.');
    });

    test('Replace is unchanged: everything from the file, no names kept', () async {
      final store = FakeRuleStore();
      await add(store, 'ask', 'Ann', RuleLevel.askFirst);
      final out = (await _svc(db, store).restore(bytes([ruleRow('SM', 'ask', name: 'Ann F', lv: 0)]), RestoreMode.replace)).rules!;
      expect([out.added, out.replaced, out.keptPhone, out.keptLocalNames], [1, 0, 0, isEmpty]);
      expect((await store.get(_sm, 'ask'))!.level, RuleLevel.suggested);
    });

    test('Merge: an identical Suggested rule is not counted as replaced; a changed one is', () async {
      final store = FakeRuleStore();
      await add(store, 'same', 'Sam', RuleLevel.suggested);
      await add(store, 'diff', 'Dee', RuleLevel.suggested);
      final out = (await _svc(db, store).restore(
              bytes([ruleRow('SM', 'same', name: 'Sam', lv: 0), ruleRow('SM', 'diff', name: 'Dee', lv: 1, catSeed: 'SEND_MONEY:rent')]),
              RestoreMode.merge))
          .rules!;
      expect([out.added, out.replaced, out.keptPhone], [0, 1, 0]);
    });

    test('Rules line text: zero parts left out, null when nothing happened', () {
      expect(restoreRulesLine(added: 0, replaced: 0, keptPhone: 0), isNull);
      expect(restoreRulesLine(added: 3, replaced: 0, keptPhone: 0), 'Rules: 3 added.');
      expect(restoreRulesNeedKeep(1), '1 person on Auto-record needs a Keep.');
      expect(restoreRulesNeedKeep(2), '2 people on Auto-record need a Keep.');
    });
  });

  group('RestoredAutoRecord', () {
    late FakeRuleStore store;
    late RestoredAutoRecord api;
    setUp(() async {
      store = FakeRuleStore();
      api = RestoredAutoRecord(store: store, categoryName: (id) async => 'Cat$id', now: () => _at);
      await _svc(db, store).restore(
          bytes([
            ruleRow('SM', 'a', name: 'Amy', lv: 2, catSeed: 'SEND_MONEY:rent', ceil: 500),
            ruleRow('BG', 'b', name: 'Bob Till', lv: 2, catSeed: 'BUY_GOODS:groceries'),
            ruleRow('SM', 'c', name: 'Cy', lv: 1, ap: 1),
            ruleRow('SM', 'd', name: 'Di', lv: 0),
          ]),
          RestoreMode.replace);
      await api.refresh();
    });
    tearDown(() => api.dispose());

    test('pending lists only Auto-record people with the marker; count follows', () async {
      expect(api.count.value, 2);
      final p = await api.pending();
      expect(p.map((x) => (x.name, x.key)), [('Amy', 'a'), ('Bob Till', 'b')]);
      expect(p.every((x) => x.categoryName != null && x.categoryName!.startsWith('Cat')), isTrue);
    });

    test('keepAll clears the marker, people stay Auto-record, others untouched', () async {
      await api.keepAll();
      expect(api.count.value, 0);
      expect(await api.pending(), isEmpty);
      final a = (await store.get(_sm, 'a'))!;
      expect([a.level, a.autoPending, a.ceilingCents], [RuleLevel.autoRecord, false, 500]);
      expect((await store.get(_sm, 'c'))!.autoPending, isTrue, reason: 'Ask first review mark is not this banner\'s');
    });

    test('turnOffAll sets Ask first, clears the marker, keeps category and limit', () async {
      await api.turnOffAll();
      expect(api.count.value, 0);
      final a = (await store.get(_sm, 'a'))!;
      expect([a.level, a.autoPending, a.ceilingCents, a.categoryId], [RuleLevel.askFirst, false, 500, isNotNull]);
      expect((await store.get(ReceiverType.buyGoods, 'b'))!.level, RuleLevel.askFirst);
      expect((await store.get(_sm, 'd'))!.level, RuleLevel.suggested);
    });

    test('count follows store changes (a person sets a level themselves)', () async {
      await store.setLevel(_sm, 'a', name: 'Amy', level: RuleLevel.askFirst, categoryId: 4, at: _at);
      await Future<void>.delayed(Duration.zero);
      expect(api.count.value, 1);
    });
  });
}
