// CA10 (mmogo 0.1.2, Judge C-A10): a restore never writes the two locked
// built-ins (Withdrawal, Airtime). Their name, active flag and date stay as
// the phone has them; the file's values are ignored; they are never parked.
// The validator is NOT changed: a file that renames or deactivates them is
// still accepted. Real in-memory v3 database; invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_writer.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

RestoreService svc(Database db) => RestoreService(
      db: () async => db,
      backup: backupOf(db),
      safety: FakeSafetyCopyStore([]),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      validateInIsolate: false,
    );

const String _withdrawal = 'AGENT_WITHDRAWAL:cash_withdrawal';
const String _airtime = 'AIRTIME:airtime';

/// id|name|active|created_at|seed_key of the two locked rows.
Future<List<String>> lockedRows(DatabaseExecutor db) async => [
      for (final r in await db.rawQuery(
          'SELECT id, name, active, created_at, seed_key FROM classifications '
          'WHERE seed_key IN (?, ?) ORDER BY id',
          [_withdrawal, _airtime]))
        r.values.join('|'),
    ];

Future<String> oneRow(DatabaseExecutor db, String seedKey) async => (await db.rawQuery(
        'SELECT name, active, created_at FROM classifications WHERE seed_key = ?', [seedKey]))
    .first
    .values
    .join('|');

Future<int> classCount(DatabaseExecutor db) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM classifications')).first['n']! as int;

/// A schema 3 file whose two locked rows are renamed, deactivated and given
/// another date; Rent and Shopping are changed too (those must still follow the
/// file). File ids follow [seedRowsV3]: 2 = SEND_MONEY:rent, 13 = Withdrawal,
/// 14 = Airtime.
List<Map<String, Object?>> hostileRows() => [
      for (final r in seedRowsV3(renamed: {
        'SEND_MONEY:rent': 'Landlord',
        _withdrawal: 'Cash out',
        _airtime: 'Top up',
      }))
        if (r['seed_key'] == _withdrawal || r['seed_key'] == _airtime)
          {...r, 'active': 0, 'created_at': f0 + 777}
        else if (r['seed_key'] == 'BUY_GOODS:groceries')
          {...r, 'active': 0}
        else
          r,
    ];

