// Wiring 1, 5 and 7: what RulesWiring.install sets (Levels deps, Suggest port, ledger hooks), the Replace
// restore chain (rules reset, Merge untouched, nothing overwritten), the "people with history" source and
// the in-app labelling store. Real preferences stores; invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/known_people.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/history/history_summary_codec.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/prefs_suggest_settings.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/runtime.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/wiring/rules_wiring.dart';
import 'package:mmogo/data/db/ledger_hooks.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/waiting_fakes.dart' show heldIdFor;
import 'wiring_db.dart';

void main() {
  const sm = ReceiverType.sendMoney;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // No test may reach the real database file.
    RulesWiring.database = () async => throw StateError('no database in this test');
  });
  tearDown(RulesWiring.uninstall);

  group('install', () {
    test('sets the Levels deps (Settings rows and Remembered tab 2), the ledger hooks and the offers list', () {
      expect(LevelsDeps.instance, isNull);
      RulesWiring.install();
      expect(LevelsDeps.instance, isNotNull);
      expect(LevelsDeps.instance!.known, isNotNull);
      expect(LevelsDeps.instance!.store, same(AutoReadRuntime.ruleStore));
      expect(RulesWiring.suggestions, isNotNull);
      expect(LedgerHooks.onInserted, isNotNull);
      expect(LedgerHooks.onEdited, isNotNull);
      expect(LedgerHooks.onRemoved, isNotNull);
      expect(LedgerHooks.onRestored, isNotNull);
      expect(LedgerHooks.onBulk, isNotNull);
      expect(AppPrefs.onCaptureIdentityWritten, isNotNull);
    });

    test('uninstall takes everything away again', () {
      RulesWiring.install();
      RulesWiring.uninstall();
      expect(LevelsDeps.instance, isNull);
      expect(LedgerHooks.onInserted, isNull);
      expect(AppPrefs.onCaptureIdentityWritten, isNull);
    });

    test('the Suggest port reads the defaults, clamps 2..10 and writes the engine keys', () async {
      var changed = 0;
      final port = PrefsSuggestSettings(onChanged: () => changed++);
      expect(await port.enabled(), isTrue);
      expect(await port.after(), 3);
      expect(await port.setAfter(99), isTrue);
      expect(await port.after(), 10);
      expect(await port.setAfter(0), isTrue);
      expect(await port.after(), 2);
      expect(await port.setEnabled(false), isTrue);
      final p = await SharedPreferences.getInstance();
      expect(p.getBool('autoread_suggest_enabled'), isFalse);
      expect(p.getInt('autoread_suggest_after'), 2);
      expect(changed, 3);
    });

    // CHANGED ON PURPOSE (0.2.2 item 2, B-HIDE, PM 25-11): OFF used to wipe the rules too; now the rules
    // stay (hidden) and come back at ON, while the undone codes and the summary still go.
    test('turning "Record receiver details" OFF hides the rules and clears the undone codes and the summary', () async {
      final store = AutoReadRuntime.ruleStore;
      await store.setLevel(sm, '0712345678', name: 'Jane', level: RuleLevel.askFirst, categoryId: 1, at: DateTime.utc(2026, 11, 1));
      await AutoReadRuntime.undoneCodes.add('CODE000001', now: DateTime.now());
      final p = await SharedPreferences.getInstance();
      await p.setString(kHistSummaryPrefKey, '{"v":1,"p":{}}');
      RulesWiring.install();
      await AppPrefs.writeCaptureIdentityPreference(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await p.reload();
      expect(p.getKeys().where((k) => k.startsWith('autoread_rule_v1.')).length, 1, reason: 'kept, hidden');
      expect(await store.all(), isEmpty);
      expect(p.containsKey(kUndoneCodesKey), isFalse);
      expect(p.containsKey(kHistSummaryPrefKey), isFalse);
      await AppPrefs.writeCaptureIdentityPreference(true);
      expect((await store.get(sm, '0712345678'))?.level, RuleLevel.askFirst, reason: 'ON brings Jane back');
    });
  });

  group('restore', () {
    Future<void> seed() async {
      await AutoReadRuntime.ruleStore
          .setLevel(sm, '0712345678', name: 'Jane', level: RuleLevel.askFirst, categoryId: 1, at: DateTime.utc(2026, 11, 1));
      await AutoReadRuntime.undoneCodes.add('CODE000001', now: DateTime.now());
    }

    test('a Replace restore sends every person back to Suggested (rules and undone codes gone)', () async {
      await seed();
      await RulesWiring.afterReplaceRestore();
      expect(await AutoReadRuntime.ruleStore.all(), isEmpty);
      expect(await AutoReadRuntime.undoneCodes.contains('CODE000001', now: DateTime.now()), isFalse);
    });

    test('the restore hook CHAINS what was there and empties the trail; it does not overwrite', () async {
      await seed();
      final calls = <String>[];
      final hook = RulesWiring.restoreHook(prior: () => calls.add('prior'), clearTrail: () => calls.add('trail'));
      hook();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, ['prior', 'trail']);
      expect(await AutoReadRuntime.ruleStore.all(), isEmpty);
    });

    test('a failing earlier hook does not stop the trail clear or the rules reset', () async {
      await seed();
      var trail = false;
      RulesWiring.restoreHook(prior: () => throw StateError('x'), clearTrail: () => trail = true)();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(trail, isTrue);
      expect(await AutoReadRuntime.ruleStore.all(), isEmpty);
    });

    test('a Merge restore (only the bulk hook) never touches a rule', () async {
      await seed();
      RulesWiring.install();
      LedgerHooks.bulkChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await AutoReadRuntime.ruleStore.all(), hasLength(1));
    });
  });

  group('people with history (Remembered tab 2)', () {
    test('lists people from the ledger newest first, one line each, plus names remembered as Pochi', () async {
      final db = await openWiringDb();
      addTearDown(db.close);
      final cats = await categoriesOf(db, 'SEND_MONEY');
      await addSendMoney(db, code: 'KNOWN00001', category: cats[0]);
      await addSendMoney(db, code: 'KNOWN00002', category: cats[0]);
      await addSendMoney(db, code: 'KNOWN00003', category: cats[0], phone: '+254733000111');
      final memory = RecipientMemory();
      await memory.remember('ZED STORES', SmsSourceType.pochi, recordDetailsOn: true);
      await memory.remember('NOT A PHONE', SmsSourceType.sendMoney, recordDetailsOn: true);
      final src = KnownPeopleSource(database: () async => db, detailsOn: () async => true, memory: memory);
      final people = await src.call();
      expect(people.map((p) => '${p.type.code}.${p.key}'), unorderedEquals(['SM.0733000111', 'SM.0712345678', 'PO.ZED STORES']));
      expect(people.firstWhere((p) => p.key == '0712345678').name, 'Jane Doe');
    });

    test('lists nobody while "Record receiver details" is off', () async {
      final db = await openWiringDb();
      addTearDown(db.close);
      await addSendMoney(db, code: 'KNOWN00004', category: (await categoriesOf(db, 'SEND_MONEY')).first);
      expect(await KnownPeopleSource(database: () async => db, detailsOn: () async => false).call(), isEmpty);
    });

    test('a failing database gives an empty list, never an error', () async {
      expect(await KnownPeopleSource(database: () async => throw StateError('x'), detailsOn: () async => true).call(), isEmpty);
    });
  });

  group('in-app Parse labels the item', () {
    test('a person on Ask first: the stored item carries the Ask first hint', () async {
      await AutoReadRuntime.ruleStore
          .setLevel(sm, '0712345678', name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: DateTime.utc(2026, 11, 1));
      final inner = SharedPrefsPendingItemsStore();
      final store = RulesWiring.labelling(inner);
      final gen = await inner.readGeneration();
      final parsed = ParsedSmsFields(
        code: 'LAB0000001',
        sourceType: SmsSourceType.sendMoney,
        amountCents: 10000,
        transactionCostCents: 0,
        counterpartyLabel: 'Jane Doe',
        counterpartyPhone: '+254712345678',
        paybillAccountNumber: null,
        transactionOccurredAt: DateTime(2026, 11, 19).millisecondsSinceEpoch,
      );
      await store.put(WaitingItem(id: heldIdFor(1), kind: WaitingKind.waitingCategory, heldAt: DateTime.now(), parsed: parsed), generation: gen);
      final stored = (await inner.list()).single;
      expect(stored.hint, isNotNull);
      expect(stored.hint!.level, RuleLevel.askFirst);
      expect(stored.hint!.key, '0712345678');
      expect(stored.hint!.suggested, [7]);
    });
  });
}
