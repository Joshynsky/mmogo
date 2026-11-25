// 0.2.1 (PM #33): backup / restore of the withdrawal "Cash" category list (group CASH_USE,
// schema 7). Real in-memory sqlite; hand-built files for the older-file side; invented data only.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/db/classification_dao.dart';
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

/// A phone with two Cash-list categories, one used by a withdrawal's linked Cash entry.
Future<Database> _phone() async {
  final db = await openTestDb();
  final fare = await ClassificationDao.createCashUseClassification(db, name: 'Fare');
  await ClassificationDao.createCashUseClassification(db, name: 'Fuel');
  final w = await db.insert('transactions', {
    'display_code': 'WDR0000001',
    'source_type': 'AGENT_WITHDRAWAL',
    'amount_cents': 500000,
    'transaction_cost_cents': 3500,
    'counterparty_label': 'TEST AGENT',
    'agent_number': '123456',
    'classification_id': await seedId(db, 'AGENT_WITHDRAWAL:cash_withdrawal'),
    'raw_parse_source': 'SMS_PARSE',
    'transaction_occurred_at': t0,
    'created_at': t0,
  });
  await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: fare);
  return db;
}

/// Cash-list categories and entries on them, as comparable text.
Future<List<String>> _cashList(DatabaseExecutor db) async => [
      for (final r in await db.rawQuery(
          'SELECT c.name AS name, c.active AS active, '
          '(SELECT COUNT(*) FROM transactions t WHERE t.classification_id = c.id AND t.deleted_at IS NULL) AS used '
          'FROM classifications c JOIN classification_groups g ON g.id = c.group_id '
          "WHERE g.code = 'CASH_USE' ORDER BY c.name"))
        r.values.join('|'),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the exporter writes schema 7 and the Cash-list categories under group CASH_USE', () async {
    final a = await _phone();
    final json = jsonDecode(utf8.decode((await backupOf(a).export()).bytes)) as Map<String, Object?>;
    expect(json['schema_version'], 9);
    final cash = ((json['classifications']! as List).cast<Map<String, Object?>>()).where((c) => c['group'] == 'CASH_USE').toList();
    expect(cash.map((c) => c['name']).toList()..sort(), ['Fare', 'Fuel']);
    expect(cash.every((c) => c['seed_key'] == null), isTrue, reason: 'user rows, no seed key');
    await a.close();
  });

  test('a file the validator accepts: schema 7 may carry CASH_USE; schema 6 and 5 may not', () {
    final classes = [...seedRowsV5(), cls(19, 'CASH_USE', 'Fare')];
    expect(BackupValidator.validate(fileBytes(fileJson(classes: classes, schemaVersion: 7))).classifications, hasLength(19));
    for (final v in [6, 5]) {
      expect(
        () => BackupValidator.validate(fileBytes(fileJson(classes: classes, schemaVersion: v))),
        throwsA(isA<RestoreRejected>()),
        reason: 'schema $v',
      );
    }
  });

  test('round trip: Merge into an empty phone and Replace onto a phone with other data, same Cash list', () async {
    final a = await _phone();
    final file = await backupOf(a).exportToBytes();
    final want = await _cashList(a);
    expect(want, ['Fare|1|1', 'Fuel|1|0']);
    for (final mode in RestoreMode.values) {
      final b = await openTestDb();
      if (mode == RestoreMode.replace) {
        // an own Cash category that is not in the file: Replace removes user categories first
        await ClassificationDao.createCashUseClassification(b, name: 'Old thing');
      }
      await svc(b).restore(file, mode);
      expect(await _cashList(b), want, reason: mode.name);
      expect(await b.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      // the linked entry points at the restored Cash category
      final entry = await b.rawQuery("SELECT c.name AS n, g.code AS g FROM transactions t JOIN classifications c ON c.id = t.classification_id "
          "JOIN classification_groups g ON g.id = c.group_id WHERE t.source_type = 'CASH'");
      expect(entry.single['n'], 'Fare');
      expect(entry.single['g'], 'CASH_USE');
      await b.close();
    }
    await a.close();
  });

  test('Merge twice adds no duplicate Cash category; Merge keeps the phone\'s own different Cash category', () async {
    final a = await _phone();
    final file = await backupOf(a).exportToBytes();
    final b = await openTestDb();
    await ClassificationDao.createCashUseClassification(b, name: 'Boda');
    await svc(b).restore(file, RestoreMode.merge);
    await svc(b).restore(file, RestoreMode.merge);
    expect((await _cashList(b)).map((l) => l.split('|').first).toList(), ['Boda', 'Fare', 'Fuel']);
    await a.close();
    await b.close();
  });

  test('a 0.2.0-shaped backup (schema 5, no Cash group) restores without error and leaves the Cash list empty', () async {
    final file = fileBytes(fileJson(
      classes: seedRowsV5(),
      txs: [tx(1, 'ABC1234567', 'SEND_MONEY', 2, label: 'T', phone: '0700000001', createdAt: f0)],
      schemaVersion: 5,
    ));
    for (final mode in RestoreMode.values) {
      final db = await openTestDb();
      final result = await svc(db).restore(file, mode);
      expect(result.tally.transactions.added, 1, reason: mode.name);
      expect(await _cashList(db), isEmpty, reason: mode.name);
      expect(await db.rawQuery("SELECT 1 FROM classification_groups WHERE code = 'CASH_USE'"), hasLength(1));
      await db.close();
    }
  });

  test('Replace from a file WITHOUT Cash categories removes the phone\'s own Cash categories along with the other user ones', () async {
    final db = await openTestDb();
    await ClassificationDao.createCashUseClassification(db, name: 'Boda');
    await svc(db).restore(fileBytes(fileJson(classes: seedRowsV5(), schemaVersion: 5)), RestoreMode.replace);
    expect(await _cashList(db), isEmpty);
    expect(await db.rawQuery("SELECT 1 FROM classification_groups WHERE code = 'CASH_USE'"), hasLength(1), reason: 'the group itself stays');
    await db.close();
  });

  test('a CASH row on a Cash-list category in a file is valid (the group is enabled)', () {
    final classes = [...seedRowsV5(), cls(19, 'CASH_USE', 'Fare')];
    final v = BackupValidator.validate(
        fileBytes(fileJson(classes: classes, txs: [tx(1, 'CASH-20260101-0101', 'CASH', 19)], schemaVersion: 7)),
        enabledGroupCodes: {'SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME', 'CASH_USE'});
    expect(v.transactions, hasLength(1));
  });
}
