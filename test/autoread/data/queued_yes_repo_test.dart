@Tags(['autoread'])
library;

// 0.2.1 Ask first, the repository side: when the app ingests (open or resume) a Yes tapped on a phone alert is
// recorded with the category of the item's OWN stored hint, once, with Undo; an undone code is not recorded
// again; no mark means nothing is recorded (a tap always decides). Real in-memory database, invented fields.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_codec.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/waiting_fakes.dart';

final _t0 = DateTime(2026, 11, 19, 14, 5);

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

class _Marks implements YesMarks {
  final Map<String, DateTime> marks = {};
  @override
  Future<Map<String, DateTime>> read() async => Map.of(marks);
  @override
  Future<void> remove(Iterable<String> ids) async => ids.forEach(marks.remove);
}

void main() {
  late Database db;
  late _HintStore store;
  late _Marks marks;
  late FakeUndoneCodes undone;
  late RealWaitingRepository repo;
  late List<QueuedYesRecorded> toasted;
  late int cat;

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
    cat = (await db.rawQuery('SELECT id FROM classifications WHERE active = 1 ORDER BY id LIMIT 1')).first['id']! as int;
    store = _HintStore();
    marks = _Marks();
    undone = FakeUndoneCodes();
    toasted = [];
    final bridge = FakeAutoReadBridge(now: () => _t0);
    repo = RealWaitingRepository(
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
      yesMarks: marks,
      undoneCodes: undone,
      onQueuedYes: toasted.addAll,
    );
  });
  tearDown(() async {
    repo.dispose();
    await db.close();
  });

  Future<WaitingItem> addAsk(int n) async {
    final item = WaitingItem(
      id: heldIdFor(n),
      kind: WaitingKind.waitingCategory,
      heldAt: _t0.subtract(const Duration(minutes: 20)),
      parsed: sampleFields(n, _t0),
      hint: RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: '0700000000', suggested: [cat]),
    );
    await store.put(item, generation: 1);
    return item;
  }

  Future<List<Map<String, Object?>>> live() => db.query('transactions', where: 'deleted_at IS NULL');

  test('opening the app records a queued Yes with the hint category, once, and offers Undo', () async {
    final item = await addAsk(1);
    marks.marks[item.id] = _t0.subtract(const Duration(minutes: 3));
    await repo.ingest();
    final rows = await live();
    expect(rows, hasLength(1));
    expect(rows.single['classification_id'], cat);
    expect(rows.single['display_code'], item.parsed!.code);
    expect(toasted.single.rowId, rows.single['id']);
    expect(marks.marks, isEmpty);
    expect(store.items, isEmpty);
    await repo.ingest(); // a second open records nothing more
    expect(await live(), hasLength(1));
    expect(toasted, hasLength(1));

    await repo.undoQueuedYes(toasted.single);
    expect(await live(), isEmpty);
  });

  test('no Yes tapped, nothing recorded: an Ask first item waits for a tap', () async {
    await addAsk(1);
    await repo.ingest();
    expect(await live(), isEmpty);
    expect(store.items, hasLength(1));
    expect(toasted, isEmpty);
  });

  test('a code the user undid is not recorded by a late Yes', () async {
    final item = await addAsk(1);
    await undone.add(item.parsed!.code, now: _t0);
    marks.marks[item.id] = _t0.subtract(const Duration(minutes: 3));
    await repo.ingest();
    expect(await live(), isEmpty);
    expect(marks.marks, isEmpty);
    expect(toasted, isEmpty);
  });

  test('no Ask first rule stored: the names are not read and the database is not touched for them', () async {
    await repo.ingest();
    expect((await SharedPreferences.getInstance()).getString(kCategoryNamesKey), isNull);
  });

  test('the category names for the phone alert are written once and only when they change', () async {
    final rule = ReceiverRule(
        type: ReceiverType.sendMoney, key: '0700000000', name: 'Jane', level: RuleLevel.askFirst, categoryId: cat, created: _t0, changed: _t0);
    SharedPreferences.setMockInitialValues({ruleStorageKey(rule.type, rule.key): encodeRule(rule)});
    await repo.ingest();
    final p = await SharedPreferences.getInstance();
    final first = p.getString(kCategoryNamesKey);
    expect(first, isNotNull);
    expect(first, contains('"$cat"'));
    await p.remove(kCategoryNamesKey);
    await repo.ingest(); // unchanged names: not rewritten
    expect(p.getString(kCategoryNamesKey), isNull);
  });
}
