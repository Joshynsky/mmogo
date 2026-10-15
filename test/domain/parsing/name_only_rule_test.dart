// NO1 (0.1.2 S8a): the name-only rule. Invented data.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/rules/name_only_rule.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

import 'sample_messages.dart';

void main() {
  test('golden: a name-only message is a needs-type result with every field', () {
    final r = SmsParser.parse(kSampleNameOnly);
    expect(r, isA<ParseNeedsType>());
    final f = (r as ParseNeedsType).fields;
    expect(f.code, 'POI1U2Y3T4');
    expect(f.amountCents, 15000);
    expect(f.transactionCostCents, 0);
    expect(f.name, 'Sample Person');
    expect(f.transactionOccurredAt, DateTime(2026, 10, 8, 16, 45).millisecondsSinceEpoch);
  });

  test('a name-only result is never a ParseSuccess (never a saved row)', () {
    expect(SmsParser.parse(kSampleNameOnly), isNot(isA<ParseSuccess>()));
  });

  test('whitespace tolerant: double spaces and a tab are collapsed', () {
    final r = SmsParser.parse(nameOnly('Sample   \t Person'));
    expect((r as ParseNeedsType).fields.name, 'Sample Person');
  });

  test('NAME HAS NO DIGITS: a Pochi name with a digit stays not parsed', () {
    expect(SmsParser.parse(nameOnly('Shop 24')), isA<ParseError>());
    expect(SmsParser.parse(nameOnly('Sample Person2')), isA<ParseError>());
  });

  test('FEE MANDATORY: no fee line or an unreadable fee is not understood', () {
    expect(SmsParser.parse(kSampleNameOnly.replaceFirst('Transaction cost, Ksh0.00.', '')),
        isA<ParseError>());
    expect(SmsParser.parse(kSampleNameOnly.replaceFirst('Ksh0.00', 'Ksh-')),
        isA<ParseError>());
  });

  test('name cap: 100 characters ok, 101 not understood', () {
    expect(kNameOnlyMaxChars, 100);
    final n100 = 'A' * 100;
    expect((SmsParser.parse(nameOnly(n100)) as ParseNeedsType).fields.name, n100);
    expect(SmsParser.parse(nameOnly('A' * 101)), isA<ParseError>());
  });

  test('a "for account" message is a Paybill, never name-only', () {
    // An account of letters has no digit to stop the name group, so only the
    // "for account" guard keeps this out of the name-only rule.
    final alpha = kSamplePaybill.replaceFirst('998877', 'ABCDEF');
    expect(NameOnlyRule.tryParse(alpha), isNull);
    final r = SmsParser.parse(alpha);
    expect(r, isA<ParseSuccess>());
    expect((r as ParseSuccess).fields.sourceType, SmsSourceType.payBill);
  });

  test('the paste screen safe behaviour: needs-type is not a ParseError', () {
    // paste_card.dart maps ParseNeedsType to the not-recognised text.
    expect(SmsParser.parse(kSampleNameOnly), isNot(isA<ParseError>()));
    expect(SmsParser.kSmsNoMatchReason, isNotEmpty);
  });
}
