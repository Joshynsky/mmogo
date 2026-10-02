// B9: BackupService (exporter) against a REAL in-memory database with the
// real schema, triggers and unique indexes. Plain test(), never testWidgets.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
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

Future<int> _addClass(Database db, String group, String name, {int active = 1}) async {
  final g = await db.rawQuery(
      'SELECT id FROM classification_groups WHERE code = ?', [group]);
  return db.insert('classifications', {
    'group_id': g.first['id'],
    'name': name,
    'active': active,
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
  int? deletedAt,
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
    'deleted_at': deletedAt,
  });
}

/// A varied, realistic database. Returns the db.
Future<Database> _populated() async {
  final db = await _openDb();
  final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
  final rent = await _classId(db, 'PAYBILL', 'Rent Payment');
  final shop = await _classId(db, 'BUY_GOODS', 'Shopping');
  // a renamed built-in and an inactive user class
  await db.rawUpdate("UPDATE classifications SET name = 'Landlord' WHERE id = ?", [rent]);
  final school = await _addClass(db, 'SEND_MONEY', 'School fees');
  await _addClass(db, 'SEND_MONEY', 'Retired', active: 0);
  await _addTx(db, code: 'AB12CD34EF', source: 'SEND_MONEY', classId: family,
      label: 'JOHN DOE', phone: '0712345678');
  await _addTx(db, code: 'QWE123RTY4', source: 'PAYBILL', classId: rent,
      label: 'KPLC', account: '12345', createdAt: _t0 + 10);
  await _addTx(db, code: 'ZXC123VBN5', source: 'BUY_GOODS', classId: shop, createdAt: _t0 + 20);
  await _addTx(db, code: 'CASH-20260921-1030', source: 'CASH', classId: school, createdAt: _t0 + 30);
  await _addTx(db, code: 'CASH-20260921-1030', source: 'CASH', classId: family, createdAt: _t0 + 40);
  await db.insert('counterparty_classification_map', {
    'source_type': 'SEND_MONEY', 'counterparty_key': '0712345678',
    'classification_id': family, 'auto_apply': 1, 'updated_at': _t0,
  });
  return db;
}

