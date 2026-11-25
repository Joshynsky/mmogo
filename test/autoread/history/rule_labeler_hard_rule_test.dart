// 0.2.2 item 2 slice B2a: the labeler on the live Auto-record path. `auto` hint ONLY when decideHardRule says
// record; any other answer for an Auto-record person is an Ask first hint with fromAutoRecord = true. While
// autoRecordLive is false (the default) today's hint is unchanged. Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/history/rule_labeler.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/hard_rule_decision.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';

final _at = DateTime(2026, 11, 25);
const _key = '0712345678';

ParsedSmsFields _msg({SmsSourceType type = SmsSourceType.sendMoney, int amount = 50000}) => ParsedSmsFields(
      code: 'QWE1R2T3Y4',
      sourceType: type,
      amountCents: amount,
      transactionCostCents: 700,
      counterpartyLabel: type == SmsSourceType.sendMoney ? 'JANE DOE' : 'SAMPLE BIZ',
      counterpartyPhone: type == SmsSourceType.sendMoney ? _key : null,
      paybillAccountNumber: type == SmsSourceType.payBill ? '123' : null,
      transactionOccurredAt: 1000,
    );

void main() {
  late FakeRuleStore rules;
  late bool paused;

  RuleLabeler lab({bool? live = true, Future<bool> Function()? pause}) => RuleLabeler(
        rules: rules,
        history: FakeHistoryReader(history: {'SM.$_key': [4, 3]}),
        paused: pause ?? () async => paused,
        live: live,
      );

  Future<void> auto({int? ceiling, int? cat = 7, ReceiverType type = ReceiverType.sendMoney, String key = _key}) async {
    await rules.saveRule(ReceiverRule(
        type: type, key: key, name: 'Jane', level: RuleLevel.autoRecord, categoryId: cat, ceilingCents: ceiling, created: _at, changed: _at));
  }

  setUp(() {
    rules = FakeRuleStore();
    paused = false;
  });

  test('dormant default: autoRecordLive false gives today\'s Ask first hint, no fromAutoRecord', () async {
    expect(autoRecordLive, isFalse);
    await auto();
    final h = await lab(live: null).label(_msg());
    expect(h, const RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: _key, suggested: [7]));
  });

  test('live, record: an auto hint with the rule category only', () async {
    await auto();
    expect(await lab().label(_msg()), const RuleHint(level: RuleLevel.autoRecord, type: ReceiverType.sendMoney, key: _key, suggested: [7]));
  });

  test('live, equal to the ceiling records; 1 cent above asks first with the mark', () async {
    await auto(ceiling: 50000);
    expect((await lab().label(_msg(amount: 50000)))!.level, RuleLevel.autoRecord);
    final h = (await lab().label(_msg(amount: 50001)))!;
    expect(h, const RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: _key, suggested: [7], fromAutoRecord: true));
  });

  test('live, paused: Ask first with the mark; a pause read that throws is paused', () async {
    await auto();
    paused = true;
    expect(await lab().label(_msg()),
        const RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: _key, suggested: [7], fromAutoRecord: true));
    final h = await lab(pause: () async => throw StateError('prefs')).label(_msg());
    expect(h!.level, RuleLevel.askFirst);
    expect(h.fromAutoRecord, isTrue);
  });

  test('live, Paybill level 2 in storage: Ask first with the mark, never auto', () async {
    await auto(type: ReceiverType.payBill, key: 'SAMPLE BIZ|123');
    final l = RuleLabeler(
      rules: rules,
      history: FakeHistoryReader(),
      paused: () async => false,
      live: true,
      keyOf: (t, {phone, business, account, shopName, name, pochiRemembered = false, recordReceiverDetails = true}) => 'SAMPLE BIZ|123',
    );
    final h = (await l.label(_msg(type: SmsSourceType.payBill)))!;
    expect(h.level, RuleLevel.askFirst);
    expect(h.fromAutoRecord, isTrue);
  });

  test('live, no category on the rule: Ask first with the history categories and the mark', () async {
    await auto(cat: null);
    final h = (await lab().label(_msg()))!;
    expect(h, const RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: _key, suggested: [4, 3], fromAutoRecord: true));
  });

  test('live, restored-pending rule (ap) is Ask first with the mark', () async {
    await rules.saveRule(ReceiverRule(
        type: ReceiverType.sendMoney, key: _key, name: 'Jane', level: RuleLevel.autoRecord, categoryId: 7, autoPending: true, created: _at, changed: _at));
    expect((await lab().label(_msg()))!.fromAutoRecord, isTrue);
  });

  test('live, Ask first and Suggested people are unchanged (no mark)', () async {
    await rules.setLevel(ReceiverType.sendMoney, _key, name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: _at);
    expect(await lab().label(_msg()), const RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: _key, suggested: [7]));
    await rules.setLevel(ReceiverType.sendMoney, _key, name: 'Jane', level: RuleLevel.suggested, at: _at);
    expect((await lab().label(_msg()))!.level, RuleLevel.suggested);
  });

  test('live, withdrawal and airtime are never labelled', () async {
    await auto();
    expect(await lab().label(_msg(type: SmsSourceType.agentWithdrawal)), isNull);
    expect(await lab().label(_msg(type: SmsSourceType.airtime)), isNull);
  });

  test('the auto hint round-trips through the pending-item codec as rl auto; the marked Ask first as ask + fa', () {
    WaitingItem item(RuleHint h) => WaitingItem(
        id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90', kind: WaitingKind.waitingCategory, heldAt: _at, parsed: _msg(), hint: h);
    const a = RuleHint(level: RuleLevel.autoRecord, type: ReceiverType.sendMoney, key: _key, suggested: [7]);
    const f = RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: _key, suggested: [7], fromAutoRecord: true);
    expect(encodePendingItem(item(a)), contains('"rl":"auto"'));
    expect(decodePendingItem(encodePendingItem(item(a)))!.hint, a);
    expect(encodePendingItem(item(f)), allOf(contains('"rl":"ask"'), contains('"fa":true')));
    expect(decodePendingItem(encodePendingItem(item(f)))!.hint, f);
  });
}
