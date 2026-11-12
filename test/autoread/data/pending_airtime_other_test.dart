// WBS row 17: the pending item carries the airtime kind in JSON key `other`.
// Invented data only; the stored JSON never holds the other number.
@Tags(['autoread'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/parsing/sample_messages.dart';

String _id(int n) => n.toRadixString(16).padLeft(32, '0');

ParsedSmsFields _f({
  String code = 'AB1CD2EF3G',
  SmsSourceType type = SmsSourceType.airtime,
  bool other = false,
}) =>
    ParsedSmsFields(
      code: code,
      sourceType: type,
      amountCents: 500,
      transactionCostCents: type == SmsSourceType.sendMoney ? 700 : 0,
      counterpartyLabel: type == SmsSourceType.sendMoney ? 'Test Person' : null,
      counterpartyPhone: type == SmsSourceType.sendMoney ? '0700000000' : null,
      paybillAccountNumber: null,
      transactionOccurredAt: 1000,
      airtimeOther: other,
    );

WaitingItem _item(int n, ParsedSmsFields f) => WaitingItem(
      id: _id(n),
      kind: WaitingKind.waitingCategory,
      heldAt: DateTime.fromMillisecondsSinceEpoch(1000),
      parsed: f,
    );

Map<String, dynamic> _json(WaitingItem i) => jsonDecode(encodePendingItem(i)) as Map<String, dynamic>;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pending_json_other_roundtrip_true', () {
    final item = _item(1, _f(other: true));
    expect(_json(item)['other'], isTrue);
    final back = decodePendingItem(encodePendingItem(item))!;
    expect(back.parsed!.airtimeOther, isTrue);
    expect(back.parsed, item.parsed);
    expect(decodePendingItem(encodePendingItem(_item(2, _f())))!.parsed!.airtimeOther, isFalse);
  });

  test('pending_json_old_item_without_key_decodes_false', () {
    final m = _json(_item(1, _f(other: true)))..remove('other');
    expect(decodePendingItem(jsonEncode(m))!.parsed!.airtimeOther, isFalse);
  });

  test('pending_json_nonbool_other_decodes_false', () {
    for (final v in ['true', 1, 'yes', null, <String>[]]) {
      final m = _json(_item(1, _f(other: true)))..['other'] = v;
      expect(decodePendingItem(jsonEncode(m))!.parsed!.airtimeOther, isFalse, reason: '$v');
    }
  });

  test('pending_json_other_on_non_airtime_decodes_false', () {
    final m = _json(_item(1, _f(type: SmsSourceType.sendMoney)))..['other'] = true;
    final back = decodePendingItem(jsonEncode(m))!;
    expect(back.parsed!.sourceType, SmsSourceType.sendMoney);
    expect(back.parsed!.airtimeOther, isFalse);
  });

  test('pending_json_contains_no_phone_digits_for_other_item', () {
    final f = (SmsParser.parse(kSampleAirtimeOtherReal) as ParseSuccess).fields;
    expect(f.airtimeOther, isTrue);
    final json = encodePendingItem(_item(1, f));
    expect(json, isNot(contains('0712345678')));
    expect(json, isNot(contains('712345678')));
    expect(json, isNot(contains('confirmed')));
  });

  test('pending_same_code_different_flag_is_flagged_not_duplicate', () async {
    final store = SharedPrefsPendingItemsStore();
    expect(await store.put(_item(1, _f()), generation: 0), StoreResult.stored);
    expect(await store.put(_item(2, _f(other: true)), generation: 0), StoreResult.storedFlagged);
    final items = await store.list();
    expect(items, hasLength(2));
    expect(items.where((i) => i.sameCodeDifferentDetails), hasLength(1));
    // Same code and same flag stays a plain duplicate.
    expect(await store.put(_item(3, _f(other: true)), generation: 0), StoreResult.duplicate);
  });
}