BackupService _service(Database db, {int? maxBytes}) => BackupService(
      db: () async => db,
      now: () => DateTime.fromMillisecondsSinceEpoch(_t0 + 99999),
      maxBytes: maxBytes ?? kBackupMaxBytes,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('export_round_trip_equals_source', () async {
    SharedPreferences.setMockInitialValues({
      'palette_id': 'indigo',
      'user_display_name': 'Amina',
      'update_check_enabled': false, // must never be exported
      'auto_backup_folder_uri': 'content://tree/x', // must never be exported
    });
    final db = await _populated();
    final result = await _service(db).export();
    final v = BackupValidator.validate(result.bytes);

    // Source rows, read the same way a person would read the DB.
    final srcClasses = await db.rawQuery(
      'SELECT c.id, g.code AS "group", c.name, c.active, c.seed_key, c.created_at '
      'FROM classifications c JOIN classification_groups g ON g.id = c.group_id ORDER BY c.id',
    );
    final srcTx = await db.rawQuery(
      'SELECT id, display_code, source_type, amount_cents, transaction_cost_cents, '
      'counterparty_label, counterparty_phone, paybill_account_number, '
      'classification_id AS classification, raw_parse_source, '
      'transaction_occurred_at, created_at FROM transactions ORDER BY id',
    );
    final srcMap = await db.rawQuery(
      'SELECT source_type, counterparty_key, classification_id AS classification, '
      'auto_apply, updated_at FROM counterparty_classification_map ORDER BY id',
    );
    expect(v.classifications, srcClasses);
    expect(v.transactions, srcTx);
    expect(v.counterpartyMap, srcMap);
    expect(v.createdAt, _t0 + 99999);
    expect(v.prefs, {'palette_id': 'indigo', 'user_display_name': 'Amina'});
    expect(result.classifications, 14);
    expect(result.transactions, 5);
    expect(result.counterpartyMap, 1);
    expect(result.excludedSoftDeleted, 0);
    // Seeds carry their key, including the renamed built-in; users do not.
    final landlord = v.classifications.firstWhere((c) => c['name'] == 'Landlord');
    expect(landlord['seed_key'], 'PAYBILL:rent_payment');
    expect(v.classifications.where((c) => c['seed_key'] != null), hasLength(12));
    // The raw text never mentions the forbidden settings.
    final text = utf8.decode(result.bytes);
    expect(text.contains('update_check_enabled'), isFalse);
    expect(text.contains('content://'), isFalse);
    expect(text.contains('deleted_at'), isFalse);
    await db.close();
  });

  test('export_excludes_soft_deleted', () async {
    final db = await _populated();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    await _addTx(db, code: 'DEL0000001', source: 'SEND_MONEY', classId: family,
        label: 'GONE ONE', phone: '0700000001', deletedAt: _t0 + 5);
    await _addTx(db, code: 'DEL0000002', source: 'CASH', classId: family,
        deletedAt: _t0 + 6, createdAt: _t0 + 6);
    final result = await _service(db).export();
    expect(result.excludedSoftDeleted, 2);
    expect(result.transactions, 5);
    final text = utf8.decode(result.bytes);
    expect(text.contains('DEL0000001'), isFalse);
    expect(text.contains('GONE ONE'), isFalse);
    expect(text.contains('0700000001'), isFalse);
    await db.close();
  });

  test('export_excluded_count_is_zero_when_nothing_deleted', () async {
    final db = await _openDb();
    final result = await _service(db).export();
    expect(result.excludedSoftDeleted, 0);
    expect(result.transactions, 0);
    expect(result.classifications, 12);
    await db.close();
  });

  test('filename_has_no_personal_data', () async {
    SharedPreferences.setMockInitialValues({
      'user_display_name': 'Joshua Mwangi 0712345678',
    });
    final db = await _populated();
    final service = _service(db);
    final pattern = kBackupManualFileNamePattern;
    expect(pattern.pattern, r'^mmogo-backup-\d{8}-\d{6}\.json$');
    expect(service.suggestedFileName(DateTime(2026, 10, 2, 9, 30, 5)),
        'mmogo-backup-20261002-093005.json');
    // The name depends on the time only, whatever the data holds.
    for (final hostile in ['Joshua', "'; DROP--", '0712345678', '../../etc', 'A' * 300]) {
      SharedPreferences.setMockInitialValues({'user_display_name': hostile});
      final name = _service(db).suggestedFileName(DateTime(2026, 1, 5, 23, 59, 59));
      expect(pattern.hasMatch(name), isTrue, reason: name);
      expect(name, 'mmogo-backup-20260105-235959.json');
    }
    // Single digits are padded.
    expect(service.suggestedFileName(DateTime(2026, 1, 2, 3, 4, 5)),
        'mmogo-backup-20260102-030405.json');
    await db.close();
  });

  test('export_ends_with_tail_marker', () async {
    final db = await _populated();
    final bytes = await _service(db).exportToBytes();
    expect(utf8.decode(bytes).endsWith('"end":"mmogo-v1"}'), isTrue);
    // and the app marker is where the auto-backup prune looks for it
    expect(utf8.decode(bytes.sublist(0, 256)).contains('"app":"mmogo"'), isTrue);
    await db.close();
  });

  test('export_20k_rows_under_20mb', () async {
    final db = await _openDb();
    final family = await _classId(db, 'SEND_MONEY', 'Family/Friends');
    final shop = await _classId(db, 'BUY_GOODS', 'Shopping');
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < 20000; i++) {
        final isSend = i.isEven;
        batch.insert('transactions', {
          'display_code': 'X${i.toString().padLeft(9, '0')}',
          'source_type': isSend ? 'SEND_MONEY' : 'BUY_GOODS',
          'amount_cents': 10000 + i,
          'transaction_cost_cents': 500,
          'counterparty_label': isSend ? 'RECEIVER NUMBER $i WITH A FAIRLY LONG NAME' : null,
          'counterparty_phone': isSend ? '0712${(100000 + i).toString()}' : null,
          'paybill_account_number': null,
          'classification_id': isSend ? family : shop,
          'raw_parse_source': 'SMS_PARSE',
          'transaction_occurred_at': _t0 + i,
          'created_at': _t0 + i,
        });
      }
      await batch.commit(noResult: true);
    });
    final sw = Stopwatch()..start();
    final result = await _service(db).export();
    sw.stop();
    expect(result.transactions, 20000);
    expect(result.bytes.length, lessThan(kBackupMaxBytes));
    // ignore: avoid_print
    print('export of 20,000 rows: ${result.bytes.length} bytes in ${sw.elapsedMilliseconds} ms (incl. round-trip validation)');
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('export_over_cap_throws_BackupTooLarge', () async {
    final db = await _populated();
    // The guard uses backup_limits.dart; a small cap proves it fires.
    final ok = await _service(db).export();
    final tooSmall = ok.bytes.length - 1;
    await expectLater(
      _service(db, maxBytes: tooSmall).export(),
      throwsA(isA<BackupTooLarge>().having((e) => e.what, 'what', 'bytes')),
    );
    // Exactly at the cap is fine.
    final atCap = await _service(db, maxBytes: ok.bytes.length).export();
    expect(atCap.bytes.length, ok.bytes.length);
    // The production default is the 20 MB constant.
    expect(_service(db).maxBytes, kBackupMaxBytes);
    expect(kBackupMaxBytes, 20 * 1024 * 1024);
    await db.close();
  });

  test('export_over_row_cap_throws_BackupTooLarge', () async {
    final db = await _openDb();
    final shop = await _classId(db, 'BUY_GOODS', 'Shopping');
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < kBackupMaxTransactions + 1; i++) {
        batch.insert('transactions', {
          'display_code': 'Y${i.toString().padLeft(9, '0')}',
          'source_type': 'BUY_GOODS',
          'amount_cents': 100,
          'transaction_cost_cents': 0,
          'classification_id': shop,
          'raw_parse_source': 'SMS_PARSE',
          'transaction_occurred_at': _t0,
          'created_at': _t0,
        });
      }
      await batch.commit(noResult: true);
    });
    await expectLater(
      _service(db).export(),
      throwsA(isA<BackupTooLarge>().having((e) => e.what, 'what', 'transactions')),
    );
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a legacy over-long name no longer fails the export (B9b: it is cut)', () async {
    final db = await _populated();
    await _addClass(db, 'SEND_MONEY', 'N' * 150); // over the 100 limit
    final result = await _service(db).export();
    expect(result.repairedCount, 1);
    expect(result.skipped, isEmpty);
    await db.close();
  });

  test('export_works_when_cash_sits_on_a_default_group', () async {
    // Pochi la Biashara is disabled by default; its classes must not make a
    // normal database unexportable. (No Pochi cash rows can exist: trigger.)
    final db = await _populated();
    final result = await _service(db).export();
    expect(result.bytes, isNotEmpty);
    await db.close();
  });
}
