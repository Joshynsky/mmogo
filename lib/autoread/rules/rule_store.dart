/// AUTOREAD RULES store interface (S2a implements it over preferences).
library;

import 'rule_model.dart';

/// At most this many people hold a rule; at the cap new rules are refused.
const int kRuleCap = 300;

abstract class RuleStore {
  Future<List<ReceiverRule>> all();
  Future<ReceiverRule?> get(ReceiverType type, String key);

  /// Creates or updates the rule. Returns false when refused (cap reached).
  Future<bool> setLevel(
    ReceiverType type,
    String key, {
    required String name,
    required RuleLevel level,
    int? categoryId,
    required DateTime at,
  });

  /// Deletes one person's rule.
  Future<void> forget(ReceiverType type, String key);

  /// Deletes every rule (Delete data, details off, Replace restore).
  Future<void> wipeAll();

  /// Fires after any change.
  Stream<void> get changes;
}
