/// AUTOREAD RULES store over SharedPreferences: one key per person
/// ([ruleStorageKey]), device only (backup carrying is a later slice). A corrupt value is
/// ignored.
///
/// "Record receiver details" OFF HIDES the rules (0.2.2 item 2, B-HIDE; PM 25-11, reverses the 0.2.1
/// privacy wipe): while OFF all() answers empty, get() answers null and setLevel / saveRule refuse, but
/// nothing is erased, so turning it ON brings every person back exactly as before (level, category,
/// limit, chosen list). Only [forget], [wipeAll], [forgetEveryone] (Forget all) and Delete data
/// (`RuleBackupGuard.wipe`) erase, and they do so whatever the switch says.
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

  /// Empty while details are OFF: the rules are hidden, never erased here (B-HIDE).
  @override
  Future<List<ReceiverRule>> all() => _serial(() async {
        final p = await _fresh();
        if (!_detailsOn(p)) return const <ReceiverRule>[];
        return _readAll(p);
      });

  /// Null while details are OFF (hidden, kept).
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
    int? ceilingCents,
    List<int> chosenCategoryIds = const <int>[],
    required DateTime at,
  }) =>
      _serial(() async {
        if (level == RuleLevel.autoRecord && !canHoldAutoRecord(type)) return false;
        if (!isValidCeilingCents(ceilingCents)) return false;
        // Chosen Suggest categories live only at Suggested; Ask first and Auto-record clear them.
        final suggested = level == RuleLevel.suggested;
        if (suggested && !isValidChosenCategoryIds(chosenCategoryIds)) return false;
        final p = await _fresh();
        if (!_detailsOn(p)) return false; // OFF: refused; the hidden rule (if any) stays exactly as it was
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
          ceilingCents: ceilingCents,
          chosenCategoryIds: suggested ? List<int>.unmodifiable(chosenCategoryIds) : const <int>[],
        );
        // A person chosen for Ask first outranks a counter-only Suggested record.
        return _write(p, next, old == null, mayDropSuggested: level != RuleLevel.suggested);
      });

  /// Writes a whole rule (the engine's counters). New rules are refused at the
  /// cap; an existing rule is always updated. Never drops anyone.
  @override
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

  /// Reads the keys directly, never through all(): every rule key, whatever the details switch says.
  @override
  Future<int> forgetEveryone() => _serial(() async {
        final p = await _fresh();
        final keys = _ruleKeys(p).toList();
        for (final k in keys) {
          await p.remove(k);
        }
        if (keys.isNotEmpty) _changes.add(null);
        return keys.length;
      });

  /// Every rule key (the set [forgetEveryone] erases; the same count the cap uses).
  @override
  Future<int> countEveryone() => _serial(() async => _ruleKeys(await _fresh()).length);

  @override
  Stream<void> get changes => _changes.stream;
}
