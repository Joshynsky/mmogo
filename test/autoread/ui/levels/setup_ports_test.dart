// 0.2.2 item 2 redesign, slice C2: the new ports (Set up list, chips picker typedef, notice category name),
// LevelsDeps defaults and the shared redesign fakes. Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';

import '../../../support/hard_rule_fakes.dart';
import '../../../support/redesign_fakes.dart';

void main() {
  test('LevelsDeps: setup and pickCategories default to null (feature absent); old callers unchanged', () {
    final d = hardTestDeps();
    expect(d.setup, isNull);
    expect(d.pickCategories, isNull);
  });

  test('redesignTestDeps carries both ports', () {
    final src = FakeSetupRecipientsSource();
    final picker = FakeCategoryPicker();
    final d = redesignTestDeps(setup: src, pickCategories: picker.pick);
    expect(d.setup, same(src));
    expect(d.pickCategories, isNotNull);
    expect(d.notice, isA<FakeCategoryRuleChangeNotice>());
    expect(d.store, isA<FakeRuleStore>());
  });

  group('FakeSetupRecipientsSource', () {
    final rows = [
      setupTestRecipient('0722', name: 'Ann', paymentCount: 4, level: RuleLevel.autoRecord),
      setupTestRecipient('888', type: ReceiverType.payBill, name: 'Water', maskedNumber: null),
      setupTestRecipient('555', type: ReceiverType.buyGoods, name: 'Shop'),
    ];
    test('lists all in the given order, or one type', () async {
      final s = FakeSetupRecipientsSource(rows);
      expect(await s.list(), rows);
      expect((await s.list(type: ReceiverType.payBill)).single.displayName, 'Water');
      expect(await s.list(type: ReceiverType.pochi), isEmpty);
      expect(s.calls, [null, ReceiverType.payBill, ReceiverType.pochi]);
    });
    test('details OFF = empty; fail = throws', () async {
      final s = FakeSetupRecipientsSource(rows)..detailsOn = false;
      expect(await s.list(), isEmpty);
      s.fail = true;
      expect(s.list(), throwsStateError);
    });
    test('SetupRecipient equality and null level / number', () {
      expect(setupTestRecipient('a'), setupTestRecipient('a'));
      expect(setupTestRecipient('a').hashCode, setupTestRecipient('a').hashCode);
      expect(setupTestRecipient('a') == setupTestRecipient('a', level: RuleLevel.suggested), isFalse);
      final r = rows[1];
      expect(r.maskedNumber, isNull);
      expect(r.level, isNull);
    });
  });

  testWidgets('FakeCategoryPicker fits PickCategories: records the call, answers, null = closed', (tester) async {
    final picker = FakeCategoryPicker(answer: [4, 7]);
    final PickCategories pick = picker.pick;
    late BuildContext ctx;
    await tester.pumpWidget(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }));
    const choices = [CategoryChoice(id: '4', name: 'Food'), CategoryChoice(id: '7', name: 'Bills')];
    expect(await pick(ctx, mode: CategoryPickMode.upTo2, choices: choices, initial: const [7], usedBefore: const {4}), [4, 7]);
    picker.answer = null;
    expect(await pick(ctx, mode: CategoryPickMode.one, choices: choices, initial: const [], usedBefore: const {}), isNull);
    expect(picker.calls.map((c) => c.mode), [CategoryPickMode.upTo2, CategoryPickMode.one]);
    expect(picker.calls.first.initial, [7]);
    expect(picker.calls.first.usedBefore, {4});
    expect(picker.calls.first.choices, choices);
  });

  test('RuleChangeNotice.show takes an optional categoryName; old 4-argument calls still work', () {
    final RuleChangeNotice n = FakeCategoryRuleChangeNotice();
    n.show('Ann', RuleLevel.askFirst, null, null, categoryName: 'Food');
    n.show('Ann', RuleLevel.suggested, null, null);
    final calls = (n as FakeCategoryRuleChangeNotice).calls;
    expect(calls.map((c) => c.categoryName), ['Food', null]);
    final RuleChangeNotice old = FakeRuleChangeNotice();
    old.show('Ann', RuleLevel.autoRecord, 500, null, categoryName: 'Food');
    expect((old as FakeRuleChangeNotice).calls.single.level, RuleLevel.autoRecord);
  });
}
