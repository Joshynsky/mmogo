// Invented rows for the spent-amount tests: one fresh current-schema database
// on real SQLite (sqflite_common_ffi), and a helper that inserts a valid row of
// any of the seven source types. No real data.
import 'package:mmogo/data/db/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The seven stored source types.
const spentTestTypes = [
  'SEND_MONEY',
  'PAYBILL',
  'BUY_GOODS',
  'POCHI_LA_BIASHARA',
  'AGENT_WITHDRAWAL',
  'AIRTIME',
  'CASH',
];

Future<Database> openSpentTestDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await AppSchema.createSchema(db);
        await AppSchema.seed(db);
      },
    ),
  );
}

Future<int> _classificationFor(Database db, String sourceType) async {
  // CASH rides on the first enabled M-Pesa group; every other type on its own.
  final group = sourceType == 'CASH' ? 'SEND_MONEY' : sourceType;
  final rows = await db.rawQuery(
    '''
    SELECT c.id FROM classifications c
    JOIN classification_groups g ON g.id = c.group_id
    WHERE g.code = ? ORDER BY c.id LIMIT 1
    ''',
    [group],
  );
  return rows.first['id'] as int;
}

/// Inserts one valid invented row. [feeCents] is ignored for CASH (no fee).
Future<int> insertSpentTx(
  Database db, {
  required String code,
  required String sourceType,
  required int amountCents,
  required int feeCents,
  required int occurredAtMs,
  int? deletedAtMs,
}) async {
  final cash = sourceType == 'CASH';
  final hasLabel = !cash && sourceType != 'AIRTIME';
  return db.insert('transactions', {
    'display_code': code,
    'source_type': sourceType,
    'amount_cents': amountCents,
    'transaction_cost_cents': cash ? null : feeCents,
    'counterparty_label': hasLabel ? 'Invented Name' : null,
    'counterparty_phone': sourceType == 'SEND_MONEY' ? '0700000000' : null,
    'paybill_account_number': sourceType == 'PAYBILL' ? '12345' : null,
    'classification_id': await _classificationFor(db, sourceType),
    'raw_parse_source': 'MANUAL',
    'transaction_occurred_at': occurredAtMs,
    'created_at': occurredAtMs,
    'deleted_at': deletedAtMs,
  });
}
