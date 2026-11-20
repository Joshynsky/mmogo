/// In-memory [RuleStore] for tests of later slices. Deterministic.
library;

import 'dart:async';

import 'rule_model.dart';
import 'rule_store.dart';

class FakeRuleStore implements RuleStore {
  final Map<String, ReceiverRule> _rules = {};
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);

  static String _id(ReceiverType t, String k) => '${t.code}.$k';

  @override
  Future<List<ReceiverRule>> all() async => List.unmodifiable(_rules.values);

  @override
  Future<ReceiverRule?> get(ReceiverType type, String key) async => _rules[_id(type, key)];

  @override
  Future<bool> setLevel(ReceiverType type, String key,
      {required String name, required RuleLevel level, int? categoryId, required DateTime at}) async {
    final id = _id(type, key);
    final old = _rules[id];
    if (old == null && _rules.length >= kRuleCap) return false;
    _rules[id] = old == null
        ? ReceiverRule(type: type, key: key, name: name, level: level, categoryId: categoryId, created: at, changed: at)
        : old.copyWith(name: name, level: level, categoryId: categoryId, changed: at);
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
