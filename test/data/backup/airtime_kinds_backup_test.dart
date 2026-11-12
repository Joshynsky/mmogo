// WBS row 17 (J-row17 v2): backup schema 5, 18 seed keys, the rename survives
// restore of older files, the row shape does not change. Real in-memory database
// with the real schema; invented data only.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/domain/airtime/airtime_kind.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

Future<int> idOf(DatabaseExecutor db, String key) async =>
    (await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [key])).first['id']! as int;

Future<String> nameOf(DatabaseExecutor db, String key) async =>
    (await db.rawQuery('SELECT name FROM classifications WHERE seed_key = ?', [key])).first['name']! as String;

/// code -> seed_key of the category holding each live airtime row.
Future<Map<String, String>> airtimeKinds(DatabaseExecutor db) async => {
      for (final r in await db.rawQuery(
          'SELECT t.display_code AS code, c.seed_key AS k FROM transactions t '
          "JOIN classifications c ON c.id = t.classification_id WHERE t.source_type = 'AIRTIME'"))
        r['code']! as String: r['k']! as String,
    };

Future<void> addAirtimeTx(Database db, String code, String key) async => db.insert('transactions', {
      'display_code': code,
      'source_type': 'AIRTIME',
      'amount_cents': 500,
      'transaction_cost_cents': 0,
      'classification_id': await idOf(db, key),
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': t0,
      'created_at': t0,
    });

