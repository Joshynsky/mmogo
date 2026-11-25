/// §AUTOREAD.RULE_STORE - AUTOREAD RULES store interface (S2a implements it over preferences).
library;

import 'rule_model.dart';

/// At most this many people hold a rule; at the cap new rules are refused.
const int kRuleCap = 300;

abstract class RuleStore {
  Future<List<ReceiverRule>> all();
  Future<ReceiverRule?> get(ReceiverType type, String key);

  /// Creates or updates the rule. Returns false when refused: cap reached,
  /// receiver details OFF, Auto-record on a kind that cannot hold it, a
  /// ceiling outside 1..100,000,000 cents, or (at Suggested only) a chosen list that is not
  /// [isValidChosenCategoryIds]. Clears `autoPending`.
  ///
  /// [chosenCategoryIds] (0.2.2 item 2 redesign, decision in code): stored exactly as passed at
  /// Suggested, like [categoryId] and [ceilingCents] (the default, empty, means "Last 10 payments", so a
  /// caller that must keep a stored list passes it). Ask first and Auto-record always store it empty,
  /// whatever is passed.
  Future<bool> setLevel(
    ReceiverType type,
    String key, {
    required String name,
    required RuleLevel level,
    int? categoryId,
    int? ceilingCents,
    List<int> chosenCategoryIds = const <int>[],
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

  /// "Forget all people" (0.2.2 item 2 redesign): erases every stored rule, whatever the "Record receiver
  /// details" switch says, so rules hidden while it is OFF go too. Returns how many were erased (the same
  /// set [countEveryone] counts). Fires [changes] when anything was erased.
  Future<int> forgetEveryone();

  /// How many rules [forgetEveryone] would erase: every stored rule, hidden ones included.
  Future<int> countEveryone();

  /// Fires after any change.
  Stream<void> get changes;
}
