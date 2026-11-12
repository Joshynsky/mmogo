import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/fuliza/fuliza_demo.dart';

/// INVENTED demo rows for the 0.2.0 UI checks (Paid to pages of 5, the Fuliza page and Home line), behind
/// the same debug-only define as the Fuliza demo (`MMOGO_FULIZA_DEMO`, see `fuliza_demo.dart`). Never runs
/// in a release build or without the define. Plain inserts into the existing `transactions` table: no
/// schema change. Runs once (skips when its first code is already there). No real names, numbers or amounts.
class DemoSeed {
  DemoSeed._();

  static Future<void> runIfOn(Database db, DateTime now) async {
    if (!fulizaDemoOn) return;
    final there = await db.rawQuery("SELECT 1 FROM transactions WHERE display_code = 'QDMPB00001' LIMIT 1");
    if (there.isNotEmpty) return;

    Future<int> cls(String group, String name) async {
      final rows = await db.rawQuery(
        'SELECT c.id FROM classifications c JOIN classification_groups g ON g.id = c.group_id WHERE g.code = ? AND c.name = ?',
        [group, name],
      );
      return rows.first['id'] as int;
    }

    final pbShopping = await cls('PAYBILL', 'Shopping');
    final bgShopping = await cls('BUY_GOODS', 'Shopping');
    final smFriends = await cls('SEND_MONEY', 'Family/Friends');
    final today = DateTime(now.year, now.month, now.day);
    int ms(DateTime d) => d.millisecondsSinceEpoch;

    Future<void> tx({
      required String code,
      required String type,
      required int amountKsh,
      required int costKsh,
      String? label,
      String? phone,
      String? account,
      required int classificationId,
      required DateTime at,
    }) => db.insert('transactions', {
      'display_code': code,
      'source_type': type,
      'amount_cents': amountKsh * 100,
      'transaction_cost_cents': costKsh * 100,
      'counterparty_label': label,
      'counterparty_phone': phone,
      'paybill_account_number': account,
      'classification_id': classificationId,
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': ms(at),
      'created_at': ms(at),
      'deleted_at': null,
    });

    // 25 accounts under one invented Paybill name (so the ACCOUNTS block has 5 pages of 5).
    for (var i = 0; i < 25; i++) {
      await tx(
        code: 'QDMPB${(i + 1).toString().padLeft(5, '0')}',
        type: 'PAYBILL',
        amountKsh: 120 + i * 35,
        costKsh: i.isEven ? 5 : 0,
        label: 'DIRECT PAY 04',
        account: '7100${(40 + i).toString()}',
        classificationId: pbShopping,
        at: today.subtract(Duration(days: i * 2)).add(Duration(hours: 8 + i % 9)),
      );
    }
    // A second invented name with two accounts, and one with a single account.
    for (var i = 0; i < 4; i++) {
      await tx(
        code: 'QDMPC${(i + 1).toString().padLeft(5, '0')}',
        type: 'PAYBILL',
        amountKsh: 300 + i * 50,
        costKsh: 5,
        label: 'DIRECT PAY 05',
        account: i < 2 ? '8200101' : '8200102',
        classificationId: pbShopping,
        at: today.subtract(Duration(days: 3 + i * 5)).add(const Duration(hours: 13)),
      );
    }

    // The ordinary payments the invented Fuliza borrowings paid for (codes in `demoFulizaCodes`).
    DateTime ago(int d, int h, int m) {
      final t = today.subtract(Duration(days: d));
      return DateTime(t.year, t.month, t.day, h, m);
    }

    await tx(
      code: 'QDMFL00001',
      type: 'BUY_GOODS',
      amountKsh: 900,
      costKsh: 0,
      label: 'JAVA HOUSE',
      classificationId: bgShopping,
      at: ago(6, 10, 2),
    );
    await tx(
      code: 'QDMFL00002',
      type: 'SEND_MONEY',
      amountKsh: 400,
      costKsh: 7,
      label: 'MARY WANJIKU',
      phone: '0722114455',
      classificationId: smFriends,
      at: ago(3, 15, 20),
    );
    await tx(
      code: 'QDMFL00004',
      type: 'PAYBILL',
      amountKsh: 500,
      costKsh: 0,
      label: 'DSTV KENYA',
      account: '5566',
      classificationId: pbShopping,
      at: ago(1, 18, 40),
    );
  }
}
