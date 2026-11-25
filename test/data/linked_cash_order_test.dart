// F13 (0.2.2): a withdrawal and its linked Cash entry share one date and time. The Cash
// entry is saved later, so in every newest-first list it must sit ABOVE its withdrawal.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/export_dao.dart';
import 'package:mmogo/data/db/home_dashboard_dao.dart';
import 'package:mmogo/data/db/linked_cash_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/restore_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late int w;
  late int entry;

  setUp(() async {
    db = await openTestDb();
    final rent = await seedId(db, 'SEND_MONEY:rent');
    final wc = await seedId(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
    w = await db.insert('transactions', {
      'display_code': 'WDR0000001',
      'source_type': 'AGENT_WITHDRAWAL',
      'amount_cents': 500000,
      'transaction_cost_cents': 3500,
      'counterparty_label': 'TEST AGENT',
      'agent_number': '123456',
      'classification_id': wc,
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': t0,
      'created_at': t0,
    });
    entry = await LinkedCashDao.createLinkedCash(db,
        withdrawalId: w, classificationId: rent, amountCents: 200000);
  });
  tearDown(() => db.close());

  test('Home recent: the Cash entry is above its withdrawal', () async {
    final rows = await HomeDashboardDao.recentTransactions(db);
    expect(rows.map((r) => r.id).toList(), [entry, w]);
  });

  test('Analytics list: the Cash entry is above its withdrawal', () async {
    final rows = await AnalyticsDao.itemizedTransactions(db,
        startMs: 0, endMs: 9999999999999, types: {'AGENT_WITHDRAWAL', 'CASH'});
    expect(rows.map((r) => r.id).toList(), [entry, w]);
  });

  test('CSV export order: the Cash entry is above its withdrawal', () async {
    final rows = await ExportDao.activeTransactions(db);
    expect(rows.map((r) => r.sourceType).toList(), ['CASH', 'AGENT_WITHDRAWAL']);
  });
}
