// 0.2.1: backup / restore of the auto-record marker (schema 8: the optional row key
// `recorded_auto`, written only when 1). Real in-memory sqlite; hand-built files for the reader.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/backup_limits_020.dart';
import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

RestoreService svc(Database db) => RestoreService(
  db: () async => db,
  backup: backupOf(db),
  safety: FakeSafetyCopyStore([]),
  settings: BackupSettings(prefs: SharedPreferences.getInstance),
  validateInIsolate: false,
);

Future<int> _add(
  Database db,
  String code, {
  String source = 'SEND_MONEY',
  int auto = 0,
  String? raw,
  int at = t0,
  int? deleted,
}) async {
  final cls = await seedId(db, switch (source) {
    'PAYBILL' => 'PAYBILL:rent_payment',
    'AIRTIME' => 'AIRTIME:airtime',
    _ => 'SEND_MONEY:rent',
  });
  return db.insert('transactions', {
    'display_code': code,
    'source_type': source,
    'amount_cents': 10000,
    'transaction_cost_cents': source == 'CASH' ? null : 500,
    if (source == 'SEND_MONEY') 'counterparty_label': 'TEST PERSON',
    if (source == 'SEND_MONEY') 'counterparty_phone': '0712345678',
    if (source == 'PAYBILL') 'counterparty_label': 'TEST CO',
    if (source == 'PAYBILL') 'paybill_account_number': '123',
    'classification_id': cls,
    'raw_parse_source': raw ?? (source == 'CASH' ? 'MANUAL' : 'SMS_PARSE'),
    'transaction_occurred_at': at,
    'created_at': at,
    'recorded_automatically': auto,
    'deleted_at': deleted,
  });
}

Future<List<String>> _dump(DatabaseExecutor db) async => [
  for (final r in await db.rawQuery(
    'SELECT display_code, source_type, recorded_automatically FROM transactions '
    'WHERE deleted_at IS NULL ORDER BY display_code',
  ))
    r.values.join('|'),
];

List<Map<String, Object?>> _txs(Object json) =>
    ((json as Map)['transactions']! as List).cast<Map<String, Object?>>();

Future<Database> _phone() async {
  final db = await openTestDb();
  await _add(db, 'SND0000001', auto: 1, at: t0 + 1);
  await _add(db, 'SND0000002', at: t0 + 2);
  await _add(db, 'PAY0000001', source: 'PAYBILL', auto: 1, at: t0 + 3);
  await _add(db, 'AIR0000001', source: 'AIRTIME', at: t0 + 4);
  await _add(
    db,
    'SND0000003',
    auto: 1,
    at: t0 + 5,
    deleted: t0 + 9,
  ); // undone: not exported
  return db;
}

