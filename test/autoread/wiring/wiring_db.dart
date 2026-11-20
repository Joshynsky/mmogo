// Helper for the wiring tests: an in-memory ledger with the real schema and seeds, a few rows, and the
// ids of one category per group. Invented data only.
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openWiringDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (d, v) async {
            await AppSchema.createSchema(d);
            await AppSchema.seed(d);
          }));
}

/// The active category ids of a group (by its code, e.g. SEND_MONEY), lowest first.
Future<List<int>> categoriesOf(Database db, String group) async {
  final rows = await db.rawQuery(
      'SELECT c.id FROM classifications c JOIN classification_groups g ON g.id = c.group_id '
      'WHERE g.code = ? AND c.active = 1 ORDER BY c.id',
      [group]);
  return [for (final r in rows) r['id']! as int];
}

/// Adds one Send Money row for Jane (0712345678).
Future<int> addSendMoney(Database db,
        {required String code, required int category, String source = 'SMS_PARSE', String phone = '0712345678'}) =>
    TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: code,
          sourceType: 'SEND_MONEY',
          amountCents: 10000,
          transactionCostCents: 0,
          counterpartyLabel: 'Jane Doe',
          counterpartyPhone: phone,
          paybillAccountNumber: null,
          classificationId: category,
          rawParseSource: source,
          transactionOccurredAt: DateTime(2026, 11, 19, 10).millisecondsSinceEpoch,
        ));
