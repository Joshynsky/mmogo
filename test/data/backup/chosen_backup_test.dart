// 0.2.2 item 2, slice B-BK: the chosen Suggest categories ("Categories I choose", `sc`) in the
// backup rule row. Export (map by seed key / name, trim), restore (map back, ACTIVE only, clamp to
// 2, Suggested only, unreadable = empty), round trip, old file, Merge, details OFF, Undo of a
// Replace, and the Reset-everyone follow-on (a restored list must stay valid for setLevel).
// Real in-memory sqlite, invented data, no wording.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_backup_source.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_restore.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart' show RuleBulkOps;
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_rules.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_rules.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

final _at = DateTime.utc(2026, 11, 25);

const _rent = 'SEND_MONEY:rent';
const _transport = 'SEND_MONEY:transport';
const _groceries = 'SEND_MONEY:groceries';

Map<String, Object?> _seed(String k) => {'cat_seed': k};
Map<String, Object?> _own(String n) => {'cat_name': n};

RuleRestoreSink _sink(RuleStore s, {bool detailsOn = true}) =>
    RuleRestoreApplier(store: s, detailsOn: () async => detailsOn, now: () => _at);

RestoreService _svc(Database db, RuleRestoreSink? sink, {FakeSafetyCopyStore? safety, BackupService? backup}) =>
    RestoreService(
      db: () async => db,
      backup: backup ?? backupOf(db),
      safety: safety ?? FakeSafetyCopyStore([]),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      validateInIsolate: false,
      afterReplace: () async {},
      rules: sink,
    );

BackupService _backup(Database db, BackupRulesSource? rules) => BackupService(
      db: () async => db,
      now: () => DateTime.fromMillisecondsSinceEpoch(t0 + 999999),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      rules: rules,
    );

Uint8List _bytes(List<Map<String, Object?>> rules,
        {List<Map<String, Object?>> classes = const [], int schema = 9}) =>
    fileBytes(fileJson(classes: classes.isEmpty ? seedRowsV5() : classes, rules: rules, schemaVersion: schema));

Map<String, Object?> _json(Uint8List b) => jsonDecode(utf8.decode(b)) as Map<String, Object?>;
List<Map<String, Object?>> _ruleRows(Map<String, Object?> j) => (j['receiver_rules']! as List).cast<Map<String, Object?>>();

BackupRuleInput _in(String t, String k, {int lv = 0, List<int> sc = const []}) =>
    BackupRuleInput(type: t, key: k, name: 'Person', level: lv, chosenCategoryIds: sc);

