// Wiring 8: an airtime message recorded on its own (the 0.2.0 switch) is marked "Recorded automatically"
// (recorded_automatically = 1); a row saved by a tap is not. Invented messages only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/airtime_trail_store.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/fake_trail_prefs.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;
import 'wiring_db.dart';

final _t0 = DateTime(2026, 11, 19, 14, 5);

void main() {
  late Database db;
  late FakeAutoReadBridge bridge;
  late RealWaitingRepository repo;
  late bool airtimeOn;

  setUp(() async {
    airtimeOn = true;
    db = await openWiringDb();
    bridge = FakeAutoReadBridge(now: () => _t0);
    final store = InMemoryPendingStore();
    repo = RealWaitingRepository(
      bridge: bridge,
      store: store,
      service: AutoReadService(bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
      database: () async => db,
      now: () => _t0,
      captureIdentity: () async => true,
      timer: (after, fire) => Timer(const Duration(days: 365), () {}),
      readAirtimeAuto: () async => airtimeOn,
      writeAirtimeAuto: (v) async => airtimeOn = v,
      trailStore: AirtimeTrailStore(prefs: FakeTrailPrefs(), now: () => _t0),
    );
  });
  tearDown(() async {
    repo.dispose();
    await db.close();
  });

  test('an airtime message recorded on its own is marked, and the history filter finds it', () async {
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    await repo.parse(heldIdFor(1));
    final rows = await db.query('transactions');
    expect(rows.single['source_type'], 'AIRTIME');
    expect(rows.single['recorded_automatically'], 1);
    final filtered = await AnalyticsDao.recordedAutomatically(db);
    expect(filtered.map((r) => r.id), [rows.single['id']]);
  });

  test('with the switch OFF a tap-saved airtime row is not marked', () async {
    airtimeOn = false;
    bridge.hold(heldIdFor(2), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    await repo.parse(heldIdFor(2));
    final air = (await categoriesOf(db, 'AIRTIME')).first;
    await repo.saveCategory(heldIdFor(2), '$air');
    final rows = await db.query('transactions');
    expect(rows.single['recorded_automatically'], 0);
    expect(await AnalyticsDao.recordedAutomatically(db), isEmpty);
  });

  test('the database itself refuses the marker on a Cash row (the repository swallows that refusal)', () async {
    final cashGroup = await categoriesOf(db, 'CASH_USE');
    final cashCat = cashGroup.isNotEmpty ? cashGroup.first : (await categoriesOf(db, 'SEND_MONEY')).first;
    final id = await db.insert('transactions', {
      'display_code': 'CASH-20261119-1000',
      'source_type': 'CASH',
      'amount_cents': 100,
      'classification_id': cashCat,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': 1,
      'created_at': 1,
    });
    await expectLater(
        db.update('transactions', {'recorded_automatically': 1}, where: 'id = ?', whereArgs: [id]), throwsA(isA<DatabaseException>()));
  });
}
