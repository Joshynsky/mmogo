// 0.2.1 (PM #33): a withdrawal's own "Cash" category list. Real in-memory sqlite (current schema,
// triggers, unique indexes); invented names only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/classification_dao.dart';
import 'package:mmogo/data/db/linked_cash_dao.dart';
import 'package:mmogo/data/db/migration_v7_ddl.dart';
import 'package:mmogo/ui/widgets/withdrawal_use_create.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/restore_test_db.dart';

void main() {
  late Database db;
  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  Future<int> withdrawal({String code = 'WDR0000001', int amount = 500000}) async => db.insert('transactions', {
        'display_code': code,
        'source_type': 'AGENT_WITHDRAWAL',
        'amount_cents': amount,
        'transaction_cost_cents': 3500,
        'counterparty_label': 'TEST AGENT',
        'agent_number': '123456',
        'classification_id': await seedId(db, 'AGENT_WITHDRAWAL:cash_withdrawal'),
        'raw_parse_source': 'SMS_PARSE',
        'transaction_occurred_at': t0,
        'created_at': t0,
      });

  group('the list itself', () {
    test('starts EMPTY on a fresh database; the group exists, is enabled, is not the locked Withdrawal group', () async {
      expect(await ClassificationDao.fetchCashUseClassifications(db), isEmpty);
      final groups = await ClassificationDao.fetchGroups(db);
      final cash = groups.singleWhere((g) => g.code == kCashUseGroupCode);
      expect(cash.displayName, 'Cash');
      expect(cash.enabled, isTrue);
      expect(cash.id, isNot(groups.singleWhere((g) => g.code == 'AGENT_WITHDRAWAL').id));
      expect(await ClassificationDao.fetchActiveClassifications(db, groupId: cash.id), isEmpty);
    });

    test('empty when the group row is missing (nothing throws); creating then says so', () async {
      await db.execute("DELETE FROM classification_groups WHERE code = 'CASH_USE'");
      expect(await ClassificationDao.fetchCashUseClassifications(db), isEmpty);
      await expectLater(ClassificationDao.createCashUseClassification(db, name: 'Fare'), throwsA(isA<StateError>()));
      final r = await createWithdrawalUseCategory(db, 'Fare');
      expect(r.id, isNull);
      expect(r.error, 'Could not create category. Try again.');
    });

    test('create puts the name in the Cash group, listed name-ordered case-insensitively', () async {
      await ClassificationDao.createCashUseClassification(db, name: 'fuel');
      await ClassificationDao.createCashUseClassification(db, name: 'Airtime for mum');
      await ClassificationDao.createCashUseClassification(db, name: 'Boda');
      expect((await ClassificationDao.fetchCashUseClassifications(db)).map((c) => c.name), ['Airtime for mum', 'Boda', 'fuel']);
    });

    test('a duplicate inside the Cash list is the real unique-constraint error', () async {
      await ClassificationDao.createCashUseClassification(db, name: 'Fuel');
      await expectLater(
        ClassificationDao.createCashUseClassification(db, name: 'Fuel'),
        throwsA(isA<DatabaseException>().having((e) => e.isUniqueConstraintError(), 'unique', isTrue)),
      );
    });

    test('a soft-deleted Cash category leaves the list and its name is free again', () async {
      final id = await ClassificationDao.createCashUseClassification(db, name: 'Fuel');
      await ClassificationDao.softDeleteClassification(db, id: id);
      expect(await ClassificationDao.fetchCashUseClassifications(db), isEmpty);
      await ClassificationDao.createCashUseClassification(db, name: 'Fuel');
      expect(await ClassificationDao.fetchCashUseClassifications(db), hasLength(1));
    });

    test('rename in Manage (generic DAO) works on a Cash category; the group is not a locked one', () async {
      final id = await ClassificationDao.createCashUseClassification(db, name: 'Fuel');
      await ClassificationDao.renameClassification(db, id: id, newName: 'Petrol');
      expect((await ClassificationDao.fetchCashUseClassifications(db)).single.name, 'Petrol');
    });
  });

  group('createWithdrawalUseCategory (the "+ New" rules)', () {
    test('empty and blank are refused', () async {
      for (final n in ['', '   ']) {
        final r = await createWithdrawalUseCategory(db, n);
        expect(r.id, isNull);
        expect(r.error, 'Type a name first.');
      }
      expect(await ClassificationDao.fetchCashUseClassifications(db), isEmpty);
    });

    test('100 characters are fine, 101 are refused', () async {
      final ok = await createWithdrawalUseCategory(db, 'a' * classificationNameMaxLength);
      expect(ok.error, isNull);
      expect(ok.id, isNotNull);
      final tooLong = await createWithdrawalUseCategory(db, 'b' * (classificationNameMaxLength + 1));
      expect(tooLong.id, isNull);
      expect(tooLong.error, contains('too long'));
      expect((await ClassificationDao.fetchCashUseClassifications(db)), hasLength(1));
    });

    test('duplicate is case-insensitive and checked ONLY inside the Cash list', () async {
      // "Rent" already exists in Send Money, Paybill and Buy Goods: it must not block a Cash "Rent".
      final first = await createWithdrawalUseCategory(db, 'Rent');
      expect(first.error, isNull);
      expect(first.choices!.map((c) => c.name), ['Rent']);
      final again = await createWithdrawalUseCategory(db, 'rENT');
      expect(again.id, isNull);
      expect(again.error, 'A category named "rENT" already exists.');
    });

    test('the reloaded choices are the Cash list only (never the 12 Send Money / Paybill / Buy Goods names)', () async {
      await createWithdrawalUseCategory(db, 'Fare');
      final choices = await loadWithdrawalUseChoices(db);
      expect(choices.map((c) => c.name), ['Fare']);
    });

    test('with nothing made, the chips list is empty (only "+ New" and "Cash only" show)', () async {
      expect(await loadWithdrawalUseChoices(db), isEmpty);
    });
  });

  group('the manual Cash tab list keeps its flat list and ADDS the Cash list, deduped', () {
    test('unchanged on a fresh database (the Cash list is empty)', () async {
      final names = (await ClassificationDao.fetchFlatActiveClassifications(db)).map((c) => c.name).toList();
      expect(names, ['Family/Friends', 'Groceries', 'Rent', 'Rent Payment', 'Shopping', 'Transport']);
    });

    test('a Cash-list name appears; a name that already exists in the flat list shows once; Cash list wins nothing', () async {
      await ClassificationDao.createCashUseClassification(db, name: 'Boda fare');
      await ClassificationDao.createCashUseClassification(db, name: 'RENT'); // same as Send Money "Rent" apart from case
      final flat = await ClassificationDao.fetchFlatActiveClassifications(db);
      final names = flat.map((c) => c.name).toList();
      expect(names, contains('Boda fare'));
      expect(names.where((n) => n.toLowerCase() == 'rent'), ['Rent'], reason: 'deduped by lower-cased name, the older row wins');
      expect(names, ['Boda fare', 'Family/Friends', 'Groceries', 'Rent', 'Rent Payment', 'Shopping', 'Transport']);
    });

    test('Pochi, Withdrawal and Airtime categories still do NOT leak into it', () async {
      final names = (await ClassificationDao.fetchFlatActiveClassifications(db)).map((c) => c.name);
      expect(names, isNot(contains('Withdrawal')));
      expect(names, isNot(contains('For myself')));
    });
  });

  group('the linked Cash entry points at the Cash-list category', () {
    test('a withdrawal with a Cash-list category gets a CASH entry in that category; spent is the full amount', () async {
      final w = await withdrawal();
      final fare = await ClassificationDao.createCashUseClassification(db, name: 'Fare');
      final entry = await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: fare);
      final entries = await LinkedCashDao.linkedEntriesOf(db, w);
      expect(entries.single.id, entry);
      expect(entries.single.classificationId, fare);
      expect(entries.single.classificationName, 'Fare');
      expect(entries.single.spentCents, 500000);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });

    test('Analytics reads the entry by its category name whatever the group (Where it went shows "Fare")', () async {
      final w = await withdrawal();
      final fare = await ClassificationDao.createCashUseClassification(db, name: 'Fare');
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: fare);
      final rows = await AnalyticsDao.itemizedTransactions(db, types: {'CASH', 'AGENT_WITHDRAWAL'});
      final cash = rows.singleWhere((r) => r.sourceType == 'CASH');
      expect(cash.classificationName, 'Fare');
      expect(cash.displayName, 'Cash — Fare');
    });

    test('a category in another group (an entry made before the Cash list) is still accepted and listed', () async {
      final w = await withdrawal();
      final rent = await seedId(db, 'SEND_MONEY:rent');
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: rent);
      expect((await LinkedCashDao.linkedEntriesOf(db, w)).single.classificationName, 'Rent');
    });

    test('a locked or other-source category (Withdrawal, Airtime) is still refused', () async {
      final w = await withdrawal();
      await expectLater(
        LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: await seedId(db, 'AGENT_WITHDRAWAL:cash_withdrawal')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a soft-deleted Cash category keeps counting on the entry (history is never orphaned)', () async {
      final w = await withdrawal();
      final fare = await ClassificationDao.createCashUseClassification(db, name: 'Fare');
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: w, classificationId: fare);
      await ClassificationDao.softDeleteClassification(db, id: fare);
      expect((await LinkedCashDao.linkedEntriesOf(db, w)).single.classificationName, 'Fare');
      expect(await ClassificationDao.countTransactionsForClassification(db, classificationId: fare), 1);
    });
  });
}
