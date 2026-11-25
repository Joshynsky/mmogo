/// AUTOREAD RULES engine interface: counters and "Ask first next time?"
/// offers (S2a implements it).
library;

import 'rule_model.dart';

/// An offer to raise one person to Ask first.
class Offer {
  final ReceiverType type;
  final String key;
  final String name;
  final int categoryId;

  /// How many records in a row used [categoryId].
  final int run;
  const Offer({required this.type, required this.key, required this.name, required this.categoryId, required this.run});

  @override
  bool operator ==(Object other) =>
      other is Offer &&
      other.type == type &&
      other.key == key &&
      other.name == name &&
      other.categoryId == categoryId &&
      other.run == run;

  @override
  int get hashCode => Object.hash(type, key, name, categoryId, run);
}

abstract class RuleEngine {
  Future<void> onRecorded(ReceiverType type, String key, {required String name, required int categoryId, required DateTime at});
  /// [recordedAutomatically]: the removed row was recorded with no tap; for a
  /// person on Auto-record that drops the rule to Suggested.
  Future<void> onUndone(ReceiverType type, String key, {bool recordedAutomatically = false});
  Future<void> onCategoryChanged(ReceiverType type, String key, {required int categoryId});

  /// "Not now": stop offering this person for now.
  Future<void> notNow(ReceiverType type, String key);

  Future<List<Offer>> pendingOffers();

  /// Records in a row before an offer (2..10, default 3).
  Future<int> suggestAfter();
  Future<bool> suggestEnabled();
}
