// BK2 (mmogo 0.1.2, S3c): the mirror pin. For every source_type x label x phone
// x account x agent number x fee case the DATABASE (real v3 CHECKs and
// triggers), the restore VALIDATOR and the exporter's REPAIR must give the
// same answer: accept or reject. A file the app writes must never exceed what
// the app reads back (backup_limits.dart header), so the three may not drift.
//
// Plus the C6 negatives (unknown type, schema 4, a v2 file carrying a new
// type) and the schema-gated lists. Every comparison has a NEGATIVE CONTROL:
// the same comparer, fed one deliberately wrong party, must report a
// disagreement (so a test that can only pass is impossible).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/db/migration_v3_ddl.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/restore_files.dart';
import '../support/restore_test_db.dart';

/// One invented transaction shape.
class _Case {
  const _Case(this.source, this.label, this.phone, this.account, this.agent, this.fee);
  final String source;
  final String? label;
  final String? phone;
  final String? account;
  final String? agent;
  final int? fee;

  @override
  String toString() =>
      '$source label=$label phone=$phone account=$account agent=$agent fee=$fee';
}

typedef _Oracle = Future<bool> Function(int index, _Case c);

const _allGroups = {
  'SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME',
};

/// Which seed (file id, in `seedRowsV3` order) a case sits on. A stored type
/// sits on its own group; CASH and a garbage type sit on a SEND_MONEY class.
int _fileClassId(String source) => switch (source) {
      'SEND_MONEY' => 1,
      'PAYBILL' => 5,
      'BUY_GOODS' => 9,
      'AGENT_WITHDRAWAL' => 13,
      'AIRTIME' => 14,
      'POCHI_LA_BIASHARA' => 15,
      _ => 1,
    };

String _seedKeyFor(int fileId) => kBackupSeedKeys[fileId - 1];

String _codeOf(int i, String source) => source == 'CASH'
    ? 'CASH-20260101-0101'
    : 'M${i.toString().padLeft(9, '0')}';

Map<String, Object?> _fileRow(int i, _Case c) => {
      'id': i + 1,
      'display_code': _codeOf(i, c.source),
      'source_type': c.source,
      'amount_cents': 10000,
      'transaction_cost_cents': c.fee,
      'counterparty_label': c.label,
      'counterparty_phone': c.phone,
      'paybill_account_number': c.account,
      'agent_number': c.agent,
      'classification': _fileClassId(c.source),
      'raw_parse_source': c.source == 'CASH' ? 'MANUAL' : 'SMS_PARSE',
      'transaction_occurred_at': f0 + i,
      'created_at': f0 + i,
    };

// --- the three parties ----------------------------------------------------------

/// The real database: insert succeeds = accepted.
_Oracle _dbOracle(Database db) => (i, c) async {
      final seedKey = _seedKeyFor(_fileClassId(c.source));
      final classId = await seedId(db, seedKey);
      try {
        await db.insert('transactions', {
          'display_code': _codeOf(i, c.source),
          'source_type': c.source,
          'amount_cents': 10000,
          'transaction_cost_cents': c.fee,
          'counterparty_label': c.label,
          'counterparty_phone': c.phone,
          'paybill_account_number': c.account,
          'agent_number': c.agent,
          'classification_id': classId,
          'raw_parse_source': c.source == 'CASH' ? 'MANUAL' : 'SMS_PARSE',
          'transaction_occurred_at': f0 + i,
          'created_at': f0 + i,
        });
        return true;
      } on DatabaseException {
        return false;
      }
    };

/// The real restore validator over a one-row file of [schemaVersion].
_Oracle _validatorOracle({int schemaVersion = 3}) => (i, c) async {
      final json = fileJson(
        classes: schemaVersion >= 3 ? seedRowsV3() : seedRows(),
        txs: [_fileRow(i, c)..removeWhere((k, _) => schemaVersion < 3 && k == 'agent_number')],
        schemaVersion: schemaVersion,
      );
      try {
        BackupValidator.validate(fileBytes(json), enabledGroupCodes: _allGroups);
        return true;
      } on RestoreRejected {
        return false;
      }
    };

