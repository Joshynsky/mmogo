// Item 2 slice S-3: Undo of a row recorded with no tap (recorded_automatically = 1) drops that
// person's Auto-record rule to Suggested (run 0, ceiling and autoPending cleared). Undo of a tapped
// row does not. Dormant: nothing records automatically yet. Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/ledger_rule_events.dart';
import 'package:mmogo/autoread/history/history_summary_writer.dart';
import 'package:mmogo/autoread/rules/fake_rule_engine.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_rule_engine.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'wiring_db.dart';

void main() {
  late Database db;
  late PrefsRuleStore store;
  late PrefsRuleEngine engine;
  late PrefsUndoneCodes undone;
  late LedgerRuleEvents events;
  late bool details;
  late List<int> cats;
  const sm = ReceiverType.sendMoney;
  const key = '0712345678';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openWiringDb();
    cats = await categoriesOf(db, 'SEND_MONEY');
    details = true;
    store = PrefsRuleStore();
    engine = PrefsRuleEngine(store);
    undone = PrefsUndoneCodes();
    events = LedgerRuleEvents(
      engine: engine,
      store: store,
      undone: undone,
      summary: HistorySummaryWriter(rows: () async => readHistoryRows(db)),
      database: () async => db,
      detailsOn: () async => details,
    );
  });
  tearDown(() async => db.close());

  Future<int> row(String code, {required bool auto}) async {
    final id = await addSendMoney(db, code: code, category: cats[0]);
    if (auto) await db.update('transactions', {'recorded_automatically': 1}, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> setAuto({int? ceiling = 5000}) async {
    final ok = await store.setLevel(sm, key,
        name: 'Jane Doe', level: RuleLevel.autoRecord, categoryId: cats[0], at: DateTime.utc(2026, 11, 1), ceilingCents: ceiling);
    expect(ok, isTrue);
  }

  Future<void> undoRow(int id) async {
    await TransactionDao.softDelete(db, id: id);
    await events.removed(id);
  }

  test('undo of an auto-recorded row: Auto-record person drops to Suggested, ceiling and category cleared', () async {
    await setAuto();
    // a stored rule carrying a leftover run and the pending marker, to prove they are cleared
    final r = (await store.get(sm, key))!;
    await store.saveRule(r.copyWith(run: 4, runCategoryId: cats[0], autoPending: true));
    await undoRow(await row('AUTO000001', auto: true));
    final d = (await store.get(sm, key))!;
    expect(d.level, RuleLevel.suggested);
    expect(d.run, 0);
    expect(d.runCategoryId, isNull);
    expect(d.ceilingCents, isNull);
    expect(d.autoPending, isFalse);
    expect(d.categoryId, isNull);
    expect(d.name, 'Jane Doe');
  });

  test('undo of a tapped row for an Auto-record person changes nothing', () async {
    await setAuto();
    final before = (await store.get(sm, key))!;
    await undoRow(await row('TAP0000001', auto: false));
    expect(await store.get(sm, key), before);
  });

  test('undo of an auto-recorded row for an Ask first person changes nothing', () async {
    await store.setLevel(sm, key,
        name: 'Jane Doe', level: RuleLevel.askFirst, categoryId: cats[0], at: DateTime.utc(2026, 11, 1), ceilingCents: 5000);
    final before = (await store.get(sm, key))!;
    await undoRow(await row('ASK0000001', auto: true));
    expect(await store.get(sm, key), before);
  });

  test('Suggested person: undo still resets the run, whether or not the row was automatic', () async {
    for (final auto in [false, true]) {
      await store.saveRule(ReceiverRule(
          type: sm, key: key, name: 'Jane Doe', run: 3, runCategoryId: cats[0], created: DateTime.utc(2026), changed: DateTime.utc(2026)));
      await undoRow(await row(auto ? 'SUGA000001' : 'SUGT000001', auto: auto));
      final r = (await store.get(sm, key))!;
      expect(r.level, RuleLevel.suggested);
      expect(r.run, 0);
    }
  });

  test('no rule: nothing is created by an undo', () async {
    await undoRow(await row('NORULE0001', auto: true));
    expect(await store.all(), isEmpty);
  });

  test('Record receiver details OFF: no rule is touched', () async {
    await setAuto();
    final before = (await store.get(sm, key))!;
    details = false;
    await undoRow(await row('OFF0000001', auto: true));
    expect(await store.get(sm, key), before);
  });

  test('the 24 h undone code is still remembered for an auto-recorded row', () async {
    await setAuto();
    await undoRow(await row('CODE000001', auto: true));
    expect(await undone.contains('CODE000001', now: DateTime.now()), isTrue);
  });

  test('Recently deleted restore of the row does not put the person back on Auto-record', () async {
    await setAuto();
    final id = await row('REST000001', auto: true);
    await undoRow(id);
    await TransactionDao.restore(db, id: id);
    await events.ledgerChanged(id);
    expect((await store.get(sm, key))!.level, RuleLevel.suggested);
  });

  test('a failing store does not throw out of removed()', () async {
    final failing = LedgerRuleEvents(
      engine: _ThrowingEngine(),
      store: FakeRuleStore(),
      undone: undone,
      summary: HistorySummaryWriter(rows: () async => readHistoryRows(db)),
      database: () async => db,
      detailsOn: () async => true,
    );
    final id = await row('FAIL000001', auto: true);
    await TransactionDao.softDelete(db, id: id);
    await failing.removed(id); // must complete
  });

  test('events pass the marker to the engine: auto row -> undone-auto, tapped row -> undone', () async {
    final fake = FakeRuleEngine();
    final e = LedgerRuleEvents(
      engine: fake,
      store: FakeRuleStore(),
      undone: undone,
      summary: HistorySummaryWriter(rows: () async => readHistoryRows(db)),
      database: () async => db,
      detailsOn: () async => true,
    );
    await e.removed(await row('MARK000001', auto: true));
    await e.removed(await row('MARK000002', auto: false));
    expect(fake.calls, ['undone-auto:SM.$key', 'undone:SM.$key']);
  });

}

class _ThrowingEngine extends FakeRuleEngine {
  @override
  Future<void> onUndone(ReceiverType type, String key, {bool recordedAutomatically = false}) async => throw StateError('boom');
}
