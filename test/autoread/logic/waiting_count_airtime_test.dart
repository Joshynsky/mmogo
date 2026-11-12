// WBS row 4: the "waiting for a category" number leaves out airtime that the app
// will add on its own (its own switch is ON). Invented items only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';

import '../../support/waiting_fakes.dart' show heldIdFor;

final _t = DateTime(2026, 11, 12, 10);

WaitingItem _item(int n, SmsSourceType type, {bool other = false}) => WaitingItem(
      id: heldIdFor(n),
      kind: WaitingKind.waitingCategory,
      heldAt: _t,
      parsed: ParsedSmsFields(
        code: 'CODE$n',
        sourceType: type,
        amountCents: 1000,
        transactionCostCents: 0,
        counterpartyLabel: null,
        counterpartyPhone: null,
        paybillAccountNumber: null,
        transactionOccurredAt: _t.millisecondsSinceEpoch,
        airtimeOther: other,
      ),
    );

int _count(List<WaitingItem> l, {bool myself = false, bool other = false}) =>
    waitingCategoryCount(l, myselfOn: myself, otherOn: other);

void main() {
  final mine = _item(1, SmsSourceType.airtime);
  final theirs = _item(2, SmsSourceType.airtime, other: true);
  final send = _item(3, SmsSourceType.sendMoney);

  test('count 0: nothing stored', () => expect(_count([]), 0));

  test('count 0 with airtime for myself and its switch ON', () {
    expect(_count([mine], myself: true), 0);
  });

  test('count 1: the same airtime with its switch OFF waits', () {
    expect(_count([mine]), 1);
    expect(_count([mine], other: true), 1, reason: 'the other switch does not cover it');
  });

  test('both kinds, each follows its own switch', () {
    expect(_count([mine, theirs], myself: true, other: true), 0);
    expect(_count([mine, theirs], myself: true), 1);
    expect(_count([mine, theirs], other: true), 1);
    expect(_count([mine, theirs]), 2);
  });

  test('count n: other items always count, airtime only while its switch is OFF', () {
    final all = [mine, theirs, send, _item(4, SmsSourceType.buyGoods)];
    expect(_count(all), 4);
    expect(_count(all, myself: true, other: true), 2);
  });
}
