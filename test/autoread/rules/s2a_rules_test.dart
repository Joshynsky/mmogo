// S2a: rules store, keys, codec, engine counters, undone codes, guard and wipe.
// Invented data only.
@Tags(['autoread'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/data/autoread_wipe.dart';
import 'package:mmogo/autoread/rules/prefs_rule_engine.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/receiver_key.dart';
import 'package:mmogo/autoread/rules/rule_backup_guard.dart';
import 'package:mmogo/autoread/rules/rule_cleanup.dart';
import 'package:mmogo/autoread/rules/rule_codec.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
import 'package:mmogo/data/backup/backup_limits.dart' show kBackupRuleKeys, kBackupTopLevelKeys;
import 'package:mmogo/data/backup/backup_setting_keys.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/reading_fakes.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 19, 10);
  const sm = ReceiverType.sendMoney;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('receiverKey', () {
    test('Send Money: 07xx, 01xx and +254 forms are one key', () {
      expect(receiverKey(sm, phone: '0712345678'), '0712345678');
      expect(receiverKey(sm, phone: '+254712345678'), '0712345678');
      expect(receiverKey(sm, phone: '254 712-345-678'), '0712345678');
      expect(receiverKey(sm, phone: '0112345678'), '0112345678');
      expect(receiverKey(sm, phone: '+254112345678'), '0112345678');
    });
    test('Paybill: business UPPERCASE, account case kept', () {
      expect(receiverKey(ReceiverType.payBill, business: ' kenya  power ', account: 'AbC 12'), 'KENYA POWER#AbC 12');
      expect(receiverKey(ReceiverType.payBill, business: '', account: '1'), isNull);
    });
    test('Buy Goods: shop name UPPERCASE', () {
      expect(receiverKey(ReceiverType.buyGoods, shopName: ' Quick  Mart '), 'QUICK MART');
    });
    test('Pochi: only when remembered as Pochi; key equals the recipient memory key', () {
      expect(receiverKey(ReceiverType.pochi, name: 'Jane Doe'), isNull);
      expect(receiverKey(ReceiverType.pochi, name: 'Jane  Doe', pochiRemembered: true), 'JANE DOE');
    });
    test('empty, over 200 chars and details OFF give null', () {
      expect(receiverKey(sm, phone: ''), isNull);
      expect(receiverKey(sm, phone: null), isNull);
      expect(receiverKey(ReceiverType.buyGoods, shopName: 'A' * 201), isNull);
      expect(receiverKey(ReceiverType.buyGoods, shopName: 'A' * 200), 'A' * 200);
      expect(receiverKey(sm, phone: '0712345678', recordReceiverDetails: false), isNull);
    });
    test('isRememberedPochi follows the recipient memory', () async {
      final m = RecipientMemory();
      await m.remember('JANE DOE', SmsSourceType.pochi, recordDetailsOn: true);
      await m.remember('BOB', SmsSourceType.sendMoney, recordDetailsOn: true);
      expect(await isRememberedPochi('Jane Doe', memory: m), isTrue);
      expect(await isRememberedPochi('bob', memory: m), isFalse);
      expect(await isRememberedPochi('nobody', memory: m), isFalse);
    });
  });

  group('codec', () {
    final r = ReceiverRule(
        type: ReceiverType.payBill,
        key: 'KPLC#123',
        name: 'Kenya Power',
        level: RuleLevel.askFirst,
        categoryId: 7,
        run: 2,
        runCategoryId: 7,
        created: t0,
        changed: t0,
        lastRecorded: t0);
    test('round trip', () => expect(decodeRule(encodeRule(r)), r));
    test('storage key is prefix + type + unpadded base64url', () {
      final k = ruleStorageKey(ReceiverType.payBill, 'KPLC#123');
      expect(k, 'autoread_rule_v1.PB.${base64Url.encode(utf8.encode('KPLC#123')).replaceAll('=', '')}');
      expect(k.contains('='), isFalse);
    });
    test('corrupt values are ignored', () {
      for (final bad in <Object?>[
        null, '', 'x', '[]', '{}', '{"v":2}',
        '{"v":1,"t":"ZZ","k":"a","name":"n","lv":0,"run":0,"created":1,"changed":1}',
        '{"v":1,"t":"SM","k":"","name":"n","lv":0,"run":0,"created":1,"changed":1}',
        '{"v":1,"t":"SM","k":"a","name":"n","lv":9,"run":0,"created":1,"changed":1}',
        '{"v":1,"t":"SM","k":"a","name":"n","lv":0,"run":-1,"created":1,"changed":1}',
        '{"v":1,"t":"SM","k":"a","name":"n","lv":0,"run":0,"created":"x","changed":1}',
        '{"v":1,"t":"SM","k":"a","name":"n","lv":0,"run":0,"cat":"q","created":1,"changed":1}',
        5,
      ]) {
        expect(decodeRule(bad), isNull, reason: '$bad');
      }
    });
  });

  group('PrefsRuleStore', () {
    test('set, get, update keeps created, forget, wipe, changes', () async {
      final s = PrefsRuleStore();
      var n = 0;
      s.changes.listen((_) => n++);
      expect(await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.askFirst, categoryId: 4, at: t0), isTrue);
      expect((await s.get(sm, '0712'))!.level, RuleLevel.askFirst);
      await s.setLevel(sm, '0712', name: 'Ann B', level: RuleLevel.suggested, at: t0.add(const Duration(hours: 1)));
      final r = (await s.get(sm, '0712'))!;
      expect(r.created, t0);
      expect(r.name, 'Ann B');
      expect(r.categoryId, isNull);
      expect((await s.all()).length, 1);
      await s.forget(sm, '0712');
      expect(await s.get(sm, '0712'), isNull);
      await s.setLevel(sm, '0713', name: 'C', level: RuleLevel.suggested, at: t0);
      await s.wipeAll();
      expect(await s.all(), isEmpty);
      expect(n, greaterThanOrEqualTo(5));
    });
    test('a corrupt value is skipped and does not break the others', () async {
      final s = PrefsRuleStore();
      await s.setLevel(sm, '0712', name: 'A', level: RuleLevel.askFirst, categoryId: 1, at: t0);
      final p = await SharedPreferences.getInstance();
      await p.setString('${kRuleKeyPrefix}SM.garbage', '{oops');
      expect((await s.all()).length, 1);
    });
    test('cap 300: new Suggested refused, Ask first replaces the oldest Suggested, never an Ask first', () async {
      final s = PrefsRuleStore();
      for (var i = 0; i < kRuleCap; i++) {
        expect(await s.setLevel(sm, 'k$i', name: 'n', level: RuleLevel.suggested, at: t0.add(Duration(minutes: i))), isTrue);
      }
      expect(await s.setLevel(sm, 'extra', name: 'n', level: RuleLevel.suggested, at: t0), isFalse);
      expect(await s.setLevel(sm, 'k0', name: 'n2', level: RuleLevel.suggested, at: t0.add(const Duration(days: 1))), isTrue, reason: 'existing updates at the cap');
      expect(await s.setLevel(sm, 'extra', name: 'n', level: RuleLevel.askFirst, categoryId: 1, at: t0), isTrue);
      expect((await s.all()).length, kRuleCap);
      expect(await s.get(sm, 'k1'), isNull, reason: 'oldest changed Suggested dropped (k0 was just touched)');
      expect(await s.get(sm, 'k0'), isNotNull);
      // fill with Ask first only
      final s2 = PrefsRuleStore();
      await s2.wipeAll();
      for (var i = 0; i < kRuleCap; i++) {
        await s2.setLevel(sm, 'a$i', name: 'n', level: RuleLevel.askFirst, categoryId: 1, at: t0);
      }
      expect(await s2.setLevel(sm, 'new', name: 'n', level: RuleLevel.askFirst, categoryId: 1, at: t0), isFalse);
      expect((await s2.all()).length, kRuleCap);
    });
    test('details OFF: nothing read, nothing written, found rules wiped', () async {
      final s = PrefsRuleStore();
      await s.setLevel(sm, '0712', name: 'A', level: RuleLevel.askFirst, categoryId: 1, at: t0);
      final p = await SharedPreferences.getInstance();
      await p.setBool(kReceiverDetailsPrefsKey, false);
      expect(await s.get(sm, '0712'), isNull);
      expect(await s.setLevel(sm, '0713', name: 'B', level: RuleLevel.askFirst, categoryId: 1, at: t0), isFalse);
      expect(await s.all(), isEmpty);
      expect(p.getKeys().where((k) => k.startsWith(kRuleKeyPrefix)), isEmpty);
    });
  });

  group('PrefsRuleEngine counters', () {
    late PrefsRuleStore store;
    late PrefsRuleEngine e;
    setUp(() {
      store = PrefsRuleStore();
      e = PrefsRuleEngine(store);
    });
    Future<void> rec(int cat, [int minutes = 0]) =>
        e.onRecorded(sm, '0712', name: 'Ann', categoryId: cat, at: t0.add(Duration(minutes: minutes)));

    test('defaults: after 3, enabled; setting clamps to 2..10', () async {
      expect(await e.suggestAfter(), 3);
      expect(await e.suggestEnabled(), isTrue);
      await e.setSuggestAfter(1);
      expect(await e.suggestAfter(), 2);
      await e.setSuggestAfter(50);
      expect(await e.suggestAfter(), 10);
      await e.setSuggestAfter(5);
      expect(await e.suggestAfter(), 5);
    });
    test('3 in a row of the same category offers once', () async {
      await rec(4);
      await rec(4);
      expect(await e.pendingOffers(), isEmpty);
      await rec(4);
      final o = await e.pendingOffers();
      expect(o.length, 1);
      expect(o.single.categoryId, 4);
      expect(o.single.run, 3);
      expect(o.single.name, 'Ann');
    });
    test('a different category restarts the run; Undo resets; Not now resets to 0', () async {
      await rec(4);
      await rec(4);
      await rec(5);
      expect((await store.get(sm, '0712'))!.run, 1);
      await rec(5);
      await rec(5);
      expect((await e.pendingOffers()).length, 1);
      await e.notNow(sm, '0712');
      expect((await store.get(sm, '0712'))!.run, 0);
      expect(await e.pendingOffers(), isEmpty);
      await rec(5);
      await e.onUndone(sm, '0712');
      expect((await store.get(sm, '0712'))!.run, 0);
      await rec(5);
      await rec(5);
      expect(await e.pendingOffers(), isEmpty, reason: 'only 2 since Undo');
    });
    test('changed category resets the run to the new category', () async {
      await rec(4);
      await rec(4);
      await e.onCategoryChanged(sm, '0712', categoryId: 9);
      final r = (await store.get(sm, '0712'))!;
      expect(r.run, 0);
      expect(r.runCategoryId, 9);
      await rec(9);
      expect((await store.get(sm, '0712'))!.run, 1);
    });
    test('user value 2 offers after 2; switch off hides offers', () async {
      await e.setSuggestAfter(2);
      await rec(4);
      await rec(4);
      expect((await e.pendingOffers()).length, 1);
      await e.setSuggestEnabled(false);
      expect(await e.pendingOffers(), isEmpty);
    });
    test('Ask first people are not counted and never offered; Auto-record untouched', () async {
      await store.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.askFirst, categoryId: 4, at: t0);
      for (var i = 0; i < 5; i++) {
        await rec(4, i);
      }
      final r = (await store.get(sm, '0712'))!;
      expect(r.run, 0);
      expect(r.level, RuleLevel.askFirst);
      expect(await e.pendingOffers(), isEmpty);
      await store.setLevel(ReceiverType.buyGoods, 'SHOP', name: 'S', level: RuleLevel.autoRecord, categoryId: 4, at: t0);
      await e.onRecorded(ReceiverType.buyGoods, 'SHOP', name: 'S', categoryId: 4, at: t0);
      expect((await store.get(ReceiverType.buyGoods, 'SHOP'))!.run, 0);
    });
    test('accepting an offer (Ask first) stops the counter', () async {
      for (var i = 0; i < 3; i++) {
        await rec(4, i);
      }
      await store.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.askFirst, categoryId: 4, at: t0);
      expect(await e.pendingOffers(), isEmpty);
    });
  });

  group('PrefsUndoneCodes', () {
    test('contains for 24 h, then expired and pruned from storage', () async {
      final u = PrefsUndoneCodes();
      await u.add('AB12CD', now: t0);
      expect(await u.contains('AB12CD', now: t0.add(const Duration(hours: 23))), isTrue);
      expect(await u.contains('AB12CD', now: t0.add(const Duration(hours: 24))), isFalse);
      final p = await SharedPreferences.getInstance();
      expect(p.containsKey(kUndoneCodesKey), isFalse);
      expect(await u.contains('OTHER', now: t0), isFalse);
    });
    test('cap 100 drops the earliest expiry; corrupt value reads empty', () async {
      final u = PrefsUndoneCodes();
      for (var i = 0; i < 105; i++) {
        await u.add('C$i', now: t0.add(Duration(minutes: i)));
      }
      final now = t0.add(const Duration(hours: 2));
      expect(await u.contains('C0', now: now), isFalse);
      expect(await u.contains('C4', now: now), isFalse);
      expect(await u.contains('C5', now: now), isTrue);
      expect(await u.contains('C104', now: now), isTrue);
      final p = await SharedPreferences.getInstance();
      expect((jsonDecode(p.getString(kUndoneCodesKey)!) as Map).length, 100);
      await p.setString(kUndoneCodesKey, 'garbage');
      expect(await u.contains('C5', now: now), isFalse);
      await u.add('N1', now: now);
      expect(await u.contains('N1', now: now), isTrue);
      await u.wipe();
      expect(await u.contains('N1', now: now), isFalse);
    });
  });

  group('backup guard, wipe, cleanup', () {
    // CHANGED ON PURPOSE (0.2.2 item 2, S-4a): the old intent was "rules never travel in a backup".
    // Rules now travel, but ONLY in the backup file's own `receiver_rules` section (schema 9); no rule
    // key may ever be a backup SETTING (a `prefs` entry). This test keeps the second half true.
    test('prefixes are pinned and none is a backup setting (rules travel only in the receiver_rules section)', () {
      expect(kRuleKeyPrefixes, ['autoread_rule_v1.', 'autoread_undone_codes_v1', 'autoread_hist_v1']);
      for (final s in kBackupSettingSpecs) {
        for (final pre in kRuleKeyPrefixes) {
          expect(s.prefsKey.startsWith(pre), isFalse, reason: s.prefsKey);
          expect(s.fileKey.startsWith(pre), isFalse, reason: s.fileKey);
        }
      }
      for (final k in [kSuggestEnabledKey, kSuggestAfterKey]) {
        expect(backupSettingSpecFor(k), isNull);
        expect(kBackupSettingSpecs.any((s) => s.prefsKey == k), isFalse);
      }
      expect(backupSettingSpecFor('auto_apply'), isNull);
    });
    test('the receiver_rules section is the ONLY way rules travel: its row keys name no prefs key, and the undone-codes list and history never travel', () {
      expect(kBackupTopLevelKeys, contains('receiver_rules'));
      expect(kBackupRuleKeys, isNot(contains('prefs')));
      for (final k in [...kBackupRuleKeys, 'receiver_rules']) {
        expect(backupSettingSpecFor(k), isNull, reason: k);
      }
      for (final pre in [kUndoneCodesKey, kHistorySummaryKey]) {
        expect(kBackupTopLevelKeys.any((k) => pre.startsWith(k) || k.startsWith(pre)), isFalse, reason: pre);
        expect(kBackupSettingSpecs.any((s) => s.prefsKey.startsWith(pre) || s.fileKey.startsWith(pre)), isFalse, reason: pre);
      }
    });
    test('guard wipes rules, undone codes, history; leaves other keys; false when a key stays', () async {
      final p = FakeReadingPrefs();
      p.data['${kRuleKeyPrefix}SM.x'] = 'v';
      p.data[kUndoneCodesKey] = 'v';
      p.data[kHistorySummaryKey] = 'v';
      p.data['other'] = 'keep';
      expect(await RuleBackupGuard(prefs: p).afterReplaceRestore(), isTrue);
      expect(p.data.keys.toList(), ['other']);
      p.data['${kRuleKeyPrefix}SM.y'] = 'v';
      p.failRemove = true;
      expect(await RuleBackupGuard(prefs: p).wipe(), isFalse);
    });
    test('Replace restore resets everyone; the guard is the only writer (Merge never calls it)', () async {
      final s = PrefsRuleStore();
      await s.setLevel(sm, '0712', name: 'A', level: RuleLevel.askFirst, categoryId: 1, at: t0);
      expect(await RuleBackupGuard().afterReplaceRestore(), isTrue);
      expect(await s.all(), isEmpty);
    });
    test('AutoReadWipe (Delete data) wipes rule data and fails closed when it cannot', () async {
      Future<(AutoReadWipe, FakeReadingPrefs)> make({bool failRemove = false}) async {
        final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 0);
        final p = FakeReadingPrefs();
        p.data['${kRuleKeyPrefix}SM.x'] = 'v';
        p.data[kUndoneCodesKey] = 'v';
        p.data[kHistorySummaryKey] = 'v';
        final c = ReadingController(bridge: b, store: FakeGenerationStore(), prefs: p);
        return (AutoReadWipe(controller: () => c, prefs: p), p);
      }

      final (w, p) = await make();
      expect(await w.run(), isTrue);
      expect(p.data.keys.where((k) => kRuleKeyPrefixes.any(k.startsWith)), isEmpty);
      final (w2, p2) = await make();
      p2.failRemove = true;
      expect(await w2.run(), isFalse);
    });
    test('cleanup: Forget and Change to Send Money delete the Pochi rule; Forget all deletes only Pochi rules', () async {
      final s = PrefsRuleStore();
      final c = RuleCleanup(s, guard: RuleBackupGuard(prefs: FakeReadingPrefs()));
      await s.setLevel(ReceiverType.pochi, 'JANE', name: 'Jane', level: RuleLevel.askFirst, categoryId: 1, at: t0);
      await s.setLevel(ReceiverType.pochi, 'BOB', name: 'Bob', level: RuleLevel.askFirst, categoryId: 1, at: t0);
      await s.setLevel(ReceiverType.pochi, 'AMY', name: 'Amy', level: RuleLevel.suggested, at: t0);
      await s.setLevel(sm, '0712', name: 'Ann', level: RuleLevel.askFirst, categoryId: 1, at: t0);
      await c.onNameForgotten('JANE');
      expect(await s.get(ReceiverType.pochi, 'JANE'), isNull);
      await c.onNameChangedToSendMoney('BOB');
      expect(await s.get(ReceiverType.pochi, 'BOB'), isNull);
      await c.onAllNamesForgotten();
      expect(await s.get(ReceiverType.pochi, 'AMY'), isNull);
      expect(await s.get(sm, '0712'), isNotNull);
    });
    test('cleanup: details OFF at launch wipes rules, undone codes and history', () async {
      SharedPreferences.setMockInitialValues({
        kReceiverDetailsPrefsKey: false,
        '${kRuleKeyPrefix}SM.x': 'v',
        kUndoneCodesKey: '{}',
        kHistorySummaryKey: '{}',
        'keep': 1,
      });
      final c = RuleCleanup(PrefsRuleStore(), guard: RuleBackupGuard(prefs: SharedReadingPrefs()));
      await c.enforceDetailsOff();
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys().where((k) => kRuleKeyPrefixes.any(k.startsWith)), isEmpty);
      expect(p.getInt('keep'), 1);
    });
  });
}
