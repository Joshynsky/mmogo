// 0.2.1: the shared "What was this money for?" block and the two-button dialog. Made-up names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/withdrawal_copy.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/widgets/two_button_dialog.dart';
import 'package:mmogo/ui/widgets/withdrawal_use_block.dart';
import 'package:mmogo/ui/widgets/withdrawal_use_create.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/restore_test_db.dart';

void main() {
  const choices = [WdChoice(1, 'Rent'), WdChoice(2, 'Groceries')];

  Widget host(Widget child) => MaterialApp(theme: AppTheme.theme, home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('Cash only chip comes first, then the categories; taps report the choice', (t) async {
    final picks = <int?>[];
    await t.pumpWidget(host(WithdrawalUseBlock(
      palette: AppPalette.light,
      choices: choices,
      selectedId: null,
      sentence: 'one grey sentence',
      onChanged: picks.add,
    )));
    expect(find.text(kWdQuestion), findsOneWidget);
    expect(find.text('one grey sentence'), findsOneWidget);
    final cashX = t.getTopLeft(find.byKey(const Key('wdChipCashOnly'))).dx;
    expect(cashX, lessThan(t.getTopLeft(find.byKey(const Key('wdChip-1'))).dx));
    await t.tap(find.byKey(const Key('wdChip-2')));
    await t.tap(find.byKey(const Key('wdChipCashOnly')));
    expect(picks, [2, null]);
  });

  testWidgets('disabled chips ignore taps; the entry sheet variant has no Cash only chip', (t) async {
    final picks = <int?>[];
    await t.pumpWidget(host(WithdrawalUseBlock(
      palette: AppPalette.light,
      choices: choices,
      selectedId: 1,
      enabled: false,
      sentence: '',
      noteUnder: kWdChangeAlsoChanges,
      onChanged: picks.add,
    )));
    await t.tap(find.byKey(const Key('wdChip-2')));
    expect(picks, isEmpty);
    expect(find.text(kWdChangeAlsoChanges), findsOneWidget);
    await t.pumpWidget(host(WithdrawalUseBlock(
      palette: AppPalette.light,
      choices: choices,
      selectedId: 1,
      showCashOnly: false,
      showQuestion: false,
      sentence: '',
      onChanged: picks.add,
    )));
    expect(find.byKey(const Key('wdChipCashOnly')), findsNothing);
    expect(find.text(kWdQuestion), findsNothing);
  });

  testWidgets('two-button dialog: buttons sit side by side, left false, right true', (t) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await showTwoButtonDialog(c,
              title: 'T', body: 'B', leftLabel: kWdCancel, rightLabel: kWdDeleteBoth, danger: true),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final l = t.getCenter(find.byKey(const Key('twoButtonLeft')));
    final r = t.getCenter(find.byKey(const Key('twoButtonRight')));
    expect(l.dy, r.dy);
    expect(l.dx, lessThan(r.dx));
    await t.tap(find.byKey(const Key('twoButtonRight')));
    await t.pumpAndSettle();
    expect(result, isTrue);
  });

  test('sentences', () {
    expect(wdArrowText(['Rent', 'Groceries']), '→ Rent, Groceries');
    expect(wdSentenceAdd(categoryId: null, categoryName: null, amountCents: 500000), contains('Nothing else is added'));
    expect(wdSentenceAdd(categoryId: 1, categoryName: 'Rent', amountCents: 500000), 'Save adds Cash — Rent for Ksh 5,000.00, counted as spent.');
    expect(wdDecisionTitle(1), '1 withdrawal needs a decision');
    expect(wdDecisionTitle(3), '3 withdrawals need a decision');
  });

  group('+ New chip', () {
    // A host that behaves like the callers: keeps the choices and the pick.
    Widget stateful(List<int?> picks, {Future<WdCreateResult> Function(String)? create}) => host(_NewHost(picks: picks, create: create));

    testWidgets('no chip without onCreate; with it the chip ends the list', (t) async {
      await t.pumpWidget(host(WithdrawalUseBlock(palette: AppPalette.light, choices: choices, selectedId: null, sentence: '', onChanged: (_) {})));
      expect(find.byKey(const Key('wdChipNew')), findsNothing);
      await t.pumpWidget(stateful([]));
      expect(find.text('+ New'), findsOneWidget);
      expect(t.getTopLeft(find.byKey(const Key('wdChipNew'))).dx, greaterThan(t.getTopLeft(find.byKey(const Key('wdChip-2'))).dx));
      expect(find.byKey(const Key('wdNewField')), findsNothing);
    });

    testWidgets('create: Add makes the category, selects it and closes the field', (t) async {
      final picks = <int?>[];
      await t.pumpWidget(stateful(picks));
      await t.tap(find.byKey(const Key('wdChipNew')));
      await t.pump();
      await t.enterText(find.byKey(const Key('wdNewField')), 'Fuel');
      await t.tap(find.byKey(const Key('wdNewAdd')));
      await t.pump();
      await t.pump();
      expect(picks, [99]);
      expect(find.byKey(const Key('wdChip-99')), findsOneWidget);
      expect(find.byKey(const Key('wdNewField')), findsNothing);
      expect(find.byKey(const Key('wdChipNew')), findsOneWidget);
    });

    testWidgets('duplicate name shows the error and keeps the field open', (t) async {
      final picks = <int?>[];
      await t.pumpWidget(stateful(picks, create: (n) async => WdCreateResult.error('A category named "$n" already exists.')));
      await t.tap(find.byKey(const Key('wdChipNew')));
      await t.pump();
      await t.enterText(find.byKey(const Key('wdNewField')), 'Rent');
      await t.tap(find.byKey(const Key('wdNewAdd')));
      await t.pump();
      await t.pump();
      expect(find.text('A category named "Rent" already exists.'), findsOneWidget);
      expect(find.byKey(const Key('wdNewField')), findsOneWidget);
      expect(picks, isEmpty);
    });

    testWidgets('the error clears as soon as the text changes', (t) async {
      await t.pumpWidget(stateful([], create: (n) async => WdCreateResult.error('Type a name first.')));
      await t.tap(find.byKey(const Key('wdChipNew')));
      await t.pump();
      await t.tap(find.byKey(const Key('wdNewAdd')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('wdNewError')), findsOneWidget);
      await t.enterText(find.byKey(const Key('wdNewField')), 'F');
      await t.pump();
      expect(find.byKey(const Key('wdNewError')), findsNothing);
    });
  });

  group('createWithdrawalUseCategory (real in-memory db)', () {
    late Database db;
    setUp(() async => db = await openTestDb());
    tearDown(() => db.close());

    test('creates INTO the Cash list, returns the reloaded Cash list; a duplicate is refused', () async {
      final r = await createWithdrawalUseCategory(db, '  Fuel run ');
      expect(r.error, isNull);
      expect(r.choices!.where((c) => c.id == r.id).single.name, 'Fuel run');
      expect(r.choices, hasLength(1), reason: 'only the Cash list, never the Send Money names');
      final row = (await db.query('classifications', where: 'id = ?', whereArgs: [r.id])).single;
      expect(row['group_id'], await groupId(db, 'CASH_USE'));
      final again = await createWithdrawalUseCategory(db, 'fuel RUN');
      expect(again.id, isNull);
      expect(again.error, 'A category named "fuel RUN" already exists.');
      expect((await createWithdrawalUseCategory(db, '   ')).id, isNull);
    });
  });

  test('Spent on wording', () {
    expect(wdReviewSpentOn(categoryName: null, amountCents: 80000), 'Cash only (only the fee is counted)');
    expect(wdReviewSpentOn(categoryName: 'Rent', amountCents: 80000), 'Rent (adds Cash — Rent, Ksh 800.00)');
  });
}

class _NewHost extends StatefulWidget {
  const _NewHost({required this.picks, this.create});
  final List<int?> picks;
  final Future<WdCreateResult> Function(String)? create;
  @override
  State<_NewHost> createState() => _NewHostState();
}

class _NewHostState extends State<_NewHost> {
  var _choices = const [WdChoice(1, 'Rent'), WdChoice(2, 'Groceries')];
  int? _sel;
  @override
  Widget build(BuildContext context) => WithdrawalUseBlock(
        palette: AppPalette.light,
        choices: _choices,
        selectedId: _sel,
        sentence: '',
        onCreate: widget.create ??
            (n) async {
              setState(() => _choices = [..._choices, WdChoice(99, n)]);
              return WdCreateResult.ok(99, _choices);
            },
        onChanged: (id) {
          widget.picks.add(id);
          setState(() => _sel = id);
        },
      );
}
