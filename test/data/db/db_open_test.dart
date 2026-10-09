// DB1 (S3a): the one shared open function and its foreign-key rule, proved on
// real database FILES (a temp dir), never in-memory (an in-memory database has
// no upgrade path).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/schema_v1.dart';
import '../../fixtures/v2_fixture.dart';

Future<int> _fk(DatabaseExecutor db) async =>
    firstIntOf(await db.rawQuery('PRAGMA foreign_keys'))!;

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('mmogo_dbopen_');
    path = '${dir.path}${Platform.pathSeparator}t.db';
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('fresh file: foreign_keys is ON in onCreate and after open', () async {
    int? inCreate;
    final db = await openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false,
        onCreate: (db, v) async {
      inCreate = await _fk(db);
      await AppSchema.createSchema(db);
      await AppSchema.seed(db);
    });
    expect(inCreate, 1);
    expect(await _fk(db), 1);
    await db.close();
  });

  test('upgrade of a v2 file to v3: OFF while onUpgrade runs, ON after open', () async {
    await (await buildV2Database(path)).close();
    int? inUpgrade;
    final db = await openMmogoDatabase(databaseFactoryFfi, path,
        version: 3, singleInstance: false, onUpgrade: (db, a, b) async {
      inUpgrade = await _fk(db);
      expect([a, b], [2, 3]);
    });
    expect(inUpgrade, 0, reason: 'the table rebuild needs foreign_keys OFF');
    expect(await _fk(db), 1, reason: 'ON again once the open has finished');
    expect(firstIntOf(await db.rawQuery('PRAGMA user_version')), 3);
    await db.close();
  });

  test('a file already at v3 opens with foreign_keys ON and runs no upgrade', () async {
    final first = await openMmogoDatabase(databaseFactoryFfi, path,
        version: 3, singleInstance: false, onCreate: (db, v) async {});
    await first.close();
    var upgraded = false;
    final db = await openMmogoDatabase(databaseFactoryFfi, path,
        version: 3, singleInstance: false, onUpgrade: (db, a, b) async {
      upgraded = true;
    });
    final state = await _fk(db);
    expect(upgraded, isFalse);
    expect(state, 1);
    await db.close();
  });

  test('live path unchanged: a v2 file opens at kDbVersion 2 with ON, no upgrade', () async {
    expect(kDbVersion, 2, reason: 'S3a does not flip the live version');
    await (await buildV2Database(path)).close();
    final db = await openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);
    expect(await _fk(db), 1);
    expect(firstIntOf(await db.rawQuery('PRAGMA user_version')), 2);
    await db.close();
  });

  test('live path unchanged: v1 -> v2 upgrade keeps foreign_keys ON throughout (0.1.1 behaviour)',
      () async {
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1,
            singleInstance: false,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, v) async {
              await AppSchemaV1.createSchema(db);
              await AppSchemaV1.seed(db);
            }));
    await v1.close();
    int? inUpgrade;
    final db = await openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false,
        onUpgrade: (db, a, b) async {
      inUpgrade = await _fk(db);
      await AppMigrations.migrate(db, a, b);
    });
    expect(inUpgrade, 1);
    expect(await _fk(db), 1);
    expect(kFkOffUpgradeFromTarget, 3);
    await db.close();
  });

  test('NEGATIVE CONTROL: the old plain open leaves foreign_keys ON during an upgrade '
      '(so the OFF assertion above can fail)', () async {
    await (await buildV2Database(path)).close();
    int? inUpgrade;
    final db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: (db, a, b) async => inUpgrade = await _fk(db),
        ));
    expect(inUpgrade, 1);
    expect(inUpgrade, isNot(0));
    await db.close();
  });

  test('after an upgrade open, foreign keys are enforced (RESTRICT refuses a delete)', () async {
    await (await buildV2Database(path)).close();
    final db = await openMmogoDatabase(databaseFactoryFfi, path,
        version: 3, singleInstance: false, onUpgrade: (db, a, b) async {});
    // class 1 is used by a transaction; deleting it must be refused with FK ON.
    await expectLater(db.rawDelete('DELETE FROM classifications WHERE id = 1'), throwsA(anything));
    await db.close();
  });
}
