// Wiring 4: record, edit, delete (undo) and restore events reach the rule engine and the history summary,
// through the real ledger hooks, the real preferences stores and a real (in-memory) ledger.
// Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/ledger_rule_events.dart';
import 'package:mmogo/autoread/history/history_summary_codec.dart';
import 'package:mmogo/autoread/history/history_summary_writer.dart';
import 'package:mmogo/autoread/rules/prefs_rule_engine.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/data/db/ledger_hooks.dart';
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
  tearDown(() async {
    LedgerHooks.onInserted = null;
    LedgerHooks.onEdited = null;
    LedgerHooks.onRemoved = null;
    LedgerHooks.onRestored = null;
    LedgerHooks.onBulk = null;
    await db.close();
  });

  Future<Map<String, List<int>>?> summary() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return decodeHistSummary(p.getString(kHistSummaryPrefKey));
  }

  test('three records in a row in one category make an offer; the summary names the person', () async {
    for (var i = 1; i <= 3; i++) {
      final id = await addSendMoney(db, code: 'REC00000$i', category: cats[0]);
      await events.inserted(id);
    }
    final offers = await engine.pendingOffers();
    expect(offers, hasLength(1));
    expect(offers.single.key, '0712345678');
    expect(offers.single.categoryId, cats[0]);
    expect(offers.single.run, 3);
    expect((await summary())!['SM.0712345678'], [cats[0]]);
  });

  test('the real hooks carry the events: DAO insert, edit, delete and restore reach the listener', () async {
    final seen = <String>[];
    LedgerHooks.onInserted = (id) => seen.add('ins$id');
    LedgerHooks.onEdited = (id) => seen.add('edit$id');
    LedgerHooks.onRemoved = (id) => seen.add('del$id');
    LedgerHooks.onRestored = (id) => seen.add('res$id');
    final id = await addSendMoney(db, code: 'HOOK000001', category: cats[0]);
    await TransactionDao.update(db,
        id: id,
        amountCents: 20000,
        transactionOccurredAt: 1,
        classificationId: cats[1],
        counterpartyLabel: 'Jane Doe',
        counterpartyPhone: '0712345678',
        transactionCostCents: 0);
    await TransactionDao.softDelete(db, id: id);
    await TransactionDao.restore(db, id: id);
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['ins$id', 'edit$id', 'del$id', 'res$id']);
  });

  test('a category change starts the run again from the new category; an amount-only edit does not', () async {
    for (var i = 1; i <= 2; i++) {
      await events.inserted(await addSendMoney(db, code: 'CHG00000$i', category: cats[0]));
    }
    final id = await addSendMoney(db, code: 'CHG000003', category: cats[0]);
    await events.inserted(id);
    expect((await store.get(sm, '0712345678'))!.run, 3);
    await events.edited(id); // nothing changed in the category
    expect((await store.get(sm, '0712345678'))!.run, 3);
    await db.update('transactions', {'classification_id': cats[1]}, where: 'id = ?', whereArgs: [id]);
    await events.edited(id);
    final r = (await store.get(sm, '0712345678'))!;
    expect(r.run, 0);
    expect(r.runCategoryId, cats[1]);
  });

  test('Undo of a parsed record: the run starts again and the code is remembered for 24 h', () async {
    final id = await addSendMoney(db, code: 'UND0000001', category: cats[0]);
    await events.inserted(id);
    await TransactionDao.softDelete(db, id: id);
    await events.removed(id);
    expect((await store.get(sm, '0712345678'))!.run, 0);
    expect(await undone.contains('UND0000001', now: DateTime.now()), isTrue);
  });

  test('deleting a typed-in (manual) row does not remember its code', () async {
    final id = await addSendMoney(db, code: 'MAN0000001', category: cats[0], source: 'MANUAL');
    await TransactionDao.softDelete(db, id: id);
    await events.removed(id);
    expect(await undone.contains('MAN0000001', now: DateTime.now()), isFalse);
  });

  test('an Ask first person is not counted; only the last-recorded time moves', () async {
    await store.setLevel(sm, '0712345678',
        name: 'Jane Doe', level: RuleLevel.askFirst, categoryId: cats[0], at: DateTime.utc(2026, 11, 1));
    await events.inserted(await addSendMoney(db, code: 'ASK0000001', category: cats[1]));
    final r = (await store.get(sm, '0712345678'))!;
    expect(r.level, RuleLevel.askFirst);
    expect(r.run, 0);
    expect(r.lastRecorded, isNotNull);
  });

  test('a row without a person (Airtime) never makes a rule', () async {
    final air = await categoriesOf(db, 'AIRTIME');
    final id = await db.insert('transactions', {
      'display_code': 'AIR0000001',
      'source_type': 'AIRTIME',
      'amount_cents': 100,
      'transaction_cost_cents': 0,
      'classification_id': air.first,
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': 1,
      'created_at': 1,
    });
    await events.inserted(id);
    expect(await store.all(), isEmpty);
  });

  test('Record receiver details OFF: no rule is written and the summary is removed', () async {
    await events.inserted(await addSendMoney(db, code: 'ON00000001', category: cats[0]));
    expect(await summary(), isNotNull);
    details = false;
    await events.inserted(await addSendMoney(db, code: 'OFF0000001', category: cats[0]));
    expect(await summary(), isNull);
    expect((await SharedPreferences.getInstance()).containsKey(kHistSummaryPrefKey), isFalse);
  });

  test('a restore from a backup (bulk change) rebuilds the summary and never touches a rule', () async {
    await store.setLevel(sm, '0712345678',
        name: 'Jane Doe', level: RuleLevel.askFirst, categoryId: cats[0], at: DateTime.utc(2026, 11, 1));
    await addSendMoney(db, code: 'BULK000001', category: cats[1]);
    await events.ledgerChanged();
    expect((await summary())!['SM.0712345678'], [cats[1]]);
    final r = (await store.get(sm, '0712345678'))!;
    expect(r.level, RuleLevel.askFirst);
    expect(r.categoryId, cats[0]);
  });
}
