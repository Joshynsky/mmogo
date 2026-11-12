// 0.2.0 S12 slice A: schema v3 -> v4 (`fuliza_events`). Invented data only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/open_classifier.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/schema_v1.dart';
import '../../fixtures/v2_fixture.dart';

late Directory _dir;
int _n = 0;
String _path(String name) => '${_dir.path}/${name}_${_n++}.db';

Future<Database> _openLive(String path) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false);

Future<Database> _openAt(String path, int version) =>
    openMmogoDatabase(databaseFactoryFfi, path, singleInstance: false, version: version);

/// A real version-3 file with invented rows (a v2 fixture upgraded by the live v3 step only).
Future<String> _v3File() async {
  final path = _path('v3');
  await (await buildV2Database(path)).close();
  await (await _openAt(path, 3)).close();
  return path;
}

Future<int> _uv(Database db) async => firstIntOf(await db.rawQuery('PRAGMA user_version'))!;

const _dataTables = [
  'classification_groups',
  'classifications',
  'transactions',
  'counterparty_classification_map',
];

Future<Map<String, List<Map<String, Object?>>>> _rows(Database db) async => {
      for (final t in _dataTables)
        t: [for (final r in await db.rawQuery('SELECT * FROM $t ORDER BY id')) {...r}],
    };

/// After the v5 step the data tables equal [before] except for the Airtime
/// seed rename and ONE added classification row (WBS row 17).
void _expectRowsAfterV5(
    Map<String, List<Map<String, Object?>>> after, Map<String, List<Map<String, Object?>>> before) {
  for (final t in _dataTables) {
    if (t != 'classifications') expect(after[t], before[t], reason: t);
  }
  final a = after['classifications']!;
  final b = before['classifications']!;
  expect(a.length, b.length + 1);
  for (final r in b) {
    final now = a.firstWhere((x) => x['id'] == r['id']);
    if (r['seed_key'] == 'AIRTIME:airtime') {
      expect(now['name'], 'For myself');
      expect({...now}..remove('name'), {...r}..remove('name'));
    } else {
      expect(now, r);
    }
  }
}

Future<bool> _hasTable(Database db, String name) async =>
    (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [name]))
        .isNotEmpty;

String _norm(Object? v) => '$v'
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll('( ', '(')
    .replaceAll(' )', ')')
    .trim();

Future<List<String>> _defs(Database db) async => [
      for (final r in await db.rawQuery('SELECT type, name, tbl_name, sql FROM sqlite_master '
          "WHERE name LIKE '%fuliza%' ORDER BY type, name"))
        _norm(r.values.join('|'))
    ];

