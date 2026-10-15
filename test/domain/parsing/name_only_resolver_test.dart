// 0.1.2 S8b (NO3): the pure name-only resolver and the recipient name key.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/counterparty/counterparty_key.dart';
import 'package:mmogo/domain/parsing/name_only_fields.dart';
import 'package:mmogo/domain/parsing/name_only_resolver.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

NameOnlyFields fieldsFor(String name) => NameOnlyFields(
      code: 'TST1A2B3C4',
      amountCents: 25000,
      transactionCostCents: 700,
      name: name,
      transactionOccurredAt: 1760000000000,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('KEY TEST: deriveRecipientNameKey == deriveCounterpartyKey(BUY_GOODS, name) for several names', () {
    for (final n in ['Mary Wanjiku', '  zed  stores ', 'JOHN\tKAMAU', 'a', 'Café Ndogo', '']) {
      expect(deriveRecipientNameKey(n),
          deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: n),
          reason: n);
    }
    expect(deriveRecipientNameKey('  mary   wanjiku '), 'MARY WANJIKU');
    // the Pochi case of the single normaliser is '' by design, so it cannot be the key source
    expect(deriveCounterpartyKey(sourceType: SmsSourceType.pochi, counterpartyLabel: 'Mary'), '');
    expect(deriveRecipientNameKey('Mary'), isNot(''));
  });

  test('hit, Send Money: phone NULL, label NULL, fromMemory, other fields carried', () {
    final r = resolveNameOnly(fieldsFor('Mary Wanjiku'), const RecipientRule(type: SmsSourceType.sendMoney, at: 1));
    expect(r, isA<Resolved>());
    final res = r as Resolved;
    expect(res.fromMemory, isTrue);
    expect(res.fields.sourceType, SmsSourceType.sendMoney);
    expect(res.fields.counterpartyPhone, isNull);
    expect(res.fields.counterpartyLabel, isNull);
    expect(res.fields.code, 'TST1A2B3C4');
    expect(res.fields.amountCents, 25000);
    expect(res.fields.transactionCostCents, 700);
    expect(res.fields.transactionOccurredAt, 1760000000000);
    expect(res.fields.paybillAccountNumber, isNull);
  });

  test('hit, Pochi: the name is kept as the label', () {
    final res = resolveNameOnly(fieldsFor('Zed Stores'), const RecipientRule(type: SmsSourceType.pochi, at: 1)) as Resolved;
    expect(res.fields.sourceType, SmsSourceType.pochi);
    expect(res.fields.counterpartyLabel, 'Zed Stores');
    expect(res.fields.counterpartyPhone, isNull);
    expect(res.fromMemory, isTrue);
  });

  test('miss: NeedsType carries the same fields; an unusable remembered type is a miss', () {
    final f = fieldsFor('Zed Stores');
    final r = resolveNameOnly(f, null);
    expect(r, isA<NeedsType>());
    expect((r as NeedsType).fields, f);
    expect(resolveNameOnly(f, const RecipientRule(type: SmsSourceType.buyGoods, at: 1)), isA<NeedsType>());
  });

  test('end to end with memory: miss, remember, odd spacing still hits, user override replaces, gate off repeats the ask', () async {
    final mem = RecipientMemory();
    Future<NameOnlyResolution> go(String name) async =>
        resolveNameOnly(fieldsFor(name), await mem.lookup(deriveRecipientNameKey(name)));

    expect(await go('Mary Wanjiku'), isA<NeedsType>());
    // switch OFF: nothing stored, the next message asks again
    await mem.remember(deriveRecipientNameKey('Mary Wanjiku'), SmsSourceType.pochi, recordDetailsOn: false);
    expect(await go('Mary Wanjiku'), isA<NeedsType>());

    await mem.remember(deriveRecipientNameKey('Mary Wanjiku'), SmsSourceType.pochi, recordDetailsOn: true);
    final hit = await go('  MARY   wanjiku ') as Resolved;
    expect(hit.fields.sourceType, SmsSourceType.pochi);
    expect(hit.fields.counterpartyLabel, '  MARY   wanjiku ');

    // a later remember replaces the type
    await mem.remember(deriveRecipientNameKey('Mary Wanjiku'), SmsSourceType.sendMoney, recordDetailsOn: true);
    final over = await go('Mary Wanjiku') as Resolved;
    expect(over.fields.sourceType, SmsSourceType.sendMoney);
    expect(over.fields.counterpartyLabel, isNull);
    expect(over.fields.counterpartyPhone, isNull);
  });

  test('corrupt memory reads as a miss, and a failed write does not block the next step', () async {
    SharedPreferences.setMockInitialValues({'recipient_types_v1': 'garbage{'});
    final mem = RecipientMemory();
    final key = deriveRecipientNameKey('Zed Stores');
    expect(resolveNameOnly(fieldsFor('Zed Stores'), await mem.lookup(key)), isA<NeedsType>());

    final failing = RecipientMemory(prefs: () => throw StateError('plugin gone'));
    // the caller has its own flow to continue: remember returns a code, never throws
    final r = await failing.remember(key, SmsSourceType.pochi, recordDetailsOn: true);
    expect(r, RememberResult.writeFailed);
    expect(resolveNameOnly(fieldsFor('Zed Stores'), await failing.lookup(key)), isA<NeedsType>());
  });

  test('failure text never contains the name: results and results.toString() are codes', () async {
    final failing = RecipientMemory(prefs: () => throw StateError('plugin gone'));
    for (final t in RememberResult.values) {
      expect(t.toString().toUpperCase().contains('ZED'), isFalse);
    }
    final r = await failing.remember('ZED STORES', SmsSourceType.pochi, recordDetailsOn: true);
    expect(r.toString().toUpperCase().contains('ZED'), isFalse);
  });
}
