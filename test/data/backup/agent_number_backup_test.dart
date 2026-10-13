// AG1 data layer (mmogo 0.1.2, S3c): the agent number in the exporter, the CSV,
// the validator, the repair and the restore. (The Add form is slice S8; the
// DB CHECK itself is pinned by the S3a/S3b tests and by check_mirror_test.)
// Invented numbers only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/db/export_dao.dart';
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

/// A withdrawal row in schema-3 file shape.
Map<String, Object?> _withdrawal({Object? agent = '123456', String? label = 'ABC AGENT', int id = 1}) => {
      'id': id,
      'display_code': 'W${id.toString().padLeft(9, '0')}',
      'source_type': 'AGENT_WITHDRAWAL',
      'amount_cents': 500000,
      'transaction_cost_cents': 3500,
      'counterparty_label': label,
      'counterparty_phone': null,
      'paybill_account_number': null,
      'agent_number': agent,
      'classification': 13,
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': f0 + id,
      'created_at': f0 + id,
    };

Uint8List _file(List<Map<String, Object?>> txs) =>
    fileBytes(fileJson(classes: seedRowsV3(), txs: txs, schemaVersion: 3));

Future<void> _addWithdrawal(Database db, String code, {String? label, String? agent}) async {
  await db.insert('transactions', {
    'display_code': code,
    'source_type': 'AGENT_WITHDRAWAL',
    'amount_cents': 500000,
    'transaction_cost_cents': 3500,
    'counterparty_label': label,
    'agent_number': agent,
    'classification_id': await seedId(db, 'AGENT_WITHDRAWAL:cash_withdrawal'),
    'raw_parse_source': 'SMS_PARSE',
    'transaction_occurred_at': t0,
    'created_at': t0,
  });
}

