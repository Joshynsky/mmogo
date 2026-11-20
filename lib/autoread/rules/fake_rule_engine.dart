/// Scripted [RuleEngine] for tests of later slices: returns what the test
/// sets and logs every call. Deterministic.
library;

import 'rule_engine.dart';
import 'rule_model.dart';

class FakeRuleEngine implements RuleEngine {
  List<Offer> offers;
  int after;
  bool enabled;

  /// One entry per call, e.g. `recorded:SM.0712:5`, `undone:SM.0712`.
  final List<String> calls = [];

  FakeRuleEngine({this.offers = const [], this.after = 3, this.enabled = true});

  static String _id(ReceiverType t, String k) => '${t.code}.$k';

  @override
  Future<void> onRecorded(ReceiverType type, String key, {required String name, required int categoryId, required DateTime at}) async =>
      calls.add('recorded:${_id(type, key)}:$categoryId');

  @override
  Future<void> onUndone(ReceiverType type, String key) async => calls.add('undone:${_id(type, key)}');

  @override
  Future<void> onCategoryChanged(ReceiverType type, String key, {required int categoryId}) async =>
      calls.add('changed:${_id(type, key)}:$categoryId');

  @override
  Future<void> notNow(ReceiverType type, String key) async {
    calls.add('notNow:${_id(type, key)}');
    offers = [for (final o in offers) if (o.type != type || o.key != key) o];
  }

  @override
  Future<List<Offer>> pendingOffers() async => List.unmodifiable(offers);

  @override
  Future<int> suggestAfter() async => after;

  @override
  Future<bool> suggestEnabled() async => enabled;
}
