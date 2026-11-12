// WBS row 4 (PM follow-up): parsed airtime whose own switch is ON is left out of the
// Notifications list, the bell number, the chips and the spoken bell text, all from
// one list. Switch OFF keeps it. Invented messages only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/bell_spoken.dart';
import 'package:mmogo/autoread/ui/waiting_bell_numbers.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/domain/airtime/airtime_kind.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;

final _t0 = DateTime(2026, 11, 3, 14, 5);

WaitingItem _stored(int n, SmsSourceType type, {bool other = false}) => WaitingItem(
      id: heldIdFor(n),
      kind: WaitingKind.waitingCategory,
      heldAt: _t0,
      parsed: ParsedSmsFields(
        code: 'CODE$n',
        sourceType: type,
        amountCents: 1000,
        transactionCostCents: 0,
        counterpartyLabel: null,
        counterpartyPhone: null,
        paybillAccountNumber: null,
        transactionOccurredAt: _t0.millisecondsSinceEpoch,
        airtimeOther: other,
      ),
    );

bool _isMine(WaitingItem i) => i.parsed!.sourceType == SmsSourceType.airtime && !i.parsed!.airtimeOther;
bool _isTheirs(WaitingItem i) => i.parsed!.sourceType == SmsSourceType.airtime && i.parsed!.airtimeOther;