/// The real exporter-side repair: kept untouched = accepted.
Future<bool> _repairAccepts(int i, _Case c) async {
  final repair = BackupRepair(
    classifications: seedRowsV3(),
    transactions: [_fileRow(i, c)],
    counterpartyMap: const [],
    enabledGroupCodes: _allGroups,
  );
  final kept = repair.transactions.length == 1 && repair.skipped.isEmpty;
  // Every case here is clean text, so an accepted row is accepted WITHOUT a repair.
  if (kept) expect(repair.repairedCount, 0, reason: c.toString());
  return kept;
}

/// Every case where the parties do not all agree.
Future<List<String>> _disagreements(
    List<_Case> cases, Map<String, _Oracle> parties) async {
  final out = <String>[];
  for (var i = 0; i < cases.length; i++) {
    final answers = {for (final e in parties.entries) e.key: await e.value(i, cases[i])};
    if (answers.values.toSet().length > 1) out.add('${cases[i]} -> $answers');
  }
  return out;
}

Future<Database> _openV3WithDdl(List<String> ddl) async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) => createFreshV3ForTest(db, ddl: ddl, nowMs: f0)));
}

List<String> _ddlWithout(String clause) {
  final stmts = v3SchemaStatements();
  final i = stmts.indexOf(kV3TransactionsDdl);
  final replaced = kV3TransactionsDdl.replaceFirst(clause, 'CHECK (1 = 1)');
  expect(replaced, isNot(kV3TransactionsDdl), reason: 'the control really removed the clause');
  return [...stmts]..[i] = replaced;
}

// --- the case lists -------------------------------------------------------------

const _sources = [
  'SEND_MONEY', 'BUY_GOODS', 'PAYBILL', 'CASH', 'POCHI_LA_BIASHARA',
  'AGENT_WITHDRAWAL', 'AIRTIME',
];

/// Source types that must be rejected everywhere (POCHI is a group NAME, not a
/// stored type; the others are garbage).
const _garbage = ['POCHI', 'GARBAGE', '', 'send_money', 'AGENT', 'WITHDRAWAL'];

/// source_type x label x phone x account x agent x fee, every combination.
List<_Case> _matrix() => [
      for (final s in [..._sources, ..._garbage])
        for (final label in const <String?>[null, 'ABC SHOP'])
          for (final phone in const <String?>[null, '0712345678'])
            for (final account in const <String?>[null, '12345'])
              for (final agent in const <String?>[null, '123456'])
                for (final fee in const <int?>[null, 500])
                  _Case(s, label, phone, account, agent, fee),
    ];

/// The agent-number dimension on a Withdrawal row with a fee (DBE T2.8).
List<_Case> _agentValues() => [
      for (final label in const <String?>[null, 'ABC AGENT'])
        for (final agent in <String?>[
          null, '123456', '1', '9' * 20, // accept
          '9' * 21, '', ' 123', '123 ', '12 34', '12a', '12\n', '\u{FF11}\u{FF12}\u{FF13}',
          '+123', '1.5', '12${String.fromCharCode(0x202E)}3', // reject
        ])
          _Case('AGENT_WITHDRAWAL', label, null, null, agent, 500),
    ];

