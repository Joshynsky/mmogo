// B9b: the exporter repairs what is safe, skips what is not, never fails the
// whole backup for one old row, and never touches the database.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _t0 = 1790000000000;

Future<Database> _openDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await AppSchema.createSchema(db);
        await AppSchema.seed(db);
      },
    ),
  );
}

Future<int> _classId(Database db, String group, String name) async {
  final r = await db.rawQuery(
    'SELECT c.id FROM classifications c JOIN classification_groups g '
    'ON g.id = c.group_id WHERE g.code = ? AND c.name = ?',
    [group, name],
  );
  return r.first['id']! as int;
}

Future<int> _addClass(Database db, String group, String name) async {
  final g = await db.rawQuery('SELECT id FROM classification_groups WHERE code = ?', [group]);
  return db.insert('classifications', {
    'group_id': g.first['id'],
    'name': name,
    'active': 1,
    'created_at': _t0,
  });
}

Future<int> _addTx(
  Database db, {
  required String code,
  required String source,
  required int classId,
  int amount = 10000,
  String? label,
  String? phone,
  String? account,
  int createdAt = _t0,
}) {
  return db.insert('transactions', {
    'display_code': code,
    'source_type': source,
    'amount_cents': amount,
    'transaction_cost_cents': source == 'CASH' ? null : 500,
    'counterparty_label': label,
    'counterparty_phone': phone,
    'paybill_account_number': account,
    'classification_id': classId,
    'raw_parse_source': source == 'CASH' ? 'MANUAL' : 'SMS_PARSE',
    'transaction_occurred_at': createdAt,
    'created_at': createdAt,
  });
}

BackupService _service(Database db) => BackupService(
      db: () async => db,
      now: () => DateTime.fromMillisecondsSinceEpoch(_t0 + 99999),
    );

