// §AUTOREAD.AIRTIME_AUTO (0.2.0 S6, J2): Airtime recorded without the Categorize
// tap, behind one preference that is OFF by default. Invented messages only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/airtime_trail_store.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/levels/airtime_switches.dart';
import 'package:mmogo/autoread/ui/auto_recorded_row.dart';
import 'package:mmogo/data/backup/backup_setting_keys.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/fake_trail_prefs.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;

final _t0 = DateTime(2026, 11, 3, 14, 5);

void main() {
  late Database db;
  late FakeAutoReadBridge bridge;
  late RealWaitingRepository repo;
  late bool prefValue;
  late List<bool> prefWrites;
  late int saved;

  setUp(() async {
    prefValue = false; // the shipped default
    prefWrites = [];
    saved = 0;
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
      onSaved: () => saved++,
      timer: (after, fire) => Timer(const Duration(days: 365), () {}),
      readAirtimeAuto: () async => prefValue,
      writeAirtimeAuto: (v) async {
        prefValue = v;
        prefWrites.add(v);
      },
      trailStore: AirtimeTrailStore(prefs: FakeTrailPrefs(), now: () => _t0), // the trail's own tests: airtime_trail_*_test.dart
    );
  });
  tearDown(() async {
    repo.dispose();
    await db.close();
  });

  Future<List<Map<String, Object?>>> live() =>
      db.query('transactions', where: 'deleted_at IS NULL');

  test('the pref key is not in the backup key table, so a backup can never turn it on', () {
    // The table is the only way a pref travels in a backup (backup_setting_keys.dart).
    expect(kBackupSettingSpecs.any((s) => s.prefsKey == kAirtimeAutoPrefKey || s.fileKey == kAirtimeAutoPrefKey),
        isFalse);
  });

  test('OFF (the default): an airtime message waits in To categorize, nothing is written', () async {
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    expect(airtimeOn(repo), isFalse);
    expect(await repo.parse(heldIdFor(1)), ParseOutcome.parsed);
    final items = await repo.watch().first;
    expect(items.single.kind, WaitingKind.waitingCategory);
    expect(isParsedAirtime(items.single), isTrue);
    expect(await live(), isEmpty);
    expect(repo.airtime.trail, isEmpty);
    expect(prefWrites, isEmpty);
  });

  test('ON: Parse records Airtime straight to the ledger; the bell and chip counts drop; trail has one entry', () async {
    prefValue = true;
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    expect(await repo.parse(heldIdFor(1)), ParseOutcome.parsed);
    final items = await repo.watch().first;
    expect(items, isEmpty);
    expect(parseCount(items, _t0), 0);
    expect(categorizeCount(items, _t0), 0);
    final rows = await live();
    expect(rows, hasLength(1));
    expect(rows.single['source_type'], 'AIRTIME');
    expect(rows.single['amount_cents'], 20000);
    expect(rows.single['raw_parse_source'], 'SMS_PARSE');
    expect(repo.airtime.trail, hasLength(1));
    expect(repo.airtime.trail.single.amountCents, 20000);
    expect(repo.airtime.trail.single.rowId, rows.single['id']);
    expect(saved, 1);
    expect(bridge.isHeld(heldIdFor(1)), isFalse);
  });

  test('ON records Airtime ONLY: a Send Money message still waits for its category', () async {
    prefValue = true;
    bridge.hold(heldIdFor(1), kSampleSendMoney, _t0.subtract(const Duration(minutes: 5)));
    bridge.hold(heldIdFor(2), kSamplePaybill, _t0.subtract(const Duration(minutes: 4)));
    bridge.hold(heldIdFor(3), kSampleAirtime, _t0.subtract(const Duration(minutes: 3)));
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2), heldIdFor(3)]);
    final items = await repo.watch().first;
    expect(items, hasLength(2));
    expect(items.every((i) => i.kind == WaitingKind.waitingCategory && !isParsedAirtime(i)), isTrue);
    final rows = await live();
    expect(rows.map((r) => r['source_type']), ['AIRTIME']);
  });

  test('switching ON records the Airtime items that already wait and saves the choice', () async {
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    bridge.hold(heldIdFor(2), kSampleSendMoney, _t0.subtract(const Duration(minutes: 4)));
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    expect(await live(), isEmpty);
    await repo.setAirtimeAuto(true);
    expect(prefWrites, [true]);
    expect(repo.airtime.on, isTrue);
    expect((await live()).map((r) => r['source_type']), ['AIRTIME']);
    final items = await repo.watch().first;
    expect(items, hasLength(1)); // the Send Money one
    expect(items.single.parsed!.code, isNot(contains('PT8N4W7Q2K')));
  });

  test('switching back OFF: the next airtime message waits again', () async {
    prefValue = true;
    await repo.ingest();
    await repo.setAirtimeAuto(false);
    expect(prefWrites, [false]);
    bridge.hold(heldIdFor(1), kSampleAirtimeOther, _t0.subtract(const Duration(minutes: 2)));
    await repo.ingest();
    await repo.parse(heldIdFor(1));
    expect((await repo.watch().first).single.kind, WaitingKind.waitingCategory);
    expect(await live(), isEmpty);
  });

  test('Undo moves the entry to Recently deleted: it leaves the totals, a second Undo changes nothing', () async {
    prefValue = true;
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    await repo.parse(heldIdFor(1));
    final e = repo.airtime.trail.single;
    expect(await live(), hasLength(1));
    await repo.undoAutoRecord(e);
    expect(repo.airtime.trail.single.inRecentlyDeleted, isTrue);
    expect(await live(), isEmpty);
    final all = await db.query('transactions');
    expect(all.single['deleted_at'], isNotNull); // restorable: the row is still there
    final savedBefore = saved;
    await repo.undoAutoRecord(e);
    expect(saved, savedBefore);
    // Restore (the existing Recently deleted action) brings it back.
    await db.update('transactions', {'deleted_at': null}, where: 'id = ?', whereArgs: [e.rowId]);
    expect(await live(), hasLength(1));
  });

  test('Undo of a row that is gone (purged or wiped) changes nothing and the entry is hidden', () async {
    prefValue = true;
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    await repo.parse(heldIdFor(1));
    final e = repo.airtime.trail.single;
    await db.delete('transactions');
    await repo.undoAutoRecord(e);
    expect(repo.airtime.trail, isEmpty);
  });

  test('the same airtime code arriving twice makes one entry and one trail row', () async {
    prefValue = true;
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    bridge.hold(heldIdFor(2), kSampleAirtime, _t0.subtract(const Duration(minutes: 4)));
    await repo.ingest();
    await repo.parseAll([heldIdFor(1), heldIdFor(2)]);
    expect(await live(), hasLength(1));
    expect(repo.airtime.trail, hasLength(1));
  });

  test('an extra category in the Airtime group does not stop auto-record: the kind picks its own built-in', () async {
    // Row 17: the category is found by seed key, not by "the only active one".
    final group = (await db.query('classification_groups', where: 'code = ?', whereArgs: ['AIRTIME'])).single['id'];
    await db.insert('classifications', {
      'group_id': group,
      'name': 'Data bundles',
      'active': 1,
      'created_at': 1,
    });
    prefValue = true;
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    await repo.parse(heldIdFor(1));
    final rows = await live();
    expect(rows, hasLength(1));
    final cls = (await db.query('classifications', where: 'id = ?', whereArgs: [rows.single['classification_id']])).single;
    expect(cls['seed_key'], 'AIRTIME:airtime');
    expect(repo.airtime.trail, hasLength(1));
  });

  test('clearTrail (Delete data) empties the in-memory trail', () async {
    prefValue = true;
    bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    await repo.parse(heldIdFor(1));
    repo.airtime.clearTrail();
    expect(repo.airtime.trail, isEmpty);
  });

  group('widgets', () {
    Widget host(Widget child) => AppPaletteScope(
          controller: AppPaletteController('ocean', 'light'),
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
        );

    testWidgets('Settings tab switch: a tap flips the preference through the controller', (t) async {
      t.view.physicalSize = const Size(390, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final writes = <bool>[];
      late AirtimeAutoController c;
      c = AirtimeAutoController(
        onSwitch: (v) async {
          writes.add(v);
          c.setOn(v);
        },
        onUndo: (_) async {},
      );
      await t.pumpWidget(AppPaletteScope(
        controller: AppPaletteController('ocean', 'light'),
        child: MaterialApp(home: Scaffold(body: AirtimeSwitches(controller: c))),
      ));
      await t.tap(find.byKey(const Key('autoRecordMyself')));
      await t.pumpAndSettle();
      expect(writes, [true]);
      expect(c.on, isTrue);
      expect(find.textContaining('can be undone'), findsNothing); // the rules text lives in the "?" sheet
    });

    testWidgets('trail row: Undo fires; an undone row has no Undo and says where it went', (t) async {
      final e = AutoRecorded(rowId: 7, amountCents: 10000, at: _t0);
      var undos = 0;
      await t.pumpWidget(host(AutoRecordedRow(entry: e, now: _t0, onUndo: () => undos++)));
      expect(find.text('Airtime for myself, Ksh 100'), findsOneWidget);
      expect(find.textContaining('counted in your totals'), findsOneWidget);
      await t.tap(find.text('Undo'));
      expect(undos, 1);
      final gone = AutoRecorded(rowId: 7, amountCents: 10000, at: _t0, inRecentlyDeleted: true);
      await t.pumpWidget(host(AutoRecordedRow(entry: gone, now: _t0, onUndo: () => undos++)));
      expect(find.text('Undo'), findsNothing);
      expect(find.text(kAutoRecordedUndone), findsOneWidget);
    });
  });
}

bool airtimeOn(RealWaitingRepository r) => r.airtime.on;
