// 0.2.2 item 2, slice S-4b: restore of the `receiver_rules` section (Replace, Merge, privacy,
// category mapping, Auto-record comes back as Ask first, old backups, pause untouched, Undo of a
// Replace, idempotent re-restore). Real in-memory sqlite, invented data, no wording.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_backup_guard.dart';
import 'package:mmogo/autoread/rules/rule_backup_source.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_restore.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
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

/// A store that fails on the Nth saveRule.
class _FailingStore extends FakeRuleStore {
  _FailingStore(this.failOn);
  final int failOn;
  int saves = 0;
  @override
  Future<bool> saveRule(ReceiverRule rule) async {
    if (++saves == failOn) throw StateError('disk');
    return super.saveRule(rule);
  }
}

class _CountingStore extends FakeRuleStore {
  int wipes = 0;
  @override
  Future<void> wipeAll() async {
    wipes++;
    await super.wipeAll();
  }
}

class _ThrowingSink implements RuleRestoreSink {
  @override
  Future<RulesRestoreOutcome> apply(RulesRestorePlan plan) async => throw StateError('boom');
}

RuleRestoreSink _sink(RuleStore s, {bool detailsOn = true}) =>
    RuleRestoreApplier(store: s, detailsOn: () async => detailsOn, now: () => _at);

RestoreService _svc(Database db, RuleRestoreSink? sink,
        {FakeSafetyCopyStore? safety, BackupService? backup, Future<void> Function()? afterReplace}) =>
    RestoreService(
      db: () async => db,
      backup: backup ?? backupOf(db),
      safety: safety ?? FakeSafetyCopyStore([]),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      validateInIsolate: false,
      afterReplace: afterReplace ?? () async {},
      rules: sink,
    );

Uint8List _bytes(
  List<Map<String, Object?>> rules, {
  int schema = 9,
  List<Map<String, Object?>> extraClasses = const [],
  List<Map<String, Object?>> txs = const [],
}) =>
    fileBytes(fileJson(
      classes: [...seedRowsV5(), ...extraClasses],
      txs: txs,
      rules: rules,
      schemaVersion: schema,
    ));

