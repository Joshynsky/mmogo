// 0.2.2 item 2 slice B-ARR, the repository side, on the real in-memory database and real (mock) preferences:
//  - B-4: Kotlin's pushed `onArrived` while the app is in front runs ONE ingest at once and records the queued
//    Auto-record entry; two arrivals and a resume at the same moment still record it ONCE (the ingest queue).
//    In the background, before the app's own first ingest, or after dispose: nothing runs.
//  - B-2: every recorded queued item (no-tap Auto-record and a tapped Yes alike) ends in the cancel of its alert;
//    a dropped mark cancels too; nothing is cancelled when nothing was queued.
// Invented data only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/receiver_key.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/waiting_fakes.dart';

final _t0 = DateTime(2026, 11, 25, 14, 5);
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

void main() {
  late Database db;
  late _HintStore store;
  late PrefsRuleStore rules;
  late List<QueuedYesRecorded> toasted;
  late int cat;
  late FakeAutoReadBridge bridge;
  late bool front;

  RealWaitingRepository repo({bool? live = true}) {
    bridge = FakeAutoReadBridge(now: () => _t0);
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
      undoneCodes: PrefsUndoneCodes(),
      onQueuedYes: toasted.addAll,
      autoRecordLive: live, // real PrefsYesMarks, PrefsAutoMarks and HardRuleRecheck (defaults)
      inFront: () => front,
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
    cat = (await db.rawQuery('SELECT c.id FROM classifications c WHERE c.active = 1 ORDER BY c.id LIMIT 1')).first['id']!
        as int;
    store = _HintStore();
    rules = PrefsRuleStore();
    toasted = [];
    front = true;
  });
  tearDown(() async => db.close());

  Future<void> setLevel(RuleLevel level) async {
    expect(
        await rules.setLevel(ReceiverType.sendMoney, _key, name: 'Sample Pharmacy', level: level, categoryId: cat, at: _t0),
        isTrue);
  }

  /// What a queued arrival leaves: the parsed item with its hint, and the mark (automatic or a tapped Yes).
  Future<WaitingItem> arrive(int n, {RuleLevel level = RuleLevel.autoRecord, bool yesTap = false}) async {
    final item = WaitingItem(
      id: heldIdFor(n),
      kind: WaitingKind.waitingCategory,
      heldAt: _t0.subtract(const Duration(minutes: 20)),
      parsed: sampleFields(n == 1 ? 1 : 7, _t0),
      hint: RuleHint(level: level, type: ReceiverType.sendMoney, key: _key, suggested: [cat]),
    );
    await store.put(item, generation: 1);
    final p = await SharedPreferences.getInstance();
    final at = _t0.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch;
    if (yesTap) {
      await p.setInt('$kYesMarkPrefix${item.id}', at);
    } else {
      await p.setString('$kYesMarkPrefix${item.id}', '$kAutoMarkTag$at');
    }
    return item;
  }

  Future<List<Map<String, Object?>>> liveRows() => db.query('transactions', where: 'deleted_at IS NULL');
  int ingests() => bridge.calls.where((c) => c == 'listHeldIds').length;

  /// Lets the pushed event, the queued ingest and its awaits finish (real I/O on the ffi database).
  Future<void> settle(RealWaitingRepository r) async {
    await pumpEventQueue();
    await r.ingest(); // queued behind anything already started; returns once those are done
  }

  group('B-4: an arrival while the app is in front imports at once', () {
    test('onArrived -> exactly one ingest, one row, the toast, the alert cancelled', () async {
      await setLevel(RuleLevel.autoRecord);
      final r = repo();
      await r.ingest(); // the app's own first ingest (start), nothing queued yet
      expect(ingests(), 1);
      final item = await arrive(1);
      bridge.pushArrived();
      await pumpEventQueue(times: 50);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(ingests(), 2, reason: 'one ingest for one arrival');
      final rows = await liveRows();
      expect(rows, hasLength(1));
      expect(rows.single['recorded_automatically'], 1);
      expect(toasted.single.automatic, isTrue);
      expect(store.items, isEmpty);
      expect(bridge.cancelledAlerts, [item.id]);
      r.dispose();
    });

    test('two arrivals and a resume at the same moment: ONE row, one toast, nothing recorded twice', () async {
      await setLevel(RuleLevel.autoRecord);
      final r = repo();
      await r.ingest();
      final item = await arrive(1);
      bridge.pushArrived();
      bridge.pushArrived();
      final resume = r.ingest(); // the resume ingest (main.dart) at the same moment
      await resume;
      await settle(r);
      expect(await liveRows(), hasLength(1));
      expect(toasted, hasLength(1));
      expect(store.items, isEmpty);
      expect(bridge.cancelledAlerts, [item.id], reason: 'the mark is finished once, so the cancel runs once');
      r.dispose();
    });

    test('in the background nothing runs; the next resume ingest records it', () async {
      await setLevel(RuleLevel.autoRecord);
      final r = repo();
      await r.ingest();
      front = false;
      await arrive(1);
      bridge.pushArrived();
      await pumpEventQueue(times: 50);
      expect(ingests(), 1);
      expect(await liveRows(), isEmpty);
      front = true;
      await r.ingest(); // resume
      expect(await liveRows(), hasLength(1));
      r.dispose();
    });

    test('before the app\'s own first ingest, and after dispose, an arrival runs nothing', () async {
      await setLevel(RuleLevel.autoRecord);
      final r = repo();
      await arrive(1);
      bridge.pushArrived();
      await pumpEventQueue(times: 50);
      expect(ingests(), 0);
      r.dispose();
      bridge.pushArrived();
      await pumpEventQueue(times: 50);
      expect(ingests(), 0);
      expect(await liveRows(), isEmpty);
    });

    test('flag false: the arrival imports, records nothing, drops the mark, clears the alert', () async {
      await setLevel(RuleLevel.autoRecord);
      final r = repo(live: false);
      await r.ingest();
      final item = await arrive(1);
      bridge.pushArrived();
      await settle(r);
      expect(await liveRows(), isEmpty);
      expect(toasted, isEmpty);
      expect(store.items.single.id, item.id, reason: 'the item keeps waiting in To do');
      expect(bridge.cancelledAlerts, [item.id]);
      r.dispose();
    });
  });

  group('B-2: a recorded queued item ends in the cancel of its alert', () {
    test('no-tap (Auto-record) entry recorded on open: its alert is cancelled', () async {
      await setLevel(RuleLevel.autoRecord);
      final item = await arrive(1);
      final r = repo();
      await r.ingest();
      expect(await liveRows(), hasLength(1));
      expect(bridge.cancelledAlerts, [item.id]);
      r.dispose();
    });

    test('tapped (a Yes on an Ask first alert) entry recorded on open: its alert is cancelled', () async {
      await setLevel(RuleLevel.askFirst);
      final item = await arrive(1, level: RuleLevel.askFirst, yesTap: true);
      final r = repo();
      await r.ingest();
      expect(await liveRows(), hasLength(1));
      expect(toasted.single.automatic, isFalse);
      expect(bridge.cancelledAlerts, [item.id]);
      r.dispose();
    });

    test('a tapped and a no-tap entry in one open: both recorded, both alerts cancelled', () async {
      await setLevel(RuleLevel.autoRecord);
      final auto = await arrive(1);
      final yes = await arrive(2, level: RuleLevel.askFirst, yesTap: true);
      final r = repo();
      await r.ingest();
      expect(await liveRows(), hasLength(2));
      expect(bridge.cancelledAlerts.toSet(), {auto.id, yes.id});
      r.dispose();
    });

    test('nothing queued: no cancel at all (other alerts are left alone)', () async {
      await setLevel(RuleLevel.autoRecord);
      final r = repo();
      await r.ingest();
      expect(bridge.cancelledAlerts, isEmpty);
      r.dispose();
    });
  });
}
