// Shared helpers for the restore tests (B15, B16, B18): a REAL in-memory
// database with the real schema, triggers and unique indexes, a statement
// log taken by sqflite's own logger (independent of the code under test),
// row dumps, and a populated "phone".
// sqflite_common is sqflite_common_ffi's own dependency; only its logger is
// used, and only in tests.
// ignore_for_file: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int t0 = 1790000000000;

/// One executed SQL statement as sqflite saw it.
class Stmt {
  Stmt(this.sql, this.args);
  final String sql;
  final Object? args;
  String get verb => sql.trimLeft().split(RegExp(r'\s+')).first.toUpperCase();
  bool get isWrite => const {'INSERT', 'UPDATE', 'DELETE', 'REPLACE'}.contains(verb);
  @override
  String toString() => sql;
}

/// Opens a fresh version-2 in-memory database. When [log] is given every
/// statement (including each operation inside a batch) is appended to it by
/// sqflite's own logger.
Future<Database> openTestDb({List<Stmt>? log}) async {
  sqfliteFfiInit();
  DatabaseFactory factory = databaseFactoryFfi;
  if (log != null) {
    factory = SqfliteDatabaseFactoryLogger(
      databaseFactoryFfi,
      options: SqfliteLoggerOptions(
        type: SqfliteDatabaseFactoryLoggerType.all,
        log: (e) {
          if (e is SqfliteLoggerSqlEvent) {
            log.add(Stmt(e.sql, e.arguments));
          } else if (e is SqfliteLoggerBatchEvent) {
            for (final op in e.operations) {
              log.add(Stmt(op.sql, op.arguments));
            }
          }
        },
      ),
    );
  }
  return factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 2,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await AppSchema.createSchema(db);
        await AppSchema.seed(db);
      },
    ),
  );
}

BackupService backupOf(Database db) => BackupService(
      db: () async => db,
      now: () => DateTime.fromMillisecondsSinceEpoch(t0 + 999999),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
    );

Future<int> groupId(DatabaseExecutor db, String code) async => (await db.rawQuery(
        'SELECT id FROM classification_groups WHERE code = ?', [code]))
    .first['id']! as int;

Future<int> classId(DatabaseExecutor db, String group, String name) async =>
    (await db.rawQuery(
      'SELECT c.id FROM classifications c JOIN classification_groups g '
      'ON g.id = c.group_id WHERE g.code = ? AND c.name = ? ORDER BY c.active DESC, c.id',
      [group, name],
    ))
        .first['id']! as int;

Future<int> seedId(DatabaseExecutor db, String seedKey) async => (await db.rawQuery(
        'SELECT id FROM classifications WHERE seed_key = ?', [seedKey]))
    .first['id']! as int;

Future<int> addClass(DatabaseExecutor db, String group, String name,
        {int active = 1, int createdAt = t0}) async =>
    db.insert('classifications', {
      'group_id': await groupId(db, group),
      'name': name,
      'active': active,
      'created_at': createdAt,
    });

Future<int> addTx(
  DatabaseExecutor db, {
  required String code,
  required String source,
  required int classId,
  int amount = 10000,
  String? label,
  String? phone,
  String? account,
  int? deletedAt,
  int createdAt = t0,
}) =>
    db.insert('transactions', {
      'display_code': code,
      'source_type': source,
      'amount_cents': amount,
      'transaction_cost_cents': source == 'CASH' ? null : 500,
      'counterparty_label': label,
      'counterparty_phone': phone,
      'paybill_account_number': account,
      'classification_id': classId,
      'raw_parse_source': source == 'CASH' ? 'MANUAL' : 'SMS_PARSE',
      'transaction_occurred_at': createdAt,
      'created_at': createdAt,
      'deleted_at': deletedAt,
    });

Future<int> addMap(DatabaseExecutor db, String source, String key, int classId,
        {int autoApply = 1}) =>
    db.insert('counterparty_classification_map', {
      'source_type': source,
      'counterparty_key': key,
      'classification_id': classId,
      'auto_apply': autoApply,
      'updated_at': t0,
    });

