// 0.2.2 item 2 slice B2d, the repository side, end to end on the real in-memory database and real (mock) preferences:
// an AUTOMATIC mark Kotlin wrote is re-checked at ingest from the stored rule, pause and details; passing writes ONE
// row through the repository's own save with recorded_automatically = 1; Undo moves it to Recently deleted, the
// person stays on Auto-record (D-U, PM 25-11; was S-3 "drops to Suggested") and the 24 h undone code stops the same
// message being recorded again. Any failed check leaves the item waiting. With the flag false (the default) nothing is recorded.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/ledger_rule_events.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/history/history_summary_writer.dart';
import 'package:mmogo/autoread/history/rule_labeler.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';
import 'package:mmogo/autoread/rules/prefs_rule_engine.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/receiver_key.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/waiting_fakes.dart';

final _t0 = DateTime(2026, 11, 19, 14, 5);
final String _key = receiverKey(ReceiverType.sendMoney, phone: sampleFields(1, _t0).counterpartyPhone)!;

/// Keeps the hint (the shared in-memory stand-in drops it).
class _HintStore implements PendingItemsStore {
  final List<WaitingItem> items = [];
  @override
  Future<StoreResult> put(WaitingItem item, {required int generation}) async {
    items.add(item);
    return StoreResult.stored;
  }

  @override
  Future<List<WaitingItem>> list() async => List.of(items);
  @override
  Future<void> remove(String id) async => items.removeWhere((i) => i.id == id);
  @override
  Future<int> readGeneration() async => 1;
  @override
  Future<int> bumpGeneration() async => 2;
  @override
  Future<bool> containsCode(String displayCode) async => items.any((i) => i.parsed?.code == displayCode);
  @override
  Future<int> count() async => items.length;
}

class _NoYes implements YesMarks {
  @override
  Future<Map<String, DateTime>> read() async => const {};
  @override
  Future<void> remove(Iterable<String> ids) async {}
}

