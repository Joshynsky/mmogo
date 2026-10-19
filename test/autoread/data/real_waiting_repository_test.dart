// §AUTOREAD.REAL_WAITING_REPO (I1): the real waiting repository over a real
// in-memory sqlite, the fake bridge and the in-memory store stand-in. Invented
// messages only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/held_window.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;

final _t0 = DateTime(2026, 10, 19, 8, 0);

/// A store whose first [failRemoves] calls to remove throw (a crash between the
/// transaction write and the item removal).
class _FlakyStore implements PendingItemsStore {
  _FlakyStore(this.inner);
  final InMemoryPendingStore inner;
  int failRemoves = 0;

  @override
  Future<StoreResult> put(WaitingItem item, {required int generation}) => inner.put(item, generation: generation);
  @override
  Future<List<WaitingItem>> list() => inner.list();
  @override
  Future<void> remove(String id) async {
    if (failRemoves > 0) {
      failRemoves--;
      throw StateError('crash');
    }
    await inner.remove(id);
  }

  @override
  Future<int> readGeneration() => inner.readGeneration();
  @override
  Future<int> bumpGeneration() => inner.bumpGeneration();
  @override
  Future<bool> containsCode(String displayCode) => inner.containsCode(displayCode);
  @override
  Future<int> count() => inner.count();
}

class _Clock {
  DateTime t = _t0;
}

class _Env {
  _Env(this.db, this.clock, this.bridge, this.inner, this.store, this.repo, this.timers, this.saved);
  final Database db;
  final _Clock clock;
  final _ListFailBridge bridge;
  final InMemoryPendingStore inner;
  final _FlakyStore store;
  final RealWaitingRepository repo;
  final List<({Duration after, void Function() fire})> timers;
  final List<String> saved; // entry-saved notifications

  Future<List<Map<String, Object?>>> transactions() => db.query('transactions');
  Future<int> classId(String name, String group) async => (await db.rawQuery(
          'SELECT c.id FROM classifications c JOIN classification_groups g ON g.id = c.group_id '
          'WHERE c.name = ? AND g.code = ? AND c.active = 1',
          [name, group]))
      .first['id'] as int;
}

Future<Database> _freshDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) async {
            await AppSchema.createSchema(db);
            await AppSchema.seed(db);
          }));
}

class _ListFailBridge extends FakeAutoReadBridge {
  _ListFailBridge({required super.now});
  bool listFails = false;
  @override
  Future<List<String>> listHeldIds() => listFails ? Future<List<String>>.error(StateError('x')) : super.listHeldIds();
}

Future<_Env> _env({int capacity = 200, bool capture = true}) async {
  final db = await _freshDb();
  final clock = _Clock();
  final bridge = _ListFailBridge(now: () => clock.t);
  final inner = InMemoryPendingStore(capacity: capacity);
  final store = _FlakyStore(inner);
  final timers = <({Duration after, void Function() fire})>[];
  final saved = <String>[];
  final env = _Env(db, clock, bridge, inner, store,
      RealWaitingRepository(
        bridge: bridge,
        store: store,
        service: AutoReadService(
          bridge: bridge,
          store: store,
          savedCodes: TransactionCodeLookup(() async => db),
          now: () => clock.t,
        ),
        database: () async => db,
        now: () => clock.t,
        captureIdentity: () async => capture,
        onSaved: () => saved.add('saved'),
        timer: (after, fire) {
          timers.add((after: after, fire: fire));
          return Timer(const Duration(days: 365), () {}); // never fires by itself
        },
      ),
      timers,
      saved);
  return env;
}

String _id(int n) => heldIdFor(n);

WaitingItem _row(List<WaitingItem> l, String id) => l.firstWhere((i) => i.id == id);

