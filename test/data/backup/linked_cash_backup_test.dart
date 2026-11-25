// 0.2.1: backup / restore of a withdrawal with linked Cash entries (schema 6: the optional
// row keys parent_id and cash_only_decided). Real in-memory sqlite; hand-built files for the
// reader side; invented data only.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/db/linked_cash_dao.dart';
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

Future<int> _w(Database db, String code, {int amount = 500000, int at = t0}) async => db.insert('transactions', {
      'display_code': code,
      'source_type': 'AGENT_WITHDRAWAL',
      'amount_cents': amount,
      'transaction_cost_cents': 3500,
      'counterparty_label': 'TEST AGENT',
      'agent_number': '123456',
      'classification_id': await seedId(db, 'AGENT_WITHDRAWAL:cash_withdrawal'),
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': at,
      'created_at': at,
    });

/// What the phone holds, as plain text a test can compare: code, amount, category, the CODE of the
/// parent, decided flag. (Ids differ between phones; the link is compared through the parent's code.)
Future<List<String>> _dump(DatabaseExecutor db) async => [
      for (final r in await db.rawQuery(
          'SELECT t.display_code AS code, t.source_type AS src, t.amount_cents AS amt, c.name AS cat, '
          'p.display_code AS parent, t.cash_only_decided AS dec FROM transactions t '
          'JOIN classifications c ON c.id = t.classification_id '
          'LEFT JOIN transactions p ON p.id = t.parent_transaction_id '
          'WHERE t.deleted_at IS NULL ORDER BY t.display_code, t.created_at'))
        r.values.join('|'),
    ];

/// A phone with two withdrawals: one with a full entry (Rent) and a part entry pair, one Cash only.
Future<Database> _phone() async {
  final db = await openTestDb();
  final rent = await seedId(db, 'SEND_MONEY:rent');
  final transport = await seedId(db, 'SEND_MONEY:transport');
  final w1 = await _w(db, 'WDR0000001');
  await LinkedCashDao.createLinkedCash(db, withdrawalId: w1, classificationId: rent, amountCents: 300000);
  await LinkedCashDao.createLinkedCash(db, withdrawalId: w1, classificationId: transport, amountCents: 100000);
  final w2 = await _w(db, 'WDR0000002', at: t0 + 60000);
  await LinkedCashDao.markCashOnly(db, withdrawalId: w2);
  await _w(db, 'WDR0000003', at: t0 + 120000); // undecided
  return db;
}

Map<String, Object?> _fileW(int id, {int amount = 500000}) => {
      ...tx(id, 'WDR${id.toString().padLeft(7, '0')}', 'AGENT_WITHDRAWAL', 13, amount: amount, createdAt: f0 + id),
      'transaction_cost_cents': 3500,
      'counterparty_label': 'TEST AGENT',
      'agent_number': '123456',
    };

Map<String, Object?> _fileCash(int id, {int? parent, int amount = 1000, Object? decided, String? code}) => {
      ...tx(id, code ?? 'CASH-20260101-01${id.toString().padLeft(2, '0')}', 'CASH', 2,
          amount: amount, createdAt: f0 + id),
      'parent_id': ?parent,
      'cash_only_decided': ?decided,
    };

List<Map<String, Object?>> _txs(Object json) => ((json as Map)['transactions']! as List).cast<Map<String, Object?>>();