List<Map<String, Object?>> hostileTxs() => [
      tx(1, 'CASH-20260101-0101', 'CASH', 13, createdAt: f0 + 1),
      tx(2, 'CASH-20260101-0102', 'CASH', 14, createdAt: f0 + 2),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the locked keys are exactly Withdrawal and Airtime, and both are real built-ins', () {
    expect(kBackupLockedSeedKeys, {_withdrawal, _airtime});
    final seeds = [for (final s in AppSchema.seedClassifications) s.seedKey];
    expect(seeds, containsAll(kBackupLockedSeedKeys));
    expect(kBackupSeedKeys, containsAll(kBackupLockedSeedKeys));
  });

  test('the validator still ACCEPTS a file that renames and deactivates them (C-A10: no validator rule)', () {
    final bytes = fileBytes(fileJson(classes: hostileRows(), txs: hostileTxs(), schemaVersion: 3));
    final file = BackupValidator.validate(bytes);
    final w = file.classifications.firstWhere((r) => r['seed_key'] == _withdrawal);
    expect(w['name'], 'Cash out');
    expect(w['active'], 0);
  });

  test('replace_ignores_the_files_name_active_and_date_for_the_two_locked_seeds', () async {
    final db = await openTestDb();
    await populate(db);
    final before = await lockedRows(db);
    expect(before, hasLength(2));
    final bytes = fileBytes(fileJson(classes: hostileRows(), txs: hostileTxs(), schemaVersion: 3));

    await svc(db).restore(bytes, RestoreMode.replace);

    expect(await lockedRows(db), before, reason: 'ids, names, active and dates all unchanged');
    expect(await oneRow(db, _withdrawal), startsWith('Withdrawal|1|'));
    expect(await oneRow(db, _airtime), startsWith('Airtime|1|'));
    // Transactions pointing at them keep a valid classification_id: the phone's own rows.
    final onLocked = [
      for (final x in await db.rawQuery(
          'SELECT c.seed_key FROM transactions t JOIN classifications c '
          'ON c.id = t.classification_id ORDER BY t.id'))
        x['seed_key'],
    ];
    expect(onLocked, [_withdrawal, _airtime]);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test('replace_other_seeds_still_follow_the_file', () async {
    final db = await openTestDb();
    await populate(db);
    final bytes = fileBytes(fileJson(classes: hostileRows(), schemaVersion: 3));
    final r = await svc(db).restore(bytes, RestoreMode.replace);
    expect(await oneRow(db, 'SEND_MONEY:rent'), startsWith('Landlord|1|'));
    expect(await oneRow(db, 'BUY_GOODS:groceries'), startsWith('Groceries|0|'));
    expect(await oneRow(db, 'SEND_MONEY:family_friends'), startsWith('Family/Friends|1|'));
    expect(r.classifications, const TableCounts(added: 0, skipped: 17));
    expect(r.tally.builtInsUpdated, 15, reason: '17 named, 2 locked and not written');
    await db.close();
  });

  test('replace_never_parks_or_writes_a_locked_seed_not_even_for_a_moment (statement log)', () async {
    final log = <Stmt>[];
    final db = await openTestDb(log: log);
    await populate(db);
    log.clear();
    final bytes = fileBytes(fileJson(classes: hostileRows(), schemaVersion: 3));
    await svc(db).restore(bytes, RestoreMode.replace);
    final touching = [
      for (final s in log)
        if (s.isWrite && '${s.args}'.contains(':cash_withdrawal') || s.isWrite && '${s.args}'.contains(':airtime')) s,
    ];
    expect(touching, isEmpty, reason: 'no write statement names a locked seed key');
    // Control: the other seeds ARE written with their seed key.
    expect(log.where((s) => s.isWrite && '${s.args}'.contains('SEND_MONEY:rent')), isNotEmpty);
    await db.close();
  });

  test('replace_of_a_schema_2_file_leaves_the_locked_seeds_untouched', () async {
    final db = await openTestDb();
    await populate(db);
    final before = await lockedRows(db);
    final bytes = fileBytes(fileJson(classes: seedRows(renamed: {'SEND_MONEY:rent': 'Landlord'})));
    await svc(db).restore(bytes, RestoreMode.replace);
    expect(await lockedRows(db), before);
    await db.close();
  });

  test('merge_never_changes_the_locked_seeds', () async {
    final db = await openTestDb();
    await populate(db);
    final before = await lockedRows(db);
    final bytes = fileBytes(fileJson(classes: hostileRows(), txs: hostileTxs(), schemaVersion: 3));
    await svc(db).restore(bytes, RestoreMode.merge);
    expect(await lockedRows(db), before);
    // And merge does not change the other seeds either (existing rule).
    expect(await oneRow(db, 'SEND_MONEY:rent'), startsWith('Landlord|1|'),
        reason: 'populate() renamed it to Landlord; merge leaves the phone as it is');
    final onLocked = [
      for (final x in await db.rawQuery(
          'SELECT c.seed_key FROM transactions t JOIN classifications c '
          'ON c.id = t.classification_id WHERE c.seed_key IN (?, ?) ORDER BY t.id',
          [_withdrawal, _airtime]))
        x['seed_key'],
    ];
    expect(onLocked, [_withdrawal, _airtime]);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  group('name clash on the locked names', () {
    // The unique index is (group_id, name) WHERE active = 1: it is scoped to a
    // group, and each locked group holds only its own built-in. So the only row
    // that can ask for "Withdrawal" / "Airtime" in that group is a USER row,
    // and the plan maps it onto the locked built-in (same group and name).
    test('a user row named Withdrawal / Airtime next to a renamed locked seed folds onto the locked seed, no crash',
        () async {
      for (final mode in RestoreMode.values) {
        final db = await openTestDb();
        final before = await lockedRows(db);
        final rows = [
          ...hostileRows(),
          cls(30, 'AGENT_WITHDRAWAL', 'Withdrawal'),
          cls(31, 'AIRTIME', 'Airtime'),
        ];
        final bytes = fileBytes(fileJson(
            classes: rows,
            txs: [tx(1, 'CASH-20260101-0101', 'CASH', 30), tx(2, 'CASH-20260101-0102', 'CASH', 31)],
            schemaVersion: 3));
        await svc(db).restore(bytes, mode);
        expect(await lockedRows(db), before, reason: mode.name);
        expect(await classCount(db), 17, reason: '${mode.name}: the user rows folded onto the built-ins');
        final onLocked = [
          for (final x in await db.rawQuery(
              'SELECT c.seed_key FROM transactions t JOIN classifications c '
              'ON c.id = t.classification_id ORDER BY t.id'))
            x['seed_key'],
        ];
        expect(onLocked, [_withdrawal, _airtime], reason: mode.name);
        await db.close();
      }
    });

    test('writer path with the validator bypassed: a different seed forced to the name Withdrawal cannot clash; locked rows stay',
        () async {
      final db = await openTestDb();
      await populate(db);
      final before = await lockedRows(db);
      final rows = hostileRows();
      final rent = rows.firstWhere((r) => r['seed_key'] == 'SEND_MONEY:rent');
      rent['name'] = 'Withdrawal';
      final file = unvalidated(fileJson(classes: rows, schemaVersion: 3), schemaVersion: 3);
      await db.transaction((txn) => const RestoreWriter().replace(txn, file));
      expect(await lockedRows(db), before);
      expect(await oneRow(db, 'SEND_MONEY:rent'), startsWith('Withdrawal|1|'),
          reason: 'a different group: the (group, name) index is not violated');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    });

    test('a failure after the built-in phase rolls the whole restore back and the locked rows are intact', () async {
      final db = await openTestDb();
      await populate(db);
      final before = await fullDump(db);
      final writer = RestoreWriter(beforeRow: (table, i) {
        if (table == 'transactions') throw StateError('injected');
      });
      final s = RestoreService(
        db: () async => db,
        backup: backupOf(db),
        safety: FakeSafetyCopyStore([]),
        settings: BackupSettings(prefs: SharedPreferences.getInstance),
        writer: writer,
        validateInIsolate: false,
      );
      final bytes = fileBytes(fileJson(classes: hostileRows(), txs: hostileTxs(), schemaVersion: 3));
      await expectLater(s.restore(bytes, RestoreMode.replace), throwsA(isA<RestoreFailed>()));
      expect(await fullDump(db), before);
      await db.close();
    });
  });
}
