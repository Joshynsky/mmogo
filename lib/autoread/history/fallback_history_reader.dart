/// AUTOREAD HISTORY: asks [primary] (the live database) and, when it answers null (unavailable), [fallback]
/// (the preferences summary). Never throws.
library;

import '../rules/rule_model.dart';
import 'history_reader.dart';

class FallbackHistoryReader implements HistoryReader {
  const FallbackHistoryReader(this.primary, this.fallback);
  final HistoryReader primary;
  final HistoryReader fallback;

  @override
  Future<List<int>?> topTwo(ReceiverType type, String key) async {
    try {
      final r = await primary.topTwo(type, key);
      if (r != null) return r;
    } catch (_) {}
    try {
      return await fallback.topTwo(type, key);
    } catch (_) {
      return null;
    }
  }
}
