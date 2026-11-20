// the 24 h "Recorded automatically" list through the real waiting
// repository, a real in-memory ledger, fake or mock prefs and an injected clock.
// Invented messages and numbers only. Auto-read flavor.
//
// ignore_for_file: depend_on_referenced_packages
@Tags(['autoread'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/airtime_trail_join.dart';
import 'package:mmogo/autoread/data/airtime_trail_store.dart';
import 'package:mmogo/autoread/data/real_waiting_actions.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/auto_group.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart' show WaitingActions;
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/airtime/airtime_kind.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/fake_trail_prefs.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;
import '../logic/reading_fakes.dart';

final _t0 = DateTime(2026, 11, 13, 8);
const _h = Duration(hours: 1);
const _key = kAirtimeTrailPrefKey;

/// Everything one test needs, built by [_make].
class _Env {
  _Env(this.db, this.bridge, this.repo, this.prefs, this.saved, this.box);
  final _ClockBox box;
  bool closed = false;
  final Database db;
  final FakeAutoReadBridge bridge;
  final RealWaitingRepository repo;
  final FakeTrailPrefs prefs;
  final List<int> saved;
}

Future<Database> _openDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (d, v) async {
            await AppSchema.createSchema(d);
            await AppSchema.seed(d);
          }));
}

/// [trailPrefs] null = a fresh [FakeTrailPrefs]; pass [SharedTrailPrefs] to use the mock preferences.
Future<_Env> _make({TrailPrefs? trailPrefs, DateTime? start, bool myself = true, bool other = false}) async {
  final db = await _openDb();
  final clockBox = _ClockBox(start ?? _t0);
  final bridge = FakeAutoReadBridge(now: () => clockBox.now);
  final store = InMemoryPendingStore();
  final fake = trailPrefs is FakeTrailPrefs ? trailPrefs : FakeTrailPrefs();
  final saved = <int>[];
  final repo = RealWaitingRepository(
    bridge: bridge,
    store: store,
    service: AutoReadService(
        bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => clockBox.now),
    database: () async => db,
    now: () => clockBox.now,
    captureIdentity: () async => true,
    onSaved: () => saved.add(1),
    timer: (after, fire) => Timer(const Duration(days: 365), () {}),
    readAirtimeAuto: () async => myself,
    writeAirtimeAuto: (v) async => myself = v,
    readAirtimeAutoOther: () async => other,
    writeAirtimeAutoOther: (v) async => other = v,
    trailStore: AirtimeTrailStore(prefs: trailPrefs ?? fake, now: () => clockBox.now),
  );
  return _Env(db, bridge, repo, fake, saved, clockBox);
}

class _ClockBox {
  _ClockBox(this.now);
  DateTime now;
}

extension on _Env {
  DateTime get now => box.now;
  set now(DateTime v) => box.now = v;

  Future<void> close() async {
    if (closed) return;
    closed = true;
    repo.dispose();
    await db.close();
  }

  /// Holds [body] and runs Parse on it (the switch is already on).
  Future<void> parseOne(int n, String body) async {
    bridge.hold(heldIdFor(n), body, now.subtract(const Duration(minutes: 5)));
    await repo.ingest();
    await repo.parse(heldIdFor(n));
  }

  Future<int> idOfSeed(String seed) async =>
      (await db.query('classifications', columns: ['id'], where: 'seed_key = ?', whereArgs: [seed])).single['id']! as int;

  /// A ledger row for the join tests.
  Future<int> addRow({
    String type = 'AIRTIME',
    String source = 'SMS_PARSE',
    String seed = kAirtimeSeedMyself,
    int amount = 500,
    int? deletedAt,
    String? code,
  }) async =>
      db.insert('transactions', {
        'display_code': code ?? 'TST${DateTime.now().microsecondsSinceEpoch}',
        'source_type': type,
        'amount_cents': amount,
        'transaction_cost_cents': 0,
        'counterparty_label': type == 'SEND_MONEY' ? 'INVENTED' : null,
        'counterparty_phone': type == 'SEND_MONEY' ? '0700000000' : null,
        'classification_id': await idOfSeed(type == 'SEND_MONEY' ? 'SEND_MONEY:family_friends' : seed),
        'raw_parse_source': source,
        'transaction_occurred_at': _t0.millisecondsSinceEpoch,
        'created_at': _t0.millisecondsSinceEpoch,
        'deleted_at': deletedAt,
      });

