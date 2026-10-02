import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Row counts shown on the Backup page ("A backup holds your N transactions,
/// ..."). Read-only; counts match what [BackupService.export] puts in the file
/// (live transactions, classifications the user made, saved receivers) and the
/// recently deleted ones it leaves out.
class BackupCounts {
  const BackupCounts({
    required this.transactions,
    required this.userClassifications,
    required this.receivers,
    required this.deletedLeftOut,
  });

  final int transactions;

  /// Classifications the user made (no `seed_key`).
  final int userClassifications;

  /// Rows of `counterparty_classification_map` (saved receivers).
  final int receivers;

  /// Soft-deleted transactions, not written to a backup.
  final int deletedLeftOut;

  /// Nothing worth backing up: no live transaction and no classification the
  /// user made.
  bool get isEmpty => transactions == 0 && userClassifications == 0;

  /// All four counts in ONE read transaction so they agree.
  static Future<BackupCounts> read(Database db) {
    return db.transaction((txn) async {
      Future<int> count(String sql) async => (await txn.rawQuery(sql)).first['n'] as int? ?? 0;
      return BackupCounts(
        transactions: await count('SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL'),
        userClassifications: await count('SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NULL'),
        receivers: await count('SELECT COUNT(*) AS n FROM counterparty_classification_map'),
        deletedLeftOut: await count('SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NOT NULL'),
      );
    });
  }
}
