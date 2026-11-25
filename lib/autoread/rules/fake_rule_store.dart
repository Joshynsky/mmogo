/// In-memory [RuleStore] for tests of later slices. Deterministic.
library;

import 'dart:async';

import 'rule_model.dart';
import 'rule_store.dart';

class FakeRuleStore implements RuleStore {
  final Map<String, ReceiverRule> _rules = {};

  /// Mirrors the "Record receiver details" switch; OFF refuses setLevel.
  bool detailsOn = true;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);

  static String _id(ReceiverType t, String k) => '${t.code}.$k';

  @override
  Future<List<ReceiverRule>> all() async => List.unmodifiable(_rules.values);

  @override
  Future<ReceiverRule?> get(ReceiverType type, String key) async => _rules[_id(type, key)];

  @override
  Future<bool> setLevel(ReceiverType type, String key,
      {required String name, required RuleLevel level, int? categoryId, int? ceilingCents, required DateTime at}) async {
    if (!detailsOn) return false;
    if (level == RuleLevel.autoRecord && !canHoldAutoRecord(type)) return false;
    if (!isValidCeilingCents(ceilingCents)) return false;
    final id = _id(type, key);
    final old = _rules[id];
    if (old == null && _rules.length >= kRuleCap) return false;
    _rules[id] = old == null
        ? ReceiverRule(
            type: type, key: key, name: name, level: level, categoryId: categoryId, ceilingCents: ceilingCents, created: at, changed: at)
        : old.copyWith(
            name: name,
            level: level,
            categoryId: categoryId,
            ceilingCents: ceilingCents,
            clearCeiling: ceilingCents == null,
            autoPending: false,
            changed: at);
    _changes.add(null);
    return true;
  }

  @override
  Future<bool> saveRule(ReceiverRule rule) async {
    if (!detailsOn) return false;
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

  @override
  Stream<void> get changes => _changes.stream;
}
