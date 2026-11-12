// §AUTOREAD.NON_TRANSACTION (0.2.0 S5): the recharge notice is ignored quietly;
// a real failed transaction message still shows. Invented text only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/non_transaction.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;

final _t0 = DateTime(2026, 11, 3, 14, 5);
const String kInventedRecharge = 'Recharge of 5.00 KSH for 0700000000 was successful. Thank you for using the service.';

void main() {
  group('isNonTransactionNotice', () {
    test('the recharge notice is ignored, in any case and spacing', () {
      expect(isNonTransactionNotice(kInventedRecharge), isTrue);
      expect(isNonTransactionNotice('  recharge of 100.00 ksh done'), isTrue);
      expect(isNonTransactionNotice('RECHARGE OF 1,000.00 KES ok'), isTrue);
    });
    test('transactions, failed messages, other text and empty are never ignored', () {
      expect(isNonTransactionNotice(kSampleSendMoney), isFalse);
      expect(isNonTransactionNotice(kSampleAirtime), isFalse);
      expect(isNonTransactionNotice('Failed. Recharge of 5.00 KSH could not be completed.'), isFalse);
      expect(isNonTransactionNotice('QWE1R2T3Y4 Confirmed. Recharge of 5.00 KSH'), isFalse);
      expect(isNonTransactionNotice('Dear customer, recharge today and win'), isFalse);
      expect(isNonTransactionNotice('hello, this is not an M-Pesa message'), isFalse);
      expect(isNonTransactionNotice(''), isFalse);
    });
  });

  group('repository with the recharge notice held', () {
    late Database db;
    late FakeAutoReadBridge bridge;
    late RealWaitingRepository repo;

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
              version: 3,
              singleInstance: false,
              onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
              onCreate: (d, v) async {
                await AppSchema.createSchema(d);
                await AppSchema.seed(d);
              }));
      bridge = FakeAutoReadBridge(now: () => _t0);
      final store = InMemoryPendingStore();
      repo = RealWaitingRepository(
        bridge: bridge,
        store: store,
        service: AutoReadService(
            bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
        database: () async => db,
        now: () => _t0,
        captureIdentity: () async => true,
        timer: (after, fire) => Timer(const Duration(days: 365), () {}),
      );
    });
    tearDown(() async {
      repo.dispose();
      await db.close();
    });

    test('no "Could not read" row, counts unchanged, the notice is dropped from the held store', () async {
      bridge.hold(heldIdFor(1), kSampleSendMoney, _t0.subtract(const Duration(minutes: 5)));
      bridge.hold(heldIdFor(2), kInventedRecharge, _t0.subtract(const Duration(minutes: 4)));
      await repo.ingest();
      final items = await repo.watch().first;
      expect(items, hasLength(1));
      expect(items.single.kind, WaitingKind.readyToParse);
      expect(parseCount(items, _t0), 1);
      expect(bridge.isHeld(heldIdFor(2)), isFalse);
      expect(bridge.isHeld(heldIdFor(1)), isTrue);
    });

    test('a real failed transaction message (unreadable) still shows', () async {
      bridge.hold(heldIdFor(3), 'ZZZ9Y8X7W6 Confirmed. something odd about Ksh 77', _t0.subtract(const Duration(minutes: 3)));
      bridge.hold(heldIdFor(4), kInventedRecharge, _t0.subtract(const Duration(minutes: 2)));
      await repo.ingest();
      final items = await repo.watch().first;
      expect(items.map((i) => i.kind), [WaitingKind.unreadable]);
      expect(items.single.id, heldIdFor(3));
    });

    test('parse on a recharge notice id changes nothing visible (gone, no row)', () async {
      bridge.hold(heldIdFor(5), kInventedRecharge, _t0);
      expect(await repo.parse(heldIdFor(5)), ParseOutcome.gone);
      expect(await repo.watch().first, isEmpty);
    });
  });
}
