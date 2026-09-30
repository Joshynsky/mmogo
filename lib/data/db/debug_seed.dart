import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// THROWAWAY VERIFICATION DATA ONLY — not `AppSchema`'s own seed data (see
/// `schema.dart`, which seeds only `classification_groups`/
/// `classifications`), and not real user data. This slice (T4) is the
/// first to read/write real `transactions` rows since T1 built the
/// schema, and there is no real transaction data seeded anywhere yet — so
/// Home has nothing real to render or to verify period-scoping/the
/// `deleted_at IS NULL` filter against without this.
///
/// Deliberately kept separate from [AppSchema.seed] (which runs
/// unconditionally at `onCreate`, in every build including release) so
/// whoever builds T3/T6 (the real Add flows) never needs to preserve or
/// clean up after this data:
///   - only runs when `kDebugMode` is true (never in a release build)
///   - only runs once — skips entirely if `transactions` already has ANY
///     rows, seeded or real, so a real Add flow's rows are never
///     clobbered or duplicated on a later launch
///
/// Seeds a small, varied sample: all 4 `source_type`s, timestamps spanning
/// today / this rolling week / this calendar month / last calendar month
/// (so the period selector's diff line has real prior-period data to
/// compare against for every one of its 3 settings, not just "no prior
/// data"), and one soft-deleted row (to prove the `deleted_at IS NULL`
/// filter actually excludes it, not just that the screen doesn't crash on
/// an empty table).
class DebugSampleData {
  DebugSampleData._();

