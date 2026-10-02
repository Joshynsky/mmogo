// B14: BackupCounts against a REAL in-memory database with the real schema.
// Plain test(), never testWidgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_counts.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

void main() {
  test('a fresh database has nothing to back up (seeded classifications do not count)', () async {
    final db = await _openDb();
    final c = await BackupCounts.read(db);
    expect(c.transactions, 0);
    expect(c.userClassifications, 0);
    expect(c.receivers, 0);
    expect(c.deletedLeftOut, 0);
    expect(c.isEmpty, isTrue);
    await db.close();
  });

  test('counts live transactions, user classifications, receivers, and deleted ones separately', () async {
    final db = await _openDb();
    final g = await db.rawQuery("SELECT id FROM classification_groups WHERE code = 'SEND_MONEY'");
    final groupId = g.first['id']! as int;
    final cls = await db.insert('classifications', {
      'group_id': groupId,
      'name': 'School fees',
      'active': 1,
      'created_at': 1790000000000,
    });
    Future<void> tx(String code, {int? deletedAt}) => db.insert('transactions', {
      'display_code': code,
      'source_type': 'SEND_MONEY',
      'amount_cents': 100,
      'transaction_cost_cents': 0,
      'counterparty_label': 'A',
      'counterparty_phone': '0712345678',
      'classification_id': cls,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': 1790000000000,
      'created_at': 1790000000000,
      'deleted_at': deletedAt,
    });
    await tx('AB12CD34E1');
    await tx('AB12CD34E2');
    await tx('AB12CD34E3', deletedAt: 1790000001000);
    await db.insert('counterparty_classification_map', {
      'source_type': 'SEND_MONEY',
      'counterparty_key': '0712345678',
      'classification_id': cls,
      'auto_apply': 1,
      'updated_at': 1790000000000,
    });
    final c = await BackupCounts.read(db);
    expect(c.transactions, 2);
    expect(c.userClassifications, 1);
    expect(c.receivers, 1);
    expect(c.deletedLeftOut, 1);
    expect(c.isEmpty, isFalse);
    await db.close();
  });
}
