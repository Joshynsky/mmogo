// S3 Test Engineer follow-ups (QA-1): tests only, invented data only.
//  1. re-key scope (mutant M22): PAYBILL / BUY_GOODS map rows are never touched;
//  2. digest guard (mutant M16): the post-migration transactions digest can fire;
//  3. existing damage (RISK-1): a v2 file with a foreign-key violation keeps
//     failing to open, stays v2 and loses nothing (the known "UPG-3 loop").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v3.dart';
import 'package:mmogo/data/db/migration_v3_rekey.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/v2_fixture.dart';
import '../../support/db_dump.dart';

const _t = kFixtureNow;

late Directory _dir;
int _n = 0;
String _path(String name) => '${_dir.path}${Platform.pathSeparator}${name}_${_n++}.db';

Future<Database> _openLive(String path) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);

Future<Database> _openRaw(String path, {bool readOnly = false}) =>
    databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(readOnly: readOnly, singleInstance: false));

Future<List<String>> _readDump(String path) async {
  final db = await _openRaw(path, readOnly: true);
  final uv = firstIntOf(await db.rawQuery('PRAGMA user_version'));
  final d = await fullDump(db);
  await db.close();
  return ['uv=$uv', ...d];
}

/// Every column of every non-SEND_MONEY map row, by id.
Future<List<String>> _otherMapRows(DatabaseExecutor db) async => (await db.rawQuery(
        "SELECT * FROM counterparty_classification_map WHERE source_type != 'SEND_MONEY' ORDER BY id"))
    .map((r) => r.values.join('|'))
    .toList();

