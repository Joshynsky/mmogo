// Builds a real 0.1.1 (version 2) database FILE: the frozen schema + seed
// (schema_v2.dart) opened through the app's shared open function, then filled
// with INVENTED rows only (no real names, numbers or amounts).
import 'package:mmogo/data/db/db_open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema_v2.dart';

const int kFixtureNow = 1790000000000;

/// Creates [path] as a version-2 database (frozen DDL + 12 seeds at
/// [kFixtureNow]) and, when [populate] is set, adds invented rows. Returns the
/// OPEN database; the caller closes it.
Future<Database> buildV2Database(String path, {bool populate = true}) async {
  sqfliteFfiInit();
  final db = await openMmogoDatabase(
    databaseFactoryFfi,
    path,
    version: 2,
    singleInstance: false,
    onCreate: (db, v) async {
      await AppSchemaV2.createSchema(db);
      await AppSchemaV2.seed(db, nowMs: kFixtureNow);
    },
    onUpgrade: (db, a, b) async => throw StateError('fixture is never upgraded'),
  );
  if (populate) await fillV2Invented(db);
  return db;
}

Future<int> _group(Database db, String code) async => firstIntOf(
    await db.rawQuery('SELECT id FROM classification_groups WHERE code = ?', [code]))!;

/// Invented rows covering every source type, a soft-deleted row, a renamed and
/// a hidden built-in, user categories (one inactive), and learned receivers.
Future<void> fillV2Invented(Database db) async {
  final send = await _group(db, 'SEND_MONEY');
  final buy = await _group(db, 'BUY_GOODS');
  await db.update('classifications', {'name': 'House rent'}, where: 'id = 2');
  await db.update('classifications', {'active': 0}, where: 'id = 12');
  final church = await db.insert('classifications',
      {'group_id': send, 'name': 'Church', 'active': 1, 'created_at': kFixtureNow});
  await db.insert('classifications',
      {'group_id': buy, 'name': 'Old shop', 'active': 0, 'created_at': kFixtureNow});

  Future<void> tx(Map<String, Object?> m) => db.insert('transactions', {
        'raw_parse_source': 'MANUAL',
        'transaction_occurred_at': kFixtureNow,
        'created_at': kFixtureNow,
        ...m,
      });

  await tx({
    'display_code': 'TST0000001', 'source_type': 'SEND_MONEY', 'amount_cents': 12300,
    'transaction_cost_cents': 700, 'counterparty_label': 'Test Person One',
    'counterparty_phone': '0700000001', 'classification_id': 1,
  });
  await tx({
    'display_code': 'TST0000002', 'source_type': 'SEND_MONEY', 'amount_cents': 4500,
    'transaction_cost_cents': 0, 'classification_id': church,
  });
  await tx({
    'display_code': 'TST0000003', 'source_type': 'BUY_GOODS', 'amount_cents': 8800,
    'transaction_cost_cents': 0, 'counterparty_label': 'Test Shop',
    'classification_id': 9,
  });
  await tx({
    'display_code': 'TST0000004', 'source_type': 'PAYBILL', 'amount_cents': 99900,
    'transaction_cost_cents': 1100, 'counterparty_label': 'Test Landlord',
    'paybill_account_number': 'ACC-0001', 'classification_id': 5,
  });
  await tx({
    'display_code': 'CASH-20260101-0101', 'source_type': 'CASH', 'amount_cents': 2000,
    'classification_id': 3,
  });
  await tx({
    'display_code': 'TST0000005', 'source_type': 'SEND_MONEY', 'amount_cents': 100,
    'transaction_cost_cents': 0, 'classification_id': 2, 'deleted_at': kFixtureNow + 5,
  });
  await db.insert('counterparty_classification_map', {
    'source_type': 'SEND_MONEY', 'counterparty_key': '0700000001',
    'classification_id': 1, 'auto_apply': 1, 'updated_at': kFixtureNow + 1,
  });
  await db.insert('counterparty_classification_map', {
    'source_type': 'BUY_GOODS', 'counterparty_key': 'test shop',
    'classification_id': 9, 'auto_apply': 0, 'updated_at': kFixtureNow + 2,
  });
}
