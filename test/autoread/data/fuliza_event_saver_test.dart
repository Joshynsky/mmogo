// §AUTOREAD.FULIZA_EVENT_SAVER (0.2.0 S12 slice D): held Fuliza messages become
// stored events once; everything else writes nothing. Invented text only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/fuliza_event_saver.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/migrations.dart' show kDbVersion;
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/db/sqlite_fuliza_repository.dart';
import 'package:mmogo/domain/fuliza/fuliza_ledger.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:mmogo/domain/parsing/fuliza_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;

final _t0 = DateTime(2026, 11, 3, 14, 5);

String draw(String code, String amt, String fee, String total) =>
    '$code Confirmed. Fuliza M-PESA amount is Ksh $amt. Interest charged Ksh $fee. '
    'Total Fuliza M-PESA outstanding amount is Ksh $total due on 14/11/26.';
String repay(String code, String amt, {bool full = true, String? limit}) =>
    '$code Confirmed. Ksh $amt from your M-PESA has been used to ${full ? 'fully' : 'partially'} pay '
    'your outstanding Fuliza M-PESA.${limit == null ? '' : ' Available Fuliza M-PESA limit is Ksh $limit.'}';

const _advert = 'AB12CD34EF Confirmed. You bought Ksh 5.00 of airtime on 3/11/26. Opt in to FULIZA to top up.';
const _refusal = 'Dear Customer, you have an outstanding Fuliza M-PESA transaction, please try again later.';
const _limitNotice = 'Dear Customer, your Fuliza M-PESA limit is Ksh 5,000.00. Keep using M-PESA to grow your limit.';
const _odd = 'ZZZ9Y8X7W6 Confirmed. something odd about Ksh 77';

class _Throwing extends InMemoryFulizaRepository {
  @override
  Future<bool> addEvent(FulizaEvent event) async => throw StateError('boom');
}

void main() {
  late Database db;
  late FakeAutoReadBridge bridge;
  late RealWaitingRepository repo;
  late FulizaRepository events;

  RealWaitingRepository build(FulizaRepository r) {
    final store = InMemoryPendingStore();
    return RealWaitingRepository(
      bridge: bridge,
      store: store,
      service: AutoReadService(
          bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
      database: () async => db,
      now: () => _t0,
      captureIdentity: () async => true,
      timer: (after, fire) => Timer(const Duration(days: 365), () {}),
      fulizaSaver: FulizaEventSaver(() async => r),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: kDbVersion,
            singleInstance: false,
            onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
            onCreate: (d, v) async {
              await AppSchema.createSchema(d);
              await AppSchema.seed(d);
            }));
    bridge = FakeAutoReadBridge(now: () => _t0);
    events = SqliteFulizaRepository(db);
    repo = build(events);
  });
  tearDown(() async {
    repo.dispose();
    await db.close();
  });

  Future<void> hold(int n, String body) async =>
      bridge.hold(heldIdFor(n), body, _t0.subtract(Duration(minutes: 10 - n)));

  test('a draw is saved once, with the held time; a second ingest and a rebuild add nothing', () async {
    await hold(1, draw('AA11BB22CC', '100.00', '1.00', '101.00'));
    await repo.ingest();
    var list = await events.events();
    expect(list, hasLength(1));
    expect(list.single.kind, FulizaEventKind.draw);
    expect(list.single.amountCents, 10000);
    expect(list.single.feeCents, 100);
    expect(list.single.printedTotalCents, 10100);
    expect(list.single.at, _t0.subtract(const Duration(minutes: 9)));
    await repo.ingest();
    expect(await repo.rebuildFromHeld(), 0);
    expect(await events.events(), hasLength(1));
  });

  test('the item still shows in Notifications as before', () async {
    await hold(1, draw('AA11BB22CC', '100.00', '1.00', '101.00'));
    await hold(2, _odd);
    await repo.ingest();
    final items = await repo.watch().first;
    final plain = build(InMemoryFulizaRepository());
    addTearDown(plain.dispose);
    await plain.ingest();
    expect(items.map((i) => i.kind), (await plain.watch().first).map((i) => i.kind));
    expect(items.map((i) => i.kind), contains(WaitingKind.unreadable));
  });

  test('full and partial repayments are saved; the limit updates', () async {
    await hold(1, repay('DD33EE44FF', '101.00', limit: '1,000.00'));
    await hold(2, repay('GG55HH66JJ', '40.00', full: false));
    await repo.ingest();
    final list = await events.events();
    expect(list.map((e) => e.kind), unorderedEquals([FulizaEventKind.repayFull, FulizaEventKind.repayPartial]));
    expect(await events.limitCents(), 100000);
  });

  test('adverts, refusals, notices and unreadable text write no event', () async {
    await hold(1, _advert);
    await hold(2, _refusal);
    await hold(3, _limitNotice);
    await hold(4, _odd);
    await hold(5, 'Failed. Insufficient funds as well as Fuliza. Available Fuliza M-PESA limit is Ksh 10.00');
    await hold(6, 'Recharge of 5.00 KSH for 0700000000 was successful.');
    await repo.ingest();
    expect(await events.events(), isEmpty);
    expect(await events.limitCents(), 500000); // the limit notice only updates the limit
  });

  test('a repository that throws does not break ingest', () async {
    final r = build(_Throwing());
    addTearDown(r.dispose);
    await hold(1, draw('AA11BB22CC', '100.00', '1.00', '101.00'));
    await r.ingest();
    expect((await r.watch().first), hasLength(1));
  });

  test('rebuildFromHeld adds only what is missing and counts it', () async {
    final noSaver = RealWaitingRepository(
      bridge: bridge,
      store: InMemoryPendingStore(),
      service: AutoReadService(
          bridge: bridge, store: InMemoryPendingStore(), savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
      database: () async => db,
      now: () => _t0,
      timer: (after, fire) => Timer(const Duration(days: 365), () {}),
    );
    addTearDown(noSaver.dispose);
    await hold(1, draw('AA11BB22CC', '100.00', '1.00', '101.00'));
    await hold(2, repay('DD33EE44FF', '101.00'));
    await noSaver.ingest();
    expect(await events.events(), isEmpty);
    expect(await repo.rebuildFromHeld(), 2);
    expect(await repo.rebuildFromHeld(), 0);
    expect(await events.events(), hasLength(2));
  });

  test('ledger over stored events equals the in-memory path (fixture B, shortened)', () async {
    final msgs = [
      draw('AA11BB22CC', '500.00', '5.00', '505.00'),
      draw('BB22CC33DD', '300.00', '3.00', '808.00'),
      repay('CC33DD44EE', '400.00', full: false),
      draw('DD44EE55FF', '50.00', '0.50', '458.50'),
      repay('EE55FF66GG', '458.50'),
    ];
    final mem = InMemoryFulizaRepository();
    for (var i = 0; i < msgs.length; i++) {
      final at = _t0.subtract(Duration(minutes: 20 - i));
      bridge.hold(heldIdFor(i + 1), msgs[i], at);
      await FulizaLedger(mem).ingest(FulizaParser.parse(msgs[i]), at);
    }
    await repo.ingest();
    final a = await FulizaLedger(events).state();
    final b = await FulizaLedger(mem).state();
    expect(a.owingCents, b.owingCents);
    expect(a.owingIsEstimate, b.owingIsEstimate);
    expect(a.chains.length, b.chains.length);
    expect(a.owingCents, 0);
  });
}
