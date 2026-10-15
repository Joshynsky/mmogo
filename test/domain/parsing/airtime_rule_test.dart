// AI1 (0.1.2 S8a): the airtime rule and its fee-line rule. Invented data.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/rules/airtime_rule.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

import 'sample_messages.dart';

ParsedSmsFields _ok(String m) {
  final r = SmsParser.parse(m);
  expect(r, isA<ParseSuccess>(), reason: m);
  return (r as ParseSuccess).fields;
}

void main() {
  test('golden: airtime for self (glued spacing, with a fee line)', () {
    final f = _ok(kSampleAirtime);
    expect(f.code, 'PT8N4W7Q2K');
    expect(f.sourceType, SmsSourceType.airtime);
    expect(f.sourceType.dbValue, 'AIRTIME');
    expect(f.amountCents, 20000);
    expect(f.transactionCostCents, 0);
    expect(f.counterpartyLabel, isNull);
    expect(f.counterpartyPhone, isNull);
    expect(f.agentNumber, isNull);
    expect(f.transactionOccurredAt, DateTime(2025, 10, 31, 14, 1).millisecondsSinceEpoch);
  });

  test('golden: airtime for another number parses; the other number is not kept', () {
    final f = _ok(kSampleAirtimeOther);
    expect(f.sourceType, SmsSourceType.airtime);
    expect(f.amountCents, 10400);
    expect(f.counterpartyLabel, isNull);
    expect(f.counterpartyPhone, isNull);
    expect(f.toString(), isNot(contains('254712345678')));
  });

  test('FEE-LINE RULE: a fee line uses the parsed fee', () {
    expect(_ok(kSampleAirtime.replaceFirst('Ksh0.00.', 'Ksh2.00.')).transactionCostCents, 200);
  });

  test('FEE-LINE RULE: no fee line gives the explicit zero constant', () {
    expect(kAirtimeNoFeeCents, 0);
    // kSampleAirtimeOther has no fee line at all.
    expect(_ok(kSampleAirtimeOther).transactionCostCents, kAirtimeNoFeeCents);
  });

  test('FEE-LINE RULE: a present but unreadable fee line is not understood', () {
    expect(SmsParser.parse(kSampleAirtime.replaceFirst('Ksh0.00.', 'Ksh.')),
        isA<ParseError>());
    expect(SmsParser.parse(kSampleAirtime.replaceFirst('Ksh0.00.', 'free.')),
        isA<ParseError>());
  });

  test('mutations: not airtime when the anchor words change', () {
    expect(SmsParser.parse(kSampleAirtime.replaceFirst('of airtime', 'of bundles')),
        isA<ParseError>());
    expect(SmsParser.parse(kSampleAirtime.replaceFirst('You bought', 'You sold')),
        isA<ParseError>());
    expect(SmsParser.parse(kSampleAirtime.replaceFirst('Ksh200.00', 'Ksh0.00')),
        isA<ParseError>());
    expect(SmsParser.parse(kSampleAirtime.replaceFirst('31/10/25', '31/11/25')),
        isA<ParseError>());
  });
}
