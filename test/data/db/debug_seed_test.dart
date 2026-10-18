// 0.1.2 F9 (R40): every row the debug seed writes must pass the same code
// check the backup validator uses, so a debug build's backup holds every seed
// row. Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/db/debug_seed.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('every debug seed row has a display code the backup validator accepts', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: 3,
            singleInstance: false,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, v) async {
              await AppSchema.createSchema(db);
              await AppSchema.seed(db);
            }));
    await DebugSampleData.seedIfEmpty(db);
    final rows = await db.rawQuery('SELECT source_type, display_code FROM transactions');
    expect(rows, isNotEmpty);
    for (final r in rows) {
      final code = r['display_code'] as String;
      final ok = r['source_type'] == 'CASH'
          ? kBackupCashCodePattern.hasMatch(code)
          : kBackupMpesaCodePattern.hasMatch(code);
      expect(ok, isTrue, reason: 'seed row ${r['source_type']} "$code"');
    }
    await db.close();
  });
}