void main() {
  late Database db;
  late _HintStore store;
  late PrefsRuleStore rules;
  late PrefsUndoneCodes undone;
  late List<QueuedYesRecorded> toasted;
  late int cat;

  RealWaitingRepository repo({bool? live = true}) {
    final bridge = FakeAutoReadBridge(now: () => _t0);
    return RealWaitingRepository(
      bridge: bridge,
      store: store,
      service: AutoReadService(bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
      database: () async => db,
      now: () => _t0,
      captureIdentity: () async => true,
      timer: (after, fire) => Timer(const Duration(days: 365), () {}),
      readAirtimeAuto: () async => false,
      writeAirtimeAuto: (_) async {},
      readAirtimeAutoOther: () async => false,
      writeAirtimeAutoOther: (_) async {},
      yesMarks: _NoYes(),
      undoneCodes: undone,
      onQueuedYes: toasted.addAll,
      autoRecordLive: live, // real PrefsAutoMarks and the real HardRuleRecheck (defaults)
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: 5,
            singleInstance: false,
            onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
            onCreate: (d, v) async {
              await AppSchema.createSchema(d);
              await AppSchema.seed(d);
            }));
    cat = (await db.rawQuery(
            "SELECT c.id FROM classifications c WHERE c.active = 1 ORDER BY c.id LIMIT 1"))
        .first['id']! as int;
    store = _HintStore();
    rules = PrefsRuleStore();
    undone = PrefsUndoneCodes();
    toasted = [];
  });
  tearDown(() async => db.close());

  Future<void> setAuto({int? ceiling}) async {
    expect(await rules.setLevel(ReceiverType.sendMoney, _key,
        name: 'Sample Pharmacy', level: RuleLevel.autoRecord, categoryId: cat, ceilingCents: ceiling, at: _t0), isTrue);
  }

  /// What the arrival leaves: the item with an `auto` hint (Dart labeler) and the automatic mark (Kotlin).
  Future<WaitingItem> arrive(int n, {RuleLevel level = RuleLevel.autoRecord, bool mark = true}) async {
    final item = WaitingItem(
      id: heldIdFor(n),
      kind: WaitingKind.waitingCategory,
      heldAt: _t0.subtract(const Duration(minutes: 20)),
      parsed: sampleFields(1, _t0), // the same person (and the same code) every time
      hint: RuleHint(level: level, type: ReceiverType.sendMoney, key: _key, suggested: [cat]),
    );
    await store.put(item, generation: 1);
    if (mark) {
      await (await SharedPreferences.getInstance())
          .setString('$kYesMarkPrefix${item.id}', '$kAutoMarkTag${_t0.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch}');
    }
    return item;
  }

  Future<List<Map<String, Object?>>> liveRows() => db.query('transactions', where: 'deleted_at IS NULL');
  Future<bool> markLeft(String id) async => (await SharedPreferences.getInstance()).containsKey('$kYesMarkPrefix$id');

  test('passes: one row through the save, recorded_automatically = 1, the item leaves, the mark goes, the toast is automatic', () async {
    await setAuto(ceiling: 120000); // equal to the amount: records
    final item = await arrive(1);
    final r = repo();
    await r.ingest();
    final rows = await liveRows();
    expect(rows, hasLength(1));
    expect(rows.single['classification_id'], cat);
    expect(rows.single['recorded_automatically'], 1);
    expect(rows.single['display_code'], item.parsed!.code);
    expect(toasted.single.automatic, isTrue);
    expect(toasted.single.rowId, rows.single['id']);
    expect(store.items, isEmpty);
    expect(await markLeft(item.id), isFalse);
    await r.ingest(); // a second open records nothing more
    expect(await liveRows(), hasLength(1));
    r.dispose();
  });

  // D-U: changed on purpose (was "the person drops to Suggested ... the next is not automatic").
  test('Undo: Recently deleted, the person stays on Auto-record, the same message is not recorded again', () async {
    await setAuto();
    final item = await arrive(1);
    final r = repo();
    await r.ingest();
    final rowId = toasted.single.rowId;
    await r.undoQueuedYes(toasted.single);
    // In the app the ledger hook calls this after the soft delete (TransactionDao.softDelete -> LedgerHooks.removed).
    await LedgerRuleEvents(
      engine: PrefsRuleEngine(rules),
      store: rules,
      undone: undone,
      summary: HistorySummaryWriter(rows: () async => readHistoryRows(db)),
      database: () async => db,
      detailsOn: () async => true,
      now: () => _t0,
    ).removed(rowId);
    expect(await liveRows(), isEmpty);
    expect((await db.query('transactions', where: 'id = ?', whereArgs: [rowId])).single['deleted_at'], isNotNull);
    final rule = (await rules.get(ReceiverType.sendMoney, _key))!;
    expect(rule.level, RuleLevel.autoRecord);
    expect(rule.categoryId, cat);

    // The same message arrives again with a (stale) automatic mark: the undone code is never recorded again.
    final again = await arrive(2);
    await r.ingest();
    expect(await liveRows(), isEmpty);
    expect(await markLeft(again.id), isFalse);

    // The next message from that person is still labelled Auto-record (the level was kept).
    final hint = await RuleLabeler(rules: rules, history: FakeHistoryReader(), live: true, paused: () async => false)
        .label(sampleFields(1, _t0));
    expect(hint?.level, RuleLevel.autoRecord);
    expect(item.id, isNot(again.id));
    r.dispose();
  });

  test('re-check fails at import (paused since): no row, the mark is dropped, the item keeps waiting', () async {
    await setAuto();
    expect(await PrefsHardRulePause().setPaused(true), isTrue);
    final item = await arrive(1);
    final r = repo();
    await r.ingest();
    expect(await liveRows(), isEmpty);
    expect(toasted, isEmpty);
    expect(store.items.single.id, item.id);
    expect(await markLeft(item.id), isFalse);
    r.dispose();
  });

  test('re-check fails: 1 cent above the ceiling, details off, rule now Ask first, rule gone', () async {
    Future<void> expectWaits(Future<void> Function() setup) async {
      SharedPreferences.setMockInitialValues({});
      store.items.clear();
      await setup();
      final item = await arrive(1);
      final r = repo();
      await r.ingest();
      expect(await liveRows(), isEmpty);
      expect(store.items.single.id, item.id);
      expect(await markLeft(item.id), isFalse);
      r.dispose();
    }

    await expectWaits(() => setAuto(ceiling: 119999));
    await expectWaits(() async {
      await setAuto();
      await (await SharedPreferences.getInstance()).setBool(AppPrefs.keyCaptureIdentityPreference, false);
    });
    await expectWaits(() => rules.setLevel(ReceiverType.sendMoney, _key, name: 'P', level: RuleLevel.askFirst, categoryId: cat, at: _t0));
    await expectWaits(() async {});
    expect(toasted, isEmpty);
  });

  test('an Ask first item with an automatic mark is never recorded by it', () async {
    await setAuto();
    final item = await arrive(1, level: RuleLevel.askFirst);
    final r = repo();
    await r.ingest();
    expect(await liveRows(), isEmpty);
    expect(store.items.single.id, item.id);
    r.dispose();
  });

  test('duplicate code: the code is already in the ledger, no second row', () async {
    await setAuto();
    final item = await arrive(1);
    final r = repo();
    await r.saveCategory(item.id, '$cat'); // the user recorded it by hand first
    expect(await liveRows(), hasLength(1));
    final again = await arrive(2); // same code, automatic mark
    await r.ingest();
    expect(await liveRows(), hasLength(1));
    expect(await markLeft(again.id), isFalse);
    r.dispose();
  });

  test('flag false: no mark can produce a row; the mark is dropped and the item waits', () async {
    await setAuto();
    final item = await arrive(1);
    final r = repo(live: false);
    await r.ingest();
    expect(await liveRows(), isEmpty);
    expect(toasted, isEmpty);
    expect(store.items.single.id, item.id);
    expect(await markLeft(item.id), isFalse);
    r.dispose();
  });
}
