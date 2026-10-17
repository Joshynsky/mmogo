// F3 (R41): the Backup result reads "18 categories (1 you made)". The number in
// the bracket is counted by the exporter from the categories that went INTO the
// file (no seed_key). In-memory only: the file format is unchanged. A real
// in-memory database with the real schema; plain test(), never testWidgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

Future<void> _addClass(Database db, String name, {int active = 1}) async {
  final g = await db.rawQuery("SELECT id FROM classification_groups WHERE code = 'SEND_MONEY'");
  await db.insert('classifications', {
    'group_id': g.first['id'],
    'name': name,
    'active': active,
    'created_at': 1790000000000,
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh phone: 17 built-in categories, none made by the person: no bracket', () async {
    final db = await _openDb();
    addTearDown(db.close);
    final e = await BackupService(db: () async => db).export();
    expect(e.classifications, 17);
    expect(e.userClassifications, 0);
    final c = e.sharedCounts;
    expect(backupSharedCountsLine(c.transactions, c.categories, e.counterpartyMap, userCategories: c.userCategories),
        '0 transactions, 17 categories and 0 saved receivers went to the share sheet.');
  });

  test('one category made by the person: "18 categories (1 you made)"; a hidden one still counts', () async {
    final db = await _openDb();
    addTearDown(db.close);
    await _addClass(db, 'Invented Hobby');
    final e = await BackupService(db: () async => db).export();
    expect(e.classifications, 18);
    expect(e.userClassifications, 1);
    var c = e.sharedCounts;
    expect(backupSharedCountsLine(c.transactions, c.categories, e.counterpartyMap, userCategories: c.userCategories),
        '0 transactions, 18 categories (1 you made) and 0 saved receivers went to the share sheet.');
    await _addClass(db, 'Invented Hidden Hobby', active: 0);
    final e2 = await BackupService(db: () async => db).export();
    expect(e2.userClassifications, 2);
    c = e2.sharedCounts;
    expect(c.userCategories, 2);
  });
}
