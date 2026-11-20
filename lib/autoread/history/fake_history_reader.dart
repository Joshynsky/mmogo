/// Map-backed [HistoryReader] for tests of later slices. Deterministic.
library;

import '../rules/rule_model.dart';
import 'history_reader.dart';

class FakeHistoryReader implements HistoryReader {
  /// Keyed `TYPE.key`, e.g. `SM.0712345678`.
  final Map<String, List<int>> history;

  /// When true every call answers null (history unavailable).
  bool unavailable;

  FakeHistoryReader({Map<String, List<int>>? history, this.unavailable = false}) : history = history ?? {};

  @override
  Future<List<int>?> topTwo(ReceiverType type, String key) async {
    if (unavailable) return null;
    final l = history['${type.code}.$key'] ?? const <int>[];
    return l.length > 2 ? l.sublist(0, 2) : List.of(l);
  }
}
