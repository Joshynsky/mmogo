/// §AUTOREAD.RULE_STORE - AUTOREAD RULES store interface (S2a implements it over preferences).
library;

import 'rule_model.dart';

/// At most this many people hold a rule; at the cap new rules are refused.
const int kRuleCap = 300;

abstract class RuleStore {
  Future<List<ReceiverRule>> all();
  Future<ReceiverRule?> get(ReceiverType type, String key);

  /// Creates or updates the rule. Returns false when refused: cap reached,
  /// receiver details OFF, Auto-record on a kind that cannot hold it, or a
  /// ceiling outside 1..100,000,000 cents. Clears `autoPending`.
  Future<bool> setLevel(
    ReceiverType type,
    String key, {
    required String name,
    required RuleLevel level,
    int? categoryId,
    int? ceilingCents,
    required DateTime at,
  });

  /// Writes a whole rule as given (the engine's counters, and a restored rule with its
  /// `autoPending` marker). New rules are refused at the cap and when details are OFF; an existing
  /// rule is always updated. Does not re-check kind or ceiling: the caller built a valid rule.
  Future<bool> saveRule(ReceiverRule rule);

  /// Deletes one person's rule.
  Future<void> forget(ReceiverType type, String key);

  /// Deletes every rule (Delete data, details off, Replace restore).
  Future<void> wipeAll();

  /// Fires after any change.
  Stream<void> get changes;
}