Future<int> dbCount(DatabaseExecutor db, String where) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM transactions $where')).first['n']! as int;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('export', () {
    test('schema 6; a link and a decision are written, and ONLY when set (an unlinked row keeps its 13 keys)', () async {
      final db = await _phone();
      final export = await backupOf(db).export();
      expect(export.skippedCount, 0);
      final json = jsonDecode(utf8.decode(export.bytes)) as Map<String, Object?>;
      expect(json['schema_version'], 9);
      final rows = {for (final r in _txs(json)) r['display_code']! as String: r};
      final entries = _txs(json).where((r) => r['source_type'] == 'CASH').toList();
      expect(entries, hasLength(2));
      final w1Id = rows['WDR0000001']!['id'];
      for (final e in entries) {
        expect(e['parent_id'], w1Id);
        expect(e.containsKey('cash_only_decided'), isFalse);
      }
      expect(rows['WDR0000001']!.keys.toList(), kBackupTransactionKeys, reason: 'no link keys on the parent');
      expect(rows['WDR0000002']!['cash_only_decided'], 1);
      expect(rows['WDR0000002']!.containsKey('parent_id'), isFalse);
      expect(rows['WDR0000003']!.keys.toList(), kBackupTransactionKeys, reason: 'undecided: 13 keys as before');
      await db.close();
    });

    test('a file with no links is byte-identical in shape to a 0.2.0 one (13 keys on every row)', () async {
      final db = await openTestDb();
      await _w(db, 'WDR0000001');
      final json = jsonDecode(utf8.decode((await backupOf(db).export()).bytes)) as Map<String, Object?>;
      for (final r in _txs(json)) {
        expect(r.keys.toList(), kBackupTransactionKeys);
      }
      await db.close();
    });

    test('an entry whose withdrawal is not in the file (deleted) is exported as plain Cash, counted as repaired', () async {
      final db = await openTestDb();
      final w = await _w(db, 'WDR0000001');
      final id = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: await seedId(db, 'SEND_MONEY:rent'));
      // The withdrawal alone (the delete trigger would take the entry with it, so it is dropped to build this odd state).
      await db.execute('DROP TRIGGER trg_transactions_delete_pair');
      await db.update('transactions', {'deleted_at': t0}, where: 'id = ?', whereArgs: [w]);
      final export = await backupOf(db).export();
      expect(export.skippedCount, 0);
      expect(export.repairedCount, 1);
      final json = jsonDecode(utf8.decode(export.bytes)) as Map<String, Object?>;
      final rows = _txs(json);
      expect(rows, hasLength(1));
      expect(rows.single.containsKey('parent_id'), isFalse);
      expect(id, greaterThan(0));
      await db.close();
    });
  });

  group('round trip (export, then restore into another phone)', () {
    test('merge into an empty phone and replace onto a phone with other data: links re-mapped, same dump', () async {
      final a = await _phone();
      final file = await backupOf(a).exportToBytes();
      final want = await _dump(a);
      expect(want.where((l) => l.contains('|WDR0000001|')), hasLength(2));
      for (final mode in RestoreMode.values) {
        final b = await openTestDb();
        if (mode == RestoreMode.replace) {
          // other data that must disappear, taking ids out of step so a wrong id mapping would show
          for (var i = 0; i < 7; i++) {
            await addTx(b, code: 'OLD000000$i', source: 'SEND_MONEY', classId: await seedId(b, 'SEND_MONEY:rent'),
                label: 'T', phone: '0700000001');
          }
        }
        final result = await svc(b).restore(file, mode);
        expect(result.tally.transactions.added, 5, reason: mode.name);
        expect(await _dump(b), want, reason: mode.name);
        // the link points at a NEW id, never the file's id
        final fk = await b.rawQuery('PRAGMA foreign_key_check');
        expect(fk, isEmpty);
        await b.close();
      }
      await a.close();
    });

    test('merging the same file twice adds nothing the second time and keeps the first links', () async {
      final a = await _phone();
      final file = await backupOf(a).exportToBytes();
      final b = await openTestDb();
      await svc(b).restore(file, RestoreMode.merge);
      final once = await _dump(b);
      final second = await svc(b).restore(file, RestoreMode.merge);
      expect(second.tally.transactions.added, 0);
      expect(await _dump(b), once);
      await a.close();
      await b.close();
    });

    test('merge when the withdrawal is already on the phone (same amount and day): the entries re-link to the phone\'s withdrawal', () async {
      final a = await _phone();
      final file = await backupOf(a).exportToBytes();
      final b = await openTestDb();
      final wid = await _w(b, 'WDR0000001'); // the same message was already read here
      final result = await svc(b).restore(file, RestoreMode.merge);
      expect(result.tally.transactions.added, 4);
      expect(result.tally.transactions.skipped, 1);
      final dump = await _dump(b);
      expect(dump.where((l) => l.startsWith('CASH-')), hasLength(2));
      expect(dump.where((l) => l.startsWith('CASH-') && l.contains('|WDR0000001|')), hasLength(2));
      expect((await dbCount(b, 'WHERE parent_transaction_id = $wid')), 2);
      expect(await dbCount(b, "WHERE display_code = 'WDR0000001'"), 1, reason: 'no duplicate withdrawal');
      await a.close();
      await b.close();
    });
  });

  group('merge re-link to a withdrawal already on the phone', () {
    Future<List<Map<String, Object?>>> restoreInto(Database db, List<Map<String, Object?>> txs) async {
      final file = fileBytes(fileJson(classes: seedRowsV5(), txs: txs, schemaVersion: 6));
      final result = await svc(db).restore(file, RestoreMode.merge);
      expect(result.tally.transactions.total, txs.length);
      return db.rawQuery("SELECT display_code AS code, parent_transaction_id AS p FROM transactions "
          "WHERE source_type = 'CASH' ORDER BY id");
    }

    test('amount and day match: re-linked to the phone\'s withdrawal id', () async {
      final db = await openTestDb();
      final wid = await _w(db, 'WDR0000001');
      final rows = await restoreInto(db, [_fileW(1), _fileCash(2, parent: 1, amount: 200000)]);
      expect(rows.single['p'], wid);
      expect((await db.rawQuery('PRAGMA foreign_key_check')), isEmpty);
      await db.close();
    });

    test('a different day: plain Cash', () async {
      final db = await openTestDb();
      await _w(db, 'WDR0000001');
      final rows = await restoreInto(db, [
        _fileW(1),
        _fileCash(2, parent: 1, amount: 200000)..['transaction_occurred_at'] = f0 + 3 * 86400000,
      ]);
      expect(rows.single['p'], isNull);
      await db.close();
    });

    test('the sum would pass the withdrawal (phone already holds entries): plain Cash', () async {
      final db = await openTestDb();
      final wid = await _w(db, 'WDR0000001');
      await LinkedCashDao.createLinkedCash(db,
          withdrawalId: wid, classificationId: await seedId(db, 'SEND_MONEY:rent'), amountCents: 400000);
      final rows = await restoreInto(db, [_fileW(1), _fileCash(2, parent: 1, amount: 200000)]);
      expect(rows.where((r) => r['code'] == 'CASH-20260101-0102').single['p'], isNull);
      expect(await LinkedCashDao.remainingCents(db, wid), 100000);
      await db.close();
    });

    test('two incoming entries: the first fits and links, the second would pass and stays plain', () async {
      final db = await openTestDb();
      final wid = await _w(db, 'WDR0000001');
      final rows = await restoreInto(db, [
        _fileW(1),
        _fileCash(2, parent: 1, amount: 300000),
        _fileCash(3, parent: 1, amount: 300000),
      ]);
      expect(rows[0]['p'], wid);
      expect(rows[1]['p'], isNull);
      await db.close();
    });

    test('the entry is already on the phone: skipped, nothing added, nothing changed', () async {
      final db = await openTestDb();
      final wid = await _w(db, 'WDR0000001');
      final entry = _fileCash(2, parent: 1, amount: 200000);
      // the phone already holds this exact Cash row (same code and created_at), unlinked
      await db.insert('transactions', {
        'display_code': entry['display_code'],
        'source_type': 'CASH',
        'amount_cents': 200000,
        'classification_id': await seedId(db, 'SEND_MONEY:rent'),
        'raw_parse_source': 'MANUAL',
        'transaction_occurred_at': entry['transaction_occurred_at'],
        'created_at': entry['created_at'],
      });
      final rows = await restoreInto(db, [_fileW(1), entry]);
      expect(rows, hasLength(1));
      expect(rows.single['p'], isNull, reason: 'the existing row is not updated');
      expect(await dbCount(db, 'WHERE parent_transaction_id = $wid'), 0);
      await db.close();
    });

    test('a withdrawal on the phone marked Cash only: not re-linked, entry stays plain Cash', () async {
      final db = await openTestDb();
      final wid = await _w(db, 'WDR0000001');
      await LinkedCashDao.markCashOnly(db, withdrawalId: wid);
      final rows = await restoreInto(db, [_fileW(1), _fileCash(2, parent: 1, amount: 200000)]);
      expect(rows.single['p'], isNull);
      expect((await db.rawQuery('SELECT cash_only_decided AS d FROM transactions WHERE id = ?', [wid])).single['d'], 1);
      await db.close();
    });

    test('a withdrawal the phone holds only as recently deleted is not a target: plain Cash', () async {
      final db = await openTestDb();
      final wid = await _w(db, 'WDR0000001');
      await db.update('transactions', {'deleted_at': t0}, where: 'id = ?', whereArgs: [wid]);
      final rows = await restoreInto(db, [_fileW(1), _fileCash(2, parent: 1, amount: 200000)]);
      expect(rows.single['p'], isNot(wid));
      await db.close();
    });
  });

  group('an old (0.2.0, schema 5) backup', () {
    test('restores with every entry unlinked (parent NULL, decided 0) and the same counts', () async {
      final file = fileBytes(fileJson(
        classes: seedRowsV5(),
        txs: [_fileW(1), _fileW(2), tx(3, 'CASH-20260101-0101', 'CASH', 2, createdAt: f0 + 3)],
        schemaVersion: 5,
      ));
      for (final mode in RestoreMode.values) {
        final db = await openTestDb();
        final result = await svc(db).restore(file, mode);
        expect(result.tally.transactions.added, 3, reason: mode.name);
        expect((await db.rawQuery('SELECT COUNT(*) AS n FROM transactions')).first['n'], 3);
        expect((await db.rawQuery(
                'SELECT COUNT(*) AS n FROM transactions WHERE parent_transaction_id IS NOT NULL OR cash_only_decided != 0'))
            .first['n'], 0);
        await db.close();
      }
    });

    test('a schema 5 file that carries a link key is refused (exact-key defence)', () {
      for (final key in kBackupTransactionLinkKeys) {
        final j = fileJson(
            classes: seedRowsV5(), txs: [_fileW(1), _fileCash(2)..[key] = key == 'parent_id' ? 1 : 1], schemaVersion: 5);
        expect(
          () => BackupValidator.validate(fileBytes(j)),
          throwsA(isA<RestoreRejected>()
              .having((e) => e.reason, 'reason', RestoreRejectReason.invalidRow)
              .having((e) => e.field, 'field', '(keys)')),
          reason: key,
        );
      }
    });

    test('this build writes schema 9 and refuses schema 10 as newer (0.2.0, max schema 5, does the same with a 6: pinned by its own test)', () {
      expect(kBackupSchemaVersion, 9);
      final j = fileJson(classes: seedRowsV5(), schemaVersion: 10);
      expect(
        () => BackupValidator.validate(fileBytes(j)),
        throwsA(isA<RestoreRejected>().having((e) => e.reason, 'reason', RestoreRejectReason.newer)),
      );
    });
  });

  group('validator: a bad link is dropped (Cash kept as plain), a bad shape is refused', () {
    Map<int, Map<String, Object?>> only(List<Map<String, Object?>> txs) =>
        {for (final r in BackupValidator.validate(fileBytes(fileJson(classes: seedRowsV5(), txs: txs, schemaVersion: 6))).transactions) r['id']! as int: r};

    test('a good link and decision are kept', () {
      final rows = only([_fileW(1)..['cash_only_decided'] = 1, _fileW(2), _fileCash(3, parent: 2)]);
      expect(rows[3]!['parent_id'], 2);
      expect(rows[1]!['cash_only_decided'], 1);
    });

    test('link to a missing row, to a non-withdrawal row, to itself: dropped, row kept', () {
      final rows = only([
        _fileW(1),
        _fileCash(2, parent: 99, code: 'CASH-20260101-0102'),
        _fileCash(3, parent: 2, code: 'CASH-20260101-0103'),
        _fileCash(4, parent: 4, code: 'CASH-20260101-0104'),
      ]);
      expect(rows.length, 4);
      for (final id in [2, 3, 4]) {
        expect(rows[id]!['parent_id'], isNull, reason: 'row $id');
      }
    });

    test('a link on a row that is not Cash is dropped', () {
      final rows = only([_fileW(1), _fileW(2)..['parent_id'] = 1]);
      expect(rows[2]!['parent_id'], isNull);
    });

    test('entries past the withdrawal amount: the first fit, the one that does not is dropped (plain Cash)', () {
      final rows = only([
        _fileW(1, amount: 5000),
        _fileCash(2, parent: 1, amount: 3000, code: 'CASH-20260101-0102'),
        _fileCash(3, parent: 1, amount: 3000, code: 'CASH-20260101-0103'),
        _fileCash(4, parent: 1, amount: 2000, code: 'CASH-20260101-0104'),
      ]);
      expect(rows[2]!['parent_id'], 1);
      expect(rows[3]!['parent_id'], isNull);
      expect(rows[4]!['parent_id'], 1);
    });

    test('decided = 1 on a row that is not a withdrawal is reset to 0', () {
      final rows = only([_fileCash(1, decided: 1)]);
      expect(rows[1]!['cash_only_decided'], 0);
    });

    test('a wrong type or range is refused, naming the field and never the value', () {
      final hostile = <String, List<Object?>>{
        'parent_id': ['abc', 0, -1, 1.5, true, <Object?>[1], 99999999999999999],
        'cash_only_decided': ['1', 2, -1, 0.5, true, null],
      };
      hostile.forEach((field, values) {
        for (final v in values) {
          try {
            BackupValidator.validate(fileBytes(fileJson(
                classes: seedRowsV5(), txs: [_fileW(1), _fileCash(2, parent: 1)..[field] = v], schemaVersion: 6)));
            fail('accepted $field = ${v.runtimeType} $v');
          } on RestoreRejected catch (e) {
            expect(e.reason, RestoreRejectReason.invalidRow);
            expect(e.table, 'transactions');
            expect(e.field, field);
          }
        }
      });
    });

    test('a dropped link does not stop a restore: the entry lands as plain Cash', () async {
      final file = fileBytes(fileJson(
        classes: seedRowsV5(),
        txs: [_fileW(1), _fileCash(2, parent: 77)],
        schemaVersion: 6,
      ));
      final db = await openTestDb();
      final result = await svc(db).restore(file, RestoreMode.merge);
      expect(result.tally.transactions.added, 2);
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM transactions WHERE parent_transaction_id IS NOT NULL')).first['n'], 0);
      await db.close();
    });
  });

  group('restore writes the link and the decision', () {
    test('the child is inserted after its parent even when it comes first in the file', () async {
      final file = fileBytes(fileJson(
        classes: seedRowsV5(),
        txs: [_fileCash(1, parent: 2, amount: 400000), _fileW(2)..['cash_only_decided'] = 1],
        schemaVersion: 6,
      ));
      final db = await openTestDb();
      await svc(db).restore(file, RestoreMode.merge);
      final rows = await db.rawQuery(
          'SELECT c.display_code AS code, p.display_code AS parent, p.cash_only_decided AS dec FROM transactions c '
          'JOIN transactions p ON p.id = c.parent_transaction_id');
      expect(rows.single['parent'], 'WDR0000002');
      expect(rows.single['dec'], 1);
      await db.close();
    });
  });
}
