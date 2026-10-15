// WD2 + agentNumber (0.1.2 S8a): the agent withdrawal rule. Invented data.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/rules/withdrawal_rule.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

import 'sample_messages.dart';

ParsedSmsFields _ok(String m) {
  final r = SmsParser.parse(m);
  expect(r, isA<ParseSuccess>(), reason: m);
  return (r as ParseSuccess).fields;
}

void main() {
  group('withdrawal rule - golden', () {
    test('the glued real-shape sample parses with every field', () {
      final f = _ok(kSampleWithdrawal);
      expect(f.code, 'ABC1D2E3F4');
      expect(f.sourceType, SmsSourceType.agentWithdrawal);
      expect(f.sourceType.dbValue, 'AGENT_WITHDRAWAL');
      expect(f.amountCents, 200000);
      expect(f.transactionCostCents, 2900);
      expect(f.counterpartyLabel, 'SAMPLE AGENT NAME');
      expect(f.counterpartyPhone, isNull);
      expect(f.paybillAccountNumber, isNull);
      expect(f.agentNumber, '1234567');
      expect(f.transactionOccurredAt, DateTime(2026, 10, 8, 9, 15).millisecondsSinceEpoch);
    });

    test('normal spacing parses to the same fields', () {
      final spaced = kSampleWithdrawal
          .replaceFirst('Confirmed.on', 'Confirmed. on')
          .replaceFirst('AMWithdraw', 'AM Withdraw')
          .replaceFirst('NAME  New', 'NAME New');
      expect(_ok(spaced), _ok(kSampleWithdrawal));
    });

    test('a printed 0.00 fee is allowed', () {
      final f = _ok(kSampleWithdrawal.replaceFirst('Ksh29.00', 'Ksh0.00'));
      expect(f.transactionCostCents, 0);
    });

    test('agent text with no balance phrase runs to the fee line', () {
      final f = _ok('ABC1D2E3F4 Confirmed.on 8/10/26 at 9:15 AMWithdraw Ksh100.00 '
          'from 99 - TINY AGENT Transaction cost, Ksh11.00.');
      expect(f.counterpartyLabel, 'TINY AGENT');
      expect(f.agentNumber, '99');
      expect(f.transactionCostCents, 1100);
    });

    test('agent text is capped at 200 characters', () {
      final long = List.filled(60, 'ABCD').join(' '); // 299 chars
      final f = _ok(kSampleWithdrawal.replaceFirst('SAMPLE AGENT NAME', long));
      expect(f.counterpartyLabel!.length, lessThanOrEqualTo(kAgentTextMaxChars));
      expect(f.counterpartyLabel!.length, greaterThan(190));
    });

    test('agent number: 20 digits ok, 21 digits not understood', () {
      expect(_ok(kSampleWithdrawal.replaceFirst('1234567', '1' * 20)).agentNumber, '1' * 20);
      expect(SmsParser.parse(kSampleWithdrawal.replaceFirst('1234567', '1' * 21)),
          isA<ParseError>());
    });
  });

  group('withdrawal rule - mutations (not understood, never a zero)', () {
    test('FEE MANDATORY: no fee line is not understood', () {
      final m = kSampleWithdrawal.replaceFirst(RegExp(r'Transaction cost, Ksh29\.00\.'), '');
      expect(SmsParser.parse(m), isA<ParseError>());
    });
    test('FEE MANDATORY: unreadable fee is not understood', () {
      expect(SmsParser.parse(kSampleWithdrawal.replaceFirst('Ksh29.00', 'Ksh--')),
          isA<ParseError>());
      expect(SmsParser.parse(kSampleWithdrawal.replaceFirst('Ksh29.00', 'Ksh29')),
          isA<ParseError>());
    });
    test('no "Withdraw" phrase, no digits agent number, no dash', () {
      expect(SmsParser.parse(kSampleWithdrawal.replaceFirst('Withdraw', 'Taken')),
          isA<ParseError>());
      expect(SmsParser.parse(kSampleWithdrawal.replaceFirst('1234567', 'ABCDEFG')),
          isA<ParseError>());
      expect(SmsParser.parse(kSampleWithdrawal.replaceFirst('1234567 - ', '1234567 ')),
          isA<ParseError>());
    });
    test('zero amount and impossible date are not understood', () {
      expect(SmsParser.parse(kSampleWithdrawal.replaceFirst('Ksh2,000.00', 'Ksh0.00')),
          isA<ParseError>());
      expect(SmsParser.parse(kSampleWithdrawal.replaceFirst('8/10/26', '31/2/26')),
          isA<ParseError>());
    });
    test('the agent-side "Take cash from" message is not read', () {
      const agentSide = 'XYZ1A2B3C4 Confirmed. On 21/4/24 at 10:12 PM Take Ksh297.00 '
          'cash from SOME PERSON Your M-PESA float balance is Ksh10.00. '
          'Transaction cost, Ksh0.00.';
      expect(SmsParser.parse(agentSide), isA<ParseError>());
    });
  });

  group('agentNumber on ParsedSmsFields', () {
    test('only the withdrawal rule sets it; the others give null', () {
      expect(_ok(kSampleWithdrawal).agentNumber, '1234567');
      for (final m in [kSampleSendMoney, kSamplePaybill, kSampleBuyGoods, kSampleAirtime]) {
        expect(_ok(m).agentNumber, isNull, reason: m);
      }
    });
    test('equality, hashCode and toString include it; old constructor calls work', () {
      const a = ParsedSmsFields(
          code: 'C', sourceType: SmsSourceType.sendMoney, amountCents: 1,
          transactionCostCents: 0, counterpartyLabel: null, counterpartyPhone: null,
          paybillAccountNumber: null, transactionOccurredAt: 1);
      const b = ParsedSmsFields(
          code: 'C', sourceType: SmsSourceType.sendMoney, amountCents: 1,
          transactionCostCents: 0, counterpartyLabel: null, counterpartyPhone: null,
          paybillAccountNumber: null, agentNumber: '5', transactionOccurredAt: 1);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
      expect(b.toString(), contains('agentNumber: 5'));
      expect(a.agentNumber, isNull);
    });
  });
}
