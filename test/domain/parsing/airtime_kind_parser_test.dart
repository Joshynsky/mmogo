// WBS row 17 (J-row17 v2): the parser decides the airtime kind. `for <digits>`
// sets `airtimeOther`; the digits are never kept. Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

import 'sample_messages.dart';

ParsedSmsFields _ok(String m) {
  final r = SmsParser.parse(m);
  expect(r, isA<ParseSuccess>(), reason: m);
  return (r as ParseSuccess).fields;
}

ParsedSmsFields _base({bool other = false, SmsSourceType type = SmsSourceType.airtime}) => ParsedSmsFields(
      code: 'AB1CD2EF3G',
      sourceType: type,
      amountCents: 500,
      transactionCostCents: 0,
      counterpartyLabel: null,
      counterpartyPhone: null,
      paybillAccountNumber: null,
      transactionOccurredAt: 1000,
      airtimeOther: other,
    );

void main() {
  test('airtime_rule_other_sets_flag_true', () {
    expect(_ok(kSampleAirtimeOtherReal).airtimeOther, isTrue);
  });

  test('airtime_rule_own_sets_flag_false', () {
    expect(_ok(kSampleAirtime).airtimeOther, isFalse);
  });

  test('airtime_rule_other_number_not_in_fields', () {
    final f = _ok(kSampleAirtimeOtherReal);
    expect(f.toString(), isNot(contains('0712345678')));
    expect(f.counterpartyLabel, isNull);
    expect(f.counterpartyPhone, isNull);
    expect(f.paybillAccountNumber, isNull);
    expect(f.agentNumber, isNull);
    // The fields are the same as the own-number message apart from the flag.
    expect(f.airtimeOther, isTrue);
  });

  test('airtime_rule_other_plus_sign_number_flag_true', () {
    const m = 'AB1CD2EF3G confirmed.You bought Ksh5.00 of airtime for +254712345678 on '
        '11/11/26 at 5:13 PM.New  balance is Ksh100.00. Transaction cost, Ksh0.00.';
    final f = _ok(m);
    expect(f.airtimeOther, isTrue);
    expect(f.toString(), isNot(contains('254712345678')));
  });

  test('parsed_sms_fields_airtime_other_in_equality_and_hash', () {
    final a = _base();
    final b = _base(other: true);
    expect(a == b, isFalse);
    expect(a.hashCode == b.hashCode, isFalse);
    expect(_base(other: true) == _base(other: true), isTrue);
    expect(_base(other: true).hashCode, _base(other: true).hashCode);
    expect(b.toString(), contains('airtimeOther: true'));
    expect(a.toString(), contains('airtimeOther: false'));
  });

  test('parsed_sms_fields_other_on_non_airtime_asserts', () {
    expect(() => _base(other: true, type: SmsSourceType.sendMoney), throwsAssertionError);
    expect(() => _base(other: false, type: SmsSourceType.sendMoney), returnsNormally);
  });

  test('other types always parse with the flag false', () {
    for (final m in [kSampleSendMoney, kSamplePaybill, kSampleWithdrawal]) {
      expect(_ok(m).airtimeOther, isFalse);
    }
  });
}
