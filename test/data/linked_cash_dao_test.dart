// 0.2.1: a withdrawal with linked Cash entries (LinkedCashDao), the cascade soft delete /
// restore / purge in TransactionDao, the read models, and the spend totals. Real in-memory
// sqlite with the real schema and triggers; invented rows only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/export_dao.dart';
import 'package:mmogo/data/db/home_dashboard_dao.dart';
import 'package:mmogo/data/db/linked_cash_dao.dart';
import 'package:mmogo/data/db/recently_deleted_dao.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/restore_test_db.dart';

late Database db;
late int rent; // SEND_MONEY:rent (a Cash picker category)
late int transport; // SEND_MONEY:transport
late int withdrawalClass;

Future<int> _withdrawal({String code = 'WDR0000001', int amount = 500000, int fee = 3500, int at = t0}) =>
    db.insert('transactions', {
      'display_code': code,
      'source_type': 'AGENT_WITHDRAWAL',
      'amount_cents': amount,
      'transaction_cost_cents': fee,
      'counterparty_label': 'TEST AGENT',
      'agent_number': '123456',
      'classification_id': withdrawalClass,
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': at,
      'created_at': at,
    });

Future<Map<String, Object?>> _row(int id) async =>
    (await db.query('transactions', where: 'id = ?', whereArgs: [id])).single;

Future<int?> _deletedAt(int id) async => (await _row(id))['deleted_at'] as int?;