Future<ReceiverRule?> _get(RuleStore s, ReceiverType t, String k) => s.get(t, k);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Database db;
  setUp(() async => db = await openTestDb());

  group('Replace', () {
    test('restores levels, ceilings and names; categories map to the phone\'s NEW ids', () async {
      final store = FakeRuleStore();
      await store.setLevel(ReceiverType.sendMoney, '0700000009', name: 'Old', level: RuleLevel.askFirst, at: _at);
      final bytes = _bytes([
        ruleRow('SM', '0700000001', name: 'Mama', lv: 1, catSeed: 'SEND_MONEY:rent', ceil: 5000),
        ruleRow('BG', '123456', name: 'Kiosk Till', lv: 1, catName: 'Kiosk'),
        ruleRow('PO', 'JANE', name: 'Jane', lv: 0),
      ], extraClasses: [cls(30, 'BUY_GOODS', 'Kiosk')]);
      final r = await _svc(db, _sink(store)).restore(bytes, RestoreMode.replace);

      expect(r.rules!.added, 3);
      expect(r.rules!.phoneRulesCleared, isTrue);
      expect(r.rules!.failed, isFalse);
      expect(await _get(store, ReceiverType.sendMoney, '0700000009'), isNull, reason: 'the phone\'s rules are replaced');
      final mama = (await _get(store, ReceiverType.sendMoney, '0700000001'))!;
      expect(mama.categoryId, await seedId(db, 'SEND_MONEY:rent'));
      expect(mama.ceilingCents, 5000);
      expect(mama.level, RuleLevel.askFirst);
      expect(mama.name, 'Mama');
      final kiosk = (await _get(store, ReceiverType.buyGoods, '123456'))!;
      expect(kiosk.categoryId, await classId(db, 'BUY_GOODS', 'Kiosk'));
      final jane = (await _get(store, ReceiverType.pochi, 'JANE'))!;
      expect(jane.level, RuleLevel.suggested);
      expect(jane.categoryId, isNull);
    });

    test('Auto-record comes back as Ask first, waiting, ceiling kept; the pending flag survives', () async {
      final store = FakeRuleStore();
      final bytes = _bytes([
        ruleRow('SM', '0700000001', lv: 2, ceil: 250000, catSeed: 'SEND_MONEY:rent'),
        ruleRow('BG', '111', lv: 1, ap: 1),
        ruleRow('BG', '222', lv: 1),
        ruleRow('PO', 'ANN', lv: 0, ap: 1),
      ]);
      final r = await _svc(db, _sink(store)).restore(bytes, RestoreMode.replace);
      final a = (await _get(store, ReceiverType.sendMoney, '0700000001'))!;
      expect(a.level, RuleLevel.askFirst);
      expect(a.autoPending, isTrue);
      expect(a.ceilingCents, 250000);
      expect((await _get(store, ReceiverType.buyGoods, '111'))!.autoPending, isTrue);
      expect((await _get(store, ReceiverType.buyGoods, '222'))!.autoPending, isFalse);
      expect((await _get(store, ReceiverType.pochi, 'ANN'))!.autoPending, isFalse, reason: 'Suggested never waits');
      expect(r.rules!.autoRecordAsAskFirst, 1);
      expect([for (final x in await store.all()) x.level], isNot(contains(RuleLevel.autoRecord)));
    });

    test('Paybill at level 2 comes back as Ask first, counted apart, no marker', () async {
      final store = FakeRuleStore();
      final r = await _svc(db, _sink(store))
          .restore(_bytes([ruleRow('PB', '888880', lv: 2, ceil: 100)]), RestoreMode.replace);
      final p = (await _get(store, ReceiverType.payBill, '888880'))!;
      expect(p.level, RuleLevel.askFirst);
      expect(p.autoPending, isFalse);
      expect(p.ceilingCents, 100);
      expect(r.rules!.paybillAsAskFirst, 1);
      expect(r.rules!.autoRecordAsAskFirst, 0);
    });

    test('a category that cannot be mapped: the rule still restores, with no category', () async {
      final store = FakeRuleStore();
      final r = await _svc(db, _sink(store))
          .restore(_bytes([ruleRow('SM', '0700000001', lv: 1, catName: 'Ghost')]), RestoreMode.replace);
      final x = (await _get(store, ReceiverType.sendMoney, '0700000001'))!;
      expect(x.categoryId, isNull);
      expect(x.level, RuleLevel.askFirst);
      expect(r.rules!.added, 1);
    });

    test('a 0.2.1 backup (schema 8, no rules section): Replace leaves the phone with NO rules, no crash', () async {
      final store = FakeRuleStore();
      await store.setLevel(ReceiverType.sendMoney, '0700000009', name: 'Old', level: RuleLevel.askFirst, at: _at);
      final r = await _svc(db, _sink(store)).restore(_bytes(const [], schema: 8), RestoreMode.replace);
      expect(await store.all(), isEmpty);
      expect(r.rules!.phoneRulesCleared, isTrue);
      expect(r.rules!.added, 0);
      expect(r.rules!.failed, isFalse);
    });

    test('a schema 9 file with an empty section also ends with no rules', () async {
      final store = FakeRuleStore();
      await store.setLevel(ReceiverType.sendMoney, '0700000009', name: 'Old', level: RuleLevel.askFirst, at: _at);
      await _svc(db, _sink(store)).restore(_bytes(const []), RestoreMode.replace);
      expect(await store.all(), isEmpty);
    });

    test('details OFF: nothing stored, the phone\'s rules are cleared, the dropped count is reported', () async {
      final store = FakeRuleStore()..detailsOn = false;
      final r = await _svc(db, _sink(store, detailsOn: false))
          .restore(_bytes([ruleRow('SM', '1', lv: 1), ruleRow('SM', '2', lv: 2)]), RestoreMode.replace);
      expect(await store.all(), isEmpty);
      expect(r.rules!.droppedForPrivacy, 2);
      expect(r.rules!.added, 0);
      expect(r.rules!.phoneRulesCleared, isTrue);
    });

    test('without a sink the result carries no rules outcome (dormant)', () async {
      final r = await _svc(db, null).restore(_bytes([ruleRow('SM', '1', lv: 1)]), RestoreMode.replace);
      expect(r.rules, isNull);
    });

    test('a failing rule write leaves the rules EMPTY (never half), ledger restored, result says failed', () async {
      final store = _FailingStore(2);
      final r = await _svc(db, _sink(store)).restore(
          _bytes([ruleRow('SM', '1', lv: 2), ruleRow('SM', '2', lv: 2), ruleRow('SM', '3', lv: 2)]),
          RestoreMode.replace);
      expect(r.rules!.failed, isTrue);
      expect(await store.all(), isEmpty);
      expect(r.mode, RestoreMode.replace);
    });

    test('a sink that throws never fails a committed restore', () async {
      final r = await _svc(db, _ThrowingSink()).restore(_bytes([ruleRow('SM', '1', lv: 1)]), RestoreMode.replace);
      expect(r.rules!.failed, isTrue);
    });

    test('Replace twice gives the same rules (idempotent)', () async {
      final store = FakeRuleStore();
      final bytes = _bytes([ruleRow('SM', '1', lv: 2, ceil: 10), ruleRow('BG', '2', lv: 1)]);
      Future<List<String>> dump() async => [
            for (final x in await store.all()) '${x.type.code}.${x.key}.${x.level.code}.${x.ceilingCents}.${x.autoPending}'
          ]..sort();
      await _svc(db, _sink(store)).restore(bytes, RestoreMode.replace);
      final first = await dump();
      await _svc(db, _sink(store)).restore(bytes, RestoreMode.replace);
      expect(await dump(), first);
    });
  });

  group('Merge', () {
    test('keeps the phone\'s rule for the same receiver and adds only for receivers with none', () async {
      final store = FakeRuleStore();
      await store.setLevel(ReceiverType.sendMoney, '1', name: 'Phone', level: RuleLevel.suggested, at: _at);
      await store.setLevel(ReceiverType.sendMoney, '9', name: 'Other', level: RuleLevel.askFirst, at: _at);
      final r = await _svc(db, _sink(store)).restore(
          _bytes([ruleRow('SM', '1', name: 'File', lv: 1, ceil: 5), ruleRow('BG', '77', name: 'Till', lv: 2)]),
          RestoreMode.merge);
      final kept = (await _get(store, ReceiverType.sendMoney, '1'))!;
      expect(kept.name, 'Phone');
      expect(kept.level, RuleLevel.suggested);
      expect(kept.ceilingCents, isNull);
      expect(await _get(store, ReceiverType.sendMoney, '9'), isNotNull);
      final till = (await _get(store, ReceiverType.buyGoods, '77'))!;
      expect(till.level, RuleLevel.askFirst);
      expect(till.autoPending, isTrue);
      expect(r.rules!.added, 1);
      expect(r.rules!.keptPhone, 1);
      expect(r.rules!.phoneRulesCleared, isFalse);
    });

    test('Merge never wipes and never runs the Replace hook', () async {
      final store = _CountingStore();
      await store.setLevel(ReceiverType.sendMoney, '9', name: 'Other', level: RuleLevel.askFirst, at: _at);
      var hooks = 0;
      await _svc(db, _sink(store), afterReplace: () async => hooks++)
          .restore(_bytes([ruleRow('SM', '1', lv: 1)]), RestoreMode.merge);
      expect(store.wipes, 0);
      expect(hooks, 0);
      expect((await store.all()).length, 2);
    });

    test('a 0.2.1 backup (schema 8) leaves the phone\'s rules alone; the sink is not even asked', () async {
      final store = _CountingStore();
      await store.setLevel(ReceiverType.sendMoney, '9', name: 'Other', level: RuleLevel.askFirst, at: _at);
      final r = await _svc(db, _sink(store)).restore(_bytes(const [], schema: 8), RestoreMode.merge);
      expect(store.wipes, 0);
      expect((await store.all()).length, 1);
      expect(r.rules, same(RulesRestoreOutcome.none));
    });

    test('a schema 9 file with an empty section does not wipe either', () async {
      final store = _CountingStore();
      await store.setLevel(ReceiverType.sendMoney, '9', name: 'Other', level: RuleLevel.askFirst, at: _at);
      await _svc(db, _sink(store)).restore(_bytes(const []), RestoreMode.merge);
      expect((await store.all()).length, 1);
    });

    test('details OFF: zero imported, dropped count returned, nothing wiped by the restore', () async {
      final store = _CountingStore()..detailsOn = false;
      final r = await _svc(db, _sink(store, detailsOn: false))
          .restore(_bytes([ruleRow('SM', '1', lv: 1), ruleRow('SM', '2', lv: 1)]), RestoreMode.merge);
      expect(await store.all(), isEmpty);
      expect(store.wipes, 0);
      expect(r.rules!.droppedForPrivacy, 2);
    });

    test('at the 300 cap the rest are skipped and counted', () async {
      final store = FakeRuleStore();
      for (var i = 0; i < kRuleCap - 1; i++) {
        await store.setLevel(ReceiverType.sendMoney, 'P$i', name: 'P$i', level: RuleLevel.askFirst, at: _at);
      }
      final r = await _svc(db, _sink(store)).restore(
          _bytes([ruleRow('BG', '1', lv: 1), ruleRow('BG', '2', lv: 1), ruleRow('BG', '3', lv: 1)]),
          RestoreMode.merge);
      expect(r.rules!.added, 1);
      expect(r.rules!.skippedOverCap, 2);
      expect((await store.all()).length, kRuleCap);
    });

    test('Merge twice is idempotent: the second run adds nothing', () async {
      final store = FakeRuleStore();
      final bytes = _bytes([ruleRow('SM', '1', lv: 2), ruleRow('BG', '2', lv: 1, ceil: 9)]);
      final one = await _svc(db, _sink(store)).restore(bytes, RestoreMode.merge);
      final before = (await store.all()).toSet();
      final two = await _svc(db, _sink(store)).restore(bytes, RestoreMode.merge);
      expect(one.rules!.added, 2);
      expect(two.rules!.added, 0);
      expect(two.rules!.keptPhone, 2);
      expect((await store.all()).toSet(), before);
    });

    test('restoring an auto-recorded row never recreates Auto-record', () async {
      final store = FakeRuleStore();
      final t = Map<String, Object?>.from(tx(1, 'AUTO111111', 'SEND_MONEY', 2, label: 'MAMA', phone: '0700000001'))
        ..['recorded_auto'] = 1;
      await _svc(db, _sink(store)).restore(_bytes(const [], txs: [t], schema: 9), RestoreMode.merge);
      expect(await store.all(), isEmpty);
    });
  });

  group('pause switch and the hook order', () {
    test('Replace and Merge never touch autoread_hard_paused (also through the real wipe hook)', () async {
      SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: true});
      final store = PrefsRuleStore();
      final bytes = _bytes([ruleRow('SM', '1', lv: 2), ruleRow('BG', '2', lv: 1)]);
      final svc = _svc(db, _sink(store), afterReplace: () async => RuleBackupGuard().afterReplaceRestore());
      await svc.restore(bytes, RestoreMode.replace);
      await svc.restore(_bytes([ruleRow('PO', 'X', lv: 1)]), RestoreMode.merge);
      await svc.restore(_bytes(const [], schema: 8), RestoreMode.replace);
      final p = await SharedPreferences.getInstance();
      await p.reload();
      expect(p.getBool(kHardPausedPrefsKey), isTrue);
      // and an unpaused phone stays unpaused
      SharedPreferences.setMockInitialValues({});
      await svc.restore(bytes, RestoreMode.replace);
      final q = await SharedPreferences.getInstance();
      await q.reload();
      expect(q.containsKey(kHardPausedPrefsKey), isFalse);
    });

    test('Replace = the hook\'s wipe first, then the import: the file\'s rules survive on the real store', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsRuleStore();
      await store.setLevel(ReceiverType.sendMoney, '9', name: 'Old', level: RuleLevel.askFirst, at: _at);
      final svc = _svc(db, _sink(store), afterReplace: () async => RuleBackupGuard().afterReplaceRestore());
      final r = await svc.restore(_bytes([ruleRow('SM', '1', lv: 2, ceil: 700)]), RestoreMode.replace);
      final all = await store.all();
      expect(all.map((x) => x.key), ['1']);
      expect(all.single.autoPending, isTrue);
      expect(all.single.ceilingCents, 700);
      expect(r.rules!.added, 1);
    });

    test('details OFF on the real store: nothing is stored, count reported', () async {
      SharedPreferences.setMockInitialValues({kReceiverDetailsPrefsKey: false});
      final store = PrefsRuleStore();
      final sink = RuleRestoreApplier(
          store: store,
          detailsOn: () async => (await SharedPreferences.getInstance()).getBool(kReceiverDetailsPrefsKey) ?? true);
      final r = await _svc(db, sink).restore(_bytes([ruleRow('SM', '1', lv: 1)]), RestoreMode.replace);
      expect(await store.all(), isEmpty);
      expect(r.rules!.droppedForPrivacy, 1);
    });
  });

  group('Undo of a Replace', () {
    test('brings the old rules back (Auto-record as Ask first, waiting, ceiling kept)', () async {
      final store = FakeRuleStore();
      await store.setLevel(ReceiverType.sendMoney, '0700000009',
          name: 'Old', level: RuleLevel.autoRecord, ceilingCents: 4200, at: _at);
      await store.setLevel(ReceiverType.buyGoods, '55', name: 'Shop', level: RuleLevel.askFirst, at: _at);
      final events = <String>[];
      final safety = FakeSafetyCopyStore(events);
      final backup = BackupService(
        db: () async => db,
        now: () => DateTime.fromMillisecondsSinceEpoch(t0 + 999999),
        settings: BackupSettings(prefs: SharedPreferences.getInstance),
        rules: () => backupRulesFrom(store),
      );
      final svc = _svc(db, _sink(store), safety: safety, backup: backup);

      await svc.restore(_bytes([ruleRow('PO', 'NEW', lv: 1)]), RestoreMode.replace);
      expect((await store.all()).map((x) => x.key), ['NEW']);

      final u = await svc.undoLastReplace();
      expect(u.rules!.added, 2);
      final back = (await _get(store, ReceiverType.sendMoney, '0700000009'))!;
      expect(back.level, RuleLevel.askFirst);
      expect(back.autoPending, isTrue);
      expect(back.ceilingCents, 4200);
      expect((await _get(store, ReceiverType.buyGoods, '55'))!.level, RuleLevel.askFirst);
      expect(await _get(store, ReceiverType.pochi, 'NEW'), isNull);
    });
  });

  group('planRulesRestore (pure)', () {
    test('Auto-record never leaves the plan at level 2', () {
      final f = BackupValidator.validate(_bytes([ruleRow('SM', '1', lv: 2), ruleRow('PB', '2', lv: 2)]));
      final plan = planRulesRestore(f, RestoreMode.replace, const RuleCategoryLookup());
      expect(plan.rows.map((r) => r.level), everyElement(lessThan(2)));
      expect(plan.replace, isTrue);
      expect(plan.hasSection, isTrue);
    });
  });
}
