/// AUTOREAD RULES store over SharedPreferences: one key per person
/// ([ruleStorageKey]), device only, never in a backup. A corrupt value is
/// ignored. When "Record receiver details" is OFF the store holds nothing: it
/// wipes what it finds and refuses writes.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'rule_codec.dart';
import 'rule_model.dart';
import 'rule_store.dart';

/// The existing "Record receiver details" preference (read only here).
const String kReceiverDetailsPrefsKey = 'capture_identity_preference';

class PrefsRuleStore implements RuleStore {
  PrefsRuleStore({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);

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

  static bool _detailsOn(SharedPreferences p) => p.getBool(kReceiverDetailsPrefsKey) ?? true;

  Future<SharedPreferences> _fresh() async {
    final p = await _prefs();
    await p.reload();
    return p;
  }

  Iterable<String> _ruleKeys(SharedPreferences p) => p.getKeys().where((k) => k.startsWith(kRuleKeyPrefix));

  Future<void> _wipe(SharedPreferences p) async {
    for (final k in _ruleKeys(p).toList()) {
      await p.remove(k);
    }
  }

  List<ReceiverRule> _readAll(SharedPreferences p) {
    final out = <ReceiverRule>[];
    for (final k in _ruleKeys(p)) {
      final r = decodeRule(p.get(k));
      if (r != null) out.add(r);
    }
    return out;
  }

  @override
  Future<List<ReceiverRule>> all() => _serial(() async {
        final p = await _fresh();
        if (!_detailsOn(p)) {
          if (_ruleKeys(p).isNotEmpty) {
            await _wipe(p);
            _changes.add(null);
          }
          return const <ReceiverRule>[];
        }
        return _readAll(p);
      });

  @override
  Future<ReceiverRule?> get(ReceiverType type, String key) => _serial(() async {
        final p = await _fresh();
        if (!_detailsOn(p)) return null;
        return decodeRule(p.get(ruleStorageKey(type, key)));
      });

  @override
  Future<bool> setLevel(
    ReceiverType type,
    String key, {
    required String name,
    required RuleLevel level,
    int? categoryId,
    required DateTime at,
  }) =>
      _serial(() async {
        final p = await _fresh();
        if (!_detailsOn(p)) return false;
        final old = decodeRule(p.get(ruleStorageKey(type, key)));
        final t = at.toUtc();
        final same = old != null && old.level == level;
        final next = ReceiverRule(
          type: type,
          key: key,
          name: name,
          level: level,
          categoryId: categoryId,
          run: same ? old.run : 0,
          runCategoryId: same ? old.runCategoryId : null,
          created: old?.created ?? t,
          changed: t,
          lastRecorded: old?.lastRecorded,
        );
        // A person chosen for Ask first outranks a counter-only Suggested record.
        return _write(p, next, old == null, mayDropSuggested: level != RuleLevel.suggested);
      });

  /// Writes a whole rule (the engine's counters). New rules are refused at the
  /// cap; an existing rule is always updated. Never drops anyone.
  Future<bool> saveRule(ReceiverRule rule) => _serial(() async {
        final p = await _fresh();
        if (!_detailsOn(p)) return false;
        final isNew = decodeRule(p.get(ruleStorageKey(rule.type, rule.key))) == null;
        return _write(p, rule, isNew, mayDropSuggested: false);
      });

  Future<bool> _write(SharedPreferences p, ReceiverRule r, bool isNew, {required bool mayDropSuggested}) async {
    if (isNew && _ruleKeys(p).length >= kRuleCap) {
      if (!mayDropSuggested) return false;
      ReceiverRule? oldest;
      for (final x in _readAll(p)) {
        if (x.level == RuleLevel.suggested && (oldest == null || x.changed.isBefore(oldest.changed))) oldest = x;
      }
      if (oldest == null) return false; // only Ask first / Auto-record people: nothing may be dropped
      await p.remove(ruleStorageKey(oldest.type, oldest.key));
    }
    final ok = await p.setString(ruleStorageKey(r.type, r.key), encodeRule(r));
    if (ok) _changes.add(null);
    return ok;
  }

  @override
  Future<void> forget(ReceiverType type, String key) => _serial(() async {
        final p = await _fresh();
        final k = ruleStorageKey(type, key);
        if (p.containsKey(k) && await p.remove(k)) _changes.add(null);
      });

  @override
  Future<void> wipeAll() => _serial(() async {
        final p = await _fresh();
        await _wipe(p);
        _changes.add(null);
      });

  @override
  Stream<void> get changes => _changes.stream;
}