Map<String, Object?> _row({
  Object? kind = 'draw',
  Object? code = 'FUL0000001',
  Object? at = 1790000000000,
  Object? amount = 1000,
  Object? fee = 0,
  Object? total = 1000,
}) =>
    {
      'kind': kind,
      'code': code,
      'occurred_at': at,
      'amount_cents': amount,
      'fee_cents': fee,
      'printed_total_cents': total,
    };

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() => _dir = Directory.systemTemp.createTempSync('mmogo_v4_'));
  tearDown(() {
    try {
      _dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the live version is 5 and the ladder has step 5', () {
    expect(kDbVersion, 5);
    expect(AppMigrations.steps.keys, [2, 3, 4, 5]);
  });

  group('upgrade', () {
    test('a v3 file upgrades to v4: every row unchanged, table present and empty', () async {
      final path = await _v3File();
      final v3 = await _openAt(path, 3);
      expect(await _uv(v3), 3);
      expect(await _hasTable(v3, 'fuliza_events'), isFalse);
      final before = await _rows(v3);
      expect(before['transactions'], isNotEmpty);
      await v3.close();

      final db = await _openLive(path);
      expect(await _uv(db), 5);
      _expectRowsAfterV5(await _rows(db), before);
      expect(await _hasTable(db, 'fuliza_events'), isTrue);
      expect(firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM fuliza_events')), 0);
      await db.close();
    });

    test('foreign_keys is ON after the upgrade and foreign_key_check is empty', () async {
      final path = await _v3File();
      final db = await _openLive(path);
      expect(firstIntOf(await db.rawQuery('PRAGMA foreign_keys')), 1);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    });

    test('a v2 file upgrades all the way to v4', () async {
      final path = _path('v2');
      await (await buildV2Database(path)).close();
      final db = await _openLive(path);
      expect(await _uv(db), 5);
      expect(await _hasTable(db, 'fuliza_events'), isTrue);
      expect(firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM transactions')), greaterThan(0));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    });

    test('a v1 file upgrades all the way to v4', () async {
      final path = _path('v1');
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
      final db = await _openLive(path);
      expect(await _uv(db), 5);
      expect(await _hasTable(db, 'fuliza_events'), isTrue);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    });

    test('a failure inside _toV4 leaves the v3 file intact and the next open succeeds', () async {
      final path = await _v3File();
      final v3 = await _openAt(path, 3);
      final before = await _rows(v3);
      await v3.close();

      Object? error;
      try {
        await openMmogoDatabase(databaseFactoryFfi, path,
            singleInstance: false,
            onUpgrade: (db, a, b) => AppMigrations.upgrade(db, a, b, steps: {
                  4: (d) async {
                    await AppMigrations.steps[4]!(d);
                    throw StateError('forced failure after the DDL ran');
                  },
                }));
      } catch (e) {
        error = e;
      }
      expect(error, isA<StateError>());

      final still = await _openAt(path, 3);
      expect(await _uv(still), 3);
      expect(await _hasTable(still, 'fuliza_events'), isFalse, reason: 'rolled back');
      expect(await _rows(still), before);
      await still.close();

      final db = await _openLive(path);
      expect(await _uv(db), 5);
      expect(await _hasTable(db, 'fuliza_events'), isTrue);
      _expectRowsAfterV5(await _rows(db), before);
      await db.close();
    });
  });

  group('definition', () {
    test('a fresh install and an upgraded file have the identical fuliza definitions', () async {
      final up = await _openLive(await _v3File());
      final fresh = await _openLive(_path('fresh'));
      final a = await _defs(up);
      expect(a, hasLength(2), reason: 'the table and the unique index');
      expect(a, await _defs(fresh));
      await up.close();
      await fresh.close();
    });

    test('kind strings in the table equal the FulizaEventKind enum names', () async {
      final db = await _openLive(_path('kinds'));
      for (final k in FulizaEventKind.values) {
        await db.insert('fuliza_events', _row(kind: k.name, code: 'K_${k.name}'));
      }
      final stored = [
        for (final r in await db.rawQuery('SELECT kind FROM fuliza_events ORDER BY id')) r['kind']
      ];
      expect(stored, [for (final k in FulizaEventKind.values) k.name]);
      final sql = (await db.rawQuery("SELECT sql FROM sqlite_master WHERE name='fuliza_events'"))
          .first['sql']! as String;
      final listed = RegExp(r'kind IN \(([^)]*)\)').firstMatch(sql)!.group(1)!;
      expect(
        listed.split(',').map((s) => s.trim().replaceAll("'", '')).toSet(),
        {for (final k in FulizaEventKind.values) k.name},
      );
      await db.close();
    });

    test('each CHECK and the NOT NULLs reject a bad row at database level', () async {
      final db = await _openLive(_path('checks'));
      final bad = <String, Map<String, Object?>>{
        'unknown kind': _row(kind: 'repay_full'),
        'empty code': _row(code: ''),
        'null code': _row(code: null),
        'null time': _row(at: null),
        'zero amount': _row(amount: 0),
        'negative amount': _row(amount: -1),
        'negative fee': _row(fee: -1),
        'negative total': _row(total: -1),
        'null kind': _row(kind: null),
      };
      for (final e in bad.entries) {
        await expectLater(db.insert('fuliza_events', e.value), throwsA(isA<DatabaseException>()),
            reason: e.key);
      }
      expect(firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM fuliza_events')), 0);
      // The boundaries that are allowed.
      await db.insert('fuliza_events', _row(code: 'OK1', fee: 0, total: 0));
      await db.insert('fuliza_events', _row(code: 'OK2', total: null));
      await db.close();
    });

    test('the same (kind, code) twice is refused by the unique index; another kind may share a code',
        () async {
      final db = await _openLive(_path('uniq'));
      await db.insert('fuliza_events', _row());
      await expectLater(db.insert('fuliza_events', _row()), throwsA(isA<DatabaseException>()));
      await db.insert('fuliza_events', _row(kind: 'repayFull'));
      await db.close();
    });
  });

  group('open path', () {
    test('kUpg3ProofOnRecord is false', () {
      expect(kUpg3ProofOnRecord, isFalse);
    });

    test('a v4 file opens with the current code, no upgrade, data kept', () async {
      final path = _path('v4');
      final first = await _openLive(path);
      await first.insert('fuliza_events', _row());
      await first.close();
      var upgraded = false;
      final db = await openMmogoDatabase(databaseFactoryFfi, path,
          singleInstance: false, onUpgrade: (db, a, b) async => upgraded = true);
      expect(upgraded, isFalse);
      expect(await _uv(db), 5);
      expect(firstIntOf(await db.rawQuery('SELECT COUNT(*) FROM fuliza_events')), 1);
      await db.close();
    });

    // S12 slice B: `openMmogoDatabase` has an `onDowngrade` that throws, so a
    // database NEWER than this build is refused and never rewritten (sqflite
    // would otherwise open it and write the lower user_version into the header).
    test('a v6 file is REFUSED by openMmogoDatabase; user_version and rows are unchanged', () async {
      final path = _path('v6');
      final seed = await openMmogoDatabase(databaseFactoryFfi, path,
          singleInstance: false, version: 6, onCreate: (db, v) async {
        await AppSchema.createSchema(db);
        await AppSchema.seed(db);
      });
      await seed.insert('fuliza_events', _row());
      await seed.close();
      final before = await File(path).readAsBytes();

      await expectLater(_openLive(path), throwsA(isA<StateError>()));

      // Read the file back with a plain open (no version, so no callbacks):
      // the header still says 6 and the row is still there.
      final raw = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      expect(await _uv(raw), 6);
      expect(firstIntOf(await raw.rawQuery('SELECT COUNT(*) FROM fuliza_events')), 1);
      expect(firstIntOf(await raw.rawQuery('SELECT COUNT(*) FROM classifications')), 18);
      await raw.close();
      expect(await File(path).readAsBytes(), before, reason: 'the refused open wrote nothing');
    });

    test('a v6 file is refused with the default onDowngrade, so the classifier sees a plain failure (OPN-1)',
        () async {
      final path = _path('v6b');
      await (await openMmogoDatabase(databaseFactoryFfi, path,
              singleInstance: false, version: 6, onCreate: (db, v) async {}))
          .close();
      Object? error;
      try {
        await _openLive(path);
      } catch (e) {
        error = e;
      }
      expect(error, isA<StateError>());
      expect(kUpg3ProofOnRecord, isFalse);
    });
  });
}
