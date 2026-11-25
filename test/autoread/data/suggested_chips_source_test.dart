// 0.2.2 item 0 Part 1: which chips one waiting item gets (rule level, kind, own key, failures).
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/suggested_chips_source.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/history/history_reader.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/receiver_key.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';

import '../../support/waiting_fakes.dart';

final _at = DateTime(2026, 11, 24, 9);

class _Choices implements CategoryChoices {
  _Choices(this.cats);
  final List<CategoryChoice> cats;
  @override
  Future<List<CategoryChoice>> categories() async => cats;
  @override
  Future<CategoryChoice> create(String name) async => throw UnimplementedError();
}

class _ThrowingHistory implements HistoryReader {
  @override
  Future<List<int>?> topTwo(ReceiverType type, String key) async => throw StateError('unreadable');
}

final _cats = _Choices([
  const CategoryChoice(id: '1', name: 'Family and friends'),
  const CategoryChoice(id: '2', name: 'Debts'),
  const CategoryChoice(id: '3', name: 'Business'),
]);

WaitingItem _item(int sample, {RuleHint? hint}) => WaitingItem(
      id: heldIdFor(sample + 1),
      kind: WaitingKind.waitingCategory,
      heldAt: _at,
      parsed: sampleFields(sample, _at),
      hint: hint,
    );

// sample 0 = Send Money 0700000000, 3 = Paybill, 4 = Buy Goods, 2 = Airtime.
final _smKey = receiverKey(ReceiverType.sendMoney, phone: '0700000000')!;
final _bgKey = receiverKey(ReceiverType.buyGoods, shopName: 'Sample Grocer')!;

void main() {
  late FakeRuleStore rules;
  late FakeHistoryReader history;
  var detailsOn = true;
  SuggestedChipsSource source({HistoryReader? h}) =>
      SuggestedChipsSource(rules: rules, history: h ?? history, recordReceiverDetails: () async => detailsOn);

  setUp(() {
    rules = FakeRuleStore();
    history = FakeHistoryReader(history: {'SM.$_smKey': [1, 2], 'BG.$_bgKey': [3]});
    detailsOn = true;
  });

  Future<List<String>> names(WaitingItem i, [SuggestedChipsSource? s]) async =>
      [for (final c in await (s ?? source()).chipsFor(i, _cats)) c.name];

  test('Send Money at Suggested with history: 2 chips, most used LAST', () async {
    expect(await names(_item(0)), ['Debts', 'Family and friends']);
  });

  test('Buy Goods (Till): one category in history is one chip', () async {
    expect(await names(_item(4)), ['Business']);
  });

  test('no history (empty or no entry): no chips', () async {
    history.history.clear();
    expect(await names(_item(0)), isEmpty);
  });

  test('Paybill with history, airtime: never chips', () async {
    history.history['PB.SAMPLE POWER CO#123456'] = [1];
    expect(await names(_item(3)), isEmpty);
    expect(await names(_item(2)), isEmpty);
  });

  test('a person on Ask first or Auto-record gets no history chips', () async {
    await rules.setLevel(ReceiverType.sendMoney, _smKey, name: 'X', level: RuleLevel.askFirst, categoryId: 1, at: _at);
    expect(await names(_item(0)), isEmpty);
    await rules.setLevel(ReceiverType.sendMoney, _smKey, name: 'X', level: RuleLevel.autoRecord, categoryId: 1, at: _at);
    expect(await names(_item(0)), isEmpty);
    await rules.setLevel(ReceiverType.sendMoney, _smKey, name: 'X', level: RuleLevel.suggested, at: _at);
    expect(await names(_item(0)), ['Debts', 'Family and friends']);
  });

  test('Record receiver details OFF (no person key): no chips', () async {
    detailsOn = false;
    expect(await names(_item(0)), isEmpty);
  });

  test('summary missing (null) or unreadable (throws): no chips, never an error', () async {
    history.unavailable = true;
    expect(await names(_item(0)), isEmpty);
    expect(await names(_item(0), source(h: _ThrowingHistory())), isEmpty);
  });

  test('a category that is inactive or deleted (not offered) is dropped quietly', () async {
    final s = source();
    final fewer = _Choices([const CategoryChoice(id: '1', name: 'Family and friends')]);
    expect([for (final c in await s.chipsFor(_item(0), fewer)) c.name], ['Family and friends']);
    expect(await s.chipsFor(_item(0), _Choices(const [])), isEmpty);
  });

  test("bound to the item's OWN key: two people never borrow each other's history", () async {
    history.history['SM.OTHERKEY'] = [3];
    final own = RuleHint(level: RuleLevel.suggested, type: ReceiverType.sendMoney, key: 'OTHERKEY');
    expect(await names(_item(0, hint: own)), ['Business']);
    expect(await names(_item(0)), ['Debts', 'Family and friends']);
  });
}
