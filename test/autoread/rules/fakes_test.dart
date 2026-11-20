@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/rules/fake_rule_engine.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/fake_undone_codes.dart';
import 'package:mmogo/autoread/rules/receiver_key.dart';
import 'package:mmogo/autoread/rules/rule_engine.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 19, 10);

  test('store: set, get, update keeps created, forget, wipe, changes', () async {
    final s = FakeRuleStore();
    var n = 0;
    s.changes.listen((_) => n++);
    expect(await s.setLevel(ReceiverType.sendMoney, '0712', name: 'Ann', level: RuleLevel.askFirst, categoryId: 4, at: t0), isTrue);
    expect((await s.get(ReceiverType.sendMoney, '0712'))!.level, RuleLevel.askFirst);
    await s.setLevel(ReceiverType.sendMoney, '0712', name: 'Ann B', level: RuleLevel.suggested, at: t0.add(const Duration(hours: 1)));
    final r2 = (await s.get(ReceiverType.sendMoney, '0712'))!;
    expect(r2.created, t0);
    expect(r2.name, 'Ann B');
    expect((await s.all()).length, 1);
    await s.forget(ReceiverType.sendMoney, '0712');
    expect(await s.get(ReceiverType.sendMoney, '0712'), isNull);
    await s.wipeAll();
    expect(n, 4);
  });

  test('store: same key under two types are two people; cap refuses new only', () async {
    final s = FakeRuleStore();
    await s.setLevel(ReceiverType.pochi, 'X', name: 'X', level: RuleLevel.suggested, at: t0);
    await s.setLevel(ReceiverType.sendMoney, 'X', name: 'X', level: RuleLevel.suggested, at: t0);
    expect((await s.all()).length, 2);
    for (var i = 0; i < kRuleCap - 2; i++) {
      await s.setLevel(ReceiverType.buyGoods, 'S$i', name: 'S', level: RuleLevel.suggested, at: t0);
    }
    expect((await s.all()).length, kRuleCap);
    expect(await s.setLevel(ReceiverType.buyGoods, 'NEW', name: 'N', level: RuleLevel.suggested, at: t0), isFalse);
    expect(await s.setLevel(ReceiverType.pochi, 'X', name: 'X2', level: RuleLevel.askFirst, at: t0), isTrue);
  });

  test('engine fake: logs calls, notNow drops the offer', () async {
    const o = Offer(type: ReceiverType.payBill, key: 'KPLC#1', name: 'KPLC', categoryId: 2, run: 3);
    final e = FakeRuleEngine(offers: [o]);
    expect(await e.pendingOffers(), [o]);
    await e.onRecorded(ReceiverType.payBill, 'KPLC#1', name: 'KPLC', categoryId: 2, at: t0);
    await e.notNow(ReceiverType.payBill, 'KPLC#1');
    expect(await e.pendingOffers(), isEmpty);
    expect(e.calls, ['recorded:PB.KPLC#1:2', 'notNow:PB.KPLC#1']);
    expect(await e.suggestAfter(), 3);
    expect(await e.suggestEnabled(), isTrue);
  });

  test('history fake: top two, empty, unavailable', () async {
    final h = FakeHistoryReader(history: {'SM.0712': [5, 6, 7]});
    expect(await h.topTwo(ReceiverType.sendMoney, '0712'), [5, 6]);
    expect(await h.topTwo(ReceiverType.sendMoney, '0799'), isEmpty);
    h.unavailable = true;
    expect(await h.topTwo(ReceiverType.sendMoney, '0712'), isNull);
  });

  test('undone codes fake: expires after 24 h, wipe clears', () async {
    final u = FakeUndoneCodes();
    await u.add('AB1', now: t0);
    expect(await u.contains('AB1', now: t0.add(const Duration(hours: 23))), isTrue);
    expect(await u.contains('AB1', now: t0.add(const Duration(hours: 24))), isFalse);
    expect(await u.contains('ZZ', now: t0), isFalse);
    await u.wipe();
    expect(await u.contains('AB1', now: t0), isFalse);
  });

  test('receiverKey is real (S2a)', () {
    expect(receiverKey(ReceiverType.sendMoney, phone: '0712'), '0712');
  });
}
