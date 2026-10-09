// DB3 (S3a, constants only): the frozen v3 DDL and seeds build a FRESH v3
// database in a test, and nothing live is switched yet.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v3_ddl.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _t = 1790000000000;

Future<Database> _freshV3({List<String>? ddl}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) => createFreshV3ForTest(db, ddl: ddl, nowMs: _t)));
  return db;
}

Future<int> _cls(Database db, String seedKey) async => firstIntOf(
    await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [seedKey]))!;

/// Inserts one invented transaction; returns null on success, else the error text.
Future<String?> _tryInsert(
  Database db, {
  required String source,
  required int classId,
  Object? agent,
  String? label,
  String? phone,
  String? account,
  int? cost = 0,
  String code = 'T0',
}) async {
  try {
    await db.insert('transactions', {
      'display_code': code,
      'source_type': source,
      'amount_cents': 100,
      'transaction_cost_cents': source == 'CASH' ? null : cost,
      'counterparty_label': label,
      'counterparty_phone': phone,
      'paybill_account_number': account,
      'agent_number': agent,
      'classification_id': classId,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': _t,
      'created_at': _t,
    });
    return null;
  } catch (e) {
    return e.toString();
  }
}

/// [kV3TransactionsDdl] with the agent-number CHECK replaced by a no-op.
List<String> _ddlWithout(String clause) {
  final stmts = v3SchemaStatements();
  final i = stmts.indexOf(kV3TransactionsDdl);
  final replaced = kV3TransactionsDdl.replaceFirst(clause, 'CHECK (1 = 1)');
  expect(replaced, isNot(kV3TransactionsDdl), reason: 'the control really removed the clause');
  return [...stmts]..[i] = replaced;
}