void main() {
  group('visibleWaiting (the one rule behind the list and every number)', () {
    final mine = _stored(1, SmsSourceType.airtime);
    final theirs = _stored(2, SmsSourceType.airtime, other: true);
    final send = _stored(3, SmsSourceType.sendMoney);
    final all = [mine, theirs, send];

    List<WaitingItem> v({bool m = false, bool o = false, Set<String> stuck = const {}}) =>
        visibleWaiting(all, myselfOn: m, otherOn: o, stuckIds: stuck);

    test('both switches OFF: every row stays', () => expect(v(), all));
    test('For myself ON: only my airtime leaves', () => expect(v(m: true), [theirs, send]));
    test('For another number ON: only that kind leaves', () => expect(v(o: true), [mine, send]));
    test('both ON: only the non-airtime row stays', () => expect(v(m: true, o: true), [send]));
    test('rows and count come from the same rule', () {
      for (final m in [false, true]) {
        for (final o in [false, true]) {
          expect(v(m: m, o: o).length, waitingCategoryCount(all, myselfOn: m, otherOn: o));
        }
      }
    });
    test('an item the app could not add stays visible', () {
      expect(v(m: true, o: true, stuck: {mine.id}), [mine, send]);
    });
  });

  group('the real repository: list, bell number, spoken text', () {
    late Database db;
    late FakeAutoReadBridge bridge;
    late InMemoryPendingStore store;
    late RealWaitingRepository repo;
    var myself = false;
    var other = false;

    setUp(() async {
      myself = false;
      other = false;
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
      bridge = FakeAutoReadBridge(now: () => _t0);
      store = InMemoryPendingStore();
      repo = RealWaitingRepository(
        bridge: bridge,
        store: store,
        service: AutoReadService(
            bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
        database: () async => db,
        now: () => _t0,
        captureIdentity: () async => true,
        timer: (after, fire) => Timer(const Duration(days: 365), () {}),
        readAirtimeAuto: () async => myself,
        writeAirtimeAuto: (v) async => myself = v,
        readAirtimeAutoOther: () async => other,
        writeAirtimeAutoOther: (v) async => other = v,
      );
    });
    tearDown(() async {
      repo.dispose();
      await db.close();
    });

    Future<({List<WaitingItem> rows, int bell, int diamond, String spoken})> look() async {
      final rows = await repo.watch().first;
      final n = await waitingBellNumbers(repo, () => _t0).first;
      return (
        rows: rows,
        bell: n.waiting,
        diamond: n.readyToParse,
        spoken: bellSpokenLabelAutoRead(
            update: false, newNotice: false, readyToParse: n.readyToParse, waiting: n.waiting),
      );
    }

    Future<void> parseThree() async {
      bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
      bridge.hold(heldIdFor(2), kSampleAirtimeOtherReal, _t0.subtract(const Duration(minutes: 4)));
      bridge.hold(heldIdFor(3), kSampleSendMoney, _t0.subtract(const Duration(minutes: 3)));
      await repo.ingest();
      await repo.parseAll([heldIdFor(1), heldIdFor(2), heldIdFor(3)]);
    }

    test('both OFF: three rows, bell 3, the spoken text says 3 messages', () async {
      await parseThree();
      final s = await look();
      expect(s.rows, hasLength(3));
      expect(s.bell, 3);
      expect(s.spoken, 'Notifications, 3 messages waiting for a category');
      expect(categorizeCount(s.rows, _t0), s.bell);
    });

    test('flipping For myself ON updates rows, bell and spoken text together', () async {
      await parseThree();
      await repo.setAirtimeAuto(true);
      final s = await look();
      expect(s.rows.where(_isMine), isEmpty);
      expect(s.rows.where(_isTheirs), hasLength(1));
      expect(s.rows, hasLength(2));
      expect(s.bell, 2);
      expect(s.spoken, 'Notifications, 2 messages waiting for a category');
    });

    test('flipping For another number ON: the reverse', () async {
      await parseThree();
      await repo.setAirtimeAutoOther(true);
      final s = await look();
      expect(s.rows.where(_isTheirs), isEmpty);
      expect(s.rows.where(_isMine), hasLength(1));
      expect(s.bell, 2);
    });

    test('both ON: one row, bell 1 (singular spoken); one switch back OFF: the next airtime shows', () async {
      myself = true;
      other = true;
      await parseThree();
      var s = await look();
      expect(s.rows, hasLength(1));
      expect(s.bell, 1);
      expect(s.spoken, 'Notifications, 1 message waiting for a category');
      await repo.setAirtimeAuto(false);
      bridge.hold(heldIdFor(4), kSampleAirtimeOther, _t0.subtract(const Duration(minutes: 2)));
      await repo.ingest();
      await repo.parse(heldIdFor(4));
      s = await look();
      expect(s.rows, hasLength(2));
      expect(s.bell, 2);
    });

    test('ON but the airtime category is missing: the item is NOT hidden (it could not be added)', () async {
      await db.update('classifications', {'active': 0}, where: 'seed_key = ?', whereArgs: [airtimeSeedKey(false)]);
      myself = true;
      bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
      await repo.ingest();
      await repo.parse(heldIdFor(1));
      final s = await look();
      expect(s.rows, hasLength(1));
      expect(s.bell, 1);
    });

    test('a stored airtime item the app has not added yet is left out of rows, bell and spoken text', () async {
      myself = true;
      bridge.hold(heldIdFor(9), 'Lunch at one? Bring the notes.', _t0.subtract(const Duration(minutes: 1)));
      await repo.ingest();
      // The headless Parse stored these while the app was closed; a plain publish (an unreadable
      // message parsed) happens before the app adds anything.
      await store.put(_stored(1, SmsSourceType.airtime), generation: 1);
      await store.put(_stored(2, SmsSourceType.airtime, other: true), generation: 1);
      await repo.parse(heldIdFor(9));
      final s = await look();
      expect(s.rows.where((r) => r.kind == WaitingKind.waitingCategory).map((r) => r.id), [heldIdFor(2)],
          reason: 'my airtime (switch ON) is hidden, the other kind (switch OFF) shows');
      expect(s.bell, 1);
      expect(s.spoken, contains('1 message waiting for a category'));
    });

    test('the ready-to-parse (diamond) count is not touched by the switches', () async {
      myself = true;
      other = true;
      bridge.hold(heldIdFor(1), kSampleSendMoney, _t0.subtract(const Duration(minutes: 5)));
      bridge.hold(heldIdFor(2), kSampleAirtime, _t0.subtract(const Duration(minutes: 4)));
      await repo.ingest();
      final s = await look();
      expect(s.diamond, 2);
      expect(s.bell, 0);
    });
  });
}
