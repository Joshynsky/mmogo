// 0.2.1 (PM #33): who shows which list. Add's manual Cash tab = the flat list PLUS the user's Cash list
// (deduped); a withdrawal's "What was this money for?" (Add type W) = the Cash list ONLY. Real in-memory
// sqlite; invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/classification_dao.dart';
import 'package:mmogo/ui/screens/add/category_chips.dart';
import 'package:mmogo/ui/screens/add/withdrawal_use_row.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/restore_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  Future<void> setUpDb(WidgetTester t, {List<String> cashList = const []}) async {
    await t.runAsync(() async {
      db = await openTestDb();
      for (final n in cashList) {
        await ClassificationDao.createCashUseClassification(db, name: n);
      }
    });
    addTearDown(() => db.close());
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Widget host(Widget child) => MaterialApp(theme: AppTheme.theme, home: Scaffold(body: SingleChildScrollView(child: child)));


  testWidgets('Add Cash tab: the flat list plus the Cash list, a name in both shows once', (t) async {
    await setUpDb(t, cashList: ['Boda fare', 'rent']);
    await t.pumpWidget(host(CategoryChips(
      db: db,
      sourceType: 'CASH',
      counterpartyKey: '',
      counterpartyDisplayName: '',
      selectedId: null,
      selectedName: null,
      onSelected: (_, _) {},
      autoApplyChecked: false,
      onAutoApplyChanged: (_) {},
    )));
    await settle(t);
    expect(find.text('Boda fare'), findsOneWidget, reason: 'a Cash-list name is reusable on a hand-entered Cash entry');
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('rent'), findsNothing, reason: 'deduped by lower-cased name, the older row wins');
    expect(find.text('Groceries'), findsOneWidget, reason: 'the flat list is kept');
    expect(find.text('Withdrawal'), findsNothing);
  });

  testWidgets('Add Cash tab: with an empty Cash list nothing changes', (t) async {
    await setUpDb(t);
    await t.pumpWidget(host(CategoryChips(
      db: db,
      sourceType: 'CASH',
      counterpartyKey: '',
      counterpartyDisplayName: '',
      selectedId: null,
      selectedName: null,
      onSelected: (_, _) {},
      autoApplyChecked: false,
      onAutoApplyChanged: (_) {},
    )));
    await settle(t);
    expect(find.text('Family/Friends'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
  });

  testWidgets('Add type W: the chips are the Cash list ONLY; Cash only and + New are always there', (t) async {
    await setUpDb(t, cashList: ['Fuel']);
    await t.pumpWidget(host(WithdrawalUseRow(
      db: db,
      palette: AppPalette.light,
      selectedId: null,
      amountCents: 500000,
      onChanged: (_, _) {},
    )));
    await settle(t);
    expect(find.text('Fuel'), findsOneWidget);
    for (final sendMoneyName in ['Family/Friends', 'Groceries', 'Rent', 'Transport', 'Shopping']) {
      expect(find.text(sendMoneyName), findsNothing, reason: sendMoneyName);
    }
    expect(find.byKey(const Key('wdChipCashOnly')), findsOneWidget);
    expect(find.byKey(const Key('wdChipNew')), findsOneWidget);
  });

  testWidgets('Add type W with an EMPTY Cash list: only Cash only and + New, the question and the grey sentence still read fine', (t) async {
    await setUpDb(t);
    await t.pumpWidget(host(WithdrawalUseRow(
      db: db,
      palette: AppPalette.light,
      selectedId: null,
      amountCents: 500000,
      onChanged: (_, _) {},
    )));
    await settle(t);
    expect(find.byKey(const Key('wdChipCashOnly')), findsOneWidget);
    expect(find.byKey(const Key('wdChipNew')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('wdChip-')), findsNothing);
    expect(find.byKey(const Key('wdQuestion')), findsOneWidget);
    expect(find.byKey(const Key('wdSentence')), findsOneWidget);
  });

  testWidgets('Add type W: + New makes a Cash-list category and selects it', (t) async {
    await setUpDb(t);
    int? picked;
    String? pickedName;
    await t.pumpWidget(host(WithdrawalUseRow(
      db: db,
      palette: AppPalette.light,
      selectedId: null,
      amountCents: 500000,
      onChanged: (id, name) {
        picked = id;
        pickedName = name;
      },
    )));
    await settle(t);
    await t.tap(find.byKey(const Key('wdChipNew')));
    await t.pump();
    await t.enterText(find.byKey(const Key('wdNewField')), 'Boda');
    await t.tap(find.byKey(const Key('wdNewAdd')));
    await settle(t);
    final cash = await t.runAsync(() => ClassificationDao.fetchCashUseClassifications(db));
    expect(cash!.map((c) => c.name), ['Boda']);
    expect(picked, cash.single.id);
    expect(pickedName, 'Boda');
    final flat = await t.runAsync(() => ClassificationDao.fetchActiveClassifications(db, groupId: 1));
    expect(flat!.map((c) => c.name), isNot(contains('Boda')), reason: 'not created under Send Money any more');
  });
}
