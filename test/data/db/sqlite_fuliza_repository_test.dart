// 0.2.0 S12 slice A: SqliteFulizaRepository over a real v4 database. Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/sqlite_fuliza_repository.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/restore_test_db.dart' show addTx, seedId;

FulizaEvent _e(FulizaEventKind k, String code, int atMs,
        {int amount = 100000, int fee = 0, int? total}) =>
    FulizaEvent(
        kind: k,
        code: code,
        at: DateTime.fromMillisecondsSinceEpoch(atMs),
        amountCents: amount,
        feeCents: fee,
        printedTotalCents: total);

void main() {
  setUpAll(sqfliteFfiInit);
  late Database db;
  late SqliteFulizaRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openMmogoDatabase(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    repo = SqliteFulizaRepository(db, prefs: SharedPreferences.getInstance);
  });
  tearDown(() => db.close());

  test('add events and read them back, every field kept', () async {
    expect(await repo.events(), isEmpty);
    expect(
        await repo.addEvent(
            _e(FulizaEventKind.draw, 'FUL1', 1000, amount: 50000, fee: 500, total: 50500)),
        isTrue);
    expect(await repo.addEvent(_e(FulizaEventKind.repayFull, 'REP1', 2000, amount: 50500)), isTrue);
    final list = await repo.events();
    expect(list, hasLength(2));
    final d = list.first;
    expect(d.kind, FulizaEventKind.draw);
    expect(d.code, 'FUL1');
    expect(d.at, DateTime.fromMillisecondsSinceEpoch(1000));
    expect([d.amountCents, d.feeCents, d.printedTotalCents], [50000, 500, 50500]);
    expect(list.last.printedTotalCents, isNull);
    expect(list.last.feeCents, 0);
  });

  test('events come back in time order, then id', () async {
    await repo.addEvent(_e(FulizaEventKind.draw, 'C3', 3000));
    await repo.addEvent(_e(FulizaEventKind.draw, 'C1', 1000));
    await repo.addEvent(_e(FulizaEventKind.draw, 'C2a', 2000));
    await repo.addEvent(_e(FulizaEventKind.repayPartial, 'C2b', 2000));
    expect([for (final e in await repo.events()) e.code], ['C1', 'C2a', 'C2b', 'C3']);
  });

  test('a duplicate (kind, code) returns false, throws nothing, stores one row', () async {
    expect(await repo.addEvent(_e(FulizaEventKind.draw, 'DUP1', 1000)), isTrue);
    expect(await repo.addEvent(_e(FulizaEventKind.draw, 'DUP1', 9999, amount: 7)), isFalse);
    expect(await repo.events(), hasLength(1));
    expect((await repo.events()).single.amountCents, 100000, reason: 'the first one is kept');
    // Same code, other kind: a different message.
    expect(await repo.addEvent(_e(FulizaEventKind.repayFull, 'DUP1', 2000)), isTrue);
  });

  test('every kind round trips', () async {
    for (final k in FulizaEventKind.values) {
      expect(await repo.addEvent(_e(k, 'K_${k.name}', 1000)), isTrue);
    }
    expect({for (final e in await repo.events()) e.kind}, FulizaEventKind.values.toSet());
  });

  test('a bad figure is a real error, not a quiet false', () async {
    await expectLater(repo.addEvent(_e(FulizaEventKind.draw, 'BAD1', 1000, amount: 0)),
        throwsA(isA<DatabaseException>()));
    expect(await repo.events(), isEmpty);
  });

  test('limit: null at first, set, read back, replaced; stored under fuliza_limit_cents', () async {
    expect(await repo.limitCents(), isNull);
    await repo.setLimitCents(5000000);
    expect(await repo.limitCents(), 5000000);
    await repo.setLimitCents(4200000);
    expect(await repo.limitCents(), 4200000);
    expect(SqliteFulizaRepository.limitPrefsKey, 'fuliza_limit_cents');
    expect((await SharedPreferences.getInstance()).getInt('fuliza_limit_cents'), 4200000);
  });

  test('payment codes: live ordinary transactions only (display_code), not soft-deleted', () async {
    expect(await repo.paymentCodes(), isEmpty);
    final cls = await seedId(db, 'SEND_MONEY:rent');
    await addTx(db,
        code: 'PAY0000001', source: 'SEND_MONEY', classId: cls, label: 'T', phone: '0700000001');
    await addTx(db,
        code: 'PAY0000002', source: 'SEND_MONEY', classId: cls, label: 'T', phone: '0700000002');
    await db.update('transactions', {'deleted_at': 1790000000001},
        where: "display_code = 'PAY0000002'");
    expect(await repo.paymentCodes(), {'PAY0000001'});
  });
}
