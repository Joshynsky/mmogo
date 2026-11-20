/// AUTOREAD RULES undone M-Pesa codes in preferences: code -> expiry (ms),
/// 24 h, cap 100, pruned on every read. Codes only, never message text.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'undone_codes.dart';

const String kUndoneCodesKey = 'autoread_undone_codes_v1';
const int kUndoneCodesCap = 100;
const Duration kUndoneCodesLife = Duration(hours: 24);

class PrefsUndoneCodes implements UndoneCodes {
  PrefsUndoneCodes({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  /// Unexpired entries; writes the pruned list back when anything dropped.
  Future<Map<String, int>> _read(SharedPreferences p, DateTime now) async {
    final out = <String, int>{};
    var dropped = false;
    final raw = p.getString(kUndoneCodesKey);
    if (raw != null) {
      try {
        final m = jsonDecode(raw);
        if (m is Map) {
          m.forEach((k, v) {
            if (k is String && k.isNotEmpty && v is int && v > now.millisecondsSinceEpoch) {
              out[k] = v;
            } else {
              dropped = true;
            }
          });
        } else {
          dropped = true;
        }
      } catch (_) {
        dropped = true;
      }
    }
    if (dropped) await _write(p, out);
    return out;
  }

  Future<void> _write(SharedPreferences p, Map<String, int> m) async {
    if (m.isEmpty) {
      await p.remove(kUndoneCodesKey);
    } else {
      await p.setString(kUndoneCodesKey, jsonEncode(m));
    }
  }

  @override
  Future<void> add(String code, {required DateTime now}) async {
    if (code.isEmpty) return;
    final p = await _prefs();
    await p.reload();
    final m = await _read(p, now);
    m.remove(code);
    while (m.length >= kUndoneCodesCap) {
      String? first;
      m.forEach((k, v) {
        if (first == null || v < m[first]!) first = k;
      });
      m.remove(first);
    }
    m[code] = now.add(kUndoneCodesLife).millisecondsSinceEpoch;
    await _write(p, m);
  }

  @override
  Future<bool> contains(String code, {required DateTime now}) async {
    final p = await _prefs();
    await p.reload();
    return (await _read(p, now)).containsKey(code);
  }

  @override
  Future<void> wipe() async {
    final p = await _prefs();
    await p.remove(kUndoneCodesKey);
  }
}
