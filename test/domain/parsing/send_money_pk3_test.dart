// PK3 (0.1.2 S8a): Send Money phone forms and name defect. Invented data.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/name_only_fields.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

import 'sample_messages.dart';

ParsedSmsFields _ok(String m) {
  final r = SmsParser.parse(m);
  expect(r, isA<ParseSuccess>(), reason: m);
  return (r as ParseSuccess).fields;
}

void main() {
  group('PK3 phone forms (stored as printed)', () {
    for (final p in ['0112345678', '+254112345678', '254112345678', '0712345678',
        '00254712345678', '+254712345678']) {
      test('$p parses and is kept as printed', () {
        final f = _ok(sendMoney(phone: p));
        expect(f.sourceType, SmsSourceType.sendMoney);
        expect(f.counterpartyPhone, p);
      });
    }
    for (final p in ['07123456', '071234567', '07123456789', '+254212345678',
        '254212345678', '0212345678', '+2547123456']) {
      test('$p is not a phone: the message does not parse as Send Money', () {
        final r = SmsParser.parse(sendMoney(phone: p));
        expect(r is ParseSuccess && r.fields.sourceType == SmsSourceType.sendMoney, isFalse);
      });
    }
  });

  group('PK3 names', () {
    final cases = {
      'grace  ochieng': 'grace ochieng', // lowercase + double space (shape of the real defect)
      'Grace Ochieng': 'Grace Ochieng',
      "JOHN O'BRIEN": "JOHN O'BRIEN",
      "mary o'brien": "mary o'brien",
      'ANNE-MARIE KAMAU': 'ANNE-MARIE KAMAU',
      'J. K. ROWE': 'J. K. ROWE',
      'JANE  DOE': 'JANE DOE',
    };
    cases.forEach((printed, saved) {
      test('"$printed" parses as "$saved"', () {
        final f = _ok(sendMoney(name: printed));
        expect(f.counterpartyLabel, saved);
        expect(f.counterpartyPhone, '0712345678');
      });
    });

    test('a name with a digit stays not parsed', () {
      expect(SmsParser.parse(sendMoney(name: 'JANE D0E')), isA<ParseError>());
    });

    test('a name-only message (no phone) goes to needs-type, not Send Money', () {
      final r = SmsParser.parse(nameOnly('grace  ochieng'));
      expect(r, isA<ParseNeedsType>());
      expect((r as ParseNeedsType).fields.name, 'grace ochieng');
    });

    test('Paybill and Buy Goods name groups are unaffected by the widening', () {
      expect(_ok(kSamplePaybill).counterpartyLabel, 'SAMPLE POWER CO');
      expect(_ok(kSamplePaybill).sourceType, SmsSourceType.payBill);
      // a Paybill name with digits and lowercase is still a Paybill
      final pb = kSamplePaybill.replaceFirst('SAMPLE POWER CO', 'Shop 24 ltd');
      expect(_ok(pb).sourceType, SmsSourceType.payBill);
      expect(_ok(pb).counterpartyLabel, 'Shop 24 ltd');
      final bg = kSampleBuyGoods.replaceFirst('SAMPLE SHOP', 'Mama 2 duka');
      expect(_ok(bg).sourceType, SmsSourceType.buyGoods);
      expect(_ok(bg).counterpartyLabel, 'Mama 2 duka');
    });
  });

  test('NameOnlyFields equality and hashCode', () {
    const a = NameOnlyFields(code: 'C', amountCents: 1, transactionCostCents: 0,
        name: 'N', transactionOccurredAt: 1);
    const b = NameOnlyFields(code: 'C', amountCents: 1, transactionCostCents: 0,
        name: 'N', transactionOccurredAt: 1);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
