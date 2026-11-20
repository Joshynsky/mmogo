/// AUTOREAD HISTORY summary writer. Runs ONLY in the app (never in the background engine): it reads the
/// ledger through the app's own database handle and rewrites the `autoread_hist_v1` preference.
///
/// The app calls [HistorySummaryWriter.rebuild] on open and after a record, Undo, category change or
/// restore, and [HistorySummaryWriter.clear] on Delete data and when "Record receiver details" goes off.
/// Nothing here throws into the caller and nothing logs.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'history_summary_codec.dart';

/// One ledger row's person and category (newest first in a list of these).
class HistoryRow {
  const HistoryRow(this.personId, this.categoryId);
  final String personId;
  final int categoryId;
}

/// The one history query (read only). The FFI reader narrows the type filter.
const String kHistoryRowsSql = 'SELECT source_type, counterparty_label, counterparty_phone, '
    'paybill_account_number, classification_id FROM transactions '
    "WHERE deleted_at IS NULL AND source_type IN ('SEND_MONEY','PAYBILL','BUY_GOODS','POCHI_LA_BIASHARA') "
    'ORDER BY transaction_occurred_at DESC, id DESC LIMIT ?';

/// How many newest ledger rows the app looks at when it rebuilds the summary.
const int kHistoryScanLimit = 5000;

/// Reads the newest rows (newest first) from an open database. Read only.
Future<List<HistoryRow>> readHistoryRows(Database db, {int limit = kHistoryScanLimit}) async {
  final rows = await db.rawQuery(kHistoryRowsSql, [limit]);
  final out = <HistoryRow>[];
  for (final r in rows) {
    final cat = r['classification_id'];
    if (cat is! int) continue;
    final id = historyPersonIdOfRow(
      sourceType: r['source_type'] as String,
      label: r['counterparty_label'] as String?,
      phone: r['counterparty_phone'] as String?,
      account: r['paybill_account_number'] as String?,
    );
    if (id != null) out.add(HistoryRow(id, cat));
  }
  return out;
}

/// Groups newest-first rows into the summary (person -> top 2 of their last 5). People come out in order
/// of their newest record; the cap is applied by the encoder.
Map<String, List<int>> summariseHistory(List<HistoryRow> newestFirst) {
  final perPerson = <String, List<int>>{};
  for (final r in newestFirst) {
    final l = perPerson.putIfAbsent(r.personId, () => <int>[]);
    if (l.length < kHistLastRecords) l.add(r.categoryId);
  }
  return {for (final e in perPerson.entries) e.key: topTwoCategories(e.value)};
}

class HistorySummaryWriter {
  HistorySummaryWriter({required this.rows, Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  /// Newest rows first. In the app: `() async => readHistoryRows(await AppDatabase.instance.database)`.
  final Future<List<HistoryRow>> Function() rows;
  final Future<SharedPreferences> Function() _prefs;

  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final run = _tail.then((_) => op());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Rewrites the summary from the ledger. When [recordReceiverDetails] is false the summary is removed
  /// instead (nothing about people may be kept). Returns true when the preference now matches; never throws.
  Future<bool> rebuild({required bool recordReceiverDetails}) {
    if (!recordReceiverDetails) return clear();
    return _serial(() async {
      try {
        final summary = summariseHistory(await rows());
        final p = await _prefs();
        return await p.setString(kHistSummaryPrefKey, encodeHistSummary(summary));
      } catch (_) {
        return false;
      }
    });
  }

  /// Removes the summary (Delete data, receiver details off). Never throws.
  Future<bool> clear() => _serial(() async {
        try {
          final p = await _prefs();
          if (!p.containsKey(kHistSummaryPrefKey)) return true;
          return await p.remove(kHistSummaryPrefKey);
        } catch (_) {
          return false;
        }
      });
}
