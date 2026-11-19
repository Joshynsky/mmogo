// 0.2.1: Notifications (auto-read build): a withdrawal's Cash only | Categorize row, the Categorize
// sheet, and the ONE "N withdrawals need a decision" item with its Review sheet. Fake callbacks only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/choose_category_row.dart';
import 'package:mmogo/autoread/ui/decision_item.dart';
import 'package:mmogo/autoread/ui/todo_section.dart';
import 'package:mmogo/autoread/ui/withdrawal_categorize_sheet.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/copy/withdrawal_copy.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/widgets/withdrawal_use_block.dart';

import '../../support/news_fakes.dart' show kFakeNow;
import '../../support/waiting_fakes.dart';

class _Choices implements CategoryChoices {
  @override
  Future<List<CategoryChoice>> categories() async => const [CategoryChoice(id: '9', name: 'Withdrawal')];
  @override
  Future<CategoryChoice> create(String name) => throw StateError('no');
}

WaitingItem _wd() => WaitingItem(
      id: heldIdFor(7),
      kind: WaitingKind.waitingCategory,
      heldAt: kFakeNow,
      parsed: ParsedSmsFields(
        code: 'WDX0000001',
        sourceType: SmsSourceType.agentWithdrawal,
        amountCents: 200000,
        transactionCostCents: 3300,
        counterpartyLabel: 'Test Agent',
        counterpartyPhone: null,
        paybillAccountNumber: null,
        agentNumber: '123456',
        transactionOccurredAt: kFakeNow.millisecondsSinceEpoch,
      ),
    );

AnalyticsTransactionRow _undecided(int id, int cents) => AnalyticsTransactionRow(
      id: id,
      displayCode: 'WDU000000$id',
      sourceType: 'AGENT_WITHDRAWAL',
      amountCents: cents,
      counterpartyLabel: 'Test Agent',
      counterpartyPhone: null,
      paybillAccountNumber: null,
      classificationId: 1,
      classificationName: 'Withdrawal',
      occurredAt: kFakeNow,
      transactionCostCents: 3300,
    );

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: child))),
    );

