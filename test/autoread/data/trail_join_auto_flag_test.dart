// 0.2.2 item 2 U-RECENT-TAG (F-5, R4.17b): joinTrail reads `transactions.recorded_automatically` into
// AutoRecorded.recordedAutomatically (1 -> true, 0 -> false). Real schema, in-memory ledger, invented rows.
//
// ignore_for_file: depend_on_referenced_packages
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/airtime_trail_join.dart';
import 'package:mmogo/autoread/data/airtime_trail_store.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/domain/airtime/airtime_kind.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _t0 = DateTime(2026, 11, 26, 9);

void main() {
  late Database db;

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
  });

  tearDown(() async => db.close());

  Future<int> seedId(String seed) async =>
      (await db.query('classifications', columns: ['id'], where: 'seed_key = ?', whereArgs: [seed])).single['id']!
          as int;

  var n = 0;
  Future<int> addRow({required String type, required int auto}) async => db.insert('transactions', {
        'display_code': 'TAG${n++}',
        'source_type': type,
        'amount_cents': 45000,
        'transaction_cost_cents': 0,
        'counterparty_label': type == 'SEND_MONEY' ? 'ALICE INVENTED' : null,
        'counterparty_phone': type == 'SEND_MONEY' ? '0700000000' : null,
        'classification_id': await seedId(type == 'SEND_MONEY' ? 'SEND_MONEY:family_friends' : kAirtimeSeedMyself),
        'raw_parse_source': 'SMS_PARSE',
        'transaction_occurred_at': _t0.millisecondsSinceEpoch,
        'created_at': _t0.millisecondsSinceEpoch,
        'recorded_automatically': auto,
      });

  test('the join maps recorded_automatically: no-tap person 1 -> true, Yes/Parse 0 -> false, airtime 1 -> true',
      () async {
    final noTap = await addRow(type: 'SEND_MONEY', auto: 1);
    final yes = await addRow(type: 'SEND_MONEY', auto: 0);
    final air = await addRow(type: 'AIRTIME', auto: 1);
    final shown = await joinTrail(db, [TrailEntry(noTap, _t0), TrailEntry(yes, _t0), TrailEntry(air, _t0)]);
    final byId = {for (final s in shown) s.rowId: s};
    expect(byId[noTap]!.recordedAutomatically, isTrue);
    expect(byId[noTap]!.partyLabel, 'ALICE INVENTED');
    expect(byId[yes]!.recordedAutomatically, isFalse);
    expect(byId[air]!.recordedAutomatically, isTrue);
    expect(byId[air]!.partyLabel, isNull); // airtime: the row draws no tag
  });

  test('a row marked later (markRecordedAutomatically path) reads true on the next join', () async {
    final id = await addRow(type: 'SEND_MONEY', auto: 0);
    expect((await joinTrail(db, [TrailEntry(id, _t0)])).single.recordedAutomatically, isFalse);
    await db.update('transactions', {'recorded_automatically': 1}, where: 'id = ?', whereArgs: [id]);
    expect((await joinTrail(db, [TrailEntry(id, _t0)])).single.recordedAutomatically, isTrue);
  });
}