/// Every table the backup reads, as plain rows, to prove nothing changed.
Future<List<Object?>> _snapshot(Database db) async => [
      await db.rawQuery('SELECT * FROM classifications ORDER BY id'),
      await db.rawQuery('SELECT * FROM transactions ORDER BY id'),
      await db.rawQuery('SELECT * FROM counterparty_classification_map ORDER BY id'),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('clean_database_reports_zero_repaired_and_zero_skipped', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    await _addTx(db, code: 'AB12CD34EF', source: 'SEND_MONEY', classId: family,
        label: 'JOHN DOE', phone: '0712345678');
    final r = await _service(db).export();
    expect(r.repairedCount, 0);
    expect(r.skipped, isEmpty);
    expect(r.skippedCount, 0);
    expect(r.deletedLeftOut, 0);
    expect(r.transactions, 1);
    await db.close();
  });

  test('legacy_control_character_is_repaired_and_restorable', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    await _addTx(db, code: 'AB12CD34EF', source: 'SEND_MONEY', classId: family,
        label: '  JOHN\u0007 \t DOE\n', phone: '0712 345\u0000678');
    final r = await _service(db).export();
    expect(r.repairedCount, 1); // one row, however many fields
    expect(r.skipped, isEmpty);
    final v = BackupValidator.validate(r.bytes);
    expect(v.transactions.single['counterparty_label'], 'JOHN DOE');
    expect(v.transactions.single['counterparty_phone'], '0712 345678');
    await db.close();
  });

  test('overlong_name_is_cut_to_the_limit', () async {
    final db = await _openDb();
    await _addClass(db, 'SEND_MONEY', '${'N' * 99}\u{1F600}tail');
    final r = await _service(db).export();
    expect(r.repairedCount, 1);
    final v = BackupValidator.validate(r.bytes);
    final cut = v.classifications.last['name']! as String;
    expect(cut.length, lessThanOrEqualTo(kBackupMaxClassificationNameLength));
    expect(cut.startsWith('N' * 99), isTrue);
    expect(cut.contains('tail'), isFalse);
    // a half emoji is never left behind
    expect(cut.codeUnits.last, 0x4E);
    await db.close();
  });

  test('unfixable_rows_are_skipped_and_reported_without_values', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    await _addTx(db, code: 'GOOD000001', source: 'SEND_MONEY', classId: family,
        label: 'OK', phone: '0712345678');
    final badAmount = await _addTx(db, code: 'BIGAMOUNT1', source: 'SEND_MONEY',
        classId: family, amount: kBackupMaxAmountCents + 1,
        label: 'SECRETNAME', phone: '0700000000');
    final badPhone = await _addTx(db, code: 'BADPHONE01', source: 'SEND_MONEY',
        classId: family, label: 'X', phone: 'call me maybe');
    // dangling foreign key (a database that once had foreign keys off)
    await db.execute('PRAGMA foreign_keys = OFF');
    final dangling = await _addTx(db, code: 'DANGLING01', source: 'BUY_GOODS',
        classId: 99999);
    await db.execute('PRAGMA foreign_keys = ON');

    final r = await _service(db).export();
    expect(r.transactions, 1);
    expect(r.skippedCount, 3);
    final byId = {for (final s in r.skipped) s.rowId: s};
    expect(byId[badAmount]!.field, 'amount_cents');
    expect(byId[badPhone]!.field, 'counterparty_phone');
    expect(byId[dangling]!.field, 'classification');
    expect(byId[dangling]!.rule, 'dangling reference');
    for (final s in r.skipped) {
      expect(s.table, 'transactions');
      final text = s.toString();
      expect(text.contains('SECRETNAME'), isFalse);
      expect(text.contains('call me'), isFalse);
    }
    final text = utf8.decode(r.bytes);
    expect(text.contains('SECRETNAME'), isFalse);
    expect(text.contains('GOOD000001'), isTrue);
    await db.close();
  });

  test('several_bad_rows_still_produce_a_valid_file', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    final shop = await _classId(db, 'BUY_GOODS', 'Shopping');
    final weird = await _addClass(db, 'SEND_MONEY', '\u0001\u0002'); // empty once cleaned
    await _addClass(db, 'SEND_MONEY', 'X' * 400);
    await _addTx(db, code: 'OK00000001', source: 'BUY_GOODS', classId: shop);
    await _addTx(db, code: 'OK00000002', source: 'SEND_MONEY', classId: family,
        label: 'A\tB', phone: ' 0712345678 ');
    await _addTx(db, code: 'OK00000003', source: 'SEND_MONEY', classId: weird,
        label: 'C', phone: '0722222222'); // follows the skipped class
    await _addTx(db, code: 'NEG0000001', source: 'BUY_GOODS', classId: shop,
        amount: 0 + kBackupMaxAmountCents + 5);
    // a cash row on a group that is switched off later
    await _addTx(db, code: 'CASH-20260921-1030', source: 'CASH', classId: shop,
        createdAt: _t0 + 5);
    await db.execute("UPDATE classification_groups SET enabled = 0 WHERE code = 'BUY_GOODS'");
    await db.insert('counterparty_classification_map', {
      'source_type': 'SEND_MONEY', 'counterparty_key': 'a\u0000b',
      'classification_id': family, 'auto_apply': 1, 'updated_at': _t0,
    });

    final r = await _service(db).export();
    // The file the service returns passes the validator on its own.
    final v = BackupValidator.validate(r.bytes, enabledGroupCodes: {'SEND_MONEY', 'PAYBILL'});
    expect(v.transactions.length, r.transactions);
    expect(r.skippedCount, greaterThanOrEqualTo(4));
    expect(r.repairedCount, greaterThanOrEqualTo(3));
    expect(r.skipped.any((s) => s.table == 'classifications' && s.field == 'name'), isTrue);
    expect(r.skipped.any((s) => s.rule == 'its classification was skipped'), isTrue);
    expect(v.counterpartyMap.single['counterparty_key'], 'ab');
    expect(r.bytes.isNotEmpty, isTrue);
    await db.close();
  });

  test('colliding_names_after_repair_are_resolved_by_skipping_not_failing', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    await db.insert('counterparty_classification_map', {
      'source_type': 'SEND_MONEY', 'counterparty_key': 'a\tb',
      'classification_id': family, 'auto_apply': 1, 'updated_at': _t0,
    });
    await db.insert('counterparty_classification_map', {
      'source_type': 'SEND_MONEY', 'counterparty_key': 'a b',
      'classification_id': family, 'auto_apply': 1, 'updated_at': _t0,
    });
    final r = await _service(db).export();
    // Either the repair or the validator backstop dropped one; the file is valid.
    expect(r.counterpartyMap, 1);
    expect(BackupValidator.validate(r.bytes).counterpartyMap, hasLength(1));
    await db.close();
  });

  test('database_rows_are_unchanged_after_export', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    await _addClass(db, 'SEND_MONEY', '  messy\tname\u0007 ');
    await _addTx(db, code: 'AB12CD34EF', source: 'SEND_MONEY', classId: family,
        label: 'JO\nHN', phone: '07 12\u0000345678');
    await _addTx(db, code: 'BIGAMOUNT1', source: 'SEND_MONEY', classId: family,
        amount: kBackupMaxAmountCents + 1, label: 'Z', phone: '0711111111');
    final before = await _snapshot(db);
    final r = await _service(db).export();
    expect(r.repairedCount, greaterThan(0));
    expect(r.skippedCount, 1);
    expect(await _snapshot(db), before);
    await db.close();
  });

  test('a_paybill_key_of_301_characters_exports', () async {
    final db = await _openDb();
    final rent = await _classId(db, 'PAYBILL', 'Rent Payment');
    final key = '${'L' * 200}#${'9' * 100}';
    expect(key.length, 301);
    await db.insert('counterparty_classification_map', {
      'source_type': 'PAYBILL', 'counterparty_key': key,
      'classification_id': rent, 'auto_apply': 1, 'updated_at': _t0,
    });
    final r = await _service(db).export();
    expect(r.repairedCount, 0);
    expect(r.skipped, isEmpty);
    expect(BackupValidator.validate(r.bytes).counterpartyMap.single['counterparty_key'], key);
    expect(kBackupMaxCounterpartyKeyLength, 310);
    await db.close();
  });

  test('phone_with_dashes_dots_and_brackets_is_kept_in_clean_form', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    final a = await _addTx(db, code: 'PHONE00001', source: 'SEND_MONEY', classId: family,
        label: 'A', phone: '(0712) 345-678');
    final b = await _addTx(db, code: 'PHONE00002', source: 'SEND_MONEY', classId: family,
        label: 'B', phone: '+254-712.345.678');
    final r = await _service(db).export();
    expect(r.skipped, isEmpty);
    expect(r.repairedCount, 2);
    final v = BackupValidator.validate(r.bytes);
    final phones = {for (final t in v.transactions) t['id']: t['counterparty_phone']};
    expect(phones[a], '0712 345678');
    expect(phones[b], '+254712345678');
    await db.close();
  });

  test('colliding_class_name_is_renamed_and_its_transactions_kept', () async {
    final db = await _openDb();
    final first = await _addClass(db, 'SEND_MONEY', 'Gym');
    final second = await _addClass(db, 'SEND_MONEY', 'Gym\t'); // 'Gym' once cleaned
    final third = await _addClass(db, 'SEND_MONEY', 'Gym  ');
    final t1 = await _addTx(db, code: 'GYM0000001', source: 'SEND_MONEY', classId: first,
        label: 'A', phone: '0711111111');
    final t2 = await _addTx(db, code: 'GYM0000002', source: 'SEND_MONEY', classId: second,
        label: 'B', phone: '0722222222');
    final t3 = await _addTx(db, code: 'GYM0000003', source: 'SEND_MONEY', classId: third,
        label: 'C', phone: '0733333333');
    final r = await _service(db).export();
    expect(r.skipped, isEmpty);
    expect(r.repairedCount, 2);
    final v = BackupValidator.validate(r.bytes);
    final names = {for (final c in v.classifications) c['id']: c['name']};
    expect(names[first], 'Gym');
    expect(names[second], 'Gym (2)');
    expect(names[third], 'Gym (3)');
    final cls = {for (final t in v.transactions) t['id']: t['classification']};
    expect(cls, {t1: first, t2: second, t3: third});
    await db.close();
  });

  test('a_long_colliding_name_is_cut_to_make_room_for_the_suffix', () async {
    final db = await _openDb();
    await _addClass(db, 'SEND_MONEY', 'L' * 100);
    await _addClass(db, 'SEND_MONEY', '${'L' * 100} '); // trims to the same
    final r = await _service(db).export();
    expect(r.skipped, isEmpty);
    final names = BackupValidator.validate(r.bytes).classifications
        .map((c) => c['name']! as String)
        .toList();
    expect(names, contains('${'L' * 96} (2)'));
    expect(names.every((n) => n.length <= 100), isTrue);
    await db.close();
  });

  test('map_key_follows_the_repaired_transaction_so_they_agree', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    await _addTx(db, code: 'KEY0000001', source: 'SEND_MONEY', classId: family,
        label: 'A', phone: '0712-345-678');
    await db.insert('counterparty_classification_map', {
      'source_type': 'SEND_MONEY', 'counterparty_key': '0712-345-678',
      'classification_id': family, 'auto_apply': 1, 'updated_at': _t0,
    });
    final r = await _service(db).export();
    expect(r.skipped, isEmpty);
    expect(r.repairedCount, 2); // the transaction and the map row
    final v = BackupValidator.validate(r.bytes);
    expect(v.transactions.single['counterparty_phone'], '0712345678');
    expect(v.counterpartyMap.single['counterparty_key'], '0712345678');
    await db.close();
  });

  test('lowercase_display_code_is_uppercased', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    await _addTx(db, code: ' ab12cd34ef ', source: 'SEND_MONEY', classId: family,
        label: 'A', phone: '0712345678');
    final r = await _service(db).export();
    expect(r.skipped, isEmpty);
    expect(r.repairedCount, 1);
    expect(BackupValidator.validate(r.bytes).transactions.single['display_code'], 'AB12CD34EF');
    // a code that is still invalid afterwards is skipped
    await _addTx(db, code: 'short', source: 'SEND_MONEY', classId: family,
        label: 'A', phone: '0712345678');
    final r2 = await _service(db).export();
    expect(r2.skipped.single.field, 'display_code');
    await db.close();
  });

  test('cleanText_unit_cases', () {
    expect(BackupRepair.cleanText('  a \t\n b  ', 50), 'a b');
    expect(BackupRepair.cleanText('a\u0000b', 50), 'ab');
    expect(BackupRepair.cleanText('a${String.fromCharCode(0x202E)}b', 50), 'ab');
    expect(BackupRepair.cleanText('abcdef', 3), 'abc');
    expect(BackupRepair.cleanText('ab \u{1F600}', 4), 'ab');
    expect(BackupRepair.cleanText('\u0001\u0002', 50), '');
  });
}
