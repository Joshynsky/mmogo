import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_validator.dart';
import 'restore_plan.dart';
import 'restore_types.dart';

/// Columns each restore INSERT writes, in order. Const: the file's keys are
/// never used as column or table names. The SQL below spells exactly these.
const List<String> kRestoreClassColumns = [
  'group_id', 'name', 'active', 'created_at', 'seed_key',
];
const List<String> kRestoreTxColumns = [
  'display_code', 'source_type', 'amount_cents', 'transaction_cost_cents',
  'counterparty_label', 'counterparty_phone', 'paybill_account_number',
  'classification_id', 'raw_parse_source', 'transaction_occurred_at',
  'created_at', 'deleted_at',
];
const List<String> kRestoreMapColumns = [
  'source_type', 'counterparty_key', 'classification_id', 'auto_apply', 'updated_at',
];

// Every statement is a const string; values only ever travel as `?` args.
const String _insertClassSql =
    'INSERT INTO classifications (group_id, name, active, created_at, seed_key) '
    'VALUES (?, ?, ?, ?, NULL)';
const String _insertTxSql =
    'INSERT INTO transactions (display_code, source_type, amount_cents, '
    'transaction_cost_cents, counterparty_label, counterparty_phone, '
    'paybill_account_number, classification_id, raw_parse_source, '
    'transaction_occurred_at, created_at, deleted_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)';
const String _insertMapSql =
    'INSERT INTO counterparty_classification_map (source_type, '
    'counterparty_key, classification_id, auto_apply, updated_at) '
    'VALUES (?, ?, ?, ?, ?)';
const String _deleteMapSql = 'DELETE FROM counterparty_classification_map';
const String _deleteTxSql = 'DELETE FROM transactions';
const String _deleteUserClassesSql = 'DELETE FROM classifications WHERE seed_key IS NULL';
const String _parkSeedSql = 'UPDATE classifications SET active = 0 WHERE seed_key = ?';
const String _setSeedSql =
    'UPDATE classifications SET name = ?, active = ?, created_at = ? WHERE seed_key = ?';
const String _countLiveTxSql =
    'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL';
const String _countClassesSql = 'SELECT COUNT(*) AS n FROM classifications';
const String _countMapSql = 'SELECT COUNT(*) AS n FROM counterparty_classification_map';
const String _fkCheckSql = 'PRAGMA foreign_key_check';

/// Rows a replace expects to find when its transaction opens (the counts of
/// the safety copy). Different = the data changed meanwhile.
class ExpectedRows {
  const ExpectedRows({
    required this.transactions,
    required this.classifications,
    required this.counterpartyMap,
  });
  final int transactions;
  final int classifications;
  final int counterpartyMap;
}

/// Thrown inside the transaction when the phone's rows differ from the safety
/// copy's counts; it rolls the transaction back.
class RestoreDataChanged implements Exception {
  const RestoreDataChanged();
}

/// Restore Stage 2: writes a VALIDATED file inside a transaction the caller
/// opened (`RestoreService` opens exactly one). It never opens its own
/// transaction and never catches: any error propagates and the caller's
/// transaction rolls back, leaving the database untouched.
///
/// Order: classifications, then transactions, then learned receivers. Fresh
/// ids always come from AUTOINCREMENT; a file id is never written. Inserts go
/// in chunked batches (500 rows, `continueOnError: false`).
class RestoreWriter {
  const RestoreWriter({this.beforeRow});

  /// TEST ONLY: called before each row is queued (table, index in that
  /// table's insert list). A throw here proves the whole restore rolls back.
  @visibleForTesting
  final void Function(String table, int index)? beforeRow;

  static const int chunkSize = 500;

  /// MERGE: adds what is new; never issues UPDATE or DELETE.
  Future<RestoreTally> merge(Transaction txn, ValidatedBackup file) async {
    final lookups = await RestoreLookups.load(txn);
    final plan = RestorePlan.build(file, lookups);
    final tally = await _apply(txn, file, plan, lookups);
    await _postCheck(txn, file, tally);
    return tally;
  }

