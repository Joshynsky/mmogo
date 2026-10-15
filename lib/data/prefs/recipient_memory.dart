import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/parsing/name_only_resolver.dart';
import '../../domain/parsing/parsed_sms_fields.dart';

/// §DATA.PREFS.RECIPIENTS — 0.1.2 S8b (NO2). Remembers "this receiver name is
/// a Pochi / a Send Money" so the next name-only message needs no question.
///
/// Device only: the key `recipient_types_v1` is NOT in the backup allowlist,
/// never in a backup, CSV or log, and a restore file cannot set it. It holds
/// receiver names (personal data), so no message, result or error text here
/// ever carries a name: results are codes only, and nothing is logged.
///
/// Stored text: one JSON object `{ "<NAME KEY>": {"t": "<type code>", "at": <ms>} }`.
/// Never a classification id.

/// What [RecipientMemory.remember] did. Codes only (no text, never a name).
enum RememberResult {
  /// Written.
  saved,

  /// Written, and the oldest remembered name was dropped to make room (cap).
  savedDroppedOldest,

  /// The "Also record the receiver details" switch was off: nothing written.
  notRecorded,

  /// Only Send Money and Pochi are rememberable: nothing written.
  notRememberable,

  /// The key was empty/blank or longer than [RecipientMemory.maxKeyLength]:
  /// nothing written.
  badKey,

  /// Preferences failed: nothing (new) was stored. The caller's save is
  /// unaffected.
  writeFailed,
}

class RecipientEntry {
  final String key;
  final RecipientRule rule;
  const RecipientEntry(this.key, this.rule);
}

class RecipientMemory {
  static const prefsKey = 'recipient_types_v1';
  static const maxEntries = 300;
  static const maxKeyLength = 200;
  static const _timeout = Duration(seconds: 2);

  final Future<SharedPreferences> Function() _prefs;
  final int Function() _nowMs;

  RecipientMemory({
    Future<SharedPreferences> Function()? prefs,
    int Function()? nowMs,
  })  : _prefs = prefs ?? SharedPreferences.getInstance,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  // One in-flight chain: every read-modify-write waits for the one before it,
  // so two quick remember() calls both land.
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await op());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  static bool _rememberable(SmsSourceType t) =>
      t == SmsSourceType.sendMoney || t == SmsSourceType.pochi;

  static SmsSourceType? _typeOf(Object? code) => switch (code) {
        'SEND_MONEY' => SmsSourceType.sendMoney,
        'POCHI_LA_BIASHARA' => SmsSourceType.pochi,
        _ => null,
      };

  /// Stored entries in insertion order (oldest write first). Corrupt text,
  /// a non-object, or a bad entry reads as empty / is skipped; never throws.
  Future<Map<String, RecipientRule>> _read() async {
    final out = <String, RecipientRule>{};
    try {
      final raw = (await _prefs().timeout(_timeout)).getString(prefsKey);
      if (raw == null || raw.isEmpty) return out;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return out;
      decoded.forEach((k, v) {
        if (k is! String || k.isEmpty || k.length > maxKeyLength) return;
        if (v is! Map) return;
        final t = _typeOf(v['t']);
        final at = v['at'];
        if (t == null || at is! int) return;
        out[k] = RecipientRule(type: t, at: at);
      });
    } catch (_) {
      return <String, RecipientRule>{};
    }
    return out;
  }

  Future<bool> _write(Map<String, RecipientRule> m) async {
    try {
      final p = await _prefs().timeout(_timeout);
      if (m.isEmpty) return await p.remove(prefsKey).timeout(_timeout);
      final text = jsonEncode({
        for (final e in m.entries) e.key: {'t': e.value.type.dbValue, 'at': e.value.at},
      });
      return await p.setString(prefsKey, text).timeout(_timeout);
    } catch (_) {
      return false;
    }
  }

  /// The remembered type for [key] (a `deriveRecipientNameKey` value), or null.
  Future<RecipientRule?> lookup(String key) async {
    if (key.isEmpty || key.length > maxKeyLength) return null;
    return (await _serial(_read))[key];
  }

  /// Remembers [type] for [key]; last write wins. [recordDetailsOn] is the
  /// value of the "Also record the receiver details" switch: false means NO
  /// write at all (the next message asks again). S8c calls this only AFTER the
  /// transaction is saved, and only when the Remember tick is on.
  Future<RememberResult> remember(
    String key,
    SmsSourceType type, {
    required bool recordDetailsOn,
  }) {
    if (!recordDetailsOn) return Future.value(RememberResult.notRecorded);
    if (!_rememberable(type)) return Future.value(RememberResult.notRememberable);
    if (key.trim().isEmpty || key.length > maxKeyLength) {
      return Future.value(RememberResult.badKey);
    }
    return _serial(() async {
      final m = await _read();
      m.remove(key); // an override moves to the newest position
      var dropped = false;
      if (m.length >= maxEntries) {
        String? oldest;
        for (final e in m.entries) {
          if (oldest == null || e.value.at < m[oldest]!.at) oldest = e.key;
        }
        m.remove(oldest);
        dropped = true;
      }
      m[key] = RecipientRule(type: type, at: _nowMs());
      final ok = await _write(m);
      if (!ok) return RememberResult.writeFailed;
      return dropped ? RememberResult.savedDroppedOldest : RememberResult.saved;
    });
  }

  /// S9a (the Remembered recipients page, "Change to ..."): changes the type
  /// of an EXISTING entry. Keeps its `at` and its place in the list, needs no
  /// receiver-details switch, and never goes through [remember] (an override
  /// there moves the name to newest). True when the entry exists, the type is
  /// Send Money or Pochi, and the stored text holds the new type; false
  /// otherwise (nothing written). No name in the result, never logged.
  Future<bool> retype(String key, SmsSourceType type) {
    if (!_rememberable(type)) return Future.value(false);
    return _serial(() async {
      final m = await _read();
      final old = m[key];
      if (old == null) return false;
      if (old.type == type) return true;
      m[key] = RecipientRule(type: type, at: old.at); // same key: same place
      return _write(m);
    });
  }

  /// Forgets one name. True when something was removed and the write held.
  Future<bool> forget(String key) => _serial(() async {
        final m = await _read();
        if (m.remove(key) == null) return false;
        return _write(m);
      });

  /// Forgets everything. True when storage ended up without the key.
  Future<bool> forgetAll() => _serial(() async {
        try {
          final p = await _prefs().timeout(_timeout);
          if (!p.containsKey(prefsKey)) return true;
          return await p.remove(prefsKey).timeout(_timeout);
        } catch (_) {
          return false;
        }
      });

  /// All remembered names, newest first (ties: the later write first).
  Future<List<RecipientEntry>> list() async {
    final m = await _serial(_read);
    final all = m.entries.toList();
    final order = List<int>.generate(all.length, (i) => i)
      ..sort((a, b) {
        final c = all[b].value.at.compareTo(all[a].value.at);
        return c != 0 ? c : b.compareTo(a); // same ms: later write first
      });
    return [for (final i in order) RecipientEntry(all[i].key, all[i].value)];
  }
}