Future<RestoreRejected> rejected(Map<String, Object?> file) async {
  final db = await openTestDb();
  try {
    await svc(db).restore(fileBytes(file), RestoreMode.merge);
  } on RestoreRejected catch (e) {
    return e;
  } finally {
    await db.close();
  }
  fail('the file was accepted');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('backup_schema_version_equals_db_version_5', () {
    expect(kBackupSchemaVersion, 5);
  });

  test('backup_locked_seed_keys_include_new_key', () {
    expect(kBackupLockedSeedKeys, {
      'AGENT_WITHDRAWAL:cash_withdrawal',
      kAirtimeSeedMyself,
      kAirtimeSeedOther,
    });
  });

  test('backup_export_schema_5_has_18_classification_rows', () async {
    final db = await openTestDb();
    await addAirtimeTx(db, 'AIR0000001', kAirtimeSeedMyself);
    await addAirtimeTx(db, 'AIR0000002', kAirtimeSeedOther);
    final json = jsonDecode(utf8.decode(await backupOf(db).exportToBytes())) as Map<String, dynamic>;
    expect(json['schema_version'], 5);
    final classes = (json['classifications'] as List).cast<Map<String, dynamic>>();
    expect(classes, hasLength(18));
    expect(classes.where((c) => c['seed_key'] != null).map((c) => c['seed_key']), kBackupSeedKeys);
    final names = {for (final c in classes) c['seed_key']: c['name']};
    expect(names[kAirtimeSeedMyself], 'For myself');
    expect(names[kAirtimeSeedOther], 'For another number');
    // The row shape did not change: same 13 keys as a schema 3/4 row.
    final tx = (json['transactions'] as List).cast<Map<String, dynamic>>();
    expect(tx.first.keys.toSet(), kBackupTransactionKeys.toSet());
    expect(kBackupTransactionKeys, hasLength(13));
    expect(tx.first.keys, isNot(contains('airtime_other')));
    await db.close();
  });

  test('backup_roundtrip_other_category_rows_preserved', () async {
    final a = await openTestDb();
    await addAirtimeTx(a, 'AIR0000001', kAirtimeSeedMyself);
    await addAirtimeTx(a, 'AIR0000002', kAirtimeSeedOther);
    final bytes = await backupOf(a).exportToBytes();
    for (final mode in [RestoreMode.merge, RestoreMode.replace]) {
      final b = await openTestDb();
      final r = await svc(b).restore(bytes, mode);
      expect(r.transactions.added, 2);
      expect(await airtimeKinds(b), {'AIR0000001': kAirtimeSeedMyself, 'AIR0000002': kAirtimeSeedOther});
      expect(await nameOf(b, kAirtimeSeedOther), 'For another number');
      await b.close();
    }
    await a.close();
  });

  test('backup_schema4_file_airtime_named_airtime_restores_name_stays_for_myself', () async {
    final rows = seedRowsV3();
    expect(rows.firstWhere((r) => r['seed_key'] == kAirtimeSeedMyself)['name'], 'Airtime');
    final file = fileJson(
      classes: rows,
      txs: [tx(1, 'AIR0000001', 'AIRTIME', 14), tx(2, 'AIR0000002', 'AIRTIME', 14)],
      schemaVersion: 4,
    );
    for (final mode in [RestoreMode.merge, RestoreMode.replace]) {
      final db = await openTestDb();
      final liveId = await idOf(db, kAirtimeSeedMyself);
      final r = await svc(db).restore(fileBytes(file), mode);
      expect(r.transactions.added, 2);
      expect(await nameOf(db, kAirtimeSeedMyself), 'For myself');
      expect(await idOf(db, kAirtimeSeedMyself), liveId);
      expect(await airtimeKinds(db), {'AIR0000001': kAirtimeSeedMyself, 'AIR0000002': kAirtimeSeedMyself});
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      // The 18th category is still on the phone, untouched.
      expect(await nameOf(db, kAirtimeSeedOther), 'For another number');
      await db.close();
    }
  });

  test('backup_schema3_file_restores_rows_into_for_myself', () async {
    final file = fileJson(
      classes: seedRowsV3(),
      txs: [tx(1, 'AIR0000001', 'AIRTIME', 14)],
      schemaVersion: 3,
    );
    final db = await openTestDb();
    await svc(db).restore(fileBytes(file), RestoreMode.merge);
    expect(await airtimeKinds(db), {'AIR0000001': kAirtimeSeedMyself});
    expect(await nameOf(db, kAirtimeSeedMyself), 'For myself');
    await db.close();
  });

  test('a schema 2 file still restores (older ladders unchanged)', () async {
    final db = await openTestDb();
    final r = await svc(db).restore(
        fileBytes(fileJson(classes: seedRows(), txs: [tx(1, 'SMX0000001', 'SEND_MONEY', 1, label: 'A', phone: '0700000001')])),
        RestoreMode.merge);
    expect(r.transactions.added, 1);
    await db.close();
  });

  test('backup_schema4_file_with_for_another_number_key_refused', () async {
    for (final v in [3, 4]) {
      final e = await rejected(fileJson(classes: seedRowsV5(), schemaVersion: v));
      expect(e.reason, RestoreRejectReason.invalidRow, reason: 'schema $v');
      expect(e.field, 'seed_key');
    }
  });

  test('a schema 5 file may carry each key once, in its own group', () async {
    final db = await openTestDb();
    await svc(db).restore(fileBytes(fileJson(classes: seedRowsV5(), schemaVersion: 5)), RestoreMode.merge);
    await db.close();
    // Twice: refused.
    final dup = [...seedRowsV5(), cls(19, 'AIRTIME', 'Copy', seedKey: kAirtimeSeedOther)];
    expect((await rejected(fileJson(classes: dup, schemaVersion: 5))).field, 'seed_key');
    // In another group: refused.
    final wrong = [for (final r in seedRowsV5()) r['seed_key'] == kAirtimeSeedOther ? {...r, 'group': 'SEND_MONEY'} : r];
    expect((await rejected(fileJson(classes: wrong, schemaVersion: 5))).field, 'seed_key');
  });

  test('backup_replace_schema4_file_count_check_not_rolled_back', () async {
    final db = await openTestDb();
    await addAirtimeTx(db, 'AIR0000009', kAirtimeSeedOther);
    final file = fileJson(classes: seedRowsV3(), txs: [tx(1, 'AIR0000001', 'AIRTIME', 14)], schemaVersion: 4);
    final r = await svc(db).restore(fileBytes(file), RestoreMode.replace);
    expect(r.transactions.added, 1);
    expect(await db.rawQuery('SELECT COUNT(*) AS n FROM classifications WHERE seed_key IS NOT NULL'), [
      {'n': 18}
    ]);
    // The phone's own entries were replaced by the file's.
    expect(await airtimeKinds(db), {'AIR0000001': kAirtimeSeedMyself});
    await db.close();
  });

  test('backup_repair_never_repairs_seed_key', () {
    final repair = BackupRepair(
      classifications: [
        cls(1, 'AIRTIME', 'For myself', seedKey: kAirtimeSeedMyself),
        cls(2, 'AIRTIME', 'For another number', seedKey: kAirtimeSeedOther),
        cls(3, 'SEND_MONEY', 'Misplaced', seedKey: kAirtimeSeedOther), // wrong group, seen second
        cls(4, 'AIRTIME', 'Unknown key', seedKey: 'AIRTIME:made_up'),
      ],
      transactions: const [],
      counterpartyMap: const [],
      enabledGroupCodes: const {'SEND_MONEY', 'AIRTIME'},
    );
    expect(repair.classifications.map((c) => c['id']), [1, 2]);
    expect(repair.skipped.where((s) => s.field == 'seed_key'), hasLength(2));
    // The kept rows still carry their seed keys, unchanged.
    expect(repair.classifications.map((c) => c['seed_key']), [kAirtimeSeedMyself, kAirtimeSeedOther]);
  });

  test('backup_file_contains_no_phone_digits_for_other_row', () async {
    final db = await openTestDb();
    await addAirtimeTx(db, 'AIR0000002', kAirtimeSeedOther);
    final text = utf8.decode(await backupOf(db).exportToBytes());
    expect(text, isNot(contains('0712345678')));
    expect(text, isNot(contains('712345678')));
    expect(text, contains('For another number'));
    await db.close();
  });
}
