// the 24 h "Recorded automatically" list as it is stored. Fake
// prefs, injected clock, invented numbers only. Auto-read flavor.
@Tags(['autoread'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/airtime_trail_store.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/data/maintenance/device_keys.dart';

import '../../support/fake_trail_prefs.dart';

final _t0 = DateTime(2026, 11, 13, 8);
const _h = Duration(hours: 1);

void main() {
  late FakeTrailPrefs prefs;
  late DateTime clock;
  late AirtimeTrailStore store;

  setUp(() {
    prefs = FakeTrailPrefs();
    clock = _t0;
    store = AirtimeTrailStore(prefs: prefs, now: () => clock);
  });

  Object? stored() => prefs.map[kAirtimeTrailPrefKey] == null
      ? null
      : jsonDecode(prefs.map[kAirtimeTrailPrefKey]!);

  test(
    'the key is the one name, the same string the standard build uses for Delete data',
    () {
      expect(kAirtimeTrailPrefKey, 'autoread_airtime_trail_v1');
      expect(kAirtimeTrailPrefKey, kAirtimeTrailPrefsKey);
    },
  );

  test('trail_stored_value_has_only_row_id_and_time', () async {
    await store.add(7, _t0);
    clock = _t0.add(_h);
    await store.add(9, clock);
    expect(prefs.map.keys, [kAirtimeTrailPrefKey], reason: 'no second key');
    final v = stored() as List;
    expect(v, hasLength(2));
    for (final pair in v) {
      expect(pair, isA<List>());
      expect((pair as List), hasLength(2));
      expect(pair.every((x) => x is int), isTrue);
    }
    expect(v.first, [7, _t0.millisecondsSinceEpoch]);
  });

  test(
    'trail_entry_shows_at_23h59m59s_and_expires_at_24h00m00s_and_is_pruned_from_store',
    () async {
      await store.add(7, _t0);
      clock = _t0.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      expect((await store.load()).map((e) => e.rowId), [7]);
      expect((stored() as List), hasLength(1));
      clock = _t0.add(const Duration(hours: 24));
      expect(await store.load(), isEmpty, reason: 'exactly 24 h is expired');
      expect(
        prefs.map.containsKey(kAirtimeTrailPrefKey),
        isFalse,
        reason: 'purged from the store',
      );
      expect(trailExpired(_t0, _t0.add(const Duration(hours: 24))), isTrue);
      expect(
        trailExpired(
          _t0,
          _t0.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
        ),
        isFalse,
      );
    },
  );

  test('trail_future_time_is_expired_zero_tolerance', () async {
    await store.add(7, _t0.add(const Duration(milliseconds: 1)));
    expect(await store.load(), isEmpty);
    expect(trailExpired(_t0.add(const Duration(milliseconds: 1)), _t0), isTrue);
    expect(
      trailExpired(_t0, _t0),
      isFalse,
      reason: 'the same instant is age 0, not the future',
    );
    // Stored by hand: a time one second ahead.
    prefs.map[kAirtimeTrailPrefKey] = jsonEncode([
      [8, _t0.add(const Duration(seconds: 1)).millisecondsSinceEpoch],
      [9, _t0.millisecondsSinceEpoch],
    ]);
    expect((await store.load()).map((e) => e.rowId), [9]);
  });

  test(
    'trail_rolling_per_entry (A at t0, B at t0+10h: at t0+24h A is gone, B shown)',
    () async {
      await store.add(1, _t0);
      clock = _t0.add(const Duration(hours: 10));
      await store.add(2, clock);
      clock = _t0.add(const Duration(hours: 24));
      expect((await store.load()).map((e) => e.rowId), [2]);
      expect((stored() as List).map((p) => (p as List).first), [2]);
    },
  );

  test(
    'trail_survives_controller_rebuild (a new store on the same prefs reads the entries back)',
    () async {
      await store.add(1, _t0);
      clock = _t0.add(_h);
      await store.add(2, clock);
      final again = AirtimeTrailStore(prefs: prefs, now: () => clock);
      expect((await again.load()).map((e) => e.rowId), [1, 2]);
    },
  );

  test('trail_cap_keeps_newest_200_oldest_dropped_first', () async {
    clock = _t0.add(const Duration(minutes: 10));
    for (var i = 1; i <= 205; i++) {
      await store.add(i, _t0.add(Duration(seconds: i)));
    }
    final list = await store.load();
    expect(list, hasLength(200));
    expect(list.first.rowId, 6);
    expect(list.last.rowId, 205);
    expect((stored() as List), hasLength(200));
  });

  test(
    'trail_corrupt_pref_is_empty_not_crash (not JSON, JSON object, number, wrong type)',
    () async {
      for (final bad in [
        'not json at all {{',
        '{"a":1}',
        '42',
        'null',
        '"text"',
        '',
      ]) {
        prefs.map[kAirtimeTrailPrefKey] = bad;
        expect(await store.load(), isEmpty, reason: bad);
      }
      expect(
        prefs.log.where((e) => e == 'write'),
        isEmpty,
        reason: 'a read writes nothing',
      );
      expect(
        prefs.map[kAirtimeTrailPrefKey],
        '',
        reason: 'the damaged value is not rewritten by a read',
      );
      prefs.failRead = true;
      expect(await store.load(), isEmpty, reason: 'a failed read is empty too');
    },
  );

  test(
    'trail_wrong_types_and_bad_elements_skipped (strings, negatives, zero, 3-element, null, doubles)',
    () async {
      final ms = _t0.millisecondsSinceEpoch;
      prefs.map[kAirtimeTrailPrefKey] = jsonEncode([
        ['5', ms],
        [-3, ms],
        [0, ms],
        [4, 0],
        [4, -1],
        [6, ms, 1],
        [6],
        null,
        'x',
        7,
        [8.5, ms],
        [9, ms + 0.5],
        [10, null],
        [11, ms], // the one good element
      ]);
      expect((await store.load()).map((e) => e.rowId), [11]);
    },
  );

  test(
    'trail_10000_entries_capped_and_bounded: the newest 200 by time, list order not trusted',
    () async {
      final raw = [
        for (var i = 1; i <= 10000; i++)
          [i, _t0.millisecondsSinceEpoch - (i * 1000)], // older as i grows
      ];
      prefs.map[kAirtimeTrailPrefKey] = jsonEncode(raw);
      final list = await store.load();
      expect(list, hasLength(200));
      expect(
        list.map((e) => e.rowId).toSet(),
        {for (var i = 1; i <= 200; i++) i},
        reason: 'the 200 newest, not the first 200 listed reversed',
      );
      expect(
        list.first.at.isBefore(list.last.at),
        isTrue,
        reason: 'oldest first',
      );
    },
  );

  test('trail_duplicate_ids_keep_newest', () async {
    final ms = _t0.millisecondsSinceEpoch;
    prefs.map[kAirtimeTrailPrefKey] = jsonEncode([
      [5, ms - 3000],
      [5, ms - 1000],
      [5, ms - 2000],
      [6, ms - 500],
    ]);
    final list = await store.load();
    expect(list.map((e) => e.rowId), [5, 6]);
    expect(list.first.atMs, ms - 1000);
  });

  test(
    'failed_prefs_write_does_not_fail_the_record: the entry still comes back for this session',
    () async {
      prefs.failWrite = true;
      final shown = await store.add(7, _t0);
      expect(shown.map((e) => e.rowId), [7]);
      expect(prefs.map, isEmpty);
    },
  );

  test(
    'a failed READ on add writes nothing (it could overwrite a list that could not be seen)',
    () async {
      await store.add(1, _t0);
      clock = _t0.add(_h);
      prefs.failRead = true;
      final shown = await store.add(2, clock);
      expect(shown.map((e) => e.rowId), [2]);
      prefs.failRead = false;
      expect((await store.load()).map((e) => e.rowId), [1]);
    },
  );

  test(
    'add_after_external_clear_does_not_resurrect_old_entries (read-modify-write on the stored value)',
    () async {
      await store.add(1, _t0);
      await store.add(2, _t0);
      prefs.map.remove(
        kAirtimeTrailPrefKey,
      ); // Delete data / Restore removed the key elsewhere
      clock = _t0.add(_h * 2);
      final shown = await store.add(3, clock);
      expect(shown.map((e) => e.rowId), [3]);
      expect((stored() as List).map((p) => (p as List).first), [3]);
    },
  );

  test(
    'the same row added twice keeps one entry with the newest time',
    () async {
      await store.add(1, _t0);
      clock = _t0.add(_h);
      await store.add(1, clock);
      final list = await store.load();
      expect(list, hasLength(1));
      expect(list.single.at, clock);
    },
  );

  test('a load that finds nothing to purge writes nothing', () async {
    await store.add(1, _t0);
    prefs.log.clear();
    await store.load();
    expect(prefs.log, ['read']);
  });

  test('clear removes the key', () async {
    await store.add(1, _t0);
    expect(await store.clear(), isTrue);
    expect(prefs.map, isEmpty);
  });

  test('no DateTime.now in the store source', () {
    // The injected clock is the only clock: the store file never asks for the real time.
    final src = File(
      'lib/autoread/data/airtime_trail_store.dart',
    ).readAsStringSync();
    expect(RegExp(r'DateTime\.now\(').hasMatch(src), isFalse);
  });
}
