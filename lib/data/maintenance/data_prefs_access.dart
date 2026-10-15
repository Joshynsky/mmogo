import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// §DATA.MAINTENANCE.PREFS — the small slice of `shared_preferences` that
/// Delete data needs, behind an interface so a test can fail any call. Every
/// read goes to a FRESH `getInstance()` + `reload()` ("read back what is
/// really stored"). Methods throw on a failed or stuck read (2 s bound); the
/// service maps that to "not finished".
abstract class DataPrefsAccess {
  /// Every stored key, read fresh.
  Future<Set<String>> keys();

  /// True when [key] is stored, read fresh.
  Future<bool> has(String key);

  /// The stored int (or null), read fresh.
  Future<int?> readInt(String key);

  /// The stored string (or null), read fresh.
  Future<String?> readString(String key);

  /// True only when the write definitely happened.
  Future<bool> setInt(String key, int value);

  /// True only when the key is definitely gone after the call.
  Future<bool> remove(String key);
}

class SharedDataPrefsAccess implements DataPrefsAccess {
  SharedDataPrefsAccess({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;
  static const _timeout = Duration(seconds: 2);

  Future<SharedPreferences> _fresh() async {
    final p = await _prefs().timeout(_timeout);
    await p.reload().timeout(_timeout);
    return p;
  }

  @override
  Future<Set<String>> keys() async => (await _fresh()).getKeys();

  @override
  Future<bool> has(String key) async => (await _fresh()).containsKey(key);

  @override
  Future<int?> readInt(String key) async => (await _fresh()).getInt(key);

  @override
  Future<String?> readString(String key) async => (await _fresh()).getString(key);

  @override
  Future<bool> setInt(String key, int value) async =>
      (await _prefs().timeout(_timeout)).setInt(key, value).timeout(_timeout);

  @override
  Future<bool> remove(String key) async =>
      (await _prefs().timeout(_timeout)).remove(key).timeout(_timeout);
}
