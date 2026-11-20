/// AUTOREAD HISTORY reader over the preferences summary `autoread_hist_v1` (the fallback route; the only
/// route that works for sure in the headless engine, which registers just shared_preferences). Read only.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../rules/rule_model.dart';
import 'history_reader.dart';
import 'history_summary_codec.dart';

class SummaryHistoryReader implements HistoryReader {
  SummaryHistoryReader({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _prefs;

  /// Null when the summary was never written or is corrupt; empty for a person it has no records for.
  @override
  Future<List<int>?> topTwo(ReceiverType type, String key) async {
    try {
      final p = await _prefs();
      await p.reload();
      final m = decodeHistSummary(p.getString(kHistSummaryPrefKey));
      if (m == null) return null;
      return m[historyPersonId(type, key)] ?? const <int>[];
    } catch (_) {
      return null;
    }
  }
}
