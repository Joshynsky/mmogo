/// §AUTOREAD.WAITING hint a waiting item carries (labels only; never text).
library;

import '../rules/rule_model.dart';

class RuleHint {
  /// Only [RuleLevel.askFirst] is produced in 0.2.1.
  final RuleLevel level;
  final ReceiverType type;
  final String key;

  /// Up to 2 category ids to offer.
  final List<int> suggested;

  /// 0.2.2: an Ask first hint made for an Auto-record person whose rule could not record (paused, above
  /// the ceiling, details off). Draws the "Auto-record paused" tag. Default false; slice B2 sets it.
  final bool fromAutoRecord;

  const RuleHint({
    required this.level,
    required this.type,
    required this.key,
    this.suggested = const [],
    this.fromAutoRecord = false,
  });

  @override
  bool operator ==(Object other) {
    if (other is! RuleHint || other.level != level || other.type != type || other.key != key) return false;
    if (other.fromAutoRecord != fromAutoRecord) return false;
    if (other.suggested.length != suggested.length) return false;
    for (var i = 0; i < suggested.length; i++) {
      if (suggested[i] != other.suggested[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(level, type, key, Object.hashAll(suggested), fromAutoRecord);
}