Future<void> _map(Database db, String src, String key, int cls, int auto, int updated) =>
    db.insert('counterparty_classification_map', {
      'source_type': src,
      'counterparty_key': key,
      'classification_id': cls,
      'auto_apply': auto,
      'updated_at': updated,
    });

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() => _dir = Directory.systemTemp.createTempSync('mmogo_v3fu_'));
  tearDown(() {
    migrateToV3Hook = null;
    try {
      _dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('re-key scope: only SEND_MONEY rows are ever re-keyed (M22)', () {
    test('phone-shaped BUY_GOODS / PAYBILL keys stay byte-identical; only SEND_MONEY work is counted',
        () async {
      final path = _path('scope');
      final db = await buildV2Database(path); // map ids 1 (SEND_MONEY) and 2 (BUY_GOODS)
      await _map(db, 'BUY_GOODS', '254712345678', 9, 1, _t + 11); // phone-shaped, would rewrite
      await _map(db, 'BUY_GOODS', '0712345678', 9, 0, _t + 12); // would merge with the one above
      await _map(db, 'PAYBILL', '0712345678#X', 5, 1, _t + 13);
      await _map(db, 'PAYBILL', '254712345678', 5, 0, _t + 14);
      await _map(db, 'SEND_MONEY', '0711000001', 2, 1, _t + 20); // loser, other category, auto
      await _map(db, 'SEND_MONEY', '+254711000001', 1, 0, _t + 30); // winner, rewritten
      await _map(db, 'SEND_MONEY', '0722000002', 1, 0, _t + 21); // loser, same category
      await _map(db, 'SEND_MONEY', '254722000002', 1, 0, _t + 31); // winner, rewritten
      await db.close();

      final v2 = await _openRaw(path, readOnly: true);
      final otherBefore = await _otherMapRows(v2);
      await v2.close();
      expect(otherBefore, hasLength(5), reason: 'ids 2 and the four planted rows');

      lastPhoneRekeyReport = null;
      final up = await _openLive(path);
      expect(await _otherMapRows(up), otherBefore, reason: 'ids, keys, classes, auto_apply, updated_at');
      expect(
          lastPhoneRekeyReport,
          const PhoneRekeyReport(
            mapBefore: 10,
            mapAfter: 8,
            keysRewritten: 2,
            groupsMerged: 2,
            losersDeleted: 2,
            losersWithDifferentCategory: 1,
            losersWithAutoApply: 1,
          ));
      expect(await mapRows(up), [
        'SEND_MONEY|0700000001|1|1|${_t + 1}',
        'BUY_GOODS|test shop|9|0|${_t + 2}',
        'BUY_GOODS|254712345678|9|1|${_t + 11}',
        'BUY_GOODS|0712345678|9|0|${_t + 12}',
        'PAYBILL|0712345678#X|5|1|${_t + 13}',
        'PAYBILL|254712345678|5|0|${_t + 14}',
        'SEND_MONEY|0711000001|1|0|${_t + 30}',
        'SEND_MONEY|0722000002|1|0|${_t + 31}',
      ]);
      await up.close();
    });
  });

  group('digest guard: a copy that loses or changes a transaction row is caught (M16)', () {
    /// Opens [path] through the real ladder step, running [sql] on the migration's
    /// own executor when the hook reaches [label]. Returns the error (or null).
    Future<Object?> openWithTamper(String path, String label, String? sql) async {
      try {
        final db = await openMmogoDatabase(databaseFactoryFfi, path,
            singleInstance: false,
            onUpgrade: (db, a, b) => AppMigrations.upgrade(db, a, b, steps: {
                  3: (d) {
                    migrateToV3Hook = (l) async {
                      if (l == label && sql != null) await d.execute(sql);
                    };
                    return migrateToV3(d);
                  },
                }));
        await db.close();
        return null;
      } catch (e) {
        return e;
      } finally {
        migrateToV3Hook = null;
      }
    }

    Future<String> v2Path() async {
      final path = _path('digest');
      await (await buildV2Database(path)).close();
      return path;
    }

    test('POSITIVE CONTROL: the same seam with a harmless statement migrates cleanly', () async {
      final path = await v2Path();
      expect(await openWithTamper(path, 'seq_restore', 'SELECT 1'), isNull);
      final up = await _openRaw(path, readOnly: true);
      expect(firstIntOf(await up.rawQuery('PRAGMA user_version')), 3);
      await up.close();
    });

    final cases = {
      'a row is lost': ('seq_restore', 'DELETE FROM transactions WHERE id = 1'),
      'an amount changes': ('index_1', 'UPDATE transactions SET amount_cents = amount_cents + 1 WHERE id = 2'),
      'a label changes length': ('trigger_2', "UPDATE transactions SET counterparty_label = 'x' || IFNULL(counterparty_label, '') WHERE id = 1"),
    };
    cases.forEach((name, c) {
      test('$name mid-migration: the open throws "digest changed" and the file stays v2, untouched',
          () async {
        final path = await v2Path();
        final pre = await _readDump(path);
        final error = await openWithTamper(path, c.$1, c.$2);
        expect(error, isNotNull, reason: 'the digest check must fire');
        expect('$error', contains('transactions digest changed'));
        expect(await _readDump(path), pre, reason: 'rolled back to the v2 file');
      });
    });
  });

  group('existing damage: a v2 file with a foreign-key violation (RISK-1, "UPG-3 loop")', () {
    test('every open throws the foreign_key_check StateError; the file stays v2 with all rows intact',
        () async {
      final path = _path('damaged');
      final db = await buildV2Database(path);
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.insert('transactions', {
        'display_code': 'TSTORPHAN1', 'source_type': 'BUY_GOODS', 'amount_cents': 100,
        'transaction_cost_cents': 0, 'classification_id': 9999, 'raw_parse_source': 'MANUAL',
        'transaction_occurred_at': _t, 'created_at': _t,
      });
      expect(await db.rawQuery('PRAGMA foreign_key_check'), hasLength(1));
      await db.close();
      final planted = await _readDump(path);
      expect(planted.first, 'uv=2');

      Future<Object?> tryOpen() async {
        try {
          await (await _openLive(path)).close();
          return null;
        } catch (e) {
          return e;
        }
      }

      for (var attempt = 1; attempt <= 2; attempt++) {
        final error = await tryOpen();
        expect(error, isA<StateError>(), reason: 'open #$attempt must throw');
        expect('$error', contains('foreign_key_check found 1 violation'), reason: 'open #$attempt');
        expect(await _readDump(path), planted,
            reason: 'open #$attempt: still v2, every row and sqlite_master entry intact');
      }
    });

    test('NEGATIVE CONTROL: the same file without the violation opens and reaches v3', () async {
      final path = _path('clean');
      await (await buildV2Database(path)).close();
      final db = await _openLive(path);
      expect(firstIntOf(await db.rawQuery('PRAGMA user_version')), 3);
      await db.close();
    });
  });
}
