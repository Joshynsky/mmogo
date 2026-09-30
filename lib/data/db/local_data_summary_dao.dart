import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T17 — Profile's "Local data summary" card: aggregates only, never any
/// per-row detail (aggregate counts only —
/// COUNT(*), MIN/MAX(transaction_occurred_at) — no per-row detail).
class LocalDataSummary {
  const LocalDataSummary({
    required this.transactionCount,
    required this.earliestOccurredAt,
    required this.latestOccurredAt,
  });

  final int transactionCount;

  /// Both `null` exactly when [transactionCount] is 0 (SQLite's `MIN`/`MAX`
  /// over zero rows is `NULL`) — Profile then shows "No data yet".
  final DateTime? earliestOccurredAt;
  final DateTime? latestOccurredAt;

  bool get isEmpty => transactionCount == 0;
}

/// Profile's own query layer — same raw-SQL-against-`AppDatabase` idiom,
/// one DAO file per screen's own real read needs, as
/// `recently_deleted_dao.dart`/`export_dao.dart`/`home_dashboard_dao.dart`
/// already establish.
class LocalDataSummaryDao {
  LocalDataSummaryDao._();

  /// Active (`deleted_at IS NULL`) transactions only — the same filter every
  /// other read in this codebase applies, so Profile's count always agrees
  /// with what Home/Analytics/Export show (a soft-deleted row sitting in its
  /// 1-hour Recently Deleted grace window is NOT counted here).
  static Future<LocalDataSummary> summary(Database db) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS tx_count,
             MIN(transaction_occurred_at) AS min_occurred_at,
             MAX(transaction_occurred_at) AS max_occurred_at
      FROM transactions
      WHERE deleted_at IS NULL
    ''');
    final row = rows.first;
    final minMs = row['min_occurred_at'] as int?;
    final maxMs = row['max_occurred_at'] as int?;
    return LocalDataSummary(
      transactionCount: (row['tx_count'] as num).toInt(),
      earliestOccurredAt: minMs == null ? null : DateTime.fromMillisecondsSinceEpoch(minMs),
      latestOccurredAt: maxMs == null ? null : DateTime.fromMillisecondsSinceEpoch(maxMs),
    );
  }

  /// "Storage used (est.)" — the on-disk size of the SQLite database file
  /// `db` was opened from (`Database.path`, i.e. exactly the path
  /// `AppDatabase` resolved — `getDatabasesPath()` on Android, the app
  /// documents directory on desktop), plus its `-wal` sidecar if one
  /// exists. Uses only `dart:io` — no new dependency/plugin.
  ///
  /// Returns `null` (Profile renders "—") whenever a size can't be
  /// determined — an in-memory database (tests), a missing file, a
  /// platform with no `dart:io` file access, or any I/O error — never
  /// throws. "est." because it's the file size, not a precise accounting
  /// of user data (includes seed rows, indexes, free pages).
  static Future<int?> databaseFileSizeBytes(Database db) async {
    try {
      final path = db.path;
      if (path == inMemoryDatabasePath || path.isEmpty) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      var total = await file.length();
      final wal = File('$path-wal');
      if (await wal.exists()) total += await wal.length();
      return total;
    } catch (_) {
      return null;
    }
  }
}