Map<String, Object?> _fileTx(
  int id, {
  Object? auto,
  String source = 'SEND_MONEY',
  String? raw,
}) => {
  ...tx(
    id,
    source == 'CASH'
        ? 'CASH-20260101-01${id.toString().padLeft(2, '0')}'
        : 'SND${id.toString().padLeft(7, '0')}',
    source,
    source == 'CASH' ? 2 : 1,
    label: source == 'SEND_MONEY' ? 'TEST PERSON' : null,
    phone: source == 'SEND_MONEY' ? '0712345678' : null,
    createdAt: f0 + id,
  ),
  'raw_parse_source': ?raw,
  'recorded_auto': ?auto,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('export', () {
    test(
      'schema 8; recorded_auto written ONLY when 1 (every other row keeps its 13 keys); undone rows are not in the file',
      () async {
        final db = await _phone();
        final export = await backupOf(db).export();
        expect(export.skippedCount, 0);
        final json =
            jsonDecode(utf8.decode(export.bytes)) as Map<String, Object?>;
        expect(json['schema_version'], 9); // 0.2.2: schema 9 (changed on purpose)
        expect(json['format_version'], 1);
        final rows = {
          for (final r in _txs(json)) r['display_code']! as String: r,
        };
        expect(rows.keys.toSet(), {
          'SND0000001',
          'SND0000002',
          'PAY0000001',
          'AIR0000001',
        });
        expect(rows['SND0000001']!['recorded_auto'], 1);
        expect(rows['PAY0000001']!['recorded_auto'], 1);
        expect(rows['SND0000002']!.keys.toList(), kBackupTransactionKeys);
        expect(rows['AIR0000001']!.keys.toList(), kBackupTransactionKeys);
        await db.close();
      },
    );
  });

  group('round trip', () {
    test(
      'merge into an empty phone and replace onto a phone with other data: the flags come back the same',
      () async {
        final a = await _phone();
        final file = await backupOf(a).exportToBytes();
        final want = (await _dump(a));
        expect(want.where((l) => l.endsWith('|1')), hasLength(2));
        for (final mode in RestoreMode.values) {
          final b = await openTestDb();
          if (mode == RestoreMode.replace) await _add(b, 'OLD0000001', auto: 1);
          await svc(b).restore(file, mode);
          expect(await _dump(b), want, reason: mode.name);
          await b.close();
        }
        await a.close();
      },
    );

    test(
      'a restored flagged row can still be undone and brought back; the flag stays 1',
      () async {
        final a = await _phone();
        final b = await openTestDb();
        await svc(
          b,
        ).restore(await backupOf(a).exportToBytes(), RestoreMode.merge);
        await b.rawUpdate(
          "UPDATE transactions SET deleted_at = 5 WHERE display_code = 'SND0000001'",
        );
        await b.rawUpdate(
          "UPDATE transactions SET deleted_at = NULL WHERE display_code = 'SND0000001'",
        );
        expect(
          (await _dump(b)).where((l) => l.startsWith('SND0000001')).single,
          'SND0000001|SEND_MONEY|1',
        );
        await a.close();
        await b.close();
      },
    );
  });

  group('old backups restore with every flag 0', () {
    for (final schema in [5, 6, 7]) {
      test('a schema $schema file', () async {
        final b = await openTestDb();
        final file = fileBytes(
          fileJson(
            classes: seedRowsV5(),
            txs: [
              _fileTx(1),
              _fileTx(2),
              tx(3, 'CASH-20260101-0103', 'CASH', 2, createdAt: f0 + 3),
            ],
            schemaVersion: schema,
          ),
        );
        final result = await svc(b).restore(file, RestoreMode.merge);
        expect(result.tally.transactions.added, 3);
        expect(
          await b.rawQuery(
            'SELECT recorded_automatically FROM transactions WHERE recorded_automatically != 0',
          ),
          isEmpty,
        );
        await b.close();
      });

      test(
        'a schema $schema file that carries recorded_auto is refused (exact keys)',
        () {
          final j = fileJson(
            classes: seedRowsV5(),
            txs: [_fileTx(1, auto: 1)],
            schemaVersion: schema,
          );
          expect(
            () => BackupValidator.validate(fileBytes(j)),
            throwsA(
              isA<RestoreRejected>().having(
                (e) => e.reason,
                'reason',
                RestoreRejectReason.invalidRow,
              ),
            ),
          );
        },
      );
    }

    test(
      'the committed anonymised schema 2 fixture still restores with flags 0',
      () async {
        final b = await openTestDb();
        final bytes = File(
          'test/fixtures/backup_v2_anonymised.json',
        ).readAsBytesSync();
        await svc(b).restore(bytes, RestoreMode.replace);
        expect(
          await b.rawQuery(
            'SELECT 1 FROM transactions WHERE recorded_automatically != 0',
          ),
          isEmpty,
        );
        expect(
          await b.rawQuery('SELECT COUNT(*) AS n FROM transactions'),
          isNot(
            equals([
              {'n': 0},
            ]),
          ),
        );
        await b.close();
      },
    );
  });

  group('validator (schema 8)', () {
    ValidatedBackup run(List<Map<String, Object?>> txs) =>
        BackupValidator.validate(
          fileBytes(
            fileJson(classes: seedRowsV5(), txs: txs, schemaVersion: 8),
          ),
        );

    test('0 and 1 on a parsed non-Cash row are accepted', () {
      final v = run([_fileTx(1, auto: 1), _fileTx(2, auto: 0), _fileTx(3)]);
      expect(v.transactions.map((r) => r['recorded_auto']), [1, 0, null]);
    });

    test(
      '1 on a CASH row or on a MANUAL row is refused, naming recorded_auto and no value',
      () {
        for (final bad in [
          _fileTx(1, auto: 1, source: 'CASH'),
          _fileTx(2, auto: 1, raw: 'MANUAL'),
        ]) {
          expect(
            () => run([bad]),
            throwsA(
              isA<RestoreRejected>()
                  .having(
                    (e) => e.reason,
                    'reason',
                    RestoreRejectReason.invalidRow,
                  )
                  .having((e) => e.field, 'field', 'recorded_auto'),
            ),
          );
        }
      },
    );

    test('a wrong type or range is refused', () {
      for (final bad in <Object?>[
        2,
        -1,
        '1',
        true,
        1.5,
        null,
        <Object?>[1],
      ]) {
        expect(
          () => run([_fileTx(1, auto: bad)..['recorded_auto'] = bad]),
          throwsA(
            isA<RestoreRejected>().having(
              (e) => e.reason,
              'reason',
              RestoreRejectReason.invalidRow,
            ),
          ),
          reason: '$bad',
        );
      }
    });
  });

  group('older apps refuse a schema 8 file as newer', () {
    test(
      'this build writes schema 8, format 1; the frozen 0.2.0 limits (max schema 5) refuse it; nothing else in the envelope changed',
      () async {
        expect(kBackupSchemaVersion, 9);
        expect(kBackupFormatVersion, 1);
        final db = await _phone();
        final json =
            jsonDecode(utf8.decode((await backupOf(db).exportToBytes())))
                as Map<String, Object?>;
        expect(refusedAsNewerBy020(json), isTrue);
        // negative control: a file this build wrote in the 0.2.0 shape is accepted by those limits
        expect(refusedAsNewerBy020({...json, 'schema_version': 5}), isFalse);
        expect(kFixture020MaxSchema, lessThan(kBackupSchemaVersion));
        await db.close();
      },
    );

    test(
      'this build refuses schema 10 and format 2 as newer, writing nothing',
      () async {
        final b = await openTestDb();
        for (final j in [
          fileJson(classes: seedRowsV5(), txs: [_fileTx(1)], schemaVersion: 10),
          {
            ...fileJson(classes: seedRowsV5(), schemaVersion: 8),
            'format_version': 2,
          },
        ]) {
          await expectLater(
            svc(b).restore(fileBytes(j), RestoreMode.replace),
            throwsA(
              isA<RestoreRejected>().having(
                (e) => e.reason,
                'reason',
                RestoreRejectReason.newer,
              ),
            ),
          );
        }
        expect(await b.rawQuery('SELECT COUNT(*) AS n FROM transactions'), [
          {'n': 0},
        ]);
        await b.close();
      },
    );
  });

  group('restore guard: rules and levels are never written by a restore', () {
    test(
      'a file with auto-record rule keys in prefs and auto_apply = 1 on every map row writes no preference beyond the allowlist',
      () async {
        for (final mode in RestoreMode.values) {
          SharedPreferences.setMockInitialValues({});
          final b = await openTestDb();
          final file = fileBytes(
            fileJson(
              classes: seedRowsV5(),
              txs: [_fileTx(1, auto: 1)],
              map: [mapRow('SEND_MONEY', '0712345678', 2, autoApply: 1)],
              prefs: {
                'auto_record_rules_v1': '{"0712345678":"AUTO"}',
                'auto_record_level:0712345678': 'AUTO',
                'auto_undone_codes_v1': '["SND0000001"]',
                'auto_record_history_v1': '{}',
                'auto_record_enabled': true,
              },
              schemaVersion: 8,
            ),
          );
          await svc(b).restore(file, mode);
          final p = await SharedPreferences.getInstance();
          final allowed = {for (final s in kBackupSettingSpecs) s.prefsKey};
          expect(p.getKeys().difference(allowed), isEmpty, reason: mode.name);
          expect(
            p.getKeys().where((k) => k.contains('auto_')),
            isEmpty,
            reason: mode.name,
          );
          await b.close();
        }
      },
    );
  });
}
