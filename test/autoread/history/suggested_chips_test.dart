// 0.2.2 Part 1: the pure chips rule (contract signed 24-11-2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/suggested_chips.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';

void main() {
  const all = {1, 2, 3, 4};

  test('most used goes on the RIGHT (history is most used first)', () {
    // Gary: Family & friends (1) is the most used, Debts (2) the second.
    expect(suggestedChips(type: ReceiverType.sendMoney, history: [1, 2], activeCategoryIds: all), [2, 1]);
  });

  test('one category in history gives one chip', () {
    expect(suggestedChips(type: ReceiverType.buyGoods, history: [3], activeCategoryIds: all), [3]);
  });

  test('no history (null or empty) gives no chips', () {
    expect(suggestedChips(type: ReceiverType.sendMoney, history: null, activeCategoryIds: all), isEmpty);
    expect(suggestedChips(type: ReceiverType.sendMoney, history: const [], activeCategoryIds: all), isEmpty);
  });

  test('a deleted or inactive category is dropped quietly', () {
    expect(suggestedChips(type: ReceiverType.sendMoney, history: [1, 2], activeCategoryIds: {1, 3}), [1]);
    expect(suggestedChips(type: ReceiverType.sendMoney, history: [1, 2], activeCategoryIds: {2}), [2]);
  });

  test('both categories gone gives no chips', () {
    expect(suggestedChips(type: ReceiverType.pochi, history: [1, 2], activeCategoryIds: {9}), isEmpty);
  });

  test('Paybill never gets history chips in 0.2.2 (held to 0.2.3)', () {
    expect(suggestedChips(type: ReceiverType.payBill, history: [1, 2], activeCategoryIds: all), isEmpty);
  });

  test('at most 2 chips and no repeats, even from a long or doubled list', () {
    expect(suggestedChips(type: ReceiverType.sendMoney, history: [1, 1, 2, 3], activeCategoryIds: all), [2, 1]);
  });

  test('chip receiver kinds are exactly Send Money, Pochi and Buy Goods', () {
    expect(kChipReceiverTypes, {ReceiverType.sendMoney, ReceiverType.pochi, ReceiverType.buyGoods});
  });
}
