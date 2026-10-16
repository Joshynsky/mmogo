// 0.1.2 S10c: the real file evidence and the AppDatabase open stage, on TEMP
// ffi databases in a temp dir only. Never AppDatabase.instance, never a real file.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/app_database.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/open_classifier.dart';
import 'package:mmogo/data/db/open_evidence_file.dart';
import 'package:mmogo/data/db/open_stage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/v2_fixture.dart';

void main() {
  late Directory dir;
  late String path;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mmogo_s10c_');
    path = p.join(dir.path, 'test.db');
    expect(p.isWithin(Directory.systemTemp.absolute.path, File(path).absolute.path), isTrue);
    // A populated file whose header says version 2.
    final db = await openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);
    await db.execute('PRAGMA user_version = 2');
    await db.close();
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  FileOpenEvidence ev() => FileOpenEvidence(path: path, factory: databaseFactoryFfi);

  Future<void> tamper() async {
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    await db.execute("UPDATE classification_groups SET display_name = 'zzz' WHERE id = 1");
    await db.close();
  }

  test('header user_version is read from bytes 60-63; missing file, garbage and header 4', () async {
    expect(await ev().headerUserVersion(), 2);
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('PRAGMA user_version = 4');
    await db.close();
    expect(await ev().headerUserVersion(), 4);
    File(path).writeAsBytesSync(Uint8List(200)..fillRange(0, 200, 7));
    expect(await ev().headerUserVersion(), isNull);
    expect(await FileOpenEvidence(path: p.join(dir.path, 'none.db'), factory: databaseFactoryFfi).headerUserVersion(), isNull);
  });

  test('two snapshots of an untouched file are equal; a second connection changing a row makes them differ', () async {
    final a = await ev().takeSnapshot();
    final b = await ev().takeSnapshot();
    expect(a, isNotNull);
    expect(a, b);
    expect(a!.userVersion, 2);
    await tamper();
    final c = await ev().takeSnapshot();
    expect(c, isNotNull);
    // display_name is part of the canary read of classification_groups.
    expect(c, isNot(a));
  });

  test('transaction amounts and fees are part of the snapshot (invented row, changed by a second connection)', () async {
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    await db.insert('transactions', {
      'display_code': 'TST0000001',
      'source_type': 'SEND_MONEY',
      'amount_cents': 1000,
      'transaction_cost_cents': 50,
      'counterparty_label': 'Test Person',
      'counterparty_phone': '0700000000',
      'classification_id': 1,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': 1790000000000,
      'created_at': 1790000000000,
    });
    await db.close();
    final a = await ev().takeSnapshot();
    expect(a, await ev().takeSnapshot());
    final db2 = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    await db2.execute('UPDATE transactions SET transaction_cost_cents = 60');
    await db2.close();
    expect(await ev().takeSnapshot(), isNot(a));
  });

  test('a snapshot that cannot be taken is null or throws (garbage header, missing file)', () async {
    File(path).writeAsBytesSync(Uint8List(200)..fillRange(0, 200, 7));
    expect(await ev().takeSnapshot(), isNull);
    expect(await FileOpenEvidence(path: p.join(dir.path, 'none.db'), factory: databaseFactoryFfi).takeSnapshot(), isNull);
    // a missing file was NOT created by the read-only evidence
    expect(File(p.join(dir.path, 'none.db')).existsSync(), isFalse);
  });

  test('fileIsClean: true on a clean file; false with a planted journal or wal', () async {
    final snap = (await ev().takeSnapshot())!;
    expect(await ev().fileIsClean(snap), isTrue);
    File('$path-journal').writeAsBytesSync([1, 2, 3]);
    expect(await ev().fileIsClean(snap), isFalse);
    File('$path-journal').deleteSync();
    File('$path-wal').writeAsBytesSync([1, 2, 3]);
    expect(await ev().fileIsClean(snap), isFalse);
  });

  test('fileIsClean: false when the foreign-key violation count differs from the snapshot', () async {
    final snap = (await ev().takeSnapshot())!;
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('classifications', {'group_id': 999, 'name': 'orphan', 'active': 1, 'created_at': 1});
    await db.close();
    expect(await ev().fileIsClean(snap), isFalse);
  });

  group('end to end with the classifier (proof flag passed true; the constant stays false)', () {
    Future<Object?> failUpgrade() async {
      try {
        final db = await openMmogoDatabase(
          databaseFactoryFfi,
          path,
          singleInstance: false,
          onUpgrade: (db, o, n) async {
            await db.execute("UPDATE classification_groups SET display_name = 'half done'");
            throw StateError('step failed');
          },
        );
        await db.close();
        return null;
      } catch (e) {
        return e;
      }
    }

    test('a rolled-back upgrade throw = UPG-3 when the proof is on record', () async {
      final snap = await prepareOpenSnapshot(ev(), proofOnRecord: true);
      expect(snap, isNotNull);
      final err = await failUpgrade();
      expect(err, isNotNull);
      final k = await classifyOpenFailure(
        error: err!,
        stage: OpenStage.inUpgrade,
        snapshot: snap,
        evidence: ev(),
        proofOnRecord: true,
      );
      expect(k, OpenFailureKind.rolledBackUpgrade);
      // The same failure with the constant as shipped (false) is OPN-1.
      expect(
        await classifyOpenFailure(error: err, stage: OpenStage.inUpgrade, snapshot: snap, evidence: ev()),
        OpenFailureKind.other,
      );
    });

    test('negative control: a second connection tampering after the failure = OPN-1', () async {
      final snap = await prepareOpenSnapshot(ev(), proofOnRecord: true);
      final err = await failUpgrade();
      await tamper();
      final k = await classifyOpenFailure(
        error: err!,
        stage: OpenStage.inUpgrade,
        snapshot: snap,
        evidence: ev(),
        proofOnRecord: true,
      );
      expect(k, OpenFailureKind.other);
    });

    test('negative controls: planted journal, header 4, snapshot read-only open failing', () async {
      final snap = await prepareOpenSnapshot(ev(), proofOnRecord: true);
      File('$path-journal').writeAsBytesSync([9]);
      expect(
        await classifyOpenFailure(error: 1, stage: OpenStage.inUpgrade, snapshot: snap, evidence: ev(), proofOnRecord: true),
        OpenFailureKind.other,
      );
      File('$path-journal').deleteSync();

      final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
      await db.execute('PRAGMA user_version = 4');
      await db.close();
      expect(await prepareOpenSnapshot(ev(), proofOnRecord: true), isNull);
      expect(
        await classifyOpenFailure(error: 1, stage: OpenStage.inUpgrade, snapshot: snap, evidence: ev(), proofOnRecord: true),
        OpenFailureKind.other,
      );

      File(path).writeAsBytesSync(Uint8List(200)..fillRange(0, 200, 7));
      expect(await prepareOpenSnapshot(ev(), proofOnRecord: true), isNull);
    });

    test('an onConfigure throw is not in onUpgrade = OPN-1 (stage none)', () async {
      final snap = await prepareOpenSnapshot(ev(), proofOnRecord: true);
      Object? err;
      try {
        await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: kDbVersion,
            singleInstance: false,
            onConfigure: (db) => throw StateError('configure failed'),
          ),
        );
      } catch (e) {
        err = e;
      }
      expect(err, isNotNull);
      expect(
        await classifyOpenFailure(error: err!, stage: OpenStage.none, snapshot: snap, evidence: ev(), proofOnRecord: true),
        OpenFailureKind.other,
      );
    });
  });

  group('AppDatabase.lastOpenStage (temp file via forPath)', () {
    AppDatabase tempDb(String f) => AppDatabase.forPath(() async => f, factory: databaseFactoryFfi);

    test('a fresh file opens with the stage none (onCreate, no upgrade)', () async {
      final f = p.join(dir.path, 'fresh.db');
      final db = tempDb(f);
      await db.database;
      expect(db.lastOpenStage, OpenStage.none);
      await db.close();
    });

    test('an upgrade that throws leaves the stage inUpgrade; the attempt resets it', () async {
      final f = p.join(dir.path, 'broken.db');
      // user_version 2 but no tables: the v3 step cannot work.
      final raw = await databaseFactoryFfi.openDatabase(f, options: OpenDatabaseOptions(singleInstance: false));
      await raw.execute('PRAGMA user_version = 2');
      await raw.close();
      final db = tempDb(f);
      await expectLater(db.database, throwsA(anything));
      expect(db.lastOpenStage, OpenStage.inUpgrade);
      expect(db.isOpen, isFalse);
      // the header is unchanged: the upgrade rolled back
      expect(await FileOpenEvidence(path: f, factory: databaseFactoryFfi).headerUserVersion(), 2);
    });

    test('a successful upgrade ends at afterUpgrade', () async {
      final f = p.join(dir.path, 'v2.db');
      await (await buildV2Database(f)).close();
      final db = tempDb(f);
      await db.database;
      expect(db.lastOpenStage, OpenStage.afterUpgrade);
      await db.close();
    });
  });
}
