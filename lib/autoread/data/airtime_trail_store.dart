/// §AUTOREAD.AIRTIME_TRAIL_STORE - the 24 h "Recorded automatically" trail on
/// disk: ONE preference, `autoread_airtime_trail_v1`, holding only
/// `[[rowId, atMs], ...]` (a ledger row number and the time it was recorded).
/// No amount, kind, code, name, number or message text is stored here; the
/// ledger row is the source for those at display time.
///
/// Rules: rolling 24 h per entry (an age of exactly 24 h
/// is expired; any time in the future is expired, zero tolerance); at most 200
/// entries, the newest kept; a damaged value reads as an empty list and never
/// throws; a read writes nothing except the purge of expired entries; an add is
/// read, purge, append, cap, write on the STORED value (never "write memory"),
/// so a list cleared elsewhere (Delete data, Restore) cannot come back.
///
/// The clock is injected; nothing here calls `DateTime.now`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/airtime_auto.dart'
    show kAirtimeTrailPrefKey, kTrailMaxEntries, trailExpired;

/// One stored entry: the ledger row and when it was recorded.
class TrailEntry {
  const TrailEntry(this.rowId, this.at);
  final int rowId;
  final DateTime at;

  int get atMs => at.millisecondsSinceEpoch;
}

/// The three preference calls the store needs, so a test can fail any of them.
abstract class TrailPrefs {
  /// The stored string, or null. May throw.
  Future<String?> read(String key);

  /// True only when the write definitely happened.
  Future<bool> write(String key, String value);

  /// True when the key is gone after the call.
  Future<bool> remove(String key);
}

/// The real thing: `shared_preferences`, re-read from disk before each read.
class SharedTrailPrefs implements TrailPrefs {
  SharedTrailPrefs({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;
  static const _timeout = Duration(seconds: 2);

  @override
  Future<String?> read(String key) async {
    final p = await _prefs().timeout(_timeout);
    try {
      await p.reload().timeout(_timeout);
    } catch (_) {
      // Fall back to the copy in memory.
    }
    final v = p.get(key);
    return v is String ? v : null; // a value of another type is "not there"
  }

  @override
  Future<bool> write(String key, String value) async => (await _prefs().timeout(
    _timeout,
  )).setString(key, value).timeout(_timeout);

  @override
  Future<bool> remove(String key) async =>
      (await _prefs().timeout(_timeout)).remove(key).timeout(_timeout);
}

/// Keeps the value in memory only. The repository's default when no store is
/// passed (tests that do not look at the trail); the app wires [SharedTrailPrefs]
/// explicitly in `main.dart`.
class MemoryTrailPrefs implements TrailPrefs {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<bool> write(String key, String value) async {
    _map[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _map.remove(key);
    return true;
  }
}

class AirtimeTrailStore {
  AirtimeTrailStore({
    required TrailPrefs prefs,
    required DateTime Function() now,
  }) : _prefs = prefs,
       _now = now;

  final TrailPrefs _prefs;
  final DateTime Function() _now;

  // No queue of its own: the only caller is the repository, which runs every
  // call inside its one-after-another queue (`_locked`). Two overlapping calls
  // on one store are therefore not supported (and a second queue deadlocked a
  // widget test that mixes the test's fake clock zone with real async).

  /// The stored entries that are still valid, oldest first. Expired ones are
  /// dropped from the stored value too (a failed purge write is ignored). A
  /// damaged value reads as empty and is NOT written back. Never throws.
  Future<List<TrailEntry>> load() async {
    final read = await _readEntries();
    if (read.failed) return const <TrailEntry>[];
    final kept = _purge(read.entries);
    if (kept.length != read.entries.length) await _tryWrite(kept);
    return kept;
  }

  /// Records [rowId] at [at] on the stored value; returns the list now valid
  /// (this entry included, even when the write failed: the session still shows
  /// it). Never throws.
  Future<List<TrailEntry>> add(int rowId, DateTime at) async {
    final read = await _readEntries();
    final merged = _purge([...read.entries, TrailEntry(rowId, at)]);
    // A failed READ writes nothing: it could overwrite a list we could not see.
    if (!read.failed) await _tryWrite(merged);
    return merged;
  }

  /// Removes the stored value. True when it is gone. Never throws.
  Future<bool> clear() async {
    try {
      return await _prefs.remove(kAirtimeTrailPrefKey);
    } catch (_) {
      return false;
    }
  }

  Future<void> _tryWrite(List<TrailEntry> list) async {
    try {
      if (list.isEmpty) {
        await _prefs.remove(kAirtimeTrailPrefKey);
      } else {
        await _prefs.write(kAirtimeTrailPrefKey, encodeTrail(list));
      }
    } catch (_) {
      // The record is not undone by a failed write.
    }
  }

  /// The entries parsed from the stored value (empty when absent or damaged);
  /// `failed` is true when the preference could not be read at all.
  Future<({bool failed, List<TrailEntry> entries})> _readEntries() async {
    final String? raw;
    try {
      raw = await _prefs.read(kAirtimeTrailPrefKey);
    } catch (_) {
      return (failed: true, entries: const <TrailEntry>[]);
    }
    return (
      failed: false,
      entries: raw == null ? const <TrailEntry>[] : decodeTrail(raw),
    );
  }

  /// Drops expired entries, then returns at most the newest 200, oldest first.
  List<TrailEntry> _purge(List<TrailEntry> all) {
    final now = _now();
    final live = [
      for (final e in all)
        if (!trailExpired(e.at, now)) e,
    ];
    return _capNewest(live);
  }
}

/// JSON of the list: `[[rowId,atMs],...]` and nothing else.
String encodeTrail(List<TrailEntry> list) => jsonEncode([
  for (final e in list) [e.rowId, e.atMs],
]);

/// Reads a stored value without trust: a value that is not JSON, not a list,
/// or throws = empty; a bad element (not a pair of ints, id or time not above
/// 0) is skipped; a repeated row keeps its newest time; more than
/// [kTrailMaxEntries] keeps the newest by time (list order is not trusted).
/// Oldest first. Never throws.
List<TrailEntry> decodeTrail(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    final newest = <int, int>{};
    for (final el in data) {
      if (el is! List || el.length != 2) continue;
      final id = el[0], ms = el[1];
      if (id is! int || ms is! int || id <= 0 || ms <= 0) continue;
      final seen = newest[id];
      if (seen == null || ms > seen) newest[id] = ms;
    }
    return _capNewest([
      for (final e in newest.entries)
        TrailEntry(e.key, DateTime.fromMillisecondsSinceEpoch(e.value)),
    ]);
  } catch (_) {
    return const [];
  }
}

List<TrailEntry> _capNewest(List<TrailEntry> list) {
  final sorted = [...list]
    ..sort((a, b) {
      final c = a.atMs.compareTo(b.atMs);
      return c != 0 ? c : a.rowId.compareTo(b.rowId);
    });
  // A repeated row id (an add of a row already stored) keeps the newest time.
  final byId = <int, TrailEntry>{};
  for (final e in sorted) {
    byId[e.rowId] = e;
  }
  final unique = byId.values.toList()
    ..sort((a, b) {
      final c = a.atMs.compareTo(b.atMs);
      return c != 0 ? c : a.rowId.compareTo(b.rowId);
    });
  return unique.length <= kTrailMaxEntries
      ? unique
      : unique.sublist(unique.length - kTrailMaxEntries);
}