Future<List<String>> _agentRows(DatabaseExecutor db) async => [
      for (final r in await db.rawQuery(
          "SELECT display_code, counterparty_label, agent_number FROM transactions "
          "WHERE source_type = 'AGENT_WITHDRAWAL' ORDER BY display_code"))
        r.values.join('|'),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('exporter', () {
    test('the 13 row keys put agent_number right after paybill_account_number', () {
      final i = kBackupTransactionKeys.indexOf('paybill_account_number');
      expect(kBackupTransactionKeys[i + 1], 'agent_number');
      expect(kBackupTransactionKeys.length, 13);
      // Schema 2 keeps its exact 12 (agent_number absent).
      expect(kBackupTransactionKeysV2.contains('agent_number'), isFalse);
      expect(kBackupTransactionKeysV2.length, 12);
    });

    test('an export carries the agent number (or null) on every transaction, stamped schema 3', () async {
      final db = await openTestDb();
      await _addWithdrawal(db, 'WAG0000001', label: 'ABC AGENT', agent: '123456');
      await _addWithdrawal(db, 'WAG0000002', agent: null);
      await addTx(db, code: 'SND0000001', source: 'SEND_MONEY', classId: await seedId(db, 'SEND_MONEY:rent'),
          label: 'T', phone: '0700000001');
      final export = await backupOf(db).export();
      expect(export.skippedCount, 0);
      final json = jsonDecode(utf8.decode(export.bytes)) as Map<String, Object?>;
      expect(json['schema_version'], 3);
      final rows = (json['transactions']! as List).cast<Map<String, Object?>>();
      for (final r in rows) {
        expect(r.keys.toList(), kBackupTransactionKeys, reason: 'exact keys, in order');
      }
      final byCode = {for (final r in rows) r['display_code']: r['agent_number']};
      expect(byCode, {'WAG0000001': '123456', 'WAG0000002': null, 'SND0000001': null});
      await db.close();
    });

    test('round trip: add, back up, restore (merge and replace), and the CSV all agree', () async {
      final a = await openTestDb();
      await _addWithdrawal(a, 'WAG0000001', label: 'ABC AGENT', agent: '123456');
      await _addWithdrawal(a, 'WAG0000002', agent: null);
      final file = await backupOf(a).exportToBytes();
      for (final mode in RestoreMode.values) {
        final b = await openTestDb();
        await svc(b).restore(file, mode);
        expect(await _agentRows(b), await _agentRows(a), reason: mode.name);
        expect(await _agentRows(b), ['WAG0000001|ABC AGENT|123456', 'WAG0000002|null|null']);
        await b.close();
      }
      // The CSV: "Agent Number" is the LAST column, the plain digits or empty.
      expect(ExportDao.csvHeader.last, 'Agent Number');
      expect(ExportDao.csvHeader.length, 11);
      final csv = ExportDao.toCsv(await ExportDao.activeTransactions(a)).trimRight().split('\r\n');
      expect(csv.first.endsWith(',Agent Number'), isTrue);
      expect(csv.skip(1).map((l) => l.split(',').last).toList()..sort(), ['', '123456']);
      await a.close();
    });

    test('NEGATIVE CONTROL: the round trip really compares the number (a changed one is seen)', () async {
      final a = await openTestDb();
      await _addWithdrawal(a, 'WAG0000001', agent: '123456');
      final before = await _agentRows(a);
      await a.rawUpdate("UPDATE transactions SET agent_number = '654321'");
      expect(await _agentRows(a), isNot(before));
      await a.close();
    });
  });

  group('validator', () {
    test('a good agent number (and null) is accepted and kept', () {
      final v = BackupValidator.validate(_file([
        _withdrawal(agent: '123456'),
        _withdrawal(agent: null, id: 2),
        _withdrawal(agent: '9' * 20, id: 3),
      ]));
      expect(v.transactions.map((t) => t['agent_number']).toList(), ['123456', null, '9' * 20]);
    });

    test('hostile values refuse the file, name the field agent_number, and never repeat the value', () {
      final hostile = <Object?>[
        '99999999999999999999 9', // 21 characters with a space
        '', '\u{FF11}\u{FF12}\u{FF13}', '12\n', ' 12', '12a', 'ab${String.fromCharCode(0x202E)}cd',
        123456, true, false, <Object?>['1'], <String, Object?>{'n': '1'}, 12.0,
      ];
      for (final h in [...hostile, '9' * 21]) {
        try {
          BackupValidator.validate(_file([_withdrawal(agent: h)]));
          fail('accepted a hostile agent number: ${h.runtimeType}');
        } on RestoreRejected catch (e) {
          expect(e.reason, RestoreRejectReason.invalidRow);
          expect(e.table, 'transactions');
          expect(e.field, 'agent_number');
          if (h is String && h.length > 3) {
            expect(e.toString().contains(h), isFalse, reason: 'the value must never be named');
          }
        }
      }
    });

    test('an agent number on a row that is not a Withdrawal is refused', () {
      for (final src in ['SEND_MONEY', 'BUY_GOODS', 'PAYBILL', 'CASH', 'POCHI_LA_BIASHARA', 'AIRTIME']) {
        final row = _withdrawal(label: null)
          ..['source_type'] = src
          ..['classification'] = 1
          ..['transaction_cost_cents'] = src == 'CASH' ? null : 500
          ..['raw_parse_source'] = src == 'CASH' ? 'MANUAL' : 'SMS_PARSE'
          ..['display_code'] = src == 'CASH' ? 'CASH-20260101-0101' : 'ZZZ0000001';
        expect(
          () => BackupValidator.validate(_file([row])),
          throwsA(isA<RestoreRejected>().having((e) => e.field, 'field', anyOf('agent_number', 'classification'))),
          reason: src,
        );
      }
    });

    test('schema 2 file (12 keys) is accepted unchanged and restores with agent_number NULL', () async {
      final bytes = File('test/fixtures/backup_v2_anonymised.json').readAsBytesSync();
      final v = BackupValidator.validate(bytes);
      expect(v.schemaVersion, 2);
      final db = await openTestDb();
      await svc(db).restore(bytes, RestoreMode.merge);
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM transactions WHERE agent_number IS NOT NULL')).first['n'], 0);
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM transactions')).first['n'], 8);
      await db.close();
    });

    test('schema 2 file carrying agent_number is refused; schema 3 file missing it is refused', () {
      final v2 = fileJson(classes: seedRows(), txs: [tx(1, 'AAA0000001', 'SEND_MONEY', 1)], schemaVersion: 2);
      (v2['transactions']! as List<Map<String, Object?>>).first['agent_number'] = null;
      expect(() => BackupValidator.validate(fileBytes(v2)),
          throwsA(isA<RestoreRejected>().having((e) => e.field, 'field', '(keys)')));
      final v3 = fileJson(classes: seedRowsV3(), txs: [tx(1, 'AAA0000001', 'SEND_MONEY', 1)], schemaVersion: 3);
      ((v3['transactions']! as List).first as Map).remove('agent_number');
      expect(() => BackupValidator.validate(fileBytes(v3)),
          throwsA(isA<RestoreRejected>().having((e) => e.field, 'field', '(keys)')));
    });
  });

  group('repair (export side)', () {
    BackupRepair repairOf(Object? agent) => BackupRepair(
          classifications: seedRowsV3(),
          transactions: [_withdrawal(agent: agent)],
          counterpartyMap: const [],
          enabledGroupCodes: BackupValidator.defaultEnabledGroups,
        );

    test('a clean value is kept untouched', () {
      final r = repairOf('123456');
      expect(r.transactions.single['agent_number'], '123456');
      expect(r.repairedCount, 0);
      expect(r.skipped, isEmpty);
    });

    test('a bad value is NEVER repaired: the row is skipped with field agent_number, rule format', () {
      for (final bad in ['12a', ' 123', '12 34', '9' * 21, '', 123456, true]) {
        final r = repairOf(bad);
        expect(r.transactions, isEmpty, reason: '$bad');
        expect(r.repairedCount, 0, reason: 'no attempt to fix digits out of "$bad"');
        expect(r.skipped.single.field, 'agent_number');
        expect(r.skipped.single.rule, 'format');
        expect(r.skipped.single.toString().contains('$bad') && '$bad'.length > 3, isFalse);
      }
    });
  });
}