/// The phone's ids for seed keys, in the order given.
Future<List<int>> _seedIds(Database db, List<String> keys) async => [for (final k in keys) await seedId(db, k)];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('constants', () {
    test('sc is the last rule key; the cap mirrors the rule model', () {
      expect(kBackupRuleKeys.last, 'sc');
      expect(kBackupMaxChosenCategories, kMaxChosenCategories);
    });
  });

  group('export builder (pure)', () {
    final classes = <Map<String, Object?>>[
      {'id': 1, 'seed_key': _rent, 'name': 'Rent'},
      {'id': 2, 'seed_key': null, 'name': 'My own'},
      {'id': 3, 'seed_key': _transport, 'name': 'Transport'},
    ];

    test('a Suggested list is written by seed key / name, in order; nothing to trim = not repaired', () {
      final r = buildBackupRuleRows([_in('SM', 'a', sc: [2, 1]), _in('SM', 'b')], classes);
      expect(r.rows[0]['sc'], [_own('My own'), _seed(_rent)]);
      expect(r.rows[1]['sc'], isEmpty);
      expect(r.repaired, 0);
    });

    test('an unknown id is dropped, an id twice is written once, more than 2 keeps the first 2; each counted', () {
      final r = buildBackupRuleRows([
        _in('SM', 'a', sc: [99, 1]),
        _in('SM', 'b', sc: [1, 1]),
        _in('SM', 'c', sc: [3, 1, 2]),
      ], classes);
      expect(r.rows[0]['sc'], [_seed(_rent)]);
      expect(r.rows[1]['sc'], [_seed(_rent)]);
      expect(r.rows[2]['sc'], [_seed(_transport), _seed(_rent)]);
      expect(r.repaired, 3);
      expect(r.skipped, isEmpty, reason: 'a chosen list never skips the rule');
    });

    test('above Suggested the list is never written (and a stray one counts as repaired)', () {
      final r = buildBackupRuleRows([
        _in('SM', 'a', lv: 1, sc: [1]),
        _in('SM', 'b', lv: 2, sc: [1, 2]),
        _in('PB', 'c', lv: 2, sc: [1]),
        _in('SM', 'd', lv: 1),
      ], classes);
      for (final row in r.rows) {
        expect(row['sc'], isEmpty, reason: '${row['k']}');
      }
      expect(r.repaired, 3, reason: 'a, b, c (c is also the Paybill repair: one count per row)');
    });

    test('every built row passes the validator', () {
      final r = buildBackupRuleRows([
        for (var i = 0; i < 30; i++) _in(kBackupRuleTypes[i % 4], 'k$i', lv: i % 3, sc: [for (var j = 0; j <= i % 4; j++) j % 3 + 1]),
      ], classes);
      final v = BackupValidator.validate(_bytes(r.rows));
      expect(v.receiverRules.length, r.rows.length);
    });
  });

  group('export (real in-memory database)', () {
    test('the store adapter carries the list; the file names categories, never ids', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final own = await addClass(db, 'SEND_MONEY', 'Invented Hobby');
      final store = PrefsRuleStore();
      final ids = [await seedId(db, _rent), own];
      expect(
          await store.setLevel(ReceiverType.sendMoney, 'jo', name: 'Jo', level: RuleLevel.suggested, chosenCategoryIds: ids, at: _at),
          isTrue);
      final e = await _backup(db, () => backupRulesFrom(store)).export();
      final row = _ruleRows(_json(e.bytes)).single;
      expect(row['sc'], [_seed(_rent), _own('Invented Hobby')]);
      expect(row.keys.toList(), kBackupRuleKeys);
      expect(e.skippedCount, 0);
    });

    test('a list whose category was deleted for good is written without it', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final e = await _backup(db, () async => [_in('SM', 'jo', sc: [987654, await seedId(db, _rent)])]).export();
      expect(_ruleRows(_json(e.bytes)).single['sc'], [_seed(_rent)]);
    });
  });

  group('restore (Replace)', () {
    test('round trip: export then Replace into a fresh phone brings the list back on the NEW ids', () async {
      final src = await openTestDb();
      addTearDown(src.close);
      final own = await addClass(src, 'SEND_MONEY', 'Invented Hobby');
      final from = FakeRuleStore();
      await from.setLevel(ReceiverType.sendMoney, 'jo',
          name: 'Jo', level: RuleLevel.suggested, chosenCategoryIds: [own, await seedId(src, _rent)], at: _at);
      await from.setLevel(ReceiverType.buyGoods, '55', name: 'Shop', level: RuleLevel.suggested, at: _at);
      final bytes = (await _backup(src, () => backupRulesFrom(from)).export()).bytes;

      final dst = await openTestDb();
      addTearDown(dst.close);
      await addClass(dst, 'SEND_MONEY', 'Filler so ids shift');
      final to = FakeRuleStore();
      final r = await _svc(dst, _sink(to)).restore(bytes, RestoreMode.replace);
      expect(r.rules!.added, 2);
      final jo = (await to.get(ReceiverType.sendMoney, 'jo'))!;
      expect(jo.level, RuleLevel.suggested);
      expect(jo.chosenCategoryIds, [await classId(dst, 'SEND_MONEY', 'Invented Hobby'), await seedId(dst, _rent)]);
      expect((await to.get(ReceiverType.buyGoods, '55'))!.chosenCategoryIds, isEmpty);
    });

    // I2: a file with more than 2 entries is now refused by the validator (field sc), so the planner's clamp
    // (the defence behind it) is tested on the planner itself.
    test('clamp (planner): more than 2 keeps the first 2 found; an entry twice is kept once', () {
      const cats = RuleCategoryLookup(idBySeed: {_transport: 11, _rent: 12, _groceries: 13}, activeIds: {11, 12, 13});
      expect(restoredChosenIds([_seed(_transport), _seed(_rent), _seed(_groceries)], cats), [11, 12]);
      expect(restoredChosenIds([_seed(_rent), _seed(_rent), _seed(_groceries)], cats), [12, 13]);
    });

    test('a deleted category is dropped: inactive own category, parked built-in, unknown name', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final store = FakeRuleStore();
      final classes = [
        for (final c in seedRowsV5()) c['seed_key'] == _transport ? {...c, 'active': 0} : c,
        cls(30, 'SEND_MONEY', 'Gone hobby', active: 0),
        cls(31, 'SEND_MONEY', 'Live hobby'),
      ];
      await _svc(db, _sink(store)).restore(
          _bytes([
            ruleRow('SM', 'a', lv: 0, sc: [_own('Gone hobby'), _own('Live hobby')]),
            ruleRow('SM', 'b', lv: 0, sc: [_seed(_transport), _own('Ghost')]),
          ], classes: classes),
          RestoreMode.replace);
      expect((await store.get(ReceiverType.sendMoney, 'a'))!.chosenCategoryIds, [await classId(db, 'SEND_MONEY', 'Live hobby')]);
      final b = (await store.get(ReceiverType.sendMoney, 'b'))!;
      expect(b.chosenCategoryIds, isEmpty, reason: 'none left = Last 10 payments; the rule itself is kept');
      expect(b.level, RuleLevel.suggested);
      // I2: 4 entries no longer pass the validator; the planner still skips dropped ones before counting 2.
      final rent = await seedId(db, _rent);
      final groceries = await seedId(db, _groceries);
      expect(
          restoredChosenIds([_own('Ghost'), _seed(_transport), _seed(_rent), _seed(_groceries)],
              RuleCategoryLookup(idBySeed: {_rent: rent, _groceries: groceries}, activeIds: {rent, groceries})),
          [rent, groceries],
          reason: 'dropped entries do not use up the 2 places');
    });

    test('kept only at Suggested: Ask first and Auto-record rows in the file restore with an empty list', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final store = FakeRuleStore();
      await _svc(db, _sink(store)).restore(
          _bytes([
            ruleRow('SM', 'a', lv: 1, catSeed: _rent, sc: [_seed(_rent)]),
            ruleRow('SM', 'b', lv: 2, catSeed: _rent, sc: [_seed(_transport)]),
          ]),
          RestoreMode.replace);
      for (final k in ['a', 'b']) {
        final x = (await store.get(ReceiverType.sendMoney, k))!;
        expect(x.level, k == 'a' ? RuleLevel.askFirst : RuleLevel.autoRecord, reason: k);
        expect(x.chosenCategoryIds, isEmpty, reason: k);
      }
    });

    // I2 (plan section 12, PM 25-11 strict): the validator now checks `sc`, so an unreadable list refuses the
    // file (field `sc`) instead of restoring as empty. The planner still reads any value as empty (defence).
    test('an unreadable sc is refused by the validator (field sc); the planner still reads it as empty', () async {
      final odd = <Object?>[
        null,
        'x',
        5,
        {'cat_seed': _rent},
        [null],
        [5],
        ['x'],
        [<String, Object?>{}],
        [_seed('SEND_MONEY:nope')],
        [{'cat_seed': _rent, 'cat_name': 'Rent'}],
        [{'cat_seed': 7}],
        [{'cat_name': ' padded '}],
        [{'cat_name': ''}],
        [{'other': 'x'}],
        [_seed(_rent), _seed(_transport), _seed(_groceries)], // more than kBackupMaxChosenCategories
      ];
      for (var i = 0; i < odd.length; i++) {
        try {
          BackupValidator.validate(_bytes([{...ruleRow('SM', 'k$i', lv: 0), 'sc': odd[i]}]));
          fail('accepted sc #$i: ${odd[i]}');
        } on RestoreRejected catch (e) {
          expect(e.reason, RestoreRejectReason.invalidRow, reason: '#$i');
          expect(e.field, 'sc', reason: '#$i');
          expect(e.table, 'receiver_rules', reason: '#$i');
        }
      }
      // The planner (after the validator) never refuses on its own.
      for (final v in odd) {
        final ids = restoredChosenIds(v, const RuleCategoryLookup(idBySeed: {_rent: 2}, activeIds: {2}));
        expect(ids.length, lessThanOrEqualTo(kBackupMaxChosenCategories));
        expect(ids.every((id) => id == 2), isTrue);
      }
    });

    test('a valid sc passes the validator: empty, one seed, a seed and a clean own name (2 = the most)', () {
      for (final ok in <List<Object?>>[
        const [],
        [_seed(_rent)],
        [_own('My own'), _seed(_rent)],
      ]) {
        final v = BackupValidator.validate(_bytes([{...ruleRow('SM', 'a', lv: 0), 'sc': ok}]));
        expect(v.receiverRules.single['sc'], ok);
      }
    });

    test('a 0.2.1 backup (schema 8) still restores with no rules; a row without the key plans as empty', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final store = FakeRuleStore();
      await store.setLevel(ReceiverType.sendMoney, 'x', name: 'X', level: RuleLevel.suggested, chosenCategoryIds: [1], at: _at);
      final r = await _svc(db, _sink(store)).restore(_bytes(const [], schema: 8), RestoreMode.replace);
      expect(await store.all(), isEmpty);
      expect(r.rules!.failed, isFalse);

      // The validator demands every key on a schema 9 row (exact-key defence), so a row with no
      // `sc` only reaches the planner by hand; it plans as empty.
      final noKey = ruleRow('SM', 'a', lv: 0)..remove('sc');
      final plan = planRulesRestore(
        ValidatedBackup(
          formatVersion: 1,
          schemaVersion: 9,
          createdAt: f0,
          classifications: const [],
          transactions: const [],
          counterpartyMap: const [],
          receiverRules: [noKey],
          prefs: const {},
        ),
        RestoreMode.replace,
        const RuleCategoryLookup(idBySeed: {_rent: 2}, activeIds: {2}),
      );
      expect(plan.rows.single.chosenCategoryIds, isEmpty);
    });

    test('on the real store: restored list stored as is, and Reset everyone keeps it (no refusal)', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final store = PrefsRuleStore();
      final r = await _svc(db, _sink(store)).restore(
          // A ceiling on a Suggested row makes Reset everyone touch this rule (needsReset).
          // I2: at most 2 entries (the validator refuses more).
          _bytes([ruleRow('SM', 'a', lv: 0, ceil: 5000, sc: [_seed(_rent), _seed(_transport)])]),
          RestoreMode.replace);
      expect(r.rules!.added, 1);
      final want = await _seedIds(db, [_rent, _transport]);
      expect((await store.get(ReceiverType.sendMoney, 'a'))!.chosenCategoryIds, want);
      expect(await RuleBulkOps(store, now: () => _at).resetAllToSuggested(), 1);
      final after = (await store.get(ReceiverType.sendMoney, 'a'))!;
      expect(after.ceilingCents, isNull);
      expect(after.chosenCategoryIds, want, reason: 'PM Q2: Reset everyone keeps the list; a valid list is not refused');
    });
  });

  group('the applier clamps whatever plan it is given', () {
    test('3 ids or an id twice at Suggested are clamped; any list above Suggested is dropped', () async {
      final store = FakeRuleStore();
      final o = await _sink(store).apply(const RulesRestorePlan(replace: true, hasSection: true, rows: [
        RestoredRule(type: 'SM', key: 'a', name: 'A', level: 0, chosenCategoryIds: [4, 4, 5, 6]),
        RestoredRule(type: 'SM', key: 'b', name: 'B', level: 1, categoryId: 4, chosenCategoryIds: [4]),
      ]));
      expect(o.added, 2);
      final a = (await store.get(ReceiverType.sendMoney, 'a'))!;
      expect(a.chosenCategoryIds, [4, 5]);
      expect(isValidChosenCategoryIds(a.chosenCategoryIds), isTrue);
      expect((await store.get(ReceiverType.sendMoney, 'b'))!.chosenCategoryIds, isEmpty);
    });
  });

  group('restore (Merge)', () {
    test('the phone keeps its own list for the same receiver; a new receiver gets the file list', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final store = FakeRuleStore();
      final phoneList = await _seedIds(db, [_groceries]);
      await store.setLevel(ReceiverType.sendMoney, 'a', name: 'Phone', level: RuleLevel.suggested, chosenCategoryIds: phoneList, at: _at);
      final r = await _svc(db, _sink(store)).restore(
          _bytes([
            ruleRow('SM', 'a', lv: 0, sc: [_seed(_rent)]),
            ruleRow('SM', 'b', lv: 0, sc: [_seed(_transport), _seed(_rent)]),
          ]),
          RestoreMode.merge);
      expect(r.rules!.replaced, 0, reason: 'slice D: only the chosen list differed, so it is not counted as replaced');
      expect(r.rules!.added, 1);
      expect(phoneList, isNotEmpty);
      expect((await store.get(ReceiverType.sendMoney, 'a'))!.chosenCategoryIds, await _seedIds(db, [_rent]));
      expect((await store.get(ReceiverType.sendMoney, 'b'))!.chosenCategoryIds, await _seedIds(db, [_transport, _rent]));
    });
  });

  group('details OFF', () {
    test('rules with chosen lists are dropped and counted as today (Replace and Merge)', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      for (final mode in RestoreMode.values) {
        final store = FakeRuleStore()..detailsOn = false;
        final r = await _svc(db, _sink(store, detailsOn: false)).restore(
            _bytes([ruleRow('SM', 'a', lv: 0, sc: [_seed(_rent)]), ruleRow('SM', 'b', lv: 0, sc: [_seed(_rent), _seed(_transport)])]),
            mode);
        expect(r.rules!.droppedForPrivacy, 2, reason: '$mode');
        expect(r.rules!.added, 0, reason: '$mode');
        expect(await store.countEveryone(), 0, reason: '$mode');
      }
    });
  });

  group('Undo of a Replace', () {
    test('brings the old lists back (own category on its re-made id, built-in by seed key)', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final own = await addClass(db, 'SEND_MONEY', 'Invented Hobby');
      final store = FakeRuleStore();
      await store.setLevel(ReceiverType.sendMoney, 'jo',
          name: 'Jo', level: RuleLevel.suggested, chosenCategoryIds: [await seedId(db, _rent), own], at: _at);
      await store.setLevel(ReceiverType.buyGoods, '55', name: 'Shop', level: RuleLevel.askFirst, categoryId: own, at: _at);
      final svc = _svc(db, _sink(store),
          safety: FakeSafetyCopyStore(<String>[]), backup: _backup(db, () => backupRulesFrom(store)));

      await svc.restore(_bytes([ruleRow('SM', 'jo', lv: 0, sc: [_seed(_groceries)])]), RestoreMode.replace);
      expect((await store.get(ReceiverType.sendMoney, 'jo'))!.chosenCategoryIds, await _seedIds(db, [_groceries]));
      expect(await store.get(ReceiverType.buyGoods, '55'), isNull);

      final u = await svc.undoLastReplace();
      expect(u.rules!.added, 2);
      final jo = (await store.get(ReceiverType.sendMoney, 'jo'))!;
      expect(jo.chosenCategoryIds, [await seedId(db, _rent), await classId(db, 'SEND_MONEY', 'Invented Hobby')]);
      expect((await store.get(ReceiverType.buyGoods, '55'))!.chosenCategoryIds, isEmpty);
    });
  });
}