  /// REPLACE: clears this phone's entries, learned receivers and user-made
  /// classifications (built-ins are kept), gives the built-ins the file's
  /// name, active flag and date, then inserts the file's rows.
  Future<RestoreTally> replace(
    Transaction txn,
    ValidatedBackup file, {
    ExpectedRows? expect,
  }) async {
    if (expect != null) {
      if (await _count(txn, _countLiveTxSql) != expect.transactions ||
          await _count(txn, _countClassesSql) != expect.classifications ||
          await _count(txn, _countMapSql) != expect.counterpartyMap) {
        throw const RestoreDataChanged();
      }
    }
    // Dependency order: nothing references the map; transactions reference
    // classifications (RESTRICT), so they go before the user classifications.
    await txn.rawDelete(_deleteMapSql);
    await txn.rawDelete(_deleteTxSql); // includes recently deleted rows
    await txn.rawDelete(_deleteUserClassesSql);

    // Built-ins: two phases so a name swap between two of them can never trip
    // idx_classifications_active_name. Phase 1 parks every built-in the file
    // names as inactive (inactive rows are outside that index); phase 2 sets
    // the file's values.
    final seeds = [
      for (final r in file.classifications)
        if (r['seed_key'] != null) r,
    ];
    for (final r in seeds) {
      if (await txn.rawUpdate(_parkSeedSql, [r['seed_key']]) != 1) {
        throw StateError('built-in missing on this phone');
      }
    }
    for (final r in seeds) {
      await txn.rawUpdate(_setSeedSql, [r['name'], r['active'], r['created_at'], r['seed_key']]);
    }

    final lookups = await RestoreLookups.load(txn);
    final plan = RestorePlan.build(file, lookups);
    final tally = await _apply(txn, file, plan, lookups, builtInsUpdated: seeds.length);
    await _postCheck(txn, file, tally);
    if (await _count(txn, _countLiveTxSql) != file.transactions.length ||
        await _count(txn, _countMapSql) != file.counterpartyMap.length) {
      throw StateError('replace row counts do not match the file');
    }
    return tally;
  }

  Future<RestoreTally> _apply(
    Transaction txn,
    ValidatedBackup file,
    RestorePlan plan,
    RestoreLookups lookups, {
    int builtInsUpdated = 0,
  }) async {
    // 1. classifications (ids needed, so results are kept).
    final newIds = <int>[];
    final classes = plan.newClassifications;
    for (var start = 0; start < classes.length; start += chunkSize) {
      final batch = txn.batch();
      final end = _end(start, classes.length);
      for (var i = start; i < end; i++) {
        beforeRow?.call('classifications', i);
        final r = classes[i];
        final groupId = lookups.groupIdByCode[r['group']];
        if (groupId == null) throw StateError('unknown group');
        batch.rawInsert(_insertClassSql, [groupId, r['name'], r['active'], r['created_at']]);
      }
      for (final id in await batch.commit(noResult: false, continueOnError: false)) {
        newIds.add(id! as int);
      }
    }
    int dbClassId(Object? fileId) {
      final t = plan.classTargets[fileId];
      if (t == null) throw StateError('dangling classification');
      return t.dbId ?? newIds[t.pending!];
    }

    // 2. transactions, always live (deleted_at NULL).
    await _insertAll(txn, 'transactions', _insertTxSql, plan.newTransactions, (r) => [
          r['display_code'], r['source_type'], r['amount_cents'],
          r['transaction_cost_cents'], r['counterparty_label'],
          r['counterparty_phone'], r['paybill_account_number'],
          dbClassId(r['classification']), r['raw_parse_source'],
          r['transaction_occurred_at'], r['created_at'],
        ]);

    // 3. learned receivers.
    await _insertAll(txn, 'counterparty_map', _insertMapSql, plan.newMapRows, (r) => [
          r['source_type'], r['counterparty_key'],
          dbClassId(r['classification']), r['auto_apply'], r['updated_at'],
        ]);

    return RestoreTally(
      classifications: TableCounts(added: classes.length, skipped: plan.classSkipped),
      transactions: TableCounts(added: plan.newTransactions.length, skipped: plan.txSkipped),
      counterpartyMap: TableCounts(added: plan.newMapRows.length, skipped: plan.mapSkipped),
      builtInsUpdated: builtInsUpdated,
    );
  }

  Future<void> _insertAll(
    Transaction txn,
    String table,
    String sql,
    List<Map<String, Object?>> rows,
    List<Object?> Function(Map<String, Object?> row) args,
  ) async {
    for (var start = 0; start < rows.length; start += chunkSize) {
      final batch = txn.batch();
      final end = _end(start, rows.length);
      for (var i = start; i < end; i++) {
        beforeRow?.call(table, i);
        batch.rawInsert(sql, args(rows[i]));
      }
      await batch.commit(noResult: true, continueOnError: false);
    }
  }

  /// Last assertions INSIDE the transaction; a throw rolls everything back.
  Future<void> _postCheck(Transaction txn, ValidatedBackup file, RestoreTally t) async {
    if ((await txn.rawQuery(_fkCheckSql)).isNotEmpty) {
      throw StateError('foreign_key_check reported rows');
    }
    if (t.classifications.total != file.classifications.length ||
        t.transactions.total != file.transactions.length ||
        t.counterpartyMap.total != file.counterpartyMap.length) {
      throw StateError('added + skipped does not equal the file counts');
    }
  }

  static int _end(int start, int length) =>
      start + chunkSize < length ? start + chunkSize : length;

  static Future<int> _count(DatabaseExecutor ex, String sql) async =>
      (await ex.rawQuery(sql)).first['n'] as int? ?? 0;
}
