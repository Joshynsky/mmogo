// 0.2.2 item 2 redesign, slice B-SRC: the Set up list read from a real (in-memory) ledger and the real
// preferences rule store. Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/ledger_rule_events.dart';
import 'package:mmogo/autoread/data/setup_recipients_source.dart';
import 'package:mmogo/autoread/history/history_summary_writer.dart';
import 'package:mmogo/autoread/rules/prefs_rule_engine.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';
import 'package:mmogo/data/db/ledger_hooks.dart';
import 'package:mmogo/data/db/transaction_dao.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../wiring/wiring_db.dart';

void main() {
  late Database db;
  late PrefsRuleStore store;
  late LedgerSetupRecipientsSource source;
  late int cat;
  late Map<String, int> catOf;
  late bool details;
  late Set<String> pochiNames;
  var seq = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openWiringDb();
    cat = (await categoriesOf(db, 'SEND_MONEY')).first;
    catOf = {
      for (final g in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AIRTIME', 'AGENT_WITHDRAWAL'])
        g: (await categoriesOf(db, g)).first,
    };
    store = PrefsRuleStore();
    details = true;
    pochiNames = {'Mama Mboga Shop'};
    source = LedgerSetupRecipientsSource(
      database: () async => db,
      store: store,
      detailsOn: () async => details,
      pochiRemembered: (n) async => pochiNames.contains(n),
    );
  });
  tearDown(() async {
    LedgerHooks.onInserted = null;
    LedgerHooks.onEdited = null;
    LedgerHooks.onRemoved = null;
    LedgerHooks.onRestored = null;
    LedgerHooks.onBulk = null;
    await db.close();
  });

  Future<int> add(String type,
      {String? label, String? phone, String? account, String? agent, int day = 1}) {
    seq++;
    return TransactionDao.insert(
        db,
        NewTransactionInput(
          displayCode: 'SRC${seq.toString().padLeft(7, '0')}',
          sourceType: type,
          amountCents: 10000,
          transactionCostCents: 0,
          counterpartyLabel: label,
          counterpartyPhone: phone,
          paybillAccountNumber: account,
          agentNumber: agent,
          classificationId: catOf[type]!,
          rawParseSource: 'SMS_PARSE',
          transactionOccurredAt: DateTime(2026, 11, day, 10).millisecondsSinceEpoch,
        ));
  }

  Future<void> seedAllTypes() async {
    await add('SEND_MONEY', label: 'Jane Doe', phone: '0712345678');
    await add('SEND_MONEY', label: 'Jane Doe', phone: '+254712345678', day: 2); // the same person, other form
    await add('PAYBILL', label: 'Nairobi Water', account: 'ACC123');
    await add('BUY_GOODS', label: 'Quickmart  Kilimani');
    await add('POCHI_LA_BIASHARA', label: 'Mama Mboga Shop');
  }

  SetupRecipient only(List<SetupRecipient> list, ReceiverType t) => list.singleWhere((r) => r.type == t);

  group('each type', () {
    test('Send Money, Paybill, Buy Goods and Pochi are listed, one row per rule key', () async {
      await seedAllTypes();
      final list = await source.list();
      expect(list.map((r) => r.type).toSet(),
          {ReceiverType.sendMoney, ReceiverType.payBill, ReceiverType.buyGoods, ReceiverType.pochi});
      expect(list, hasLength(4));
      expect(only(list, ReceiverType.sendMoney).key, '0712345678');
      expect(only(list, ReceiverType.payBill).key, 'NAIROBI WATER#ACC123');
      expect(only(list, ReceiverType.buyGoods).key, 'QUICKMART KILIMANI');
      expect(only(list, ReceiverType.pochi).key, 'MAMA MBOGA SHOP');
      expect(only(list, ReceiverType.payBill).displayName, 'Nairobi Water');
      expect(only(list, ReceiverType.buyGoods).displayName, 'Quickmart  Kilimani');
    });

    test('a Pochi not remembered as Pochi has no rule key and is not listed', () async {
      await add('POCHI_LA_BIASHARA', label: 'Unknown Kiosk');
      expect(await source.list(), isEmpty);
    });

    test('rows with no key are not listed (Buy Goods without a name, Pochi without a name)', () async {
      await add('BUY_GOODS', label: '   ');
      await add('POCHI_LA_BIASHARA', label: null);
      expect(await source.list(), isEmpty);
    });

    test('a Paybill with a business but no account is listed under BUSINESS# (as the ledger events key it)',
        () async {
      await add('PAYBILL', label: 'Kenya Power', account: '');
      expect((await source.list()).single.key, 'KENYA POWER#');
    });

    test('the type filter returns only that type', () async {
      await seedAllTypes();
      for (final t in ReceiverType.values) {
        final list = await source.list(type: t);
        expect(list, hasLength(1), reason: t.name);
        expect(list.single.type, t);
      }
    });

    test('Paybill: two accounts under one business are two rows (the rule key is business + account)', () async {
      await add('PAYBILL', label: 'Kenya Power', account: '111');
      await add('PAYBILL', label: 'Kenya Power', account: '222');
      final keys = (await source.list(type: ReceiverType.payBill)).map((r) => r.key).toSet();
      expect(keys, {'KENYA POWER#111', 'KENYA POWER#222'});
    });
  });

  group('Airtime and withdrawals (PM Q3)', () {
    test('never listed, with or without a type filter', () async {
      await add('AIRTIME', label: null);
      await add('AGENT_WITHDRAWAL', label: 'Agent Juma', agent: '123456');
      expect(await source.list(), isEmpty);
      for (final t in ReceiverType.values) {
        expect(await source.list(type: t), isEmpty);
      }
      await add('SEND_MONEY', label: 'Jane Doe', phone: '0712345678');
      expect((await source.list()).map((r) => r.type), [ReceiverType.sendMoney]);
    });

    test('the read set is exactly the four rule types', () {
      expect(kSetupSourceTypes.keys.toSet(), {'SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA'});
    });
  });

  group('masking (F2)', () {
    test('Send Money shows 0712***678; the full number appears nowhere', () async {
      await add('SEND_MONEY', label: 'Jane Doe', phone: '0712345678');
      final r = (await source.list()).single;
      expect(r.maskedNumber, '0712***678');
      expect(r.displayName, 'Jane Doe');
      expect(r.toString().replaceAll(r.key, ''), isNot(contains('12345')));
    });

    test('+254 form is masked the same way', () async {
      await add('SEND_MONEY', label: 'Jane Doe', phone: '254712345678');
      expect((await source.list()).single.maskedNumber, '0712***678');
    });

    test('a name that is only a number is masked', () async {
      await add('SEND_MONEY', label: '0722000555', phone: '0722000555');
      expect((await source.list()).single.displayName, '0722***555');
    });

    test('Pochi, Paybill and Buy Goods show no number (an account is not a phone)', () async {
      await add('POCHI_LA_BIASHARA', label: 'Mama Mboga Shop');
      await add('PAYBILL', label: 'Nairobi Water', account: '0722000555');
      await add('BUY_GOODS', label: 'Quickmart');
      final list = await source.list();
      expect(only(list, ReceiverType.pochi).maskedNumber, isNull);
      expect(only(list, ReceiverType.payBill).maskedNumber, isNull);
      expect(only(list, ReceiverType.buyGoods).maskedNumber, isNull);
    });

    test('the name shown is the newest one', () async {
      await add('SEND_MONEY', label: 'Jane', phone: '0712345678', day: 1);
      await add('SEND_MONEY', label: 'Jane Doe', phone: '0712345678', day: 9);
      expect((await source.list()).single.displayName, 'Jane Doe');
    });
  });

  group('counts', () {
    test('every non-deleted payment, all time; deleted rows are not counted', () async {
      final ids = <int>[];
      for (var i = 1; i <= 4; i++) {
        ids.add(await add('SEND_MONEY', label: 'Jane Doe', phone: '0712345678', day: i));
      }
      await TransactionDao.softDelete(db, id: ids[1]);
      expect((await source.list()).single.paymentCount, 3);
    });

    test('a recipient whose every payment was deleted is not listed', () async {
      final id = await add('BUY_GOODS', label: 'Quickmart');
      await TransactionDao.softDelete(db, id: id);
      expect(await source.list(), isEmpty);
    });

    test('order: most payments first, then name', () async {
      await add('BUY_GOODS', label: 'Zeta Shop');
      await add('BUY_GOODS', label: 'Alpha Shop');
      for (var i = 0; i < 3; i++) {
        await add('SEND_MONEY', label: 'Jane Doe', phone: '0712345678');
      }
      final names = (await source.list()).map((r) => r.displayName).toList();
      expect(names, ['Jane Doe', 'Alpha Shop', 'Zeta Shop']);
      expect((await source.list()).first.paymentCount, 3);
    });
  });

  group('level tag from the rule store', () {
    test('a level set under the listed key shows on that row; others have none', () async {
      await seedAllTypes();
      final before = await source.list();
      expect(before.every((r) => r.level == null), isTrue);
      final sm = only(before, ReceiverType.sendMoney);
      final po = only(before, ReceiverType.pochi);
      final pb = only(before, ReceiverType.payBill);
      final at = DateTime(2026, 11, 26);
      expect(await store.setLevel(sm.type, sm.key, name: sm.displayName, level: RuleLevel.autoRecord, categoryId: cat, at: at),
          isTrue);
      expect(await store.setLevel(po.type, po.key, name: po.displayName, level: RuleLevel.askFirst, categoryId: cat, at: at),
          isTrue);
      expect(await store.setLevel(pb.type, pb.key, name: pb.displayName, level: RuleLevel.suggested, at: at), isTrue);
      final after = await source.list();
      expect(only(after, ReceiverType.sendMoney).level, RuleLevel.autoRecord);
      expect(only(after, ReceiverType.pochi).level, RuleLevel.askFirst);
      expect(only(after, ReceiverType.payBill).level, RuleLevel.suggested);
      expect(only(after, ReceiverType.buyGoods).level, isNull);
    });

    test('key matches the rule store key: the ledger events create the rule, the source finds it', () async {
      final undone = PrefsUndoneCodes();
      final events = LedgerRuleEvents(
        engine: PrefsRuleEngine(store),
        store: store,
        undone: undone,
        summary: HistorySummaryWriter(rows: () async => readHistoryRows(db)),
        database: () async => db,
        detailsOn: () async => true,
        pochiRemembered: (n) async => pochiNames.contains(n),
      );
      final ids = [
        await add('SEND_MONEY', label: 'Jane Doe', phone: '+254712345678'),
        await add('PAYBILL', label: '  nairobi   water ', account: 'Acc 9'),
        await add('BUY_GOODS', label: 'quickmart kilimani'),
        await add('POCHI_LA_BIASHARA', label: 'Mama Mboga Shop'),
      ];
      for (final id in ids) {
        await events.inserted(id);
      }
      final list = await source.list();
      expect(list, hasLength(4));
      for (final r in list) {
        expect(await store.get(r.type, r.key), isNotNull, reason: '${r.type.name} ${r.key}');
        expect(r.level, (await store.get(r.type, r.key))!.level);
      }
      // And row by row: the same key LedgerRuleEvents.personOf derives.
      for (final id in ids) {
        final row = (await db.rawQuery(
                'SELECT source_type, counterparty_label, counterparty_phone, paybill_account_number '
                'FROM transactions WHERE id = ?',
                [id]))
            .single;
        final p = (await events.personOf(row, details: true))!;
        expect(list.where((r) => r.type == p.type && r.key == p.key), hasLength(1), reason: p.key);
      }
    });

    test('a person removed by Forget all appears as new: no level', () async {
      await add('SEND_MONEY', label: 'Jane Doe', phone: '0712345678');
      final r = (await source.list()).single;
      await store.setLevel(r.type, r.key, name: r.displayName, level: RuleLevel.askFirst, categoryId: cat, at: DateTime(2026));
      expect((await source.list()).single.level, RuleLevel.askFirst);
      expect(await store.forgetEveryone(), 1);
      final again = (await source.list()).single;
      expect(again.level, isNull);
      expect(again.paymentCount, 1);
    });

    test('Forget one person: that row has no level, the others keep theirs', () async {
      await add('SEND_MONEY', label: 'Jane Doe', phone: '0712345678');
      await add('BUY_GOODS', label: 'Quickmart');
      for (final r in await source.list()) {
        await store.setLevel(r.type, r.key, name: r.displayName, level: RuleLevel.askFirst, categoryId: cat, at: DateTime(2026));
      }
      await store.forget(ReceiverType.sendMoney, '0712345678');
      final list = await source.list();
      expect(only(list, ReceiverType.sendMoney).level, isNull);
      expect(only(list, ReceiverType.buyGoods).level, RuleLevel.askFirst);
    });
  });

  group('details OFF (privacy)', () {
    test('the list is empty while details are OFF, and back when ON', () async {
      await seedAllTypes();
      details = false;
      expect(await source.list(), isEmpty);
      for (final t in ReceiverType.values) {
        expect(await source.list(type: t), isEmpty);
      }
      details = true;
      expect(await source.list(), hasLength(4));
    });

    test('a switch that cannot be read lists nobody (fails closed)', () async {
      await seedAllTypes();
      final broken = LedgerSetupRecipientsSource(
        database: () async => db,
        store: store,
        detailsOn: () async => throw StateError('prefs'),
        pochiRemembered: (n) async => true,
      );
      expect(await broken.list(), isEmpty);
    });

    test('the stored switch OFF (default reader) gives an empty list', () async {
      await seedAllTypes();
      SharedPreferences.setMockInitialValues({'capture_identity_preference': false});
      final real = LedgerSetupRecipientsSource(
        database: () async => db,
        store: store,
        pochiRemembered: (n) async => true,
      );
      expect(await real.list(), isEmpty);
    });

    test('a failing Pochi lookup treats the name as not remembered (no row, no error)', () async {
      await add('POCHI_LA_BIASHARA', label: 'Mama Mboga Shop');
      final s = LedgerSetupRecipientsSource(
        database: () async => db,
        store: store,
        detailsOn: () async => true,
        pochiRemembered: (n) async => throw StateError('memory'),
      );
      expect(await s.list(), isEmpty);
    });
  });
}
