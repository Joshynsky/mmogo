/// AUTOREAD HISTORY reader interface (S2b implements: database read or the
/// preferences summary).
library;

import '../rules/rule_model.dart';

abstract class HistoryReader {
  /// The up-to-2 most used category ids from the person's last 10 records,
  /// most used first. Empty when no history; null when unavailable (caller
  /// falls back, never fails).
  Future<List<int>?> topTwo(ReceiverType type, String key);
}