void main() {
  group('BK2 the three-way mirror: DB CHECK = validator = repair', () {
    late Database db;
    setUp(() async => db = await openTestDb());
    tearDown(() => db.close());

    test('every source_type x label x phone x account x agent x fee case', () async {
      final cases = _matrix();
      expect(cases.length, (_sources.length + _garbage.length) * 32);
      final bad = await _disagreements(cases, {
        'db': _dbOracle(db),
        'validator': _validatorOracle(),
        'repair': _repairAccepts,
      });
      expect(bad, isEmpty, reason: bad.take(10).join('\n'));
    });

    test('the matrix really covers accept and reject, POCHI and a garbage type are rejected by all three',
        () async {
      final parties = {
        'db': _dbOracle(db),
        'validator': _validatorOracle(),
        'repair': _repairAccepts,
      };
      var accepted = 0;
      var rejected = 0;
      final cases = _matrix();
      for (var i = 0; i < cases.length; i++) {
        final c = cases[i];
        final answers = [for (final p in parties.values) await p(i, c)];
        // The matrix is only an oracle if the three agree; count the verdict.
        answers.first ? accepted++ : rejected++;
        if (_garbage.contains(c.source)) {
          expect(answers, [false, false, false], reason: '${c.source} must be rejected by all three');
        }
      }
      // Hand count of the legal shapes: Send Money 2 (nothing, or label+phone),
      // Buy Goods 2, Paybill 2 (nothing, or label+account), Cash 1, Pochi 2,
      // Withdrawal 4 (label x agent number, fee set), Airtime 1.
      expect(accepted, 14);
      expect(rejected, cases.length - 14);
    });

    test('agent number values: accepted and rejected alike in all three (T2.8)', () async {
      final cases = _agentValues();
      final bad = await _disagreements(cases, {
        'db': _dbOracle(db),
        'validator': _validatorOracle(),
        'repair': _repairAccepts,
      });
      expect(bad, isEmpty, reason: bad.take(10).join('\n'));
      // And the verdicts are the ones the spec names.
      for (var i = 0; i < cases.length; i++) {
        final a = cases[i].agent;
        final shouldAccept = a == null || a == '123456' || a == '1' || a == '9' * 20;
        expect(await _validatorOracle()(i, cases[i]), shouldAccept, reason: cases[i].toString());
      }
    });

    test('an agent number with no fee is rejected by all three (fee rule)', () async {
      const c = _Case('AGENT_WITHDRAWAL', null, null, null, '123456', null);
      expect(await _dbOracle(db)(0, c), isFalse);
      expect(await _validatorOracle()(0, c), isFalse);
      expect(await _repairAccepts(0, c), isFalse);
    });

    test('a JSON number as agent_number: validator and repair reject it (type; the DB is excluded by TEXT affinity)',
        () async {
      final row = _fileRow(0, const _Case('AGENT_WITHDRAWAL', null, null, null, null, 500))
        ..['agent_number'] = 123456;
      expect(
        () => BackupValidator.validate(
            fileBytes(fileJson(classes: seedRowsV3(), txs: [row], schemaVersion: 3))),
        throwsA(isA<RestoreRejected>().having((e) => e.field, 'field', 'agent_number')),
      );
      final repair = BackupRepair(
        classifications: seedRowsV3(),
        transactions: [row],
        counterpartyMap: const [],
        enabledGroupCodes: _allGroups,
      );
      expect(repair.transactions, isEmpty);
      expect(repair.skipped.single.field, 'agent_number');
      expect(repair.skipped.single.rule, 'format');
    });

    test('group codes: DB CHECK = validator = repair (six accepted, POCHI and garbage rejected)', () async {
      const codes = [..._allGroups, 'POCHI', 'GARBAGE', '', 'pochi_la_biasha'];
      for (final code in codes) {
        sqfliteFfiInit();
        final empty = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
            options: OpenDatabaseOptions(
                version: 3,
                singleInstance: false,
                onCreate: (d, v) => AppSchema.createSchema(d)));
        var dbOk = true;
        try {
          await empty.insert('classification_groups',
              {'code': code, 'display_name': 'x', 'enabled': 1, 'created_at': f0});
        } on DatabaseException {
          dbOk = false;
        }
        await empty.close();

        final classRow = cls(1, code, 'Stock');
        var validatorOk = true;
        try {
          BackupValidator.validate(fileBytes(fileJson(classes: [classRow], schemaVersion: 3)));
        } on RestoreRejected {
          validatorOk = false;
        }
        final repair = BackupRepair(
          classifications: [classRow],
          transactions: const [],
          counterpartyMap: const [],
          enabledGroupCodes: _allGroups,
        );
        final repairOk = repair.classifications.length == 1;
        expect([dbOk, validatorOk, repairOk], [_allGroups.contains(code), _allGroups.contains(code), _allGroups.contains(code)],
            reason: 'group code "$code"');
      }
    });
  });

  group('BK2 NEGATIVE CONTROLS: the comparer must be able to FAIL', () {
    test('a database without the agent-number CHECK disagrees with validator and repair', () async {
      final db = await _openV3WithDdl(_ddlWithout(kV3AgentNumberCheck));
      final bad = await _disagreements(_agentValues(), {
        'db': _dbOracle(db),
        'validator': _validatorOracle(),
        'repair': _repairAccepts,
      });
      await db.close();
      expect(bad, isNotEmpty);
      expect(bad.every((m) => m.contains('agent=')), isTrue);
    });

    test('a database with the OLD label rule (label allowed unless CASH) disagrees on Airtime', () async {
      final db = await _openV3WithDdl(_ddlWithout(kV3LabelCheck));
      const c = _Case('AIRTIME', 'ABC SHOP', null, null, null, 500);
      final bad = await _disagreements(const [c], {
        'db': _dbOracle(db),
        'validator': _validatorOracle(),
        'repair': _repairAccepts,
      });
      await db.close();
      expect(bad.length, 1);
      expect(bad.single, contains('AIRTIME'));
    });

    test('a validator that treats the file as schema 2 disagrees on every new type', () async {
      final db = await openTestDb();
      final cases = [
        const _Case('POCHI_LA_BIASHARA', 'ABC SHOP', null, null, null, 500),
        const _Case('AGENT_WITHDRAWAL', null, null, null, null, 500),
        const _Case('AIRTIME', null, null, null, null, 500),
      ];
      final bad = await _disagreements(cases, {
        'db': _dbOracle(db),
        'validator': _validatorOracle(schemaVersion: 2),
        'repair': _repairAccepts,
      });
      await db.close();
      expect(bad.length, 3);
    });

    test('a party that wrongly accepts POCHI is caught by the garbage rule', () async {
      final db = await openTestDb();
      const c = _Case('POCHI', null, null, null, null, 500);
      Future<bool> lax(int i, _Case c) async => true;
      final bad = await _disagreements(const [c], {'db': _dbOracle(db), 'lax': lax});
      await db.close();
      expect(bad.length, 1);
    });
  });

  group('BK2 C6 negatives and schema gating', () {
    RestoreRejected rejected(Map<String, Object?> json) {
      try {
        BackupValidator.validate(fileBytes(json));
      } on RestoreRejected catch (e) {
        return e;
      }
      fail('expected the file to be refused');
    }

    test('C6: an unknown source type in a schema 3 file is refused (field source_type)', () {
      final e = rejected(fileJson(
          classes: seedRowsV3(),
          txs: [_fileRow(0, const _Case('POCHI', null, null, null, null, 500))],
          schemaVersion: 3));
      expect(e.reason, RestoreRejectReason.invalidRow);
      expect(e.table, 'transactions');
      expect(e.field, 'source_type');
    });

    test('C6: schema 4 is refused whole as newer', () {
      final e = rejected(fileJson(classes: seedRowsV3(), schemaVersion: 4));
      expect(e.reason, RestoreRejectReason.newer);
      expect(e.field, 'schema_version');
    });

    test('C6: a v2 file with a new-type row is refused (AIRTIME, AGENT_WITHDRAWAL, POCHI_LA_BIASHARA)', () {
      for (final s in ['AIRTIME', 'AGENT_WITHDRAWAL', 'POCHI_LA_BIASHARA']) {
        final e = rejected(fileJson(
            classes: seedRows(),
            txs: [
              tx(1, 'V2NEW00001', s, 1, label: s == 'POCHI_LA_BIASHARA' ? 'SHOP' : null),
            ],
            schemaVersion: 2));
        expect(e.reason, RestoreRejectReason.invalidRow, reason: s);
        expect(e.field, 'source_type', reason: s);
      }
    });

    test('the same new-type rows ARE accepted in a schema 3 file (the gate is the version)', () {
      for (final s in ['AIRTIME', 'AGENT_WITHDRAWAL', 'POCHI_LA_BIASHARA']) {
        final v = BackupValidator.validate(fileBytes(fileJson(
            classes: seedRowsV3(),
            txs: [
              tx(1, 'V3NEW00001', s, _fileClassId(s), label: s == 'POCHI_LA_BIASHARA' ? 'SHOP' : null),
            ],
            schemaVersion: 3)));
        expect(v.transactions.single['source_type'], s);
      }
    });

    test('a v2 file with a new group code, or a new seed key, is refused', () {
      var e = rejected(fileJson(
          classes: [...seedRows(), cls(20, 'AIRTIME', 'Airtime', seedKey: 'AIRTIME:airtime')],
          schemaVersion: 2));
      expect(e.field, 'group');
      // Isolate the seed-key gate: the group is valid in v2, the key is a v3 key.
      e = rejected(fileJson(
          classes: [...seedRows(), cls(20, 'POCHI_LA_BIASHARA', 'Transport', seedKey: 'POCHI_LA_BIASHARA:transport')],
          schemaVersion: 2));
      expect(e.field, 'seed_key');
      // ...and the same row is fine in a schema 3 file.
      final v = BackupValidator.validate(fileBytes(fileJson(
          classes: [...seedRows(), cls(20, 'POCHI_LA_BIASHARA', 'Transport', seedKey: 'POCHI_LA_BIASHARA:transport')],
          schemaVersion: 3)));
      expect(v.classifications.last['seed_key'], 'POCHI_LA_BIASHARA:transport');
    });

    test('locked seeds are NOT required to be active (C-A10: no validator refusal)', () {
      final rows = seedRowsV3();
      rows[12] = cls(13, 'AGENT_WITHDRAWAL', 'Renamed', active: 0, seedKey: 'AGENT_WITHDRAWAL:cash_withdrawal');
      rows[13] = cls(14, 'AIRTIME', 'Other', active: 0, seedKey: 'AIRTIME:airtime');
      final v = BackupValidator.validate(fileBytes(fileJson(classes: rows, schemaVersion: 3)));
      expect(v.classifications[12]['active'], 0);
      expect(v.classifications[13]['active'], 0);
    });

    test('exact key sets: schema 2 = 12 keys (agent_number refused), schema 3 = 13 keys (missing refused)', () {
      final v2 = fileJson(classes: seedRows(), txs: [tx(1, 'K2000000001', 'SEND_MONEY', 1, label: 'A', phone: '0712345678')], schemaVersion: 2);
      ((v2['transactions']! as List).first as Map)['agent_number'] = null;
      expect(rejected(v2).field, '(keys)');

      final v3 = fileJson(classes: seedRowsV3(), txs: [tx(1, 'K3000000001', 'SEND_MONEY', 1, label: 'A', phone: '0712345678')], schemaVersion: 3);
      ((v3['transactions']! as List).first as Map).remove('agent_number');
      expect(rejected(v3).field, '(keys)');
    });
  });

  group('BK2 the committed anonymised v2 file', () {
    final bytes = File('test/fixtures/backup_v2_anonymised.json').readAsBytesSync();

    test('is a schema 2 file with 12 transaction keys and validates', () {
      final v = BackupValidator.validate(bytes);
      expect(v.schemaVersion, 2);
      expect(v.classifications.where((c) => c['seed_key'] != null), hasLength(12));
      expect(v.transactions, hasLength(8));
      // Read as one shape: every row got agent_number null.
      expect(v.transactions.every((t) => t.containsKey('agent_number') && t['agent_number'] == null), isTrue);
      expect(v.counterpartyMap, hasLength(5));
    });

    test('NEGATIVE CONTROL: the same bytes stamped schema 3 are refused (12 keys are not 13)', () {
      final text = String.fromCharCodes(bytes).replaceFirst('"schema_version":2', '"schema_version":3');
      expect(text, isNot(String.fromCharCodes(bytes)));
      expect(() => BackupValidator.validate(Uint8List.fromList(text.codeUnits)),
          throwsA(isA<RestoreRejected>().having((e) => e.field, 'field', '(keys)')));
    });
  });
}