void main() {
  late _Env env;
  tearDown(() async {
    env.repo.dispose();
    await env.db.close();
  });

  group('ingest', () {
    test('a readable held message becomes ready to parse, an unreadable one an unreadable row, none lost', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0.subtract(const Duration(hours: 1)));
      env.bridge.hold(_id(2), 'hello, this is not an M-Pesa message', _t0.subtract(const Duration(hours: 2)));
      env.bridge.hold(_id(3), kSampleNameOnly, _t0.subtract(const Duration(hours: 3)));
      await env.repo.ingest();
      final items = await env.repo.watch().first;
      expect(items, hasLength(3));
      expect(_row(items, _id(1)).kind, WaitingKind.readyToParse);
      expect(_row(items, _id(2)).kind, WaitingKind.unreadable);
      expect(_row(items, _id(3)).kind, WaitingKind.unreadable);
      expect(_row(items, _id(2)).heldAt, _t0.subtract(const Duration(hours: 2)));
      // Looking is not parsing: nothing stored, nothing acked.
      expect(await env.inner.count(), 0);
      expect([for (final i in [1, 2, 3]) env.bridge.isHeld(_id(i))], [true, true, true]);
      expect(parseCount(items, _t0), 1);
    });

    test('a second ingest does not look at known messages again', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      env.bridge.calls.clear();
      await env.repo.ingest();
      expect(env.bridge.calls.where((c) => c.startsWith('peekHeld')), isEmpty);
    });

    test('a message that left the held list leaves the rows', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      await env.bridge.ackHeld(_id(1), generation: 1);
      await env.repo.ingest();
      expect(await env.repo.watch().first, isEmpty);
    });

    test('works with no read switch at all: held items are shown (Read off keeps them)', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0.subtract(const Duration(hours: 5)));
      await env.repo.ingest();
      expect((await env.repo.watch().first).single.kind, WaitingKind.readyToParse);
    });

    test('an already recorded payment is dropped and its held copy acked', () async {
      env = await _env();
      await env.db.insert('transactions', {
        'display_code': 'QWE1R2T3Y4',
        'source_type': 'SEND_MONEY',
        'amount_cents': 50000,
        'transaction_cost_cents': 700,
        'classification_id': await env.classId('Transport', 'SEND_MONEY'),
        'raw_parse_source': 'MANUAL',
        'transaction_occurred_at': 1,
        'created_at': 1,
      });
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      expect(await env.repo.watch().first, isEmpty);
      expect(env.bridge.isHeld(_id(1)), isFalse);
    });

    test('a held copy of a payment already waiting is dropped (duplicate)', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      expect(await env.repo.parse(_id(1)), ParseOutcome.parsed);
      env.bridge.hold(_id(2), kSampleSendMoney, _t0); // the same message again
      await env.repo.ingest();
      final items = await env.repo.watch().first;
      expect(items.where((i) => i.kind == WaitingKind.waitingCategory), hasLength(1));
      expect(items.any((i) => i.id == _id(2)), isFalse);
      expect(env.bridge.isHeld(_id(2)), isFalse);
    });

    test('a bridge failure keeps what is known and still answers', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      env.bridge.listFails = true;
      await env.repo.ingest(); // listing fails: swallowed, the list stays
      final items = await env.repo.watch().first;
      expect(items.map((i) => i.id), [_id(1)]);
    });
  });

  group('parse', () {
    test('readable: ready to parse, then Categorize; the held copy is acked after the read back', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      expect(await env.repo.parse(_id(1)), ParseOutcome.parsed);
      final items = await env.repo.watch().first;
      final r = _row(items, _id(1));
      expect(r.kind, WaitingKind.waitingCategory);
      expect(r.parsed!.code, 'QWE1R2T3Y4');
      expect(r.parsed!.amountCents, 50000);
      expect(env.bridge.isHeld(_id(1)), isFalse);
      expect(categorizeCount(items, _t0), 1);
      expect(parseCount(items, _t0), 0);
    });

    test('unreadable stays an unreadable row and the message stays held', () async {
      env = await _env();
      env.bridge.hold(_id(1), 'not a payment', _t0);
      await env.repo.ingest();
      expect(await env.repo.parse(_id(1)), ParseOutcome.couldNotRead);
      final items = await env.repo.watch().first;
      expect(_row(items, _id(1)).kind, WaitingKind.unreadable);
      expect(env.bridge.isHeld(_id(1)), isTrue);
    });

    test('full: the message stays held and stays on the list', () async {
      env = await _env(capacity: 1);
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      env.bridge.hold(_id(2), kSampleBuyGoods, _t0);
      await env.repo.ingest();
      expect(await env.repo.parse(_id(1)), ParseOutcome.parsed);
      expect(await env.repo.parse(_id(2)), ParseOutcome.couldNotRead);
      expect(env.bridge.isHeld(_id(2)), isTrue);
      expect(env.repo.itemById(_id(2)), isNotNull);
    });

    test('stale generation (Delete data bumped it): nothing is stored', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      env.bridge.generation = 99; // the store is still on its old generation
      expect(await env.repo.parse(_id(1)), ParseOutcome.gone);
      expect(await env.inner.count(), 0);
      expect(env.repo.itemById(_id(1))!.kind, WaitingKind.gone);
    });

    test('parse all: counts the ones that parsed', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      env.bridge.hold(_id(2), kSampleBuyGoods, _t0);
      env.bridge.hold(_id(3), 'nothing to read', _t0);
      await env.repo.ingest();
      expect(await env.repo.parseAll([_id(1), _id(2), _id(3)]), 2);
      final items = await env.repo.watch().first;
      expect(categorizeCount(items, _t0), 2);
      expect(_row(items, _id(3)).kind, WaitingKind.unreadable);
    });
  });

  group('expiry', () {
    test('a timer on the next expiry re-emits and the ready row counts as gone', () async {
      env = await _env();
      final heldAt = _t0.subtract(const Duration(hours: 23));
      env.bridge.hold(_id(1), kSampleSendMoney, heldAt);
      await env.repo.ingest();
      expect(env.timers, isNotEmpty);
      expect(env.timers.last.after, heldAt.add(kHeldWindow).difference(_t0) + const Duration(seconds: 1));
      final emissions = <List<WaitingItem>>[];
      final sub = env.repo.watch().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(parseCount(emissions.last, _t0), 1);
      // Time passes the window; the timer fires.
      final later = _t0.add(const Duration(hours: 1, seconds: 2));
      env.clock.t = later;
      env.timers.last.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(parseCount(emissions.last, later), 0);
      expect(effectiveKind(_row(emissions.last, _id(1)), later), WaitingKind.gone);
      await sub.cancel();
    });
  });

  group('remove', () {
    test('an unreadable row is removed and its held copy deleted', () async {
      env = await _env();
      env.bridge.hold(_id(1), 'nothing', _t0);
      await env.repo.ingest();
      await env.repo.remove(_id(1));
      expect(await env.repo.watch().first, isEmpty);
      expect(env.bridge.isHeld(_id(1)), isFalse);
    });

    test('a readable ready row and a waiting-category row cannot be removed', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      env.bridge.hold(_id(2), kSampleBuyGoods, _t0);
      await env.repo.ingest();
      await env.repo.parse(_id(2));
      expect(env.repo.remove(_id(1)), throwsStateError);
      expect(env.repo.remove(_id(2)), throwsStateError);
      expect(env.repo.itemById(_id(1)), isNotNull);
      expect(env.repo.itemById(_id(2)), isNotNull);
    });
  });

  group('saveCategory', () {
    Future<void> parsedItem(String text, {int n = 1}) async {
      env.bridge.hold(_id(n), text, _t0.subtract(const Duration(minutes: 5)));
      await env.repo.ingest();
      expect(await env.repo.parse(_id(n)), ParseOutcome.parsed);
    }

    test('creates exactly one transaction with the parsed fields and the chosen category', () async {
      env = await _env();
      await parsedItem(kSampleSendMoney);
      final cls = await env.classId('Transport', 'SEND_MONEY');
      env.bridge.calls.clear();
      await env.repo.saveCategory(_id(1), '$cls');
      final rows = await env.transactions();
      expect(rows, hasLength(1));
      final t = rows.single;
      expect(t['display_code'], 'QWE1R2T3Y4');
      expect(t['source_type'], 'SEND_MONEY');
      expect(t['amount_cents'], 50000);
      expect(t['transaction_cost_cents'], 700);
      expect(t['counterparty_label'], 'JANE DOE');
      expect(t['counterparty_phone'], '0712345678');
      expect(t['classification_id'], cls);
      expect(t['raw_parse_source'], 'SMS_PARSE');
      expect(t['transaction_occurred_at'], DateTime(2026, 10, 8, 9, 15).millisecondsSinceEpoch);
      expect(t['deleted_at'], isNull);
      // The item left, the bridge was acked, auto-backup counted once.
      expect(await env.inner.count(), 0);
      expect(env.repo.itemById(_id(1)), isNull);
      expect(env.bridge.calls, contains('ackHeld:${_id(1)}'));
      expect(env.saved, hasLength(1));
      // The counterparty now remembers the category (same as Add's save).
      final map = await env.db.query('counterparty_classification_map');
      expect(map.single['classification_id'], cls);
    });

    test('the same code saved again is a no-op for the ledger', () async {
      env = await _env();
      await parsedItem(kSampleSendMoney);
      final cls = await env.classId('Transport', 'SEND_MONEY');
      await env.repo.saveCategory(_id(1), '$cls');
      // The same payment arrives again (a second held copy) and is saved again.
      await env.inner.put(
          WaitingItem(
              id: _id(9),
              kind: WaitingKind.waitingCategory,
              heldAt: _t0,
              parsed: (SmsParser.parse(kSampleSendMoney) as ParseSuccess).fields),
          generation: 1);
      await env.repo.saveCategory(_id(9), '$cls');
      expect(await env.transactions(), hasLength(1));
      expect(await env.inner.count(), 0);
      // Saving an id that is already gone does nothing.
      await env.repo.saveCategory(_id(1), '$cls');
      expect(await env.transactions(), hasLength(1));
    });

    test('a code already recorded by Add: no second row, the item still leaves', () async {
      env = await _env();
      await parsedItem(kSampleSendMoney);
      final cls = await env.classId('Transport', 'SEND_MONEY');
      await TransactionDao.insert(
          env.db,
          NewTransactionInput(
            displayCode: 'QWE1R2T3Y4',
            sourceType: 'SEND_MONEY',
            amountCents: 50000,
            transactionCostCents: 700,
            counterpartyLabel: null,
            counterpartyPhone: null,
            paybillAccountNumber: null,
            classificationId: cls,
            rawParseSource: 'MANUAL',
            transactionOccurredAt: 1,
          ));
      await env.repo.saveCategory(_id(1), '$cls');
      expect(await env.transactions(), hasLength(1));
      expect(await env.inner.count(), 0);
      expect(env.saved, isEmpty);
    });

    test('a crash between the write and the removal: nothing lost, no duplicate on retry', () async {
      env = await _env();
      await parsedItem(kSampleSendMoney);
      final cls = await env.classId('Transport', 'SEND_MONEY');
      env.store.failRemoves = 1;
      await expectLater(env.repo.saveCategory(_id(1), '$cls'), throwsStateError);
      expect(await env.transactions(), hasLength(1)); // written
      expect(await env.inner.count(), 1); // the item is still there: recoverable
      await env.repo.saveCategory(_id(1), '$cls'); // retry
      expect(await env.transactions(), hasLength(1)); // no duplicate
      expect(await env.inner.count(), 0);
    });

    test('a crash after the removal leaves a held copy that the next ingest drops', () async {
      env = await _env();
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      await env.repo.parse(_id(1));
      final cls = await env.classId('Transport', 'SEND_MONEY');
      // Simulate: the held copy survived (ack lost): put it back.
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.saveCategory(_id(1), '$cls');
      env.bridge.hold(_id(1), kSampleSendMoney, _t0);
      await env.repo.ingest();
      expect(await env.repo.watch().first, isEmpty);
      expect(env.bridge.isHeld(_id(1)), isFalse);
      expect(await env.transactions(), hasLength(1));
    });

    test('identity switch off: no name or number is stored', () async {
      env = await _env(capture: false);
      await parsedItem(kSampleSendMoney);
      await env.repo.saveCategory(_id(1), '${await env.classId('Transport', 'SEND_MONEY')}');
      final t = (await env.transactions()).single;
      expect(t['counterparty_label'], isNull);
      expect(t['counterparty_phone'], isNull);
    });

    test('withdrawal keeps the agent number and fee; buy goods and paybill keep their fields', () async {
      env = await _env();
      await parsedItem(kSampleWithdrawal);
      await parsedItem(kSamplePaybill, n: 2);
      await parsedItem(kSampleBuyGoods, n: 3);
      final wd = (await env.db.rawQuery("SELECT id FROM classifications WHERE seed_key = 'AGENT_WITHDRAWAL:cash_withdrawal'"))
          .first['id'] as int;
      await env.repo.saveCategory(_id(1), '$wd');
      await env.repo.saveCategory(_id(2), '${await env.classId('Transport', 'PAYBILL')}');
      await env.repo.saveCategory(_id(3), '${await env.classId('Transport', 'BUY_GOODS')}');
      final rows = {for (final r in await env.transactions()) r['display_code'] as String: r};
      expect(rows['ABC1D2E3F4']!['agent_number'], '1234567');
      expect(rows['ABC1D2E3F4']!['transaction_cost_cents'], 2900);
      expect(rows['ZXC1V2B3N4']!['paybill_account_number'], '998877');
      expect(rows['ZXC1V2B3N4']!['counterparty_label'], 'SAMPLE POWER CO');
      expect(rows['ASD1F2G3H4']!['counterparty_label'], 'SAMPLE SHOP');
    });

    test('a category from another group is refused by the database (nothing saved, item stays)', () async {
      env = await _env();
      await parsedItem(kSampleSendMoney);
      final other = await env.classId('Transport', 'PAYBILL');
      await expectLater(env.repo.saveCategory(_id(1), '$other'), throwsA(anything));
      expect(await env.transactions(), isEmpty);
      expect(await env.inner.count(), 1);
    });

    test('a bad category id is refused', () async {
      env = await _env();
      await parsedItem(kSampleSendMoney);
      await expectLater(env.repo.saveCategory(_id(1), 'abc'), throwsArgumentError);
    });
  });
}