/// A phone that has been used for a while: renamed and deactivated
/// built-ins, user classifications (active and not), every source type,
/// cash rows sharing a code, a recently deleted row, learned receivers.
Future<void> populate(Database db) async {
  await db.update('classifications', {'name': 'Landlord'},
      where: 'seed_key = ?', whereArgs: ['SEND_MONEY:rent']);
  await db.update('classifications', {'active': 0},
      where: 'seed_key = ?', whereArgs: ['BUY_GOODS:groceries']);
  final church = await addClass(db, 'SEND_MONEY', 'Church', createdAt: t0 + 1);
  final oldShop = await addClass(db, 'BUY_GOODS', 'Old shop', active: 0, createdAt: t0 + 2);
  final fees = await addClass(db, 'PAYBILL', 'School fees', createdAt: t0 + 3);
  final rent = await seedId(db, 'SEND_MONEY:rent');
  final shopping = await seedId(db, 'BUY_GOODS:shopping');

  await addTx(db, code: 'AAA1111111', source: 'SEND_MONEY', classId: rent,
      label: 'JANE DOE', phone: '0712345678', createdAt: t0 + 10);
  await addTx(db, code: 'AAA2222222', source: 'SEND_MONEY', classId: church, createdAt: t0 + 11);
  await addTx(db, code: 'BBB1111111', source: 'PAYBILL', classId: fees,
      label: 'SCHOOL', account: 'ADM 42', createdAt: t0 + 12);
  await addTx(db, code: 'CCC1111111', source: 'BUY_GOODS', classId: shopping,
      label: 'DUKA', createdAt: t0 + 13);
  await addTx(db, code: 'DDD1111111', source: 'BUY_GOODS', classId: oldShop, createdAt: t0 + 14);
  await addTx(db, code: 'CASH-20260921-1030', source: 'CASH', classId: church, createdAt: t0 + 15);
  await addTx(db, code: 'CASH-20260921-1030', source: 'CASH', classId: rent,
      amount: 777, createdAt: t0 + 16);
  // Recently deleted: never in a backup (A1).
  await addTx(db, code: 'EEE1111111', source: 'SEND_MONEY', classId: church,
      deletedAt: t0 + 100, createdAt: t0 + 17);
  await addMap(db, 'SEND_MONEY', '0712345678', rent);
  await addMap(db, 'PAYBILL', 'SCHOOL#ADM 42', fees, autoApply: 0);
}

/// Every row of the four tables plus `sqlite_sequence`, ids included.
Future<Map<String, List<Map<String, Object?>>>> fullDump(DatabaseExecutor db) async => {
      for (final t in const [
        'classification_groups',
        'classifications',
        'transactions',
        'counterparty_classification_map',
        'sqlite_sequence',
      ])
        t: [
          for (final r in await db.rawQuery(
              t == 'sqlite_sequence' ? 'SELECT * FROM sqlite_sequence ORDER BY name' : 'SELECT * FROM $t ORDER BY id'))
            Map<String, Object?>.of(r),
        ],
    };

/// The content of the user's data WITHOUT ids (references are followed to
/// the classification's group, name and seed key). Two databases holding the
/// same data compare equal even when their ids differ. Recently deleted
/// rows are included only when [withDeleted].
Future<Map<String, List<String>>> contentDump(DatabaseExecutor db, {bool withDeleted = false}) async {
  final classes = [
    for (final r in await db.rawQuery(
        'SELECT g.code, c.name, c.active, c.seed_key, c.created_at FROM classifications c '
        'JOIN classification_groups g ON g.id = c.group_id'))
      r.values.join('|'),
  ]..sort();
  final txs = [
    for (final r in await db.rawQuery(
        'SELECT t.display_code, t.source_type, t.amount_cents, t.transaction_cost_cents, '
        't.counterparty_label, t.counterparty_phone, t.paybill_account_number, '
        'g.code, c.name, c.seed_key, t.raw_parse_source, t.transaction_occurred_at, '
        't.created_at, t.deleted_at FROM transactions t '
        'JOIN classifications c ON c.id = t.classification_id '
        'JOIN classification_groups g ON g.id = c.group_id '
        '${withDeleted ? '' : 'WHERE t.deleted_at IS NULL'}'))
      r.values.join('|'),
  ]..sort();
  final map = [
    for (final r in await db.rawQuery(
        'SELECT m.source_type, m.counterparty_key, g.code, c.name, c.seed_key, '
        'm.auto_apply, m.updated_at FROM counterparty_classification_map m '
        'JOIN classifications c ON c.id = m.classification_id '
        'JOIN classification_groups g ON g.id = c.group_id'))
      r.values.join('|'),
  ]..sort();
  return {'classifications': classes, 'transactions': txs, 'counterparty_map': map};
}

/// Rows changed by INSERT/UPDATE/DELETE on this connection so far (SQLite's
/// own counter).
Future<int> totalChanges(DatabaseExecutor db) async =>
    (await db.rawQuery('SELECT total_changes() AS n')).first['n']! as int;

Future<Uint8List> exportOf(Database db) => backupOf(db).exportToBytes();