  static Future<void> seedIfEmpty(Database db) async {
    if (!kDebugMode) return;

    final countRows = await db.rawQuery('SELECT COUNT(*) AS n FROM transactions');
    final existing = (countRows.first['n'] as num).toInt();
    if (existing > 0) return;

    Future<int> classificationId(String groupCode, String name) async {
      final rows = await db.rawQuery(
        '''
        SELECT c.id FROM classifications c
        JOIN classification_groups g ON g.id = c.group_id
        WHERE g.code = ? AND c.name = ?
        ''',
        [groupCode, name],
      );
      return rows.first['id'] as int;
    }

    final sendFamilyFriends = await classificationId('SEND_MONEY', 'Family/Friends');
    final sendRent = await classificationId('SEND_MONEY', 'Rent');
    final buyGoodsShopping = await classificationId('BUY_GOODS', 'Shopping');
    final buyGoodsGroceries = await classificationId('BUY_GOODS', 'Groceries');
    final paybillShopping = await classificationId('PAYBILL', 'Shopping');
    final paybillTransport = await classificationId('PAYBILL', 'Transport');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int ms(DateTime d) => d.millisecondsSinceEpoch;
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String cashCode(DateTime d) =>
        'CASH-${d.year}${twoDigits(d.month)}${twoDigits(d.day)}-${twoDigits(d.hour)}${twoDigits(d.minute)}';

    final yesterday = today.subtract(const Duration(days: 1));
    final fourDaysAgo = today.subtract(const Duration(days: 4));
    final nineDaysAgo = today.subtract(const Duration(days: 9)); // prior-week bucket
    final earlyThisMonth = DateTime(now.year, now.month, 3);
    final lastMonth = DateTime(now.year, now.month - 1, 15); // prior-month bucket

    Future<void> insertTx(Map<String, Object?> data) => db.insert('transactions', data);

    // 1. SEND_MONEY, today — active.
    await insertTx({
      'display_code': 'DBG-SEND1',
      'source_type': 'SEND_MONEY',
      'amount_cents': 150000,
      'transaction_cost_cents': 2200,
      'counterparty_label': 'JOHN KAMAU',
      'counterparty_phone': '0798630424',
      'paybill_account_number': null,
      'classification_id': sendFamilyFriends,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(today.add(const Duration(hours: 9))),
      'created_at': ms(today.add(const Duration(hours: 9))),
      'deleted_at': null,
    });

    // 2. BUY_GOODS, today — active.
    await insertTx({
      'display_code': 'DBG-BUY1',
      'source_type': 'BUY_GOODS',
      'amount_cents': 85000,
      'transaction_cost_cents': 0,
      'counterparty_label': 'NAIVAS SUPERMARKET',
      'counterparty_phone': null,
      'paybill_account_number': null,
      'classification_id': buyGoodsShopping,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(today.add(const Duration(hours: 11))),
      'created_at': ms(today.add(const Duration(hours: 11))),
      'deleted_at': null,
    });

    // 3. PAYBILL, yesterday — active (feeds Today period's prior-day diff).
    await insertTx({
      'display_code': 'DBG-PAY1',
      'source_type': 'PAYBILL',
      'amount_cents': 120000,
      'transaction_cost_cents': 1500,
      'counterparty_label': 'DSTV KENYA',
      'counterparty_phone': null,
      'paybill_account_number': '5566',
      'classification_id': paybillShopping,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(yesterday.add(const Duration(hours: 14))),
      'created_at': ms(yesterday.add(const Duration(hours: 14))),
      'deleted_at': null,
    });

    // 4. CASH, 4 days ago (within the current rolling week) — active.
    //    Cross-group per the trigger's CASH branch: references a
    //    Buy-Goods-group classification while itself typed CASH.
    await insertTx({
      'display_code': cashCode(fourDaysAgo),
      'source_type': 'CASH',
      'amount_cents': 50000,
      'transaction_cost_cents': null,
      'counterparty_label': null,
      'counterparty_phone': null,
      'paybill_account_number': null,
      'classification_id': buyGoodsGroceries,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(fourDaysAgo.add(const Duration(hours: 17))),
      'created_at': ms(fourDaysAgo.add(const Duration(hours: 17))),
      'deleted_at': null,
    });

    // 5. SEND_MONEY, 9 days ago (prior-week bucket, still this calendar
    //    month) — active.
    await insertTx({
      'display_code': 'DBG-SEND2',
      'source_type': 'SEND_MONEY',
      'amount_cents': 200000,
      'transaction_cost_cents': 2500,
      'counterparty_label': 'MARY WANJIKU',
      'counterparty_phone': '0722114455',
      'paybill_account_number': null,
      'classification_id': sendRent,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(nineDaysAgo.add(const Duration(hours: 10))),
      'created_at': ms(nineDaysAgo.add(const Duration(hours: 10))),
      'deleted_at': null,
    });

    // 6. CASH, 9 days ago (prior-week bucket variety) — active.
    await insertTx({
      'display_code': cashCode(nineDaysAgo),
      'source_type': 'CASH',
      'amount_cents': 30000,
      'transaction_cost_cents': null,
      'counterparty_label': null,
      'counterparty_phone': null,
      'paybill_account_number': null,
      'classification_id': paybillTransport,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(nineDaysAgo.add(const Duration(hours: 18))),
      'created_at': ms(nineDaysAgo.add(const Duration(hours: 18))),
      'deleted_at': null,
    });

    // 7. BUY_GOODS, early this month (this-month bucket, outside this-week)
    //    — active.
    await insertTx({
      'display_code': 'DBG-BUY2',
      'source_type': 'BUY_GOODS',
      'amount_cents': 64000,
      'transaction_cost_cents': 0,
      'counterparty_label': 'JAVA HOUSE',
      'counterparty_phone': null,
      'paybill_account_number': null,
      'classification_id': buyGoodsGroceries,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(earlyThisMonth.add(const Duration(hours: 8))),
      'created_at': ms(earlyThisMonth.add(const Duration(hours: 8))),
      'deleted_at': null,
    });

    // 8. SEND_MONEY, last calendar month (prior-month bucket, feeds the
    //    Month period's diff line) — active.
    await insertTx({
      'display_code': 'DBG-SEND3',
      'source_type': 'SEND_MONEY',
      'amount_cents': 175000,
      'transaction_cost_cents': 2000,
      'counterparty_label': 'PETER OTIENO',
      'counterparty_phone': '0711223344',
      'paybill_account_number': null,
      'classification_id': sendRent,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(lastMonth.add(const Duration(hours: 12))),
      'created_at': ms(lastMonth.add(const Duration(hours: 12))),
      'deleted_at': null,
    });

    // 9. SEND_MONEY, today, SOFT-DELETED — must be excluded from every
    //    total/aggregate and from the recent list immediately
    //    (`deleted_at IS NULL` on every read), proving the filter
    //    actually works rather than just not crashing on an empty table.
    await insertTx({
      'display_code': 'DBG-DELETED1',
      'source_type': 'SEND_MONEY',
      'amount_cents': 999999,
      'transaction_cost_cents': 5000,
      'counterparty_label': 'SHOULD NOT APPEAR',
      'counterparty_phone': '0700000000',
      'paybill_account_number': null,
      'classification_id': sendFamilyFriends,
      'raw_parse_source': 'MANUAL',
      'transaction_occurred_at': ms(today.add(const Duration(hours: 12))),
      'created_at': ms(today.add(const Duration(hours: 12))),
      'deleted_at': now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
    });
  }
}