void main() {
  group('constants and pins', () {
    test('five new seeds, 17 keys in all, no duplicates, each key starts with its group', () {
      expect(kV3NewSeeds, hasLength(5));
      expect(kV3NewSeedKeys, hasLength(5));
      expect(kV3NewSeeds.map((s) => s.seedKey).toList(), kV3NewSeedKeys);
      final all = v3SeedKeys();
      expect(all, hasLength(17));
      expect(all.toSet(), hasLength(17));
      expect(all.take(12).toList(), AppMigrations.v2SeedClassifications.map((s) => s.seedKey).toList());
      for (final s in [...AppMigrations.v2SeedClassifications, ...kV3NewSeeds]) {
        expect(s.seedKey, startsWith('${s.group}:'));
      }
    });

    test('FROZEN seed shapes (name, group, key) are exactly the Judge-accepted five', () {
      expect(kV3NewSeeds.map((s) => '${s.group}|${s.name}|${s.seedKey}').toList(), [
        'AGENT_WITHDRAWAL|Withdrawal|AGENT_WITHDRAWAL:cash_withdrawal',
        'AIRTIME|Airtime|AIRTIME:airtime',
        'POCHI_LA_BIASHARA|Transport|POCHI_LA_BIASHARA:transport',
        'POCHI_LA_BIASHARA|Groceries|POCHI_LA_BIASHARA:groceries',
        'POCHI_LA_BIASHARA|Shopping|POCHI_LA_BIASHARA:shopping',
      ]);
    });

    test('nothing live is switched: kDbVersion 2, 12 live seeds, 4-group live createSchema', () async {
      expect(kDbVersion, 2);
      expect(AppSchema.seedClassifications, hasLength(12));
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
              version: 2,
              singleInstance: false,
              onCreate: (db, v) async {
                await AppSchema.createSchema(db);
                await AppSchema.seed(db);
              }));
      expect(firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM classification_groups')), 4);
      expect(firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM classifications')), 12);
      await db.close();
    });

    test('the v3 constants are referenced by no live code (only this file and tests)', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll('\\', '/');
        if (!path.endsWith('.dart') || path.endsWith('data/db/migration_v3_ddl.dart')) continue;
        if (mentionsV3Constants(f.readAsStringSync())) offenders.add(path);
      }
      expect(offenders, isEmpty);
    });

    test('NEGATIVE CONTROL: the reference scan flags a file that uses a v3 constant', () {
      expect(mentionsV3Constants('final x = kV3TransactionsDdl;'), isTrue);
      expect(mentionsV3Constants("import 'migration_v3_ddl.dart';"), isTrue);
      expect(mentionsV3Constants('final x = 1;'), isFalse);
    });
  });

  group('a FRESH v3 database built from the constants', () {
    late Database db;
    setUp(() async => db = await _freshV3());
    tearDown(() => db.close());

    test('6 groups in the order SEND_MONEY, PAYBILL, BUY_GOODS, POCHI, AGENT_WITHDRAWAL, AIRTIME', () async {
      final rows = await db.rawQuery(
          'SELECT id, code, display_name, enabled FROM classification_groups ORDER BY id');
      expect(rows.map((r) => '${r['id']}|${r['code']}|${r['display_name']}|${r['enabled']}').toList(), [
        '1|SEND_MONEY|Send Money|1',
        '2|PAYBILL|Paybill|1',
        '3|BUY_GOODS|Buy Goods|1',
        '4|POCHI_LA_BIASHARA|Pochi|1',
        '5|AGENT_WITHDRAWAL|Withdrawal|1',
        '6|AIRTIME|Airtime|1',
      ]);
    });

    test('17 seeds, ids 1..17 in order, all active, all with their key', () async {
      final rows = await db.rawQuery(
          'SELECT c.id, g.code AS g, c.name, c.active, c.seed_key FROM classifications c '
          'JOIN classification_groups g ON g.id = c.group_id ORDER BY c.id');
      expect(rows, hasLength(17));
      expect(rows.map((r) => r['id']).toList(), List.generate(17, (i) => i + 1));
      expect(rows.map((r) => r['seed_key']).toList(), v3SeedKeys());
      expect(rows.every((r) => r['active'] == 1), isTrue);
      expect(rows.skip(12).map((r) => '${r['g']}|${r['name']}').toList(), [
        'AGENT_WITHDRAWAL|Withdrawal',
        'AIRTIME|Airtime',
        'POCHI_LA_BIASHARA|Transport',
        'POCHI_LA_BIASHARA|Groceries',
        'POCHI_LA_BIASHARA|Shopping',
      ]);
    });

    test('transactions: 14 columns, agent_number TEXT NULL after paybill_account_number; '
        '5 indexes + 2 triggers; foreign_key_check clean', () async {
      final cols = await db.rawQuery('PRAGMA table_info(transactions)');
      expect(cols, hasLength(14));
      final names = cols.map((c) => c['name']).toList();
      expect(names.indexOf('agent_number'), names.indexOf('paybill_account_number') + 1);
      final agent = cols.firstWhere((c) => c['name'] == 'agent_number');
      expect(agent['type'], 'TEXT');
      expect(agent['notnull'], 0);
      final idx = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transactions' "
          "AND name LIKE 'idx_%' ORDER BY name");
      expect(idx.map((r) => r['name']).toList(), [
        'idx_transactions_classification',
        'idx_transactions_deleted_at',
        'idx_transactions_mpesa_code',
        'idx_transactions_occurred',
        'idx_transactions_source',
      ]);
      final trg = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='trigger' ORDER BY name");
      expect(trg.map((r) => r['name']).toList(), [
        'trg_transactions_classification_scope_ins',
        'trg_transactions_classification_scope_upd',
      ]);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });

    test('agent_number CHECK accepts NULL, 1 digit, 20 digits, leading zeros on a Withdrawal row', () async {
      final w = await _cls(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
      var n = 0;
      for (final ok in <String?>[null, '1', '0012345', '9' * 20]) {
        expect(await _tryInsert(db, source: 'AGENT_WITHDRAWAL', classId: w, agent: ok, code: 'A${n++}'),
            isNull, reason: 'agent_number=$ok');
      }
      // label and number are independent on a withdrawal
      expect(await _tryInsert(db, source: 'AGENT_WITHDRAWAL', classId: w, label: 'Test Agent', agent: '555', code: 'A9'),
          isNull);
    });

    test('agent_number CHECK rejects: non-digits, empty, 21 digits, spaces, newline, full-width digits', () async {
      final w = await _cls(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
      var n = 0;
      for (final bad in <String>[
        'abc', '12a', '12 34', ' 123', '123 ', '', '9' * 21, '12\n', '１２３', '+123', '12-3',
      ]) {
        final err = await _tryInsert(db, source: 'AGENT_WITHDRAWAL', classId: w, agent: bad, code: 'B${n++}');
        expect(err, isNotNull, reason: 'agent_number "$bad" must be rejected');
        expect(err, contains('CHECK'), reason: 'rejected by the CHECK, not by something else');
      }
    });

    test('agent_number CHECK rejects an agent number on every non-Withdrawal type', () async {
      var n = 0;
      final send = await _cls(db, 'SEND_MONEY:family_friends');
      final buy = await _cls(db, 'BUY_GOODS:shopping');
      final bill = await _cls(db, 'PAYBILL:rent_payment');
      final pochi = await _cls(db, 'POCHI_LA_BIASHARA:transport');
      final air = await _cls(db, 'AIRTIME:airtime');
      final cases = <(String, int, String?, String?, String?)>[
        ('SEND_MONEY', send, 'Test Person', '0700000001', null),
        ('BUY_GOODS', buy, null, null, null),
        ('PAYBILL', bill, null, null, null),
        ('POCHI_LA_BIASHARA', pochi, null, null, null),
        ('AIRTIME', air, null, null, null),
      ];
      for (final c in cases) {
        // the same row without an agent number is legal ...
        expect(await _tryInsert(db, source: c.$1, classId: c.$2, label: c.$3, phone: c.$4, code: 'C${n++}'),
            isNull, reason: '${c.$1} baseline row must insert');
        // ... and with one it is refused by the CHECK
        final err = await _tryInsert(db,
            source: c.$1, classId: c.$2, label: c.$3, phone: c.$4, agent: '123456', code: 'C${n++}');
        expect(err, isNotNull, reason: '${c.$1} + agent_number must be rejected');
        expect(err, contains('CHECK'));
      }
      // CASH has no fee and must be MANUAL; still no agent number
      final cash = await _cls(db, 'SEND_MONEY:rent');
      expect(await _tryInsert(db, source: 'CASH', classId: cash, code: 'CASH-1'), isNull);
      expect(await _tryInsert(db, source: 'CASH', classId: cash, agent: '1', code: 'CASH-2'), contains('CHECK'));
    });

    test('label CHECK: Airtime and Cash may not carry a label; Pochi and Withdrawal may', () async {
      final air = await _cls(db, 'AIRTIME:airtime');
      final pochi = await _cls(db, 'POCHI_LA_BIASHARA:transport');
      final w = await _cls(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
      expect(await _tryInsert(db, source: 'AIRTIME', classId: air, label: 'x', code: 'L1'), contains('CHECK'));
      expect(await _tryInsert(db, source: 'POCHI_LA_BIASHARA', classId: pochi, label: 'x', code: 'L2'), isNull);
      expect(await _tryInsert(db, source: 'AGENT_WITHDRAWAL', classId: w, label: 'x', code: 'L3'), isNull);
    });

    test('source_type and group code CHECKs reject an unknown value', () async {
      final w = await _cls(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
      // the BEFORE INSERT trigger would fire first (no group has that code), so
      // take the triggers out of the way to reach the column CHECK itself
      await db.execute('DROP TRIGGER trg_transactions_classification_scope_ins');
      expect(await _tryInsert(db, source: 'NOT_A_TYPE', classId: w, code: 'S1'), contains('CHECK'));
      expect(await _tryInsert(db, source: 'AIRTIME', classId: w, code: 'S2'), isNull,
          reason: 'with the trigger gone the legal type AIRTIME is accepted: the CHECK lists it');
      Object? err;
      try {
        await db.insert('classification_groups',
            {'code': 'NOT_A_GROUP', 'display_name': 'x', 'enabled': 1, 'created_at': _t});
      } catch (e) {
        err = e;
      }
      expect(err.toString(), contains('CHECK'));
    });

    test('the group-scope trigger still routes: a Withdrawal row on a Send Money class is refused', () async {
      final send = await _cls(db, 'SEND_MONEY:family_friends');
      expect(await _tryInsert(db, source: 'AGENT_WITHDRAWAL', classId: send, code: 'G1'),
          contains('classification_id does not belong'));
    });
  });

  group('NEGATIVE CONTROLS: the same bad rows ARE accepted when the clause is removed', () {
    test('without the agent-number CHECK: letters, 21 digits and a Send Money agent number go in', () async {
      final db = await _freshV3(ddl: _ddlWithout(kV3AgentNumberCheck));
      final w = await _cls(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
      final send = await _cls(db, 'SEND_MONEY:family_friends');
      expect(await _tryInsert(db, source: 'AGENT_WITHDRAWAL', classId: w, agent: 'abc', code: 'N1'), isNull);
      expect(await _tryInsert(db, source: 'AGENT_WITHDRAWAL', classId: w, agent: '9' * 21, code: 'N2'), isNull);
      expect(
          await _tryInsert(db,
              source: 'SEND_MONEY', classId: send, label: 'T', phone: '0700000001', agent: '12', code: 'N3'),
          isNull);
      await db.close();
    });

    test('without the label CHECK: an Airtime row with a label goes in', () async {
      final db = await _freshV3(ddl: _ddlWithout(kV3LabelCheck));
      final air = await _cls(db, 'AIRTIME:airtime');
      expect(await _tryInsert(db, source: 'AIRTIME', classId: air, label: 'x', code: 'N4'), isNull);
      await db.close();
    });
  });
}

/// True when [source] refers to a frozen-v3 name (constant, helper or file).
bool mentionsV3Constants(String source) =>
    RegExp(r'\bkV3[A-Za-z]+|\bv3SeedKeys\b|\bv3SchemaStatements\b|\bcreateFreshV3ForTest\b|migration_v3_ddl')
        .hasMatch(source);