  Future<void> store(int rowId, DateTime at) => AirtimeTrailStore(prefs: prefs, now: () => now).add(rowId, at);

  Object? stored() => prefs.map[_key] == null ? null : jsonDecode(prefs.map[_key]!);
}

void main() {
  late _Env e;

  Future<void> start({TrailPrefs? prefs}) async => e = await _make(trailPrefs: prefs);

  tearDown(() async => e.close());

  group('what is stored and shown', () {
    test('trail_stored_value_has_only_row_id_and_time (after a real record)', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      final rows = await e.db.query('transactions');
      expect(e.prefs.map.keys, [_key]);
      expect(e.stored(), [
        [rows.single['id'], _t0.millisecondsSinceEpoch],
      ]);
      expect(e.prefs.map[_key], isNot(contains('200')), reason: 'no amount');
      expect(e.repo.airtime.trail.single.amountCents, 20000, reason: 'the amount comes from the ledger row');
    });

    test('trail_survives_controller_rebuild: a new repository on the same prefs shows the entry', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      final again = RealWaitingRepository(
        bridge: e.bridge,
        store: InMemoryPendingStore(),
        service: AutoReadService(
            bridge: e.bridge,
            store: InMemoryPendingStore(),
            savedCodes: TransactionCodeLookup(() async => e.db),
            now: () => _t0),
        database: () async => e.db,
        now: () => e.now,
        timer: (a, f) => Timer(const Duration(days: 365), () {}),
        readAirtimeAuto: () async => true,
        writeAirtimeAuto: (_) async {},
        trailStore: AirtimeTrailStore(prefs: e.prefs, now: () => e.now),
      );
      expect(again.airtime.trail, isEmpty, reason: 'before the first look');
      await again.ingest();
      expect(again.airtime.trail.single.amountCents, 20000);
      expect(again.airtime.trail.single.inRecentlyDeleted, isFalse);
      again.dispose();
    });

    test('entry expires with the injected clock, also at the controller (the purge write may have failed)', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      e.now = _t0.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      expect(e.repo.airtime.trail, hasLength(1));
      e.now = _t0.add(_h * 24);
      expect(e.repo.airtime.trail, isEmpty, reason: 'filtered at display');
      expect(e.repo.airtime.trailNewestFirst, isEmpty);
      await e.repo.ingest();
      expect(e.prefs.map.containsKey(_key), isFalse, reason: 'purged from the store at the next look');
    });

    test('trail_hidden_when_row_missing', () async {
      await start();
      await e.store(999, _t0);
      await e.repo.ingest();
      expect(e.repo.airtime.trail, isEmpty);
    });

    test('trail_row_of_non_airtime_or_manual_not_shown', () async {
      await start();
      final good = await e.addRow();
      final manual = await e.addRow(source: 'MANUAL');
      final send = await e.addRow(type: 'SEND_MONEY');
      for (final id in [good, manual, send]) {
        await e.store(id, _t0);
      }
      await e.repo.ingest();
      expect(e.repo.airtime.trail.map((x) => x.rowId), [good]);
    });

    test('kind comes from the row: for another number shows as such', () async {
      await start();
      final a = await e.addRow(seed: kAirtimeSeedOther, amount: 700);
      await e.store(a, _t0);
      await e.repo.ingest();
      expect(e.repo.airtime.trail.single.airtimeOther, isTrue);
      expect(e.repo.airtime.trail.single.amountCents, 700);
    });

    test('trail_undone_row_shows_recently_deleted_footer (Undo, or deleted from Home)', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      await e.repo.undoAutoRecord(e.repo.airtime.trail.single);
      expect(e.repo.airtime.trail.single.inRecentlyDeleted, isTrue);
      expect(e.saved, isNotEmpty, reason: 'Home is told');
      final other = await e.addRow(deletedAt: _t0.millisecondsSinceEpoch);
      await e.store(other, _t0);
      await e.repo.ingest();
      expect(e.repo.airtime.trail.every((x) => x.inRecentlyDeleted), isTrue);
      expect(e.repo.airtime.trail, hasLength(2));
    });

    test('trail_restored_row_shows_counted_again', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      final entry = e.repo.airtime.trail.single;
      await e.repo.undoAutoRecord(entry);
      expect(e.repo.airtime.trail.single.inRecentlyDeleted, isTrue);
      await e.db.update('transactions', {'deleted_at': null}, where: 'id = ?', whereArgs: [entry.rowId]); // Restore
      await e.repo.ingest();
      expect(e.repo.airtime.trail.single.inRecentlyDeleted, isFalse);
    });

    test('second_undo_does_not_change_deleted_at', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      final entry = e.repo.airtime.trail.single;
      await e.repo.undoAutoRecord(entry);
      Future<Object?> deletedAt() async =>
          (await e.db.query('transactions', columns: ['deleted_at'])).single['deleted_at'];
      final first = await deletedAt();
      expect(first, isNotNull);
      await e.db.update('transactions', {'deleted_at': 1234}, where: 'id = ?', whereArgs: [entry.rowId]);
      final savedBefore = e.saved.length;
      await e.repo.undoAutoRecord(entry); // a stale card
      expect(await deletedAt(), 1234, reason: 'the 1 hour window is not moved');
      expect(e.saved.length, savedBefore);
    });

    test('undo_on_missing_row_changes_nothing_and_hides_entry', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      final entry = e.repo.airtime.trail.single;
      await e.db.delete('transactions');
      final savedBefore = e.saved.length;
      await e.repo.undoAutoRecord(entry);
      expect(await e.db.query('transactions'), isEmpty);
      expect(e.repo.airtime.trail, isEmpty, reason: 'hidden, no "could not undo" line');
      expect(e.saved.length, savedBefore);
    });

    test('trail_10000_entries_capped_and_bounded_query', () async {
      await start();
      final id = await e.addRow();
      final entries = [
        for (var i = 0; i < 10000; i++) TrailEntry(id + i, _t0.subtract(Duration(seconds: i))),
      ];
      final shown = await joinTrail(e.db, entries); // would throw past SQLite's variable limit if unbounded
      expect(shown.length, lessThanOrEqualTo(kTrailMaxEntries));
      expect(shown.single.rowId, id);
      e.prefs.map[_key] = jsonEncode([
        for (var i = 1; i <= 10000; i++) [i, _t0.subtract(Duration(seconds: i)).millisecondsSinceEpoch],
      ]);
      await e.repo.ingest();
      expect(e.repo.airtime.trail.length, lessThanOrEqualTo(kTrailMaxEntries));
    });

    test('a corrupt stored value is an empty trail, and Parse still records and rewrites it', () async {
      await start();
      e.prefs.map[_key] = '{"not":"a list"}';
      await e.repo.ingest();
      expect(e.repo.airtime.trail, isEmpty);
      await e.parseOne(1, kSampleAirtime);
      expect(e.repo.airtime.trail, hasLength(1));
      expect(e.stored(), isA<List>());
    });
  });

  group('recording', () {
    test('failed_prefs_write_does_not_fail_the_record', () async {
      await start();
      e.prefs.failWrite = true;
      await e.parseOne(1, kSampleAirtime);
      expect(await e.db.query('transactions'), hasLength(1), reason: 'the ledger row is there');
      expect(e.repo.airtime.recordedCount, 1);
      expect(e.repo.airtime.trail, hasLength(1), reason: 'still shown for this session');
      expect(e.prefs.map, isEmpty);
    });

    test('concurrent_adds_are_serialised_both_kept', () async {
      e = await _make(myself: false);
      e.bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
      e.bridge.hold(heldIdFor(2), kSampleAirtimeOtherReal, _t0.subtract(const Duration(minutes: 4)));
      await e.repo.ingest();
      await e.repo.parseAll([heldIdFor(1), heldIdFor(2)]);
      await Future.wait([e.repo.setAirtimeAuto(true), e.repo.setAirtimeAutoOther(true)]);
      final ids = (e.stored()! as List).map((p) => (p as List).first).toSet();
      expect(ids, hasLength(2));
      expect(e.repo.airtime.trail, hasLength(2));
      expect(e.repo.airtime.recordedCount, 2);
    });

    test('add_after_external_clear_does_not_resurrect_old_entries', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      e.prefs.map.remove(_key); // Delete data or Replace restore removed the stored list
      await e.parseOne(2, kSampleAirtimeOtherReal);
      await e.repo.setAirtimeAutoOther(true);
      expect((e.stored()! as List), hasLength(1), reason: 'only the new entry');
      expect(e.repo.airtime.trail, hasLength(1));
    });

    test('delete_data_removes_trail_key_and_in_memory_list (memory half: the refresh hook leaves nothing)', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      expect(e.repo.airtime.trail, hasLength(1));
      e.prefs.map.remove(_key); // the Delete data prefs step
      e.repo.airtime.clearTrail(); // main.dart's refresh hook, then ingest
      await e.repo.ingest();
      expect(e.repo.airtime.trail, isEmpty);
      expect(e.prefs.map.containsKey(_key), isFalse);
    });

    /// 200 real airtime rows on the trail (the cap), the newest a minute old.
    Future<void> fillCap() async {
      for (var i = 0; i < 200; i++) {
        final id = await e.addRow(code: 'CAP$i');
        await e.store(id, _t0.subtract(Duration(minutes: 1 + i)));
      }
    }

    test('trail_toast_still_shows_at_cap_and_when_purge_runs: the counter, not the list length, says "recorded"', () async {
      await start();
      await fillCap();
      await e.repo.ingest();
      expect(e.repo.airtime.trail, hasLength(200));
      await e.parseOne(1, kSampleAirtime);
      expect(e.repo.airtime.trail, hasLength(200), reason: 'the list did not grow: the old length test would miss this');
      expect(e.repo.airtime.recordedCount, 1);
      expect(e.repo.airtime.lastRecorded!.amountCents, 20000);
      expect((e.stored()! as List), hasLength(200), reason: 'capped; the oldest dropped');
      // Purge in the same run: the one shown entry expires while the new one is added.
      await e.close();
      await start();
      final old = await e.addRow(code: 'OLD1');
      await e.store(old, _t0.subtract(const Duration(hours: 23, minutes: 59, seconds: 59)));
      await e.repo.ingest();
      expect(e.repo.airtime.trail, hasLength(1));
      e.now = _t0.add(const Duration(seconds: 5));
      await e.parseOne(1, kSampleAirtime);
      expect(e.repo.airtime.trail, hasLength(1), reason: 'one in, one purged: no growth');
      expect(e.repo.airtime.trail.single.amountCents, 20000);
      expect(e.repo.airtime.recordedCount, 1);
    });

    testWidgets('the Recorded as Airtime toast shows when the list is at the cap', (t) async {
      late WaitingActions actions;
      late WaitingItem item;
      await t.runAsync(() async {
        await start();
        for (var i = 0; i < 200; i++) {
          final id = await e.addRow(code: 'CAP$i');
          await e.store(id, _t0.subtract(Duration(minutes: 1 + i)));
        }
        e.bridge.hold(heldIdFor(1), kSampleAirtime, _t0.subtract(const Duration(minutes: 5)));
        await e.repo.ingest();
        item = (await e.repo.watch().first).single;
      });
      await t.pumpWidget(MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Scaffold(
          body: Builder(builder: (c) {
            actions = buildRealWaitingActions(c, e.repo);
            return const SizedBox();
          }),
        ),
      ));
      await t.runAsync(() async {
        actions.onParse!(item); // returns at once; wait for the record
        for (var i = 0; i < 200 && e.repo.airtime.recordedCount == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Recorded as Airtime, Ksh 200.'), findsOneWidget);
      await t.runAsync(e.close);
    });
  });

  group('what leaves it alone', () {
    // The real preferences (mock), so the other operations act on the same store.
    Future<void> startReal() async {
      SharedPreferences.setMockInitialValues({});
      e = await _make(trailPrefs: SharedTrailPrefs());
    }

    Future<Object?> raw() async {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      return p.getString(_key);
    }

    test('read_off_keeps_trail', () async {
      await startReal();
      await e.parseOne(1, kSampleAirtime);
      final before = await raw();
      expect(before, isNotNull);
      final c = ReadingController(
          bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true),
          store: FakeGenerationStore(),
          prefs: FakeReadingPrefs());
      expect(await c.turnOff(), TurnOffResult.off);
      expect(await raw(), before);
      await e.repo.ingest();
      expect(e.repo.airtime.trail, hasLength(1));
    });

    test('forget_all_recipients_keeps_trail', () async {
      await startReal();
      await e.parseOne(1, kSampleAirtime);
      final before = await raw();
      final memory = RecipientMemory(prefs: SharedPreferences.getInstance, nowMs: () => 1790000000000);
      expect(await memory.forgetAll(), isTrue);
      expect(await raw(), before);
      await e.repo.ingest();
      expect(e.repo.airtime.trail, hasLength(1));
    });

    test('switch_off_keeps_trail', () async {
      await startReal();
      await e.parseOne(1, kSampleAirtime);
      final before = await raw();
      await e.repo.setAirtimeAuto(false);
      await e.repo.setAirtimeAutoOther(false);
      expect(await raw(), before);
      expect(e.repo.airtime.trail, hasLength(1));
      await e.repo.ingest();
      expect(e.repo.airtime.trail, hasLength(1));
    });

    test('undo keeps the entry (the footer changes, the stored list does not)', () async {
      await startReal();
      await e.parseOne(1, kSampleAirtime);
      final before = await raw();
      await e.repo.undoAutoRecord(e.repo.airtime.trail.single);
      expect(await raw(), before);
    });
  });

  group('J2 rules and JN1 still hold', () {
    test('trail_not_counted_in_bell_or_chips', () async {
      await start();
      await e.parseOne(1, kSampleAirtime);
      expect(e.repo.airtime.trail, hasLength(1));
      final items = await e.repo.watch().first;
      expect(items, isEmpty);
      expect(parseCount(items, _t0), 0);
      expect(categorizeCount(items, _t0), 0);
    });

    testWidgets('trail_change_in_settings_link_still_shown on every trail row', (t) async {
      final c = AirtimeAutoController(onSwitch: (_) async {}, onUndo: (_) async {}, now: () => _t0)
        ..add(AutoRecorded(rowId: 1, amountCents: 500, at: _t0))
        ..add(AutoRecorded(rowId: 2, amountCents: 700, at: _t0, airtimeOther: true, inRecentlyDeleted: true));
      var taps = 0;
      await t.pumpWidget(AppPaletteScope(
        controller: AppPaletteController('ocean', 'light'),
        child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: AutoGroup(c, _t0, onChangeInSettings: () => taps++)))),
      ));
      expect(find.text(kAutoRecordedChangeInSettings), findsNWidgets(2));
      expect(find.text(kAutoRecordedUndone), findsOneWidget);
      expect(find.text(kAutoRecordedUndo), findsOneWidget, reason: 'Undo only on the live row');
      await t.tap(find.text(kAutoRecordedChangeInSettings).first);
      expect(taps, 1);
    });
  });
}
