// 0.2.2 S-C (F10, contract 6e): a suggested-chip record and an Ask first Yes appear in the
// "Recorded automatically" list (the 24 h trail), with Undo; no schema change, no column flag.
// Real waiting repository over an in-memory ledger. Invented messages only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;

final _t0 = DateTime(2026, 11, 24, 8);

void main() {
  late Database db;
  late RealWaitingRepository repo;
  late FakeAutoReadBridge bridge;

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
      service: AutoReadService(bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
      database: () async => db,
      now: () => _t0,
      captureIdentity: () async => true,
      onSaved: () {},
      timer: (a, f) => Timer(const Duration(days: 365), () {}),
    );
  });
  tearDown(() async {
    repo.dispose();
    await db.close();
  });

  Future<int> transport() async => (await db.rawQuery(
          "SELECT c.id FROM classifications c JOIN classification_groups g ON g.id = c.group_id "
          "WHERE c.name = 'Transport' AND g.code = 'SEND_MONEY' AND c.active = 1"))
      .first['id'] as int;

  Future<void> parsed() async {
    bridge.hold(heldIdFor(1), kSampleSendMoney, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    await repo.parse(heldIdFor(1));
  }

  test('a chip record is listed with person, category and Undo; the column flag stays 0', () async {
    await parsed();
    final cls = await transport();
    final r = await repo.recordChip(heldIdFor(1), '$cls');
    final list = repo.airtime.trailNewestFirst;
    expect(list, hasLength(1));
    expect(list.single.rowId, r.rowId);
    expect(list.single.categoryName, 'Transport');
    expect(list.single.partyLabel, isNotEmpty);
    expect(list.single.airtimeOther, isFalse);
    expect(list.single.inRecentlyDeleted, isFalse);
    expect((await db.query('transactions')).single['recorded_automatically'], 0);
    await repo.undoAutoRecord(list.single);
    expect(repo.airtime.trailNewestFirst.single.inRecentlyDeleted, isTrue);
  });

  test('Undo from the pill (undoChipRecord) updates the Recorded automatically list at once; a second Undo changes nothing', () async {
    await parsed();
    final cls = await transport();
    final r = await repo.recordChip(heldIdFor(1), '$cls');
    expect(repo.airtime.trailNewestFirst.single.inRecentlyDeleted, isFalse);
    await repo.undoChipRecord(r.rowId!);
    expect(repo.airtime.trailNewestFirst.single.inRecentlyDeleted, isTrue);
    await repo.undoChipRecord(r.rowId!);
    expect(repo.airtime.trailNewestFirst.single.inRecentlyDeleted, isTrue);
  });

  test('an Ask first Yes (saveCategoryListed) is listed the same way', () async {
    await parsed();
    final cls = await transport();
    await repo.saveCategoryListed(heldIdFor(1), '$cls');
    expect(repo.airtime.trailNewestFirst.single.categoryName, 'Transport');
  });

  test('a plain Categorize save is NOT listed; a refused inactive chip lists nothing', () async {
    await parsed();
    final cls = await transport();
    await db.rawUpdate('UPDATE classifications SET active = 0 WHERE id = ?', [cls]);
    expect((await repo.recordChip(heldIdFor(1), '$cls')).active, isFalse);
    expect(repo.airtime.trailNewestFirst, isEmpty);
    await db.rawUpdate('UPDATE classifications SET active = 1 WHERE id = ?', [cls]);
    await repo.saveCategory(heldIdFor(1), '$cls');
    expect(repo.airtime.trailNewestFirst, isEmpty);
  });
}