void main() {
  group('withdrawal row', () {
    testWidgets('two side-by-side buttons, Cash only | Categorize (filled), no Later chip', (t) async {
      final events = <String>[];
      await t.pumpWidget(_host(ChooseCategoryRow(
        item: _wd(),
        description: 'Withdrew Ksh 2,000 from Test Agent',
        choicesFor: (_) async => _Choices(),
        onPickCategory: (_, _) async {},
        onLater: (_) => events.add('later'),
        onCashOnly: (i) async => events.add('cash'),
        onCategorizeWithdrawal: (i) async => events.add('categorize'),
      )));
      expect(find.text(kWdQuestion), findsOneWidget);
      expect(find.byKey(const Key('choose-later')), findsNothing);
      final a = t.getCenter(find.byKey(const Key('choose-cash-only')));
      final b = t.getCenter(find.byKey(const Key('choose-categorize')));
      expect(a.dy, b.dy);
      expect(a.dx, lessThan(b.dx));
      expect(t.getSize(find.byKey(const Key('choose-cash-only'))).width, t.getSize(find.byKey(const Key('choose-categorize'))).width);
      await t.tap(find.byKey(const Key('choose-categorize')));
      expect(events, ['categorize']);
      await t.tap(find.byKey(const Key('choose-cash-only')));
      expect(events, ['categorize', 'cash']);
      // After a saved Cash only the row is about to leave: a second tap is ignored.
      await t.tap(find.byKey(const Key('choose-categorize')));
      expect(events, ['categorize', 'cash']);
    });

    testWidgets('a failing Cash only keeps the row usable', (t) async {
      var calls = 0;
      await t.pumpWidget(_host(ChooseCategoryRow(
        item: _wd(),
        description: 'd',
        choicesFor: (_) async => _Choices(),
        onPickCategory: (_, _) async {},
        onCashOnly: (i) async {
          calls++;
          throw StateError('save failed');
        },
        onCategorizeWithdrawal: (i) async {},
      )));
      await t.tap(find.byKey(const Key('choose-cash-only')));
      await t.pump();
      await t.tap(find.byKey(const Key('choose-cash-only')));
      await t.pump();
      expect(calls, 2);
    });
  });

  group('Categorize sheet', () {
    testWidgets('Cash only first and default (button Save); a category turns the button into Add Cash — X', (t) async {
      t.view.physicalSize = const Size(400, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final saved = <int?>[];
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: WithdrawalCategorizeSheet(
            title: 'Withdrew Ksh 2,000 from Test Agent',
            amountCents: 200000,
            choices: const [WdChoice(1, 'Rent'), WdChoice(2, 'Groceries')],
            onSave: (id) async => saved.add(id),
          ),
        ),
      ));
      expect(find.text('Withdrew Ksh 2,000 from Test Agent'), findsOneWidget);
      expect(t.widget<Text>(find.descendant(of: find.byKey(const Key('wdSheetSave')), matching: find.byType(Text))).data, 'Save');
      await t.tap(find.byKey(const Key('wdChip-1')));
      await t.pump();
      expect(find.text('Add Cash — Rent'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('wdSentence'))).data, contains('Cash — Rent for Ksh 2,000.00'));
      await t.tap(find.byKey(const Key('wdSheetSave')));
      await t.pump();
      expect(saved, [1]);
    });
  });

  group('the one decision item', () {
    testWidgets('counts as ONE row in To categorize however many withdrawals wait; Review lists each with two buttons', (t) async {
      t.view.physicalSize = const Size(400, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final rows = ValueNotifier<List<AnalyticsTransactionRow>>([_undecided(1, 200000), _undecided(2, 500000), _undecided(3, 100000)]);
      final done = <String>[];
      await t.pumpWidget(_host(Builder(
        builder: (c) => ValueListenableBuilder<List<AnalyticsTransactionRow>>(
          valueListenable: rows,
          builder: (c, list, _) => TodoSection(
            waiting: const [],
            now: kFakeNow,
            rowBuilder: (w) => const SizedBox(),
            decision: DecisionItem(
              count: list.length,
              onReview: () => showDecisionReview(
                c,
                rows: rows,
                onCashOnly: (r) async {
                  done.add('cash-${r.id}');
                  rows.value = [for (final x in rows.value) if (x.id != r.id) x];
                },
                onCategorize: (r) async => done.add('cat-${r.id}'),
              ),
            ),
          ),
        ),
      )));
      expect(find.text('To categorize (1)'), findsOneWidget);
      expect(find.text('3 withdrawals need a decision'), findsOneWidget);
      expect(find.byKey(const Key('todo-empty')), findsNothing);
      await t.tap(find.byKey(const Key('decision-review')));
      await t.pumpAndSettle();
      for (final id in [1, 2, 3]) {
        expect(find.byKey(Key('decision-cash-$id')), findsOneWidget);
        expect(find.byKey(Key('decision-cat-$id')), findsOneWidget);
        expect(t.getCenter(find.byKey(Key('decision-cash-$id'))).dy, t.getCenter(find.byKey(Key('decision-cat-$id'))).dy);
      }
      expect(find.textContaining('Details'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      await t.tap(find.byKey(const Key('decision-cash-2')));
      await t.pumpAndSettle();
      expect(done, ['cash-2']);
      expect(find.byKey(const Key('decision-row-2')), findsNothing);
      expect(find.text('2 withdrawals need a decision'), findsWidgets);
      await t.tap(find.byKey(const Key('decision-cat-1')));
      expect(done, ['cash-2', 'cat-1']);
    });

    group('Cash only for all', () {
      Future<ValueNotifier<List<AnalyticsTransactionRow>>> open(
        WidgetTester t,
        int n,
        Future<void> Function(List<AnalyticsTransactionRow>)? all,
      ) async {
        t.view.physicalSize = const Size(400, 1600);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final rows = ValueNotifier<List<AnalyticsTransactionRow>>([for (var i = 1; i <= n; i++) _undecided(i, 100000 * i)]);
        await t.pumpWidget(_host(Builder(
          builder: (c) => TextButton(
            key: const Key('open'),
            onPressed: () => showDecisionReview(c,
                rows: rows, onCashOnly: (r) async {}, onCategorize: (r) async {}, onCashOnlyAll: all),
            child: const Text('open'),
          ),
        )));
        await t.tap(find.byKey(const Key('open')));
        await t.pumpAndSettle();
        return rows;
      }

      testWidgets('asks first; Cancel changes nothing; the confirm decides all and the sheet closes', (t) async {
        late ValueNotifier<List<AnalyticsTransactionRow>> rows;
        var calls = 0;
        rows = await open(t, 3, (list) async {
          calls++;
          expect(list.map((r) => r.id), [1, 2, 3]);
          rows.value = const [];
        });
        expect(find.byKey(const Key('decision-cash-all')), findsOneWidget);
        expect(find.text(kWdCashOnlyAll), findsOneWidget);
        await t.tap(find.byKey(const Key('decision-cash-all')));
        await t.pumpAndSettle();
        expect(find.text('Cash only for all 3?'), findsOneWidget);
        expect(find.text(kWdCashOnlyAllBody), findsOneWidget);
        expect(t.getCenter(find.byKey(const Key('twoButtonLeft'))).dy, t.getCenter(find.byKey(const Key('twoButtonRight'))).dy);
        await t.tap(find.byKey(const Key('twoButtonLeft')));
        await t.pumpAndSettle();
        expect(calls, 0);
        expect(find.byKey(const Key('decision-row-1')), findsOneWidget);
        await t.tap(find.byKey(const Key('decision-cash-all')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('twoButtonRight')));
        await t.pumpAndSettle();
        expect(calls, 1);
        expect(find.text(kWdDecisionDone), findsOneWidget);
        expect(find.byKey(const Key('decision-cash-all')), findsNothing);
      });

      testWidgets('a failing batch keeps the sheet open with the error and every row', (t) async {
        await open(t, 2, (list) async => throw StateError('db'));
        await t.tap(find.byKey(const Key('decision-cash-all')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('twoButtonRight')));
        await t.pumpAndSettle();
        expect(find.text(kWdCashOnlyAllError), findsOneWidget);
        expect(find.byKey(const Key('decision-row-1')), findsOneWidget);
        expect(find.byKey(const Key('decision-row-2')), findsOneWidget);
        expect(find.byKey(const Key('decision-cash-all')), findsOneWidget); // can try again
      });

      testWidgets('hidden when only one withdrawal waits (or no batch action is wired)', (t) async {
        await open(t, 1, (list) async {});
        expect(find.byKey(const Key('decision-cash-all')), findsNothing);
      });

      testWidgets('hidden when no batch action is wired', (t) async {
        await open(t, 3, null);
        expect(find.byKey(const Key('decision-cash-all')), findsNothing);
      });
    });

    testWidgets('no item and nothing waiting: the empty card', (t) async {
      await t.pumpWidget(_host(TodoSection(waiting: const [], now: kFakeNow, rowBuilder: (w) => const SizedBox())));
      expect(find.byKey(const Key('todo-empty')), findsOneWidget);
    });
  });
}
