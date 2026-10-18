@Tags(['autoread'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';

String _id(int n) => n.toRadixString(16).padLeft(32, '0');

ParsedSmsFields _fields(String code, {int amount = 10000, int at = 1000}) => ParsedSmsFields(
      code: code,
      sourceType: SmsSourceType.sendMoney,
      amountCents: amount,
      transactionCostCents: 700,
      counterpartyLabel: 'Test Person',
      counterpartyPhone: '0700000000',
      paybillAccountNumber: null,
      transactionOccurredAt: at,
    );

WaitingItem _item(int n, String code, {int amount = 10000, int at = 1000}) => WaitingItem(
      id: _id(n),
      kind: WaitingKind.waitingCategory,
      heldAt: DateTime.fromMillisecondsSinceEpoch(at),
      parsed: _fields(code, amount: amount, at: at),
    );

Future<Set<String>> _itemKeys() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  return p.getKeys().where((k) => k.startsWith(kPendingItemPrefix)).toSet();
}

void main() {
  late SharedPrefsPendingItemsStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = SharedPrefsPendingItemsStore();
  });

  test('two puts write two per-item keys and no index blob', () async {
    expect(await store.put(_item(1, 'AAA1'), generation: 0), StoreResult.stored);
    expect(await store.put(_item(2, 'AAA2'), generation: 0), StoreResult.stored);
    final p = await SharedPreferences.getInstance();
    expect(await _itemKeys(), {'$kPendingItemPrefix${_id(1)}', '$kPendingItemPrefix${_id(2)}'});
    expect(p.getKeys().length, 2);
    expect(await store.count(), 2);
  });

  test('round trip keeps every parsed field; newest transaction first', () async {
    final full = WaitingItem(
      id: _id(3),
      kind: WaitingKind.waitingCategory,
      heldAt: DateTime.fromMillisecondsSinceEpoch(5000),
      parsed: const ParsedSmsFields(
        code: 'BBB3',
        sourceType: SmsSourceType.agentWithdrawal,
        amountCents: 250000,
        transactionCostCents: 2900,
        counterpartyLabel: 'Agent One',
        counterpartyPhone: null,
        paybillAccountNumber: 'ACC1',
        agentNumber: '123456',
        transactionOccurredAt: 5000,
      ),
    );
    await store.put(_item(1, 'OLD1', at: 1000), generation: 0);
    await store.put(full, generation: 0);
    final l = await store.list();
    expect(l.map((i) => i.id), [_id(3), _id(1)]);
    expect(l.first.parsed, full.parsed);
    expect(l.first.heldAt, full.heldAt);
    expect(l.first.kind, WaitingKind.waitingCategory);
  });

  test('list reloads: a value written elsewhere is seen', () async {
    await store.put(_item(1, 'AAA1'), generation: 0);
    expect((await store.list()).length, 1);
    final other = SharedPrefsPendingItemsStore();
    // Another isolate wrote a second item, then this isolate's cache is stale.
    final p = await SharedPreferences.getInstance();
    final existing = p.getString('$kPendingItemPrefix${_id(1)}')!;
    final sibling = encodePendingItem(_item(2, 'AAA2'));
    SharedPreferences.setMockInitialValues({
      '$kPendingItemPrefix${_id(1)}': existing,
      '$kPendingItemPrefix${_id(2)}': sibling,
    });
    expect((await other.list()).length, 2);
    expect((await store.list()).length, 2);
    expect(await store.containsCode('AAA2'), isTrue);
  });

  test('remove touches only that key', () async {
    await store.put(_item(1, 'AAA1'), generation: 0);
    await store.put(_item(2, 'AAA2'), generation: 0);
    await store.bumpGeneration();
    await store.remove(_id(1));
    expect(await _itemKeys(), {'$kPendingItemPrefix${_id(2)}'});
    expect(await store.readGeneration(), 1);
    await store.remove(_id(9)); // absent: no error
    expect(await store.count(), 1);
  });

  test('SEC-R H1 race: concurrent puts of different ids lose and duplicate nothing', () async {
    final results = await Future.wait([
      for (var i = 1; i <= 30; i++) store.put(_item(i, 'C$i'), generation: 0),
    ]);
    expect(results.every((r) => r == StoreResult.stored), isTrue);
    final l = await store.list();
    expect(l.length, 30);
    expect(l.map((i) => i.id).toSet().length, 30);
  });

  test('concurrent puts from two store instances lose nothing', () async {
    final a = SharedPrefsPendingItemsStore();
    final b = SharedPrefsPendingItemsStore();
    await Future.wait([
      for (var i = 1; i <= 10; i++) (i.isEven ? a : b).put(_item(i, 'D$i'), generation: 0),
    ]);
    expect((await store.list()).length, 10);
  });

  test('idempotent: same code and identical fields is a duplicate, nothing written', () async {
    expect(await store.put(_item(1, 'AAA1'), generation: 0), StoreResult.stored);
    expect(await store.put(_item(2, 'AAA1'), generation: 0), StoreResult.duplicate);
    expect(await store.count(), 1);
    expect(await store.put(_item(1, 'AAA1'), generation: 0), StoreResult.duplicate);
    expect(await store.count(), 1);
  });

  test('same code with different fields keeps both; the new one is flagged', () async {
    await store.put(_item(1, 'AAA1', amount: 10000), generation: 0);
    expect(await store.put(_item(2, 'AAA1', amount: 99900), generation: 0), StoreResult.storedFlagged);
    final l = await store.list();
    expect(l.length, 2);
    expect(l.firstWhere((i) => i.id == _id(2)).sameCodeDifferentDetails, isTrue);
    expect(l.firstWhere((i) => i.id == _id(1)).sameCodeDifferentDetails, isFalse);
  });

  test('cap 200: the 201st put returns full and everything stays', () async {
    final seed = <String, Object>{};
    for (var i = 1; i <= kPendingItemsCap; i++) {
      seed['$kPendingItemPrefix${_id(i)}'] = encodePendingItem(_item(i, 'E$i'));
    }
    SharedPreferences.setMockInitialValues(seed);
    expect(await store.count(), 200);
    expect(await store.put(_item(500, 'NEW1'), generation: 0), StoreResult.full);
    expect(await store.count(), 200);
    expect(await store.containsCode('NEW1'), isFalse);
    expect(await store.containsCode('E1'), isTrue);
  });

  test('stale generation is rejected and writes nothing; bump invalidates a prepared put', () async {
    final prepared = await store.readGeneration();
    expect(prepared, 0);
    expect(await store.put(_item(1, 'AAA1'), generation: 7), StoreResult.staleGeneration);
    expect(await store.count(), 0);
    expect(await store.bumpGeneration(), 1);
    expect(await store.put(_item(1, 'AAA1'), generation: prepared), StoreResult.staleGeneration);
    expect(await store.count(), 0);
    expect(await store.put(_item(1, 'AAA1'), generation: 1), StoreResult.stored);
  });

  test('corrupt JSON under one key is ignored and does not break list', () async {
    await store.put(_item(1, 'AAA1'), generation: 0);
    final p = await SharedPreferences.getInstance();
    await p.setString('$kPendingItemPrefix${_id(2)}', '{not json');
    await p.setString('$kPendingItemPrefix${_id(3)}', '{"id":"${_id(3)}"}');
    await p.setString('$kPendingItemPrefix${_id(4)}', encodePendingItem(_item(5, 'MISMATCH')));
    final l = await store.list();
    expect(l.map((i) => i.id), [_id(1)]);
  });

  test('invalid ids are rejected with ArgumentError', () async {
    expect(() => store.remove('../x'), throwsArgumentError);
    expect(() => store.remove('ABC'), throwsArgumentError);
    // WaitingItem itself refuses a bad id before it can reach put.
    expect(
      () => WaitingItem(
        id: 'nothex',
        kind: WaitingKind.waitingCategory,
        heldAt: DateTime(2026),
        parsed: _fields('X'),
      ),
      throwsArgumentError,
    );
  });

  test('only waiting-category items are accepted', () async {
    final unparsed = WaitingItem(id: _id(1), kind: WaitingKind.readyToParse, heldAt: DateTime(2026));
    expect(() => store.put(unparsed, generation: 0), throwsArgumentError);
  });

  test('the source file has no old blob name and no message-text field', () {
    final src = File('lib/autoread/data/pending_items_store.dart').readAsStringSync();
    expect(src.contains('pending_entries_v1'), isFalse);
    for (final name in ['body', 'raw', 'sms', 'message', 'text']) {
      expect(src.contains("'$name'"), isFalse, reason: name);
    }
    // Every JSON key the codec writes is a parsed field or flag.
    expect(encodePendingItem(_item(1, 'AAA1')).contains('"body"'), isFalse);
  });
}