Future<int> _spent() => HomeDashboardDao.sumAmountCents(db, startMs: 0, endMs: 9999999999999);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    db = await openTestDb();
    rent = await seedId(db, 'SEND_MONEY:rent');
    transport = await seedId(db, 'SEND_MONEY:transport');
    withdrawalClass = await seedId(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
  });
  tearDown(() => db.close());

  group('liveEntryRow / spentCents', () {
    test('returns the live entry row; null once deleted or unknown; spentCents = amount', () async {
      final w = await _withdrawal();
      final id = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 120000);
      final row = await LinkedCashDao.liveEntryRow(db, id);
      expect(row, isNotNull);
      expect(row!.id, id);
      expect(row.parentTransactionId, w);
      expect(row.amountCents, 120000);
      expect((await LinkedCashDao.linkedEntriesOf(db, w)).single.spentCents, 120000);
      expect(await LinkedCashDao.liveEntryRow(db, 999999), isNull);
      await db.update('transactions', {'deleted_at': 1}, where: 'id = ?', whereArgs: [id]);
      expect(await LinkedCashDao.liveEntryRow(db, id), isNull);
    });
  });

  group('createLinkedCash', () {
    test('adds a Cash entry: same date, CASH code, cost NULL, MANUAL, parent set, withdrawal untouched', () async {
      final at = DateTime(2026, 11, 3, 14, 5).millisecondsSinceEpoch;
      final w = await _withdrawal(at: at);
      final id = await LinkedCashDao.createLinkedCash(db,
          withdrawalId: w, classificationId: rent, amountCents: 500000);
      final r = await _row(id);
      expect(r['source_type'], 'CASH');
      expect(r['display_code'], 'CASH-20261103-1405');
      expect(r['transaction_occurred_at'], at);
      expect(r['transaction_cost_cents'], isNull);
      expect(r['raw_parse_source'], 'MANUAL');
      expect(r['parent_transaction_id'], w);
      expect(r['classification_id'], rent);
      expect(r['deleted_at'], isNull);
      final wr = await _row(w);
      expect(wr['source_type'], 'AGENT_WITHDRAWAL');
      expect(wr['amount_cents'], 500000);
      expect(wr['transaction_cost_cents'], 3500);
      expect(wr['cash_only_decided'], 0);
    });

    test('part spent: entries add up to at most the withdrawal; the rest is still cash', () async {
      final w = await _withdrawal();
      await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 300000);
      expect(await LinkedCashDao.remainingCents(db, w), 200000);
      await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: transport, amountCents: 200000);
      expect(await LinkedCashDao.remainingCents(db, w), 0);
      expect(
        () => LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 1),
        throwsArgumentError,
      );
      final entries = await LinkedCashDao.linkedEntriesOf(db, w);
      expect(entries.map((e) => e.amountCents), [300000, 200000]);
      expect(entries.map((e) => e.classificationName), ['Rent', 'Transport']);
    });

    test('two entries in the same minute get different created_at (a backup needs unique pairs)', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100);
      final b = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100);
      expect((await _row(a))['display_code'], (await _row(b))['display_code']);
      expect((await _row(a))['created_at'], isNot((await _row(b))['created_at']));
    });

    test('refuses: amount 0 or negative, a non-withdrawal, a deleted withdrawal, a category the picker lacks', () async {
      final w = await _withdrawal();
      final cash = await db.insert('transactions', {
        'display_code': 'CASH-20260101-0101',
        'source_type': 'CASH',
        'amount_cents': 100,
        'classification_id': rent,
        'raw_parse_source': 'MANUAL',
        'transaction_occurred_at': t0,
        'created_at': t0,
      });
      expect(() => LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 0),
          throwsArgumentError);
      expect(() => LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: -5),
          throwsArgumentError);
      expect(() => LinkedCashDao.createLinkedCash(db, withdrawalId: cash, classificationId: rent, amountCents: 5),
          throwsStateError);
      expect(() => LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: withdrawalClass, amountCents: 5),
          throwsArgumentError);
      await TransactionDao.softDelete(db, id: w);
      expect(() => LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 5),
          throwsStateError);
    });

    test('a failed create leaves nothing behind', () async {
      final w = await _withdrawal();
      try {
        await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 999999999);
      } on ArgumentError {
        // expected
      }
      expect(await LinkedCashDao.linkedEntriesOf(db, w), isEmpty);
    });
  });

  group('updateLinkedEntry', () {
    test('lowers the amount, never above what the withdrawal has left (own old amount counts as free)', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 300000);
      await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: transport, amountCents: 100000);
      await LinkedCashDao.updateLinkedEntry(db, entryId: a, amountCents: 400000); // 500000 - 100000
      expect((await _row(a))['amount_cents'], 400000);
      expect(() => LinkedCashDao.updateLinkedEntry(db, entryId: a, amountCents: 400001), throwsArgumentError);
      expect(() => LinkedCashDao.updateLinkedEntry(db, entryId: a, amountCents: 0), throwsArgumentError);
      await LinkedCashDao.updateLinkedEntry(db, entryId: a, amountCents: 1000);
      expect(await LinkedCashDao.remainingCents(db, w), 399000);
    });

    test('changes the category; refuses a category the picker lacks; refuses a non-entry', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 1000);
      await LinkedCashDao.updateLinkedEntry(db, entryId: a, classificationId: transport);
      expect((await _row(a))['classification_id'], transport);
      expect(() => LinkedCashDao.updateLinkedEntry(db, entryId: a, classificationId: withdrawalClass),
          throwsArgumentError);
      expect(() => LinkedCashDao.updateLinkedEntry(db, entryId: w, amountCents: 1), throwsStateError);
    });
  });

  group('setWithdrawalCategory', () {
    test('no entry yet: one full-amount entry; a change follows the category and keeps the amount', () async {
      final w = await _withdrawal();
      final id = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      expect((await _row(id))['amount_cents'], 500000);
      final again = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: transport);
      expect(again, id);
      expect((await _row(id))['classification_id'], transport);
      expect(await LinkedCashDao.linkedEntriesOf(db, w), hasLength(1));
    });

    test('a lowered single entry keeps its lowered amount when the category changes', () async {
      final w = await _withdrawal();
      final id = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await LinkedCashDao.updateLinkedEntry(db, entryId: id, amountCents: 300000);
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: transport);
      expect((await _row(id))['amount_cents'], 300000);
    });

    test('several entries: the caller must say which one (StateError)', () async {
      final w = await _withdrawal();
      await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100);
      await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100);
      expect(() => LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: transport),
          throwsStateError);
    });
  });

  group('markCashOnly and undecidedWithdrawals', () {
    test('undecided = withdrawal, live, no live entry, not decided; newest first', () async {
      final old = await _withdrawal(code: 'WDR0000001', at: t0);
      final mid = await _withdrawal(code: 'WDR0000002', at: t0 + 1000);
      final newest = await _withdrawal(code: 'WDR0000003', at: t0 + 2000);
      final linked = await _withdrawal(code: 'WDR0000004', at: t0 + 3000);
      final decided = await _withdrawal(code: 'WDR0000005', at: t0 + 4000);
      final deleted = await _withdrawal(code: 'WDR0000006', at: t0 + 5000);
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: linked, classificationId: rent);
      await LinkedCashDao.markCashOnly(db, withdrawalId: decided);
      await TransactionDao.softDelete(db, id: deleted);
      final other = await db.insert('transactions', {
        'display_code': 'SND0000001',
        'source_type': 'SEND_MONEY',
        'amount_cents': 100,
        'transaction_cost_cents': 0,
        'classification_id': rent,
        'raw_parse_source': 'SMS_PARSE',
        'transaction_occurred_at': t0 + 9000,
        'created_at': t0,
      });
      expect(other, greaterThan(0));
      final rows = await LinkedCashDao.undecidedWithdrawals(db);
      expect(rows.map((r) => r.id), [newest, mid, old]);
      expect(rows.every((r) => r.sourceType == 'AGENT_WITHDRAWAL'), isTrue);
      expect((await LinkedCashDao.undecidedWithdrawals(db, sinceMs: t0 + 1000)).map((r) => r.id), [newest, mid]);
    });

    test('markCashOnly on a plain withdrawal sets decided and removes it from the list', () async {
      final w = await _withdrawal();
      await LinkedCashDao.markCashOnly(db, withdrawalId: w);
      expect((await _row(w))['cash_only_decided'], 1);
      expect(await LinkedCashDao.undecidedWithdrawals(db), isEmpty);
      expect((await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes)).single.cashOnlyDecided,
          isTrue);
    });

    test('with a live entry it needs removeLinked; then the entry leaves every total (soft deleted)', () async {
      final w = await _withdrawal();
      final id = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      expect(await _spent(), 500000);
      expect(() => LinkedCashDao.markCashOnly(db, withdrawalId: w), throwsStateError);
      expect(await LinkedCashDao.linkedEntriesOf(db, w), hasLength(1));
      await LinkedCashDao.markCashOnly(db, withdrawalId: w, removeLinked: true);
      expect(await _deletedAt(id), isNotNull);
      expect(await LinkedCashDao.linkedEntriesOf(db, w), isEmpty);
      expect((await _row(w))['cash_only_decided'], 1);
      expect(await _spent(), 0);
      expect(await _deletedAt(w), isNull);
    });

    test('creating an entry clears an earlier Cash only decision', () async {
      final w = await _withdrawal();
      await LinkedCashDao.markCashOnly(db, withdrawalId: w);
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      expect((await _row(w))['cash_only_decided'], 0);
    });

    test('markManyCashOnly decides every id in one go', () async {
      final a = await _withdrawal(code: 'WDR0000001', at: t0);
      final b = await _withdrawal(code: 'WDR0000002', at: t0 + 1000);
      final c = await _withdrawal(code: 'WDR0000003', at: t0 + 2000);
      await LinkedCashDao.markManyCashOnly(db, withdrawalIds: [a, b]);
      expect((await _row(a))['cash_only_decided'], 1);
      expect((await _row(b))['cash_only_decided'], 1);
      expect((await LinkedCashDao.undecidedWithdrawals(db)).map((r) => r.id), [c]);
    });

    test('markManyCashOnly is all or nothing: one failure leaves every withdrawal undecided', () async {
      final a = await _withdrawal(code: 'WDR0000001', at: t0);
      final b = await _withdrawal(code: 'WDR0000002', at: t0 + 1000);
      final linked = await _withdrawal(code: 'WDR0000003', at: t0 + 2000);
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: linked, classificationId: rent);
      await expectLater(LinkedCashDao.markManyCashOnly(db, withdrawalIds: [a, b, linked]), throwsStateError);
      expect((await _row(a))['cash_only_decided'], 0);
      expect((await _row(b))['cash_only_decided'], 0);
      await expectLater(LinkedCashDao.markManyCashOnly(db, withdrawalIds: [a, 99999]), throwsStateError);
      expect((await _row(a))['cash_only_decided'], 0);
      expect((await LinkedCashDao.undecidedWithdrawals(db)).map((r) => r.id), [b, a]);
    });

    test('"Keep withdrawal" after deleting the only entry: decided 1, not asked again', () async {
      final w = await _withdrawal();
      final id = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await TransactionDao.softDelete(db, id: id); // deleting ONLY the entry leaves the withdrawal
      expect(await _deletedAt(w), isNull);
      expect((await LinkedCashDao.undecidedWithdrawals(db)).map((r) => r.id), [w]);
      await LinkedCashDao.markCashOnly(db, withdrawalId: w);
      expect(await LinkedCashDao.undecidedWithdrawals(db), isEmpty);
    });
  });

  group('delete, restore and purge', () {
    test('deleting a withdrawal soft-deletes its entries with the SAME deleted_at', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100000);
      final b = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: transport, amountCents: 100000);
      await TransactionDao.softDelete(db, id: w);
      final stamp = await _deletedAt(w);
      expect(stamp, isNotNull);
      expect(await _deletedAt(a), stamp);
      expect(await _deletedAt(b), stamp);
      expect(await _spent(), 0);
    });

    test('deleting only an entry leaves the withdrawal and the other entry', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100000);
      final b = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: transport, amountCents: 100000);
      await TransactionDao.softDelete(db, id: a);
      expect(await _deletedAt(w), isNull);
      expect(await _deletedAt(b), isNull);
      expect(await _spent(), 100000);
    });

    test('restoring the withdrawal brings the pair back together (the count is the row asked for: 1)', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await TransactionDao.softDelete(db, id: w);
      expect(await TransactionDao.restore(db, id: w), 1);
      expect(await _deletedAt(w), isNull);
      expect(await _deletedAt(a), isNull);
      expect(await _spent(), 500000);
    });

    test('restoring either member of a pair restores both; a second restore changes nothing', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await TransactionDao.softDelete(db, id: w);
      expect(await TransactionDao.restore(db, id: a), 1);
      expect(await _deletedAt(w), isNull);
      expect(await _deletedAt(a), isNull);
      expect(await TransactionDao.restore(db, id: a), 0);
    });

    test('an entry deleted on its own is not restored with the withdrawal, and comes back alone while it fits',
        () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 300000);
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await TransactionDao.softDelete(db, id: a);
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await TransactionDao.softDelete(db, id: w);
      // the withdrawal alone: the earlier entry stays deleted
      expect(await TransactionDao.restore(db, id: w), 1);
      expect(await _deletedAt(a), isNotNull);
      // now the entry fits again: it comes back alone
      expect(await TransactionDao.restore(db, id: a), 1);
      expect(await _deletedAt(a), isNull);
    });

    test('an entry that no longer fits (other entries took the room) is refused: 0, nothing changes', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 300000);
      await TransactionDao.softDelete(db, id: a);
      await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: transport, amountCents: 400000);
      expect(await TransactionDao.restore(db, id: a), 0);
      expect(await _deletedAt(a), isNotNull);
    });

    test('an entry whose withdrawal is deleted on its own cannot come back first', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 300000);
      await TransactionDao.softDelete(db, id: a);
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await TransactionDao.softDelete(db, id: w);
      expect(await TransactionDao.restore(db, id: a), 0);
      expect(await _deletedAt(a), isNotNull);
    });

    test('the purge removes the pair together; a withdrawal purged alone leaves its entry as plain Cash', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await TransactionDao.softDelete(db, id: w);
      final old = DateTime.now().millisecondsSinceEpoch - 2 * 3600000;
      await db.update('transactions', {'deleted_at': old}, where: 'id IN (?, ?)', whereArgs: [w, a]);
      expect(await TransactionDao.purgeExpiredSoftDeletes(db), 2);
      expect(await db.query('transactions', where: 'id IN (?, ?)', whereArgs: [w, a]), isEmpty);

      // The withdrawal alone (the delete trigger would take the entry with it, so it is dropped to build this odd state).
      await db.execute('DROP TRIGGER trg_transactions_delete_pair');
      final w2 = await _withdrawal(code: 'WDR0000002');
      final a2 = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w2, classificationId: rent);
      await db.update('transactions', {'deleted_at': old}, where: 'id = ?', whereArgs: [w2]);
      expect(await TransactionDao.purgeExpiredSoftDeletes(db), 1);
      final left = await _row(a2);
      expect(left['parent_transaction_id'], isNull);
      expect(left['deleted_at'], isNull);
    });

    test('three entries: restoring one of them brings the withdrawal and the other two back', () async {
      final w = await _withdrawal();
      final ids = [
        for (final amount in [100000, 200000, 150000])
          await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: amount),
      ];
      await TransactionDao.softDelete(db, id: w);
      expect(await TransactionDao.restore(db, id: ids[1]), 1);
      for (final id in [w, ...ids]) {
        expect(await _deletedAt(id), isNull, reason: 'row $id');
      }
      expect(await _spent(), 450000);
    });

    test('softDelete works inside a transaction the caller opened (no nested transaction)', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await db.transaction((txn) async {
        await TransactionDao.softDelete(txn, id: w);
      });
      expect(await _deletedAt(a), isNotNull);
    });
  });

  group('reads', () {
    test('Analytics rows: the withdrawal lists its category names and total; the entry says from withdrawal', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100000);
      await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: transport, amountCents: 100000);
      await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100000);
      final rows = await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes);
      final wr = rows.firstWhere((r) => r.id == w);
      expect(wr.linkedCategoryNames, ['Rent', 'Transport']); // each name once, oldest first
      expect(wr.linkedCents, 300000);
      expect(wr.fromWithdrawal, isFalse);
      final ar = rows.firstWhere((r) => r.id == a);
      expect(ar.fromWithdrawal, isTrue);
      expect(ar.parentTransactionId, w);
      expect(ar.displayName, 'Cash — Rent');
      expect(ar.linkedCategoryNames, isEmpty);
    });

    test('a deleted entry is not listed on the withdrawal', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 100000);
      await TransactionDao.softDelete(db, id: a);
      final wr = (await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes)).single;
      expect(wr.linkedCategoryNames, isEmpty);
      expect(wr.linkedCents, 0);
    });

    test('byCodes carries the same fields', () async {
      final w = await _withdrawal();
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      final r = (await AnalyticsDao.byCodes(db, {'WDR0000001'})).single;
      expect(r.linkedCategoryNames, ['Rent']);
    });

    test('Home recent: the withdrawal has the names, the entry has its parent', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      final rows = await HomeDashboardDao.recentTransactions(db);
      final wr = rows.firstWhere((r) => r.id == w);
      final ar = rows.firstWhere((r) => r.id == a);
      expect(wr.linkedCategoryNames, ['Rent']);
      expect(wr.fromWithdrawal, isFalse);
      expect(ar.fromWithdrawal, isTrue);
      expect(ar.parentTransactionId, w);
      expect(ar.displayName, 'Cash — Rent');
    });

    test('Recently deleted: the pair shows the link and the names of the entries deleted with it', () async {
      final w = await _withdrawal();
      final a = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await TransactionDao.softDelete(db, id: w);
      final rows = await RecentlyDeletedDao.deletedTransactions(db);
      expect(rows.firstWhere((r) => r.id == w).linkedCategoryNames, ['Rent']);
      final ar = rows.firstWhere((r) => r.id == a);
      expect(ar.fromWithdrawal, isTrue);
      expect(ar.parentTransactionId, w);
    });

    test('Export rows: the entry knows its parent and its code; the CSV header and columns are unchanged', () async {
      final w = await _withdrawal();
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      final rows = await ExportDao.activeTransactions(db);
      final entry = rows.firstWhere((r) => r.sourceType == 'CASH');
      expect(entry.fromWithdrawal, isTrue);
      expect(entry.parentTransactionId, w);
      expect(entry.linkedToCode, 'WDR0000001');
      expect(rows.firstWhere((r) => r.sourceType == 'AGENT_WITHDRAWAL').fromWithdrawal, isFalse);
      expect(ExportDao.csvHeader.length, 11);
      final lines = ExportDao.toCsv(rows).trimRight().split('\r\n');
      expect(lines.every((l) => l.split(',').length == 11 || l.contains('"')), isTrue);
    });
  });

  group('spend totals: the one spend rule is untouched', () {
    test('withdrawal 5,000 + linked Rent 5,000 = spent 5,000; withdrawn 5,000; the Cash entry is not withdrawn', () async {
      final w = await _withdrawal();
      expect(await _spent(), 0);
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      expect(await _spent(), 500000);
      final totals = await HomeDashboardDao.sourceTypeTotals(db, startMs: 0, endMs: 9999999999999);
      expect(totals['AGENT_WITHDRAWAL']!.totalCents, 0);
      expect(totals['AGENT_WITHDRAWAL']!.withdrawnCents, 500000);
      expect(totals['AGENT_WITHDRAWAL']!.costCents, 3500); // the fee stays the withdrawal's cost
      expect(totals['CASH']!.totalCents, 500000);
      expect(totals['CASH']!.withdrawnCents, 0);
      final rows = await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes);
      expect(rows.fold<int>(0, (s, r) => s + r.spent), 500000);
      expect(cashOutTotal(rows), 500000);
    });

    test('part spent 3,000 = spent 3,000, withdrawn still 5,000', () async {
      final w = await _withdrawal();
      final id = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await LinkedCashDao.updateLinkedEntry(db, entryId: id, amountCents: 300000);
      expect(await _spent(), 300000);
      final rows = await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes);
      expect(rows.fold<int>(0, (s, r) => s + r.spent), 300000);
      expect(cashOutTotal(rows), 500000);
      final totals = await HomeDashboardDao.sourceTypeTotals(db, startMs: 0, endMs: 9999999999999);
      expect(totals['AGENT_WITHDRAWAL']!.withdrawnCents, 500000);
    });

    test('Cash only: spent stays 0, withdrawn 5,000', () async {
      final w = await _withdrawal();
      await LinkedCashDao.markCashOnly(db, withdrawalId: w);
      expect(await _spent(), 0);
      expect(cashOutTotal(await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes)), 500000);
    });

    test('a deleted pair leaves spent and withdrawn at 0 until restored', () async {
      final w = await _withdrawal();
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      await TransactionDao.softDelete(db, id: w);
      expect(await _spent(), 0);
      expect(cashOutTotal(await AnalyticsDao.itemizedTransactions(db, types: AnalyticsDao.allTypes)), 0);
      await TransactionDao.restore(db, id: w);
      expect(await _spent(), 500000);
    });
  });
}
