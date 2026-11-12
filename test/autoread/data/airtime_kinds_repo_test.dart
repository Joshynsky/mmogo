// WBS row 17: Categorize and auto-record file an airtime item into the category
// of its own kind only. Invented messages and numbers only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/data/backup/backup_setting_keys.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/domain/airtime/airtime_kind.dart';
import 'package:mmogo/ui/screens/add/add_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;

final _t0 = DateTime(2026, 11, 12, 14, 5);

void main() {
  late Database db;
  late FakeAutoReadBridge bridge;
  late InMemoryPendingStore store;
  late RealWaitingRepository repo;
  late bool myselfPref;
  late bool otherPref;

  RealWaitingRepository build({bool seams = true}) => RealWaitingRepository(
        bridge: bridge,
        store: store,
        service: AutoReadService(
            bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
        database: () async => db,
        now: () => _t0,
        captureIdentity: () async => true,
        timer: (after, fire) => Timer(const Duration(days: 365), () {}),
        readAirtimeAuto: seams ? () async => myselfPref : null,
        writeAirtimeAuto: seams ? (v) async => myselfPref = v : null,
        readAirtimeAutoOther: seams ? () async => otherPref : null,
        writeAirtimeAutoOther: seams ? (v) async => otherPref = v : null,
      );

  setUp(() async {
    myselfPref = false;
    otherPref = false;
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
    bridge = FakeAutoReadBridge(now: () => _t0);
    store = InMemoryPendingStore();
    repo = build();
  });
  tearDown(() async {
    repo.dispose();
    await db.close();
  });

  Future<int> idOf(String key) async =>
      (await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [key])).first['id']! as int;

  Future<List<Map<String, Object?>>> live() => db.query('transactions', where: 'deleted_at IS NULL');

  Future<void> holdOwn(int n) async =>
      bridge.hold(heldIdFor(n), kSampleAirtime, _t0.subtract(Duration(minutes: 10 - n)));
  Future<void> holdOther(int n) async =>
      bridge.hold(heldIdFor(n), kSampleAirtimeOtherReal, _t0.subtract(Duration(minutes: 10 - n)));

  Future<WaitingItem> parsed(int n) async {
    await repo.ingest();
    await repo.parse(heldIdFor(n));
    return (await repo.watch().first).firstWhere((i) => i.id == heldIdFor(n));
  }

  test('categorize_sheet_offers_only_myself_for_own_item', () async {
    await holdOwn(1);
    final item = await parsed(1);
    expect(item.parsed!.airtimeOther, isFalse);
    final cats = await (await repo.categoryChoicesFor(item)).categories();
    expect(cats.map((c) => c.name), [kAirtimeNameMyself]);
    expect(cats.single.id, '${await idOf(kAirtimeSeedMyself)}');
    await expectLater((await repo.categoryChoicesFor(item)).create('Data'), throwsA(isA<StateError>()));
  });

  test('categorize_sheet_offers_only_other_for_other_item', () async {
    await holdOther(1);
    final item = await parsed(1);
    expect(item.parsed!.airtimeOther, isTrue);
    final cats = await (await repo.categoryChoicesFor(item)).categories();
    expect(cats.map((c) => c.name), [kAirtimeNameOther]);
    expect(cats.single.id, '${await idOf(kAirtimeSeedOther)}');
    await expectLater((await repo.categoryChoicesFor(item)).create('Data'), throwsA(isA<StateError>()));
  });

  test('categorize saves each kind into its own category', () async {
    await holdOwn(1);
    await holdOther(2);
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    await repo.saveCategory(heldIdFor(1), '${await idOf(kAirtimeSeedMyself)}');
    await repo.saveCategory(heldIdFor(2), '${await idOf(kAirtimeSeedOther)}');
    final rows = await live();
    expect(rows, hasLength(2));
    final byCode = {for (final r in rows) r['display_code']: r['classification_id']};
    expect(byCode['PT8N4W7Q2K'], await idOf(kAirtimeSeedMyself));
    expect(byCode['AB1CD2EF3G'], await idOf(kAirtimeSeedOther));
  });

  test('categorize_stale_wrong_category_saves_nothing', () async {
    await holdOwn(1);
    await holdOther(2);
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    // A stale sheet: the own item with the other category, and the reverse.
    await repo.saveCategory(heldIdFor(1), '${await idOf(kAirtimeSeedOther)}');
    await repo.saveCategory(heldIdFor(2), '${await idOf(kAirtimeSeedMyself)}');
    // A category of another group for an airtime item.
    await repo.saveCategory(heldIdFor(1), '${await idOf('SEND_MONEY:rent')}');
    expect(await live(), isEmpty);
    final items = await repo.watch().first;
    expect(items.where((i) => i.kind == WaitingKind.waitingCategory), hasLength(2));
  });

  test('auto_record_myself_switch_on_other_item_waits', () async {
    myselfPref = true;
    await holdOther(1);
    await repo.ingest();
    await repo.parse(heldIdFor(1));
    expect(await live(), isEmpty);
    expect((await repo.watch().first).single.kind, WaitingKind.waitingCategory);
    expect(repo.airtime.trail, isEmpty);
  });

  test('auto_record_other_switch_on_own_item_waits', () async {
    otherPref = true;
    await holdOwn(1);
    await repo.ingest();
    await repo.parse(heldIdFor(1));
    expect(await live(), isEmpty);
    expect((await repo.watch().first).single.kind, WaitingKind.waitingCategory);
  });

  test('auto_record_each_kind_goes_to_its_own_category', () async {
    myselfPref = true;
    otherPref = true;
    await holdOwn(1);
    await holdOther(2);
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    final rows = await live();
    expect(rows, hasLength(2));
    final byCode = {for (final r in rows) r['display_code']: r['classification_id']};
    expect(byCode['PT8N4W7Q2K'], await idOf(kAirtimeSeedMyself));
    expect(byCode['AB1CD2EF3G'], await idOf(kAirtimeSeedOther));
    expect(repo.airtime.trail, hasLength(2));
    expect(await repo.watch().first, isEmpty);
  });

  test('turning the other switch on records only the waiting other-number items', () async {
    await holdOwn(1);
    await holdOther(2);
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    await repo.setAirtimeAutoOther(true);
    expect(otherPref, isTrue);
    expect(repo.airtime.onOther, isTrue);
    expect(repo.airtime.on, isFalse);
    final rows = await live();
    expect(rows.map((r) => r['classification_id']), [await idOf(kAirtimeSeedOther)]);
    expect((await repo.watch().first).single.parsed!.airtimeOther, isFalse);
  });

  test('auto_record_missing_category_records_nothing_no_fallback', () async {
    myselfPref = true;
    otherPref = true;
    // The other category is gone: an other-number item waits, never filed under For myself.
    await db.update('classifications', {'active': 0}, where: 'seed_key = ?', whereArgs: [kAirtimeSeedOther]);
    await holdOther(1);
    await holdOwn(2);
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    var rows = await live();
    expect(rows.map((r) => r['display_code']), ['PT8N4W7Q2K']); // only the own item
    expect((await repo.watch().first).single.parsed!.airtimeOther, isTrue);

    // And the reverse: no For myself category, an own item waits and is not filed under the other.
    await db.update('classifications', {'active': 1}, where: 'seed_key = ?', whereArgs: [kAirtimeSeedOther]);
    await db.update('classifications', {'active': 0}, where: 'seed_key = ?', whereArgs: [kAirtimeSeedMyself]);
    await db.delete('transactions');
    bridge.hold(heldIdFor(3), kSampleAirtime.replaceFirst('PT8N4W7Q2K', 'PT8N4W7Q3K'), _t0.subtract(const Duration(minutes: 1)));
    await repo.ingest();
    await repo.parse(heldIdFor(3));
    rows = await live();
    expect(rows.map((r) => r['display_code']), isNot(contains('PT8N4W7Q3K')));
    final myselfId = await idOf(kAirtimeSeedMyself);
    expect(rows.every((r) => r['classification_id'] != myselfId), isTrue);
  });

  test('auto_record_existing_pref_key_means_myself_only_other_default_off', () async {
    expect(kAirtimeAutoPrefKey, 'autoread_airtime_auto_record');
    expect(kAirtimeAutoOtherPrefKey, 'autoread_airtime_auto_record_other');
    expect(kAirtimeAutoOtherPrefKey, isNot(kAirtimeAutoPrefKey));
    for (final k in [kAirtimeAutoPrefKey, kAirtimeAutoOtherPrefKey]) {
      expect(kBackupSettingSpecs.any((s) => s.prefsKey == k || s.fileKey == k), isFalse);
    }
    // A user who opted in under the old key (real preference store, no seams).
    SharedPreferences.setMockInitialValues({kAirtimeAutoPrefKey: true});
    repo.dispose();
    repo = build(seams: false);
    await holdOwn(1);
    await holdOther(2);
    await repo.ingest();
    expect(repo.airtime.on, isTrue);
    expect(repo.airtime.onOther, isFalse);
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    final rows = await live();
    expect(rows.map((r) => r['display_code']), ['PT8N4W7Q2K']);
    // Switching the other kind on writes the NEW key only.
    await repo.setAirtimeAutoOther(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kAirtimeAutoOtherPrefKey), isTrue);
    expect(prefs.getBool(kAirtimeAutoPrefKey), isTrue);
  });

  test('isAutoRecordEligible follows the kind of the item', () async {
    await holdOwn(1);
    await holdOther(2);
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    final items = await repo.watch().first;
    final own = items.firstWhere((i) => !i.parsed!.airtimeOther);
    final oth = items.firstWhere((i) => i.parsed!.airtimeOther);
    expect(isAutoRecordEligible(own, myselfOn: true, otherOn: false), isTrue);
    expect(isAutoRecordEligible(own, myselfOn: false, otherOn: true), isFalse);
    expect(isAutoRecordEligible(oth, myselfOn: true, otherOn: false), isFalse);
    expect(isAutoRecordEligible(oth, myselfOn: false, otherOn: true), isTrue);
  });

  test('manual_add_airtime_files_into_for_myself', () async {
    expect(AddDraft.fixedSeedKey('AIRTIME'), kAirtimeSeedMyself);
    final row = await db.query('classifications', where: 'seed_key = ?', whereArgs: [AddDraft.fixedSeedKey('AIRTIME')]);
    expect(row.single['name'], kAirtimeNameMyself);
    expect(AddDraft.fixedSeedKey('AGENT_WITHDRAWAL'), 'AGENT_WITHDRAWAL:cash_withdrawal');
  });
}
