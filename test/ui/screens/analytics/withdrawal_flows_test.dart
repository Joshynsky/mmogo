// 0.2.1: delete prompts, the linked entry sheet, the withdrawal block, the row words. Real in-memory
// sqlite (current schema + triggers); invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/classification_dao.dart';
import 'package:mmogo/data/db/linked_cash_dao.dart';
import 'package:mmogo/ui/copy/withdrawal_copy.dart';
import 'package:mmogo/ui/screens/analytics/linked_entry_flow.dart';
import 'package:mmogo/ui/screens/analytics/linked_entry_sheet.dart';
import 'package:mmogo/ui/screens/analytics/swipe_row.dart';
import 'package:mmogo/ui/screens/analytics/withdrawal_delete_flow.dart';
import 'package:mmogo/ui/screens/analytics/withdrawal_use_section.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/restore_test_db.dart';

const int _at = 1790000000000;

Future<AnalyticsTransactionRow> _row(Database db, int id) async {
  final r = await db.rawQuery(
    'SELECT ${AnalyticsDao.rowColumns} FROM transactions t JOIN classifications c ON c.id = t.classification_id WHERE t.id = ?',
    [id],
  );
  return AnalyticsDao.rowFrom(r.single);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late int rent, groceries, wdClass, cashCat;

  Future<int> withdrawal({String code = 'WDR0000001', int amount = 500000}) => db.insert('transactions', {
        'display_code': code,
        'source_type': 'AGENT_WITHDRAWAL',
        'amount_cents': amount,
        'transaction_cost_cents': 3500,
        'counterparty_label': 'TEST AGENT',
        'agent_number': '123456',
        'classification_id': wdClass,
        'raw_parse_source': 'SMS_PARSE',
        'transaction_occurred_at': _at,
        'created_at': _at,
      });

  Future<int?> deletedAt(int id) async =>
      (await db.query('transactions', columns: ['deleted_at'], where: 'id = ?', whereArgs: [id])).single['deleted_at'] as int?;

  Future<void> setUpDb(WidgetTester t) async {
    await t.runAsync(() async {
      db = await openTestDb();
      rent = await seedId(db, 'SEND_MONEY:rent');
      groceries = await seedId(db, 'SEND_MONEY:transport');
      wdClass = await seedId(db, 'AGENT_WITHDRAWAL:cash_withdrawal');
      // 0.2.1 (PM #33): a withdrawal's chips are the user's own Cash list, which starts empty.
      cashCat = await ClassificationDao.createCashUseClassification(db, name: 'Boda fare');
    });
    addTearDown(() => db.close());
  }

  /// Taps "go", which runs [body] with a context.
  Future<void> host(WidgetTester t, Future<void> Function(BuildContext c) body) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => body(c), child: const Text('go')))),
    ));
    await t.tap(find.text('go'));
    await t.pump();
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('delete prompts', () {
    testWidgets('withdrawal with a linked entry: Cancel | Delete both; both go together', (t) async {
      await setUpDb(t);
      late int w, e;
      await t.runAsync(() async {
        w = await withdrawal();
        e = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 500000);
      });
      final tx = await t.runAsync(() => _row(db, w));
      DeleteOutcome? out;
      await host(t, (c) async => out = await deleteWithPrompt(c, db, tx!));
      await settle(t);
      expect(find.text(kWdDeleteWithdrawalTitle), findsOneWidget);
      expect(find.text(kWdCancel), findsOneWidget);
      expect(find.text(kWdDeleteBoth), findsOneWidget);
      expect(find.textContaining('Rent Ksh 5,000'), findsOneWidget);
      await t.tap(find.byKey(const Key('twoButtonLeft')));
      await settle(t);
      expect(out, isNull);
      expect(await t.runAsync(() => deletedAt(w)), isNull);
      await t.tap(find.text('go'));
      await settle(t);
      await t.tap(find.byKey(const Key('twoButtonRight')));
      await settle(t);
      expect(out!.undoId, w);
      final wd = await t.runAsync(() => deletedAt(w));
      expect(wd, isNotNull);
      expect(await t.runAsync(() => deletedAt(e)), wd);
    });

    testWidgets('plain withdrawal asks Cancel | Delete', (t) async {
      await setUpDb(t);
      late int w;
      await t.runAsync(() async => w = await withdrawal());
      final tx = await t.runAsync(() => _row(db, w));
      DeleteOutcome? out;
      await host(t, (c) async => out = await deleteWithPrompt(c, db, tx!));
      await settle(t);
      expect(find.text(kWdDelete), findsOneWidget);
      expect(find.text(kWdDeleteBoth), findsNothing);
      await t.tap(find.byKey(const Key('twoButtonRight')));
      await settle(t);
      expect(out!.undoId, w);
      expect(await t.runAsync(() => deletedAt(w)), isNotNull);
    });

    testWidgets('linked entry alone: Keep withdrawal removes only the entry and marks Cash only', (t) async {
      await setUpDb(t);
      late int w, e;
      await t.runAsync(() async {
        w = await withdrawal();
        e = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 500000);
      });
      final tx = await t.runAsync(() => _row(db, e));
      DeleteOutcome? out;
      await host(t, (c) async => out = await deleteWithPrompt(c, db, tx!));
      await settle(t);
      expect(find.text(kWdKeepWithdrawal), findsOneWidget);
      expect(find.text(kWdDeleteWithdrawalToo), findsOneWidget);
      await t.tap(find.byKey(const Key('twoButtonLeft')));
      await settle(t);
      expect(out!.undoId, e);
      expect(await t.runAsync(() => deletedAt(e)), isNotNull);
      expect(await t.runAsync(() => deletedAt(w)), isNull);
      final decided = await t.runAsync(() => db.query('transactions', columns: ['cash_only_decided'], where: 'id = ?', whereArgs: [w]));
      expect(decided!.single['cash_only_decided'], 1);
    });

    testWidgets('linked entry alone: Delete withdrawal too takes the pair', (t) async {
      await setUpDb(t);
      late int w, e;
      await t.runAsync(() async {
        w = await withdrawal();
        e = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 500000);
      });
      final tx = await t.runAsync(() => _row(db, e));
      DeleteOutcome? out;
      await host(t, (c) async => out = await deleteWithPrompt(c, db, tx!));
      await settle(t);
      await t.tap(find.byKey(const Key('twoButtonRight')));
      await settle(t);
      expect(out!.undoId, w);
      expect(await t.runAsync(() => deletedAt(w)), isNotNull);
      expect(await t.runAsync(() => deletedAt(e)), isNotNull);
    });
  });

  group('Cash only on a linked withdrawal asks first', () {
    testWidgets('Keep it changes nothing; Remove it deletes the entry and decides', (t) async {
      await setUpDb(t);
      late int w, e;
      await t.runAsync(() async {
        w = await withdrawal();
        e = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 500000);
      });
      final tx = await t.runAsync(() => _row(db, w));
      bool? changed;
      await host(t, (c) async => changed = await applyWithdrawalPick(c, db, tx!, const WithdrawalPick(null)));
      await settle(t);
      expect(find.text(kWdCashOnlyAskTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('twoButtonLeft')));
      await settle(t);
      expect(changed, isFalse);
      expect(await t.runAsync(() => deletedAt(e)), isNull);
      await t.tap(find.text('go'));
      await settle(t);
      await t.tap(find.byKey(const Key('twoButtonRight')));
      await settle(t);
      expect(changed, isTrue);
      expect(await t.runAsync(() => deletedAt(e)), isNotNull);
    });

    testWidgets('a category on a plain withdrawal adds the full-amount entry', (t) async {
      await setUpDb(t);
      late int w;
      await t.runAsync(() async => w = await withdrawal());
      final tx = await t.runAsync(() => _row(db, w));
      await host(t, (c) async => applyWithdrawalPick(c, db, tx!, WithdrawalPick(rent)));
      await settle(t);
      final entries = await t.runAsync(() => LinkedCashDao.linkedEntriesOf(db, w));
      expect(entries!.single.amountCents, 500000);
    });
  });

  group('linked entry sheet', () {
    Widget sheet({required int max, int? amount, int? cat, String? name, bool isNew = false}) => MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: LinkedEntrySheet(
              db: db,
              palette: AppPalette.light,
              withdrawalCents: 500000,
              occurredAt: DateTime.fromMillisecondsSinceEpoch(_at),
              maxCents: max,
              isNew: isNew,
              categoryId: cat,
              categoryName: name,
              amountCents: amount,
            ),
          ),
        );

    testWidgets('title, tag, words; stepper stops at the cap; typing above the cap blocks Save', (t) async {
      await setUpDb(t);
      t.view.physicalSize = const Size(400, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(sheet(max: 500000, amount: 300000, cat: rent, name: 'Rent'));
      await settle(t);
      expect(find.text('Cash — Rent'), findsOneWidget);
      expect(find.text(kWdFromWithdrawalTag), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('linkedEntryWords'))).data, contains('Ksh 2,000.00 of the withdrawal stays as cash'));
      for (var i = 0; i < 25; i++) {
        await t.tap(find.byKey(const Key('linkedEntryMore')));
        await t.pump();
      }
      expect(t.widget<TextField>(find.byKey(const Key('linkedEntryAmount'))).controller!.text, '5000.00');
      expect(t.widget<Text>(find.byKey(const Key('linkedEntryWords'))).data, contains('All of the withdrawal is spent'));
      expect(t.widget<OutlinedButton>(find.byKey(const Key('linkedEntryAddAnother'))).onPressed, isNull);
      await t.enterText(find.byKey(const Key('linkedEntryAmount')), '6000');
      await t.pump();
      expect(t.widget<FilledButton>(find.byKey(const Key('linkedEntrySave'))).onPressed, isNull);
      expect(find.textContaining('Up to'), findsOneWidget);
    });

    testWidgets('a new entry needs a category; Add another is offered while money is left', (t) async {
      await setUpDb(t);
      t.view.physicalSize = const Size(400, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(sheet(max: 200000, isNew: true));
      await settle(t);
      expect(find.byKey(const Key('linkedEntryDelete')), findsNothing);
      expect(t.widget<FilledButton>(find.byKey(const Key('linkedEntrySave'))).onPressed, isNull);
      expect(find.byKey(Key('wdChip-$groceries')), findsNothing, reason: 'Send Money names are not offered: the Cash list only');
      await t.tap(find.byKey(Key('wdChip-$cashCat')));
      await t.pump();
      expect(t.widget<FilledButton>(find.byKey(const Key('linkedEntrySave'))).onPressed, isNotNull);
      expect(t.widget<OutlinedButton>(find.byKey(const Key('linkedEntryAddAnother'))).onPressed, isNull,
          reason: 'the whole 2,000 is used, nothing is left');
      await t.enterText(find.byKey(const Key('linkedEntryAmount')), '1000');
      await t.pump();
      expect(t.widget<OutlinedButton>(find.byKey(const Key('linkedEntryAddAnother'))).onPressed, isNotNull);
    });
  });

  group('withdrawal block in the edit sheet', () {
    testWidgets('one entry: its category is preselected and the rest-stays-cash sentence shows', (t) async {
      await setUpDb(t);
      late int w;
      await t.runAsync(() async {
        w = await withdrawal();
        await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 300000);
      });
      final tx = await t.runAsync(() => _row(db, w));
      final picks = <(bool, int?)>[];
      t.view.physicalSize = const Size(400, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WithdrawalUseSection(
              db: db,
              palette: AppPalette.light,
              tx: tx!,
              onChanged: (c, id) => picks.add((c, id)),
              onOpenEntry: (_) {},
            ),
          ),
        ),
      ));
      await settle(t);
      expect(find.text(kWdQuestion), findsOneWidget);
      expect(find.text(kWdChangeAlsoChanges), findsOneWidget);
      expect(find.textContaining('Ksh 2,000.00 is still cash'), findsOneWidget);
      await t.tap(find.byKey(const Key('wdChipCashOnly')));
      await t.pump();
      expect(picks.last, (true, null));
      expect(find.textContaining('removes the linked Cash'), findsOneWidget);
      await t.tap(find.byKey(Key('wdChip-$rent')));
      await t.pump();
      expect(picks.last, (false, rent), reason: 'back to what it had: nothing changed');
    });
  });

  group('rows', () {
    Widget row(AnalyticsTransactionRow tx) => MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: AnalyticsSwipeRow(
              rowKey: GlobalKey(),
              palette: AppPalette.light,
              tx: tx,
              highlighted: false,
              forceClosed: false,
              onOpened: (_) {},
              onEdit: () {},
              onDelete: () {},
            ),
          ),
        );

    testWidgets('withdrawal shows "→ Rent" on its date line; the entry shows its title and the tag', (t) async {
      await setUpDb(t);
      late int w, e;
      await t.runAsync(() async {
        w = await withdrawal();
        e = await LinkedCashDao.createLinkedCash(db, withdrawalId: w, classificationId: rent, amountCents: 500000);
      });
      final wTx = await t.runAsync(() => _row(db, w));
      final eTx = await t.runAsync(() => _row(db, e));
      await t.pumpWidget(row(wTx!));
      expect(find.textContaining('→ '), findsOneWidget);
      expect(find.byKey(Key('analyticsRowFromWithdrawal-$w')), findsNothing);
      await t.pumpWidget(row(eTx!));
      expect(find.text('Cash — ${eTx.classificationName}'), findsOneWidget);
      expect(find.byKey(Key('analyticsRowFromWithdrawal-$e')), findsOneWidget);
      expect(find.text(kWdFromWithdrawalTag), findsOneWidget);
    });
  });
}
