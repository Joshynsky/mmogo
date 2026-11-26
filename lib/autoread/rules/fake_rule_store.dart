/// In-memory [RuleStore] for tests of later slices. Deterministic.
library;

import 'dart:async';

import 'rule_model.dart';
import 'rule_store.dart';

class FakeRuleStore implements RuleStore {
  final Map<String, ReceiverRule> _rules = {};

  /// Mirrors the "Record receiver details" switch. Like PrefsRuleStore (B-HIDE): OFF hides the rules
  /// (all() empty, get() null) and refuses setLevel / saveRule; nothing is erased, so ON brings them back.
  bool detailsOn = true;

  /// Test knob: refuses setLevel / saveRule like a store that cannot write, but (unlike [detailsOn] = false)
  /// keeps every rule readable. Tests that used `detailsOn = false` as "a store that refuses every write"
  /// use this since B-HIDE made OFF hide the rules too.
  bool refuseWrites = false;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);

  static String _id(ReceiverType t, String k) => '${t.code}.$k';

  @override
  Future<List<ReceiverRule>> all() async => detailsOn ? List.unmodifiable(_rules.values) : const <ReceiverRule>[];

  @override
  Future<ReceiverRule?> get(ReceiverType type, String key) async => detailsOn ? _rules[_id(type, key)] : null;

  @override
  Future<bool> setLevel(ReceiverType type, String key,
      {required String name,
      required RuleLevel level,
      int? categoryId,
      int? ceilingCents,
      List<int> chosenCategoryIds = const <int>[],
      required DateTime at}) async {
    if (!detailsOn || refuseWrites) return false;
    if (level == RuleLevel.autoRecord && !canHoldAutoRecord(type)) return false;
    if (!isValidCeilingCents(ceilingCents)) return false;
    // Like PrefsRuleStore.setLevel: the chosen list is kept only at Suggested.
    final suggested = level == RuleLevel.suggested;
    if (suggested && !isValidChosenCategoryIds(chosenCategoryIds)) return false;
    final chosen = suggested ? List<int>.unmodifiable(chosenCategoryIds) : const <int>[];
    final id = _id(type, key);
    final old = _rules[id];
    if (old == null && _rules.length >= kRuleCap) return false;
    _rules[id] = old == null
        ? ReceiverRule(
            type: type,
            key: key,
            name: name,
            level: level,
            categoryId: categoryId,
            ceilingCents: ceilingCents,
            chosenCategoryIds: chosen,
            created: at,
            changed: at)
        // Like PrefsRuleStore.setLevel: the category and ceiling are exactly what is passed (null
        // clears them; a caller that must keep the category passes the stored one), and the
        // restore mark is cleared. (0.2.2 U6: copyWith used to keep the old category on null.)
        : ReceiverRule(
            type: type,
            key: key,
            name: name,
            level: level,
            categoryId: categoryId,
            run: old.run,
            runCategoryId: old.runCategoryId,
            created: old.created,
            changed: at,
            lastRecorded: old.lastRecorded,
            ceilingCents: ceilingCents,
            autoPending: false,
            chosenCategoryIds: chosen);
    _changes.add(null);
    return true;
  }

  @override
  Future<bool> saveRule(ReceiverRule rule) async {
    if (!detailsOn || refuseWrites) return false;
    final id = _id(rule.type, rule.key);
    if (!_rules.containsKey(id) && _rules.length >= kRuleCap) return false;
    _rules[id] = rule;
    _changes.add(null);
    return true;
  }

  @override
  Future<void> forget(ReceiverType type, String key) async {
    if (_rules.remove(_id(type, key)) != null) _changes.add(null);
  }

  @override
  Future<void> wipeAll() async {
    _rules.clear();
    _changes.add(null);
  }

  /// Like PrefsRuleStore.forgetEveryone: every rule, whatever [detailsOn] says.
  @override
  Future<int> forgetEveryone() async {
    final n = _rules.length;
    _rules.clear();
    if (n > 0) _changes.add(null);
    return n;
  }

  /// Like PrefsRuleStore.countEveryone: every rule, whatever [detailsOn] says.
  @override
  Future<int> countEveryone() async => _rules.length;

  @override
  Stream<void> get changes => _changes.stream;
}
