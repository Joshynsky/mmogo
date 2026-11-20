import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/linked_cash_dao.dart';
import 'backup_limits.dart' show kBackupLockedSeedKeys;
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
  'agent_number', 'classification_id', 'raw_parse_source',
  'transaction_occurred_at', 'created_at', 'deleted_at',
  // 0.2.1 (appended): the link to the withdrawal (a NEW id, re-mapped) and the decision.
  'parent_transaction_id', 'cash_only_decided',
  // 0.2.1 (appended): the auto-record marker (0 for a file without the key).
  'recorded_automatically',
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
    'paybill_account_number, agent_number, classification_id, raw_parse_source, '
    'transaction_occurred_at, created_at, deleted_at, '
    'parent_transaction_id, cash_only_decided, recorded_automatically) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)';
const String _insertMapSql =
    'INSERT INTO counterparty_classification_map (source_type, '
    'counterparty_key, classification_id, auto_apply, updated_at) '
    'VALUES (?, ?, ?, ?, ?)';
const String _insertFulizaSql =
    'INSERT INTO fuliza_events (kind, code, occurred_at, amount_cents, '
    'fee_cents, printed_total_cents) VALUES (?, ?, ?, ?, ?, ?)';
const String _deleteFulizaSql = 'DELETE FROM fuliza_events';
const String _countFulizaSql = 'SELECT COUNT(*) AS n FROM fuliza_events';
const String _deleteMapSql = 'DELETE FROM counterparty_classification_map';
const String _deleteTxSql = 'DELETE FROM transactions';
const String _deleteUserClassesSql = 'DELETE FROM classifications WHERE seed_key IS NULL';
const String _parkSeedSql = 'UPDATE classifications SET active = 0 WHERE seed_key = ?';
const String _setSeedSql =
    'UPDATE classifications SET name = ?, active = ?, created_at = ? WHERE seed_key = ?';
const String _countLiveTxSql =
    'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL';
const String _countClassesSql = 'SELECT COUNT(*) AS n FROM classifications';
const String _countSeedClassesSql =
    'SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NOT NULL';
const String _countOneSeedSql =
    'SELECT COUNT(*) AS n FROM classifications WHERE seed_key = ?';
const String _countMapSql = 'SELECT COUNT(*) AS n FROM counterparty_classification_map';
const String _findWithdrawalSql =
    'SELECT id, amount_cents, transaction_occurred_at, cash_only_decided FROM transactions '
    "WHERE display_code = ? AND source_type = 'AGENT_WITHDRAWAL' AND deleted_at IS NULL "
    'ORDER BY id LIMIT 1';
const String _fkCheckSql = 'PRAGMA foreign_key_check';

/// Rows a replace expects to find when its transaction opens (the counts of
/// the safety copy). Different = the data changed meanwhile.
class ExpectedRows {
  const ExpectedRows({
    required this.transactions,
    required this.classifications,
    required this.counterpartyMap,
    this.fulizaEvents,
  });
  final int transactions;
  final int classifications;
  final int counterpartyMap;

