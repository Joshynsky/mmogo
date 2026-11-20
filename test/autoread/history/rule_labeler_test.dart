// Auto-record S2b: the labeler on fakes, the waiting-item codec (old and new), and the labelling store.
@Tags(['autoread'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/background/labelling_pending_store.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/history/history_reader.dart';
import 'package:mmogo/autoread/history/rule_labeler.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/fake_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';


const _id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
final _at = DateTime(2026, 11, 19);


ParsedSmsFields _sm({String code = 'QWE1R2T3Y4', String phone = '0712345678'}) => ParsedSmsFields(
      code: code,
      sourceType: SmsSourceType.sendMoney,
      amountCents: 50000,
      transactionCostCents: 700,
      counterpartyLabel: 'JANE DOE',
      counterpartyPhone: phone,
      paybillAccountNumber: null,
      transactionOccurredAt: 1000,
    );

class _SlowHistory implements HistoryReader {
  @override
  Future<List<int>?> topTwo(ReceiverType type, String key) => Future<List<int>?>.delayed(const Duration(seconds: 30));
}

class _ThrowingHistory implements HistoryReader {
  @override
  Future<List<int>?> topTwo(ReceiverType type, String key) => throw StateError('history');
}

void main() {
  late FakeRuleStore rules;

  RuleLabeler labeler(HistoryReader h, {Future<bool> Function()? details, Duration? cap}) =>
      RuleLabeler(rules: rules, history: h, recordReceiverDetails: details, cap: cap ?? kLabelCap);

  setUp(() {
    rules = FakeRuleStore();
    SharedPreferences.setMockInitialValues({});
  });

  group('labeler', () {
    test('no rule and no history: no hint', () async {
      expect(await labeler(FakeHistoryReader()).label(_sm()), isNull);
    });

    test('no rule, history: Suggested with the 2 categories (phone forms are one key)', () async {
      final h = FakeHistoryReader(history: {'SM.0712345678': [4, 3, 1]});
      final hint = await labeler(h).label(_sm(phone: '+254712345678'));
      expect(hint, const RuleHint(level: RuleLevel.suggested, type: ReceiverType.sendMoney, key: '0712345678', suggested: [4, 3]));
    });

    test('Suggested rule with no history still labels the person', () async {
      await rules.setLevel(ReceiverType.sendMoney, '0712345678', name: 'Jane', level: RuleLevel.suggested, at: _at);
      final hint = await labeler(FakeHistoryReader()).label(_sm());
      expect(hint!.level, RuleLevel.suggested);
      expect(hint.suggested, isEmpty);
    });

    test('Ask first rule: level ask first with the rule category', () async {
      await rules.setLevel(ReceiverType.sendMoney, '0712345678',
          name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: _at);
      final hint = await labeler(FakeHistoryReader(history: {'SM.0712345678': [4, 3]})).label(_sm());
      expect(hint, const RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: '0712345678', suggested: [7]));
    });

    test('a stored Auto-record level is NEVER emitted in 0.2.1: it is labelled Ask first', () async {
      await rules.setLevel(ReceiverType.sendMoney, '0712345678',
          name: 'Jane', level: RuleLevel.autoRecord, categoryId: 7, at: _at);
      final hint = await labeler(FakeHistoryReader()).label(_sm());
      expect(hint!.level, RuleLevel.askFirst);
    });

    test('history unavailable: the labeler still answers from the rule (no failure)', () async {
      await rules.setLevel(ReceiverType.sendMoney, '0712345678', name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: _at);
      final hint = await labeler(FakeHistoryReader(unavailable: true)).label(_sm());
      expect(hint!.suggested, [7]);
      expect((await labeler(_ThrowingHistory()).label(_sm()))!.suggested, [7]);
    });

    test('Record receiver details OFF: no key, no read, no hint', () async {
      await rules.setLevel(ReceiverType.sendMoney, '0712345678', name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: _at);
      expect(await labeler(FakeHistoryReader(history: {'SM.0712345678': [1]}), details: () async => false).label(_sm()), isNull);
    });

    test('Withdrawal, Airtime and Pochi are never labelled', () async {
      for (final t in [SmsSourceType.agentWithdrawal, SmsSourceType.airtime, SmsSourceType.pochi]) {
        final p = ParsedSmsFields(
            code: 'C1', sourceType: t, amountCents: 100, transactionCostCents: 0, counterpartyLabel: 'X', counterpartyPhone: null, paybillAccountNumber: null, transactionOccurredAt: 1);
        expect(await labeler(FakeHistoryReader(history: {'SM.X': [1]})).label(p), isNull);
      }
    });

    test('a hung history answers within the cap and never throws', () async {
      final sw = Stopwatch()..start();
      final hint = await labeler(_SlowHistory(), cap: const Duration(milliseconds: 200)).label(_sm());
      expect(hint, isNull);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    test('the labeler reads only: the rule store is unchanged', () async {
      await rules.setLevel(ReceiverType.sendMoney, '0712345678', name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: _at);
      final before = await rules.all();
      var fired = 0;
      final sub = rules.changes.listen((_) => fired++);
      await labeler(FakeHistoryReader(history: {'SM.0712345678': [1, 2]})).label(_sm());
      await sub.cancel();
      expect(fired, 0);
      expect(await rules.all(), before);
    });
  });

  group('waiting item codec', () {
    WaitingItem item({RuleHint? hint}) =>
        WaitingItem(id: _id, kind: WaitingKind.waitingCategory, heldAt: _at, parsed: _sm(), hint: hint);

    test('an old item (no hint fields) still decodes, hint null', () {
      final old = jsonEncode({
        'id': _id,
        'heldAt': 5,
        'flagged': false,
        'code': 'QWE1R2T3Y4',
        'type': 'sendMoney',
        'amountCents': 50000,
        'costCents': 700,
        'label': 'JANE DOE',
        'phone': '0712345678',
        'account': null,
        'agent': null,
        'other': false,
        'occurredAt': 1000,
      });
      final d = decodePendingItem(old)!;
      expect(d.hint, isNull);
      expect(d.parsed!.code, 'QWE1R2T3Y4');
    });

    test('an item without a hint writes none of the hint fields', () {
      final m = jsonDecode(encodePendingItem(item())) as Map<String, dynamic>;
      for (final k in ['rl', 'rc', 'rk', 'sg']) {
        expect(m.containsKey(k), isFalse);
      }
    });

    test('hint round trip: Suggested (no rl), Ask first (ask), 2 categories', () {
      const sug = RuleHint(level: RuleLevel.suggested, type: ReceiverType.sendMoney, key: '0712345678', suggested: [4, 3]);
      const ask = RuleHint(level: RuleLevel.askFirst, type: ReceiverType.payBill, key: 'KPLC#1', suggested: [7]);
      expect(decodePendingItem(encodePendingItem(item(hint: sug)))!.hint, sug);
      expect(decodePendingItem(encodePendingItem(item(hint: ask)))!.hint, ask);
      final m = jsonDecode(encodePendingItem(item(hint: ask))) as Map<String, dynamic>;
      expect(m['rl'], 'ask');
      expect(m['rc'], 'PB');
      expect((jsonDecode(encodePendingItem(item(hint: sug))) as Map).containsKey('rl'), isFalse);
    });

    test('a damaged hint is dropped, the item still decodes; at most 2 category ids', () {
      final base = jsonDecode(encodePendingItem(item())) as Map<String, dynamic>;
      for (final bad in [
        {'rk': 5, 'rc': 'SM'},
        {'rk': 'k', 'rc': 'ZZ'},
        {'rk': 'k', 'rc': 'SM', 'rl': 'maybe'},
        {'rk': '', 'rc': 'SM'},
      ]) {
        final d = decodePendingItem(jsonEncode({...base, ...bad}));
        expect(d, isNotNull);
        expect(d!.hint, isNull);
      }
      final d = decodePendingItem(jsonEncode({...base, 'rk': 'k', 'rc': 'SM', 'sg': [1, 'x', 2, 3]}))!;
      expect(d.hint!.suggested, [1, 2]);
    });

    test('the stored text carries no message text field', () {
      const hint = RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: '0712345678', suggested: [7]);
      final m = jsonDecode(encodePendingItem(item(hint: hint))) as Map<String, dynamic>;
      expect(m.keys.toSet().intersection({'body', 'text', 'message', 'sms'}), isEmpty);
    });

    test('the real store keeps the hint, also on a flagged same-code item', () async {
      final store = SharedPrefsPendingItemsStore();
      const hint = RuleHint(level: RuleLevel.suggested, type: ReceiverType.sendMoney, key: '0712345678', suggested: [4]);
      await store.put(item(), generation: 0);
      final second = WaitingItem(
        id: '0f1e2d3c4b5a69788796a5b4c3d2e1f0',
        kind: WaitingKind.waitingCategory,
        heldAt: _at,
        parsed: ParsedSmsFields(
            code: 'QWE1R2T3Y4',
            sourceType: SmsSourceType.sendMoney,
            amountCents: 99900,
            transactionCostCents: 700,
            counterpartyLabel: 'JANE DOE',
            counterpartyPhone: '0712345678',
            paybillAccountNumber: null,
            transactionOccurredAt: 1000),
        hint: hint,
      );
      expect(await store.put(second, generation: 0), StoreResult.storedFlagged);
      final stored = (await store.list()).firstWhere((i) => i.id == second.id);
      expect(stored.sameCodeDifferentDetails, isTrue);
      expect(stored.hint, hint);
    });
  });

  group('labelling store and undone codes', () {
    test('put stores the item with the hint; list returns it', () async {
      final inner = SharedPrefsPendingItemsStore();
      await rules.setLevel(ReceiverType.sendMoney, '0712345678', name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: _at);
      final store = LabellingPendingStore(inner, labeler(FakeHistoryReader()));
      final res = await store.put(
          WaitingItem(id: _id, kind: WaitingKind.waitingCategory, heldAt: _at, parsed: _sm()), generation: 0);
      expect(res, StoreResult.stored);
      expect((await inner.list()).single.hint!.level, RuleLevel.askFirst);
    });

    test('a labeller that throws still stores the item, unlabelled', () async {
      final inner = SharedPrefsPendingItemsStore();
      final bad = RuleLabeler(
          rules: rules, history: FakeHistoryReader(), keyOf: (_, {phone, business, account, shopName, name, pochiRemembered = false, recordReceiverDetails = true}) => throw StateError('x'));
      final store = LabellingPendingStore(inner, bad);
      await store.put(WaitingItem(id: _id, kind: WaitingKind.waitingCategory, heldAt: _at, parsed: _sm()), generation: 0);
      expect((await inner.list()).single.hint, isNull);
    });

    test('UndoneCodeLookup: an undone code counts, an expired one does not, errors read as not undone', () async {
      final undone = FakeUndoneCodes();
      var now = DateTime(2026, 11, 19, 8);
      await undone.add('QWE1R2T3Y4', now: now);
      final lookup = UndoneCodeLookup(undone, () => now);
      expect(await lookup.contains('QWE1R2T3Y4'), isTrue);
      expect(await lookup.contains('OTHER00000'), isFalse);
      now = now.add(const Duration(hours: 25));
      expect(await lookup.contains('QWE1R2T3Y4'), isFalse);
    });
  });
}
