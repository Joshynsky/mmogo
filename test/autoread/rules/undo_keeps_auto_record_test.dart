// 0.2.2 item 2 slice B-DU (D-U, PM 25-11): Undo of an entry recorded with no tap KEEPS the person on
// Auto-record with the same category and limit; Undo of a tapped entry is unchanged; the 24 h undone-code
// check still works. Engine on real (mock) preferences; the 24 h check through the ledger hook on the
// in-memory database. Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/ledger_rule_events.dart';
import 'package:mmogo/autoread/history/history_summary_writer.dart';
import 'package:mmogo/autoread/rules/prefs_rule_engine.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../wiring/wiring_db.dart';

void main() {
  const sm = ReceiverType.sendMoney;
  const key = '0712345678';
  final t0 = DateTime.utc(2026, 11, 20, 9);
  late PrefsRuleStore store;
  late PrefsRuleEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = PrefsRuleStore();
    engine = PrefsRuleEngine(store);
  });

  Future<ReceiverRule> setLevel(RuleLevel level, {int? categoryId = 7, int? ceiling = 250000}) async {
    expect(
        await store.setLevel(sm, key, name: 'Jane Doe', level: level, categoryId: categoryId, at: t0, ceilingCents: ceiling),
        isTrue);
    return (await store.get(sm, key))!;
  }

  group('engine', () {
    test('Undo of a no-tap entry keeps Auto-record, the category and the limit', () async {
      final before = await setLevel(RuleLevel.autoRecord);
      await engine.onUndone(sm, key, recordedAutomatically: true);
      final after = (await store.get(sm, key))!;
      expect(after, before);
      expect(after.level, RuleLevel.autoRecord);
      expect(after.categoryId, 7);
      expect(after.ceilingCents, 250000);
    });

    test('Undo of a no-tap entry keeps Auto-record with no limit set', () async {
      final before = await setLevel(RuleLevel.autoRecord, ceiling: null);
      await engine.onUndone(sm, key, recordedAutomatically: true);
      expect(await store.get(sm, key), before);
    });

    test('repeated no-tap Undos never lower the level', () async {
      final before = await setLevel(RuleLevel.autoRecord);
      for (var i = 0; i < 5; i++) {
        await engine.onUndone(sm, key, recordedAutomatically: true);
      }
      expect(await store.get(sm, key), before);
    });

    test('Undo of a tapped entry is unchanged: Auto-record and Ask first untouched', () async {
      for (final level in [RuleLevel.autoRecord, RuleLevel.askFirst]) {
        SharedPreferences.setMockInitialValues({});
        final before = await setLevel(level);
        await engine.onUndone(sm, key);
        expect(await store.get(sm, key), before, reason: '$level');
      }
    });

    test('Suggested: the run counter still starts again on Undo (tapped or no tap)', () async {
      for (final auto in [false, true]) {
        await store.saveRule(
            ReceiverRule(type: sm, key: key, name: 'Jane Doe', run: 3, runCategoryId: 7, created: t0, changed: t0));
        await engine.onUndone(sm, key, recordedAutomatically: auto);
        final r = (await store.get(sm, key))!;
        expect(r.level, RuleLevel.suggested);
        expect(r.run, 0);
        expect(r.runCategoryId, 7);
      }
    });

    test('no rule: Undo creates nothing', () async {
      await engine.onUndone(sm, key, recordedAutomatically: true);
      expect(await store.all(), isEmpty);
    });
  });

  group('ledger hook', () {
    late Database db;
    late PrefsUndoneCodes undone;
    late DateTime now;
    late LedgerRuleEvents events;
    late List<int> cats;

    setUp(() async {
      db = await openWiringDb();
      cats = await categoriesOf(db, 'SEND_MONEY');
      undone = PrefsUndoneCodes();
      now = DateTime(2026, 11, 20, 9);
      events = LedgerRuleEvents(
        engine: engine,
        store: store,
        undone: undone,
        summary: HistorySummaryWriter(rows: () async => readHistoryRows(db)),
        database: () async => db,
        detailsOn: () async => true,
        now: () => now,
      );
    });
    tearDown(() async => db.close());

    Future<int> undoNoTap(String code) async {
      final id = await addSendMoney(db, code: code, category: cats[0]);
      await db.update('transactions', {'recorded_automatically': 1}, where: 'id = ?', whereArgs: [id]);
      await TransactionDao.softDelete(db, id: id);
      await events.removed(id);
      return id;
    }

    test('no-tap Undo: level, category and limit kept, and the undone code is held for 24 h', () async {
      expect(await store.setLevel(sm, key,
          name: 'Jane Doe', level: RuleLevel.autoRecord, categoryId: cats[0], at: t0, ceilingCents: 500000), isTrue);
      final before = (await store.get(sm, key))!;
      await undoNoTap('DUKEEP0001');
      expect(await store.get(sm, key), before);
      expect(await undone.contains('DUKEEP0001', now: now), isTrue);
      expect(await undone.contains('DUKEEP0001', now: now.add(const Duration(hours: 23, minutes: 59))), isTrue);
      expect(await undone.contains('DUKEEP0001', now: now.add(const Duration(hours: 24, minutes: 1))), isFalse);
    });

    test('tapped-entry Undo: the rule is untouched and the code is still held', () async {
      expect(await store.setLevel(sm, key,
          name: 'Jane Doe', level: RuleLevel.autoRecord, categoryId: cats[0], at: t0, ceilingCents: 500000), isTrue);
      final before = (await store.get(sm, key))!;
      final id = await addSendMoney(db, code: 'DUTAP00001', category: cats[0]);
      await TransactionDao.softDelete(db, id: id);
      await events.removed(id);
      expect(await store.get(sm, key), before);
      expect(await undone.contains('DUTAP00001', now: now), isTrue);
    });
  });
}