  /// Fuliza events the phone must hold when the transaction opens; null = not
  /// checked (only a hand-built value in a test; the service always sets it).
  final int? fulizaEvents;
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
          await _count(txn, _countMapSql) != expect.counterpartyMap ||
          (expect.fulizaEvents != null &&
              await _count(txn, _countFulizaSql) != expect.fulizaEvents)) {
        throw const RestoreDataChanged();
      }
    }
    // C3 (PM choice A): a file WITHOUT a Fuliza section (schema < 4) leaves the
    // phone's Fuliza events and limit alone; only a schema >= 4 file replaces them.
    final fulizaBefore = await _count(txn, _countFulizaSql);
    // Dependency order: nothing references the map; transactions reference
    // classifications (RESTRICT), so they go before the user classifications.
    await txn.rawDelete(_deleteMapSql);
    await txn.rawDelete(_deleteTxSql); // includes recently deleted rows
    await txn.rawDelete(_deleteUserClassesSql);
    if (file.hasFulizaSection) await txn.rawDelete(_deleteFulizaSql);

    // Built-ins: two phases so a name swap between two of them can never trip
    // idx_classifications_active_name. Phase 1 parks every built-in the file
    // names as inactive (inactive rows are outside that index); phase 2 sets
    // the file's values.
    final seeds = [
      for (final r in file.classifications)
        if (r['seed_key'] != null) r,
    ];
    // C-A10: the two locked built-ins (Withdrawal, Airtime) are never parked and
    // never written: the file's name, active flag and date for them are
    // ignored. They must still exist on this phone.
    final writable = [
      for (final r in seeds)
        if (!kBackupLockedSeedKeys.contains(r['seed_key'])) r,
    ];
    for (final r in seeds) {
      if (kBackupLockedSeedKeys.contains(r['seed_key']) &&
          await _countSeed(txn, r['seed_key']! as String) != 1) {
        throw StateError('built-in missing on this phone');
      }
    }
    for (final r in writable) {
      if (await txn.rawUpdate(_parkSeedSql, [r['seed_key']]) != 1) {
        throw StateError('built-in missing on this phone');
      }
    }
    for (final r in writable) {
      await txn.rawUpdate(_setSeedSql, [r['name'], r['active'], r['created_at'], r['seed_key']]);
    }

    final lookups = await RestoreLookups.load(txn);
    final plan = RestorePlan.build(file, lookups);
    final tally = await _apply(txn, file, plan, lookups,
        builtInsUpdated: writable.length, fulizaLeftAlone: !file.hasFulizaSection);
    await _postCheck(txn, file, tally);
    // The file's counts are not the phone's counts any more: saved receivers
    // that combine into one (C-A5) make the map smaller than the file, and a
    // built-in the file does not name (a version-2 file has 12 of the 17) stays
    // on the phone. So the phone must hold exactly what the plan wrote.
    if (await _count(txn, _countLiveTxSql) != file.transactions.length ||
        await _count(txn, _countMapSql) != plan.newMapRows.length) {
      throw StateError('replace row counts do not match the file');
    }
    // The Fuliza table holds exactly the file's events (schema >= 4), or is
    // exactly as it was (older file).
    final fulizaExpected = file.hasFulizaSection ? file.fulizaEvents.length : fulizaBefore;
    if (await _count(txn, _countFulizaSql) != fulizaExpected) {
      throw StateError('replace Fuliza count does not match');
    }
    final dbSeeds = await _count(txn, _countSeedClassesSql);
    final expectedClasses = expectedReplaceClassCount(
      fileClassifications: file.classifications.length,
      dbSeedRows: dbSeeds,
      fileSeedRows: seeds.length,
      mergedIntoExisting: plan.classSkipped - seeds.length,
    );
    if (await _count(txn, _countClassesSql) != expectedClasses) {
      throw StateError('replace classification count does not match the file');
    }
    return tally;
  }

  /// BK3: what `COUNT(classifications)` must be after a Replace. The file's
  /// classification count, plus the built-ins this phone has that the file does
  /// not name (a schema 2 file names 12 of the 17), minus the file's user rows
  /// that landed on an existing row of the same group and name instead of
  /// being inserted. Comparing with the file's count alone would roll back
  /// every Replace of an older file.
  @visibleForTesting
  static int expectedReplaceClassCount({
    required int fileClassifications,
    required int dbSeedRows,
    required int fileSeedRows,
    required int mergedIntoExisting,
  }) =>
      fileClassifications + (dbSeedRows - fileSeedRows) - mergedIntoExisting;

  Future<RestoreTally> _apply(
    Transaction txn,
    ValidatedBackup file,
    RestorePlan plan,
    RestoreLookups lookups, {
    int builtInsUpdated = 0,
    bool fulizaLeftAlone = false,
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
    await _insertTransactions(txn, plan.newTransactions, file.transactions, dbClassId);

    // 3. learned receivers.
    await _insertAll(txn, 'counterparty_map', _insertMapSql, plan.newMapRows, (r) => [
          r['source_type'], r['counterparty_key'],
          dbClassId(r['classification']), r['auto_apply'], r['updated_at'],
        ]);

    // 4. Fuliza events (already filtered against what is stored).
    await _insertAll(txn, 'fuliza_events', _insertFulizaSql, plan.newFulizaEvents, (r) => [
          r['kind'], r['code'], r['occurred_at'], r['amount_cents'],
          r['fee_cents'], r['printed_total_cents'],
        ]);

    return RestoreTally(
      classifications: TableCounts(added: classes.length, skipped: plan.classSkipped),
      transactions: TableCounts(added: plan.newTransactions.length, skipped: plan.txSkipped),
      counterpartyMap: TableCounts(added: plan.newMapRows.length, skipped: plan.mapSkipped),
      builtInsUpdated: builtInsUpdated,
      fulizaEvents: TableCounts(
          added: plan.newFulizaEvents.length, skipped: plan.fulizaSkipped),
      fulizaLeftAlone: fulizaLeftAlone,
    );
  }

  /// Transactions in two passes so a linked Cash entry gets its withdrawal's NEW id:
  /// first every row that is not a child of a row inserted by this restore (ids kept),
  /// then the children. A child whose withdrawal was skipped (it was already on this phone)
  /// is inserted as plain Cash, EXCEPT when it can be re-linked to the phone's own copy of that
  /// withdrawal (see [_relinkTargets]). File order is kept inside each pass.
  Future<void> _insertTransactions(
    Transaction txn,
    List<Map<String, Object?>> rows,
    List<Map<String, Object?>> fileRows,
    int Function(Object? fileId) dbClassId,
  ) async {
    final inFile = {for (final r in rows) r['id']};
    bool isChild(Map<String, Object?> r) => r['parent_id'] != null && inFile.contains(r['parent_id']);
    final first = [for (final r in rows) if (!isChild(r)) r];
    final second = [for (final r in rows) if (isChild(r)) r];
    final relink = await _relinkTargets(txn, rows, fileRows, inFile);
    final newIdByFileId = <Object?, int>{};
    var index = 0;
    for (final pass in [first, second]) {
      for (var start = 0; start < pass.length; start += chunkSize) {
        final batch = txn.batch();
        final end = _end(start, pass.length);
        for (var i = start; i < end; i++) {
          beforeRow?.call('transactions', index++);
          final r = pass[i];
          batch.rawInsert(_insertTxSql, [
            r['display_code'], r['source_type'], r['amount_cents'],
            r['transaction_cost_cents'], r['counterparty_label'],
            r['counterparty_phone'], r['paybill_account_number'],
            r['agent_number'], dbClassId(r['classification']), r['raw_parse_source'],
            r['transaction_occurred_at'], r['created_at'],
            isChild(r) ? newIdByFileId[r['parent_id']] : relink[r['id']],
            r['cash_only_decided'] ?? 0,
            r['recorded_auto'] ?? 0,
          ]);
        }
        final ids = await batch.commit(noResult: false, continueOnError: false);
        for (var i = start; i < end; i++) {
          newIdByFileId[pass[i]['id']] = ids[i - start]! as int;
        }
      }
    }
  }

  /// MERGE re-link: a Cash row about to be inserted whose withdrawal was skipped because the phone
  /// already has it gets that withdrawal's id, when the phone's row is a live AGENT_WITHDRAWAL, the
  /// entry is on the same (local) day, and the phone's live entries plus the entries already
  /// re-linked to it in this restore (file order) plus this one stay within its amount. Otherwise
  /// the entry stays plain Cash. Only reads; the result maps file row id -> phone withdrawal id.
  Future<Map<Object?, int>> _relinkTargets(
    Transaction txn,
    List<Map<String, Object?>> rows,
    List<Map<String, Object?>> fileRows,
    Set<Object?> insertedFileIds,
  ) async {
    final result = <Object?, int>{};
    final fileById = {for (final r in fileRows) r['id']: r};
    final left = <int, int>{}; // phone withdrawal id -> cents still free
    final misses = <Object?>{}; // file parent ids with no usable phone withdrawal
    final found = <Object?, ({int id, int amount, int at})>{};
    for (final r in rows) {
      final pid = r['parent_id'];
      if (pid == null || insertedFileIds.contains(pid) || misses.contains(pid)) continue;
      if (r['source_type'] != 'CASH') continue;
      var w = found[pid];
      if (w == null) {
        final parent = fileById[pid];
        if (parent == null || parent['source_type'] != 'AGENT_WITHDRAWAL') {
          misses.add(pid);
          continue;
        }
        final hit = await txn.rawQuery(_findWithdrawalSql, [parent['display_code']]);
        if (hit.isEmpty || hit.first['cash_only_decided'] == 1) {
          misses.add(pid);
          continue;
        }
        w = (
          id: hit.first['id']! as int,
          amount: (hit.first['amount_cents']! as num).toInt(),
          at: (hit.first['transaction_occurred_at']! as num).toInt(),
        );
        found[pid] = w;
        left[w.id] = await LinkedCashDao.remainingCents(txn, w.id);
      }
      final amount = r['amount_cents'];
      final at = r['transaction_occurred_at'];
      if (amount is! int || at is! int || amount <= 0 || amount > left[w.id]!) continue;
      final a = DateTime.fromMillisecondsSinceEpoch(at);
      final b = DateTime.fromMillisecondsSinceEpoch(w.at);
      if (a.year != b.year || a.month != b.month || a.day != b.day) continue;
      left[w.id] = left[w.id]! - amount;
      result[r['id']] = w.id;
    }
    return result;
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
        t.counterpartyMap.total != file.counterpartyMap.length ||
        t.fulizaEvents.total != file.fulizaEvents.length) {
      throw StateError('added + skipped does not equal the file counts');
    }
  }

  static int _end(int start, int length) =>
      start + chunkSize < length ? start + chunkSize : length;

  static Future<int> _countSeed(DatabaseExecutor ex, String seedKey) async =>
      (await ex.rawQuery(_countOneSeedSql, [seedKey])).first['n'] as int? ?? 0;

  static Future<int> _count(DatabaseExecutor ex, String sql) async =>
      (await ex.rawQuery(sql)).first['n'] as int? ?? 0;
}
