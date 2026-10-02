// Unit tests for T5 — SMS parsing engine
// (lib/domain/parsing/sms_parser.dart).
//
// Sample message text below is transcribed VERBATIM from the three real
// M-Pesa screenshots in `image refrences/` (not invented):
//   - Send Money  -> "mpesa message example.png"
//   - Paybill     -> "Paybill example.png"
//   - Buy Goods   -> "Buy goods example.png"
// Each screenshot's actual body ends with real-world boilerplate
// ("Amount you can transact within the day is ...", "Download My OneApp
// on https://saf.cx/...") — kept in the test fixtures, not trimmed away,
// specifically so the parser is proven to ignore it correctly rather
// than only being tested against a hand-cleaned message.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

void main() {
  group('SmsParser.parse — Send Money (real sample)', () {
    const message =
        'UHM8E3SB8M Confirmed. Ksh200.00 sent to LETRICIA  OTIENO 0798630424 '
        'on 22/8/26 at 10:52 AM. New M-PESA balance is Ksh0.00. Transaction '
        'cost, Ksh7.00. Amount you can transact within the day is '
        '499,629.00. Download My OneApp on https://saf.cx/lPKcC';

    test('classifies as Send Money and extracts all fields', () {
      final result = SmsParser.parse(message);
      expect(result, isA<ParseSuccess>());
      final fields = (result as ParseSuccess).fields;

      expect(fields.code, 'UHM8E3SB8M');
      expect(fields.sourceType, SmsSourceType.sendMoney);
      expect(fields.sourceType.dbValue, 'SEND_MONEY');
      expect(fields.amountCents, 20000);
      expect(fields.transactionCostCents, 700);
      // Real sample has a double space between names — normalized to one.
      expect(fields.counterpartyLabel, 'LETRICIA OTIENO');
      expect(fields.counterpartyPhone, '0798630424');
      expect(fields.paybillAccountNumber, isNull);
      expect(
        fields.transactionOccurredAt,
        DateTime(2026, 8, 22, 10, 52).millisecondsSinceEpoch,
      );
    });
  });

  group('SmsParser.parse — Paybill (real sample)', () {
    const message =
        'UHL8E3PJ8Y Confirmed. Ksh200.00 sent to LOOP BIZ for account 464332 '
        'on 21/8/26 at 4:24 PM New M-PESA balance is Ksh0.00. Transaction '
        'cost, Ksh5.00.Amount you can transact within the day is '
        '499,613.00. Download My OneApp on https://saf.cx/kWQpy';

    test('classifies as Paybill (not Send Money) and extracts all fields',
        () {
      final result = SmsParser.parse(message);
      expect(result, isA<ParseSuccess>());
      final fields = (result as ParseSuccess).fields;

      expect(fields.code, 'UHL8E3PJ8Y');
      expect(fields.sourceType, SmsSourceType.payBill);
      expect(fields.sourceType.dbValue, 'PAYBILL');
      expect(fields.amountCents, 20000);
      expect(fields.transactionCostCents, 500);
      expect(fields.counterpartyLabel, 'LOOP BIZ');
      expect(fields.counterpartyPhone, isNull);
      expect(fields.paybillAccountNumber, '464332');
      expect(
        fields.transactionOccurredAt,
        DateTime(2026, 8, 21, 16, 24).millisecondsSinceEpoch,
      );
    });
  });

  group('SmsParser.parse — Buy Goods (real sample)', () {
    const message =
        'UHK8E3KJ3L Confirmed. Ksh200.00 paid to RONGO SHELL SERVICE '
        'STATION. on 20/8/26 at 2:32 PM.New M-PESA balance is Ksh364.94. '
        'Transaction cost, Ksh0.00. Amount you can transact within the day '
        'is 499,222.00. Download My OneApp on https://saf.cx/lPKcC';

    test('classifies as Buy Goods (checked before Paybill/Send Money) '
        'and extracts all fields', () {
      final result = SmsParser.parse(message);
      expect(result, isA<ParseSuccess>());
      final fields = (result as ParseSuccess).fields;

      expect(fields.code, 'UHK8E3KJ3L');
      expect(fields.sourceType, SmsSourceType.buyGoods);
      expect(fields.sourceType.dbValue, 'BUY_GOODS');
      expect(fields.amountCents, 20000);
      // Zero transaction cost is a real, valid value (Buy Goods sample).
      expect(fields.transactionCostCents, 0);
      expect(fields.counterpartyLabel, 'RONGO SHELL SERVICE STATION');
      expect(fields.counterpartyPhone, isNull);
      expect(fields.paybillAccountNumber, isNull);
      expect(
        fields.transactionOccurredAt,
        DateTime(2026, 8, 20, 14, 32).millisecondsSinceEpoch,
      );
    });
  });

  group('SmsParser.parse — Paybill account with spaces (B50)', () {
    String msg(String account) =>
        'UHL8E3PJ8Y Confirmed. Ksh100.00 sent to SAFARICOM DATA BUNDLES '
        'for account $account on 21/8/26 at 4:24 PM New M-PESA balance is '
        'Ksh0.00. Transaction cost, Ksh0.00.';

    test('keeps a multi-word account whole', () {
      final result = SmsParser.parse(msg('SAFARICOM DATA BUNDLES'));
      expect(result, isA<ParseSuccess>());
      final fields = (result as ParseSuccess).fields;
      expect(fields.sourceType, SmsSourceType.payBill);
      expect(fields.counterpartyLabel, 'SAFARICOM DATA BUNDLES');
      expect(fields.paybillAccountNumber, 'SAFARICOM DATA BUNDLES');
    });

    test('single-token accounts still parse', () {
      for (final account in ['Talkmore', 'Tunukiwa', 'SMSBundles', 'ATL12345']) {
        final fields = (SmsParser.parse(msg(account)) as ParseSuccess).fields;
        expect(fields.paybillAccountNumber, account);
      }
    });
  });

  group('SmsParser.parse — check-order correctness', () {
    test(
        'a Paybill message is never misclassified as Send Money '
        '(both share a "sent to" prefix)', () {
      const paybillMessage =
          'UHL8E3PJ8Y Confirmed. Ksh200.00 sent to LOOP BIZ for account '
          '464332 on 21/8/26 at 4:24 PM New M-PESA balance is Ksh0.00. '
          'Transaction cost, Ksh5.00.';
      final result = SmsParser.parse(paybillMessage) as ParseSuccess;
      expect(result.fields.sourceType, SmsSourceType.payBill);
    });

    test(
        'a Buy Goods message is never misclassified as Paybill or Send '
        'Money (checked first)', () {
      const buyGoodsMessage =
          'UHK8E3KJ3L Confirmed. Ksh200.00 paid to RONGO SHELL SERVICE '
          'STATION. on 20/8/26 at 2:32 PM.New M-PESA balance is '
          'Ksh364.94. Transaction cost, Ksh0.00.';
      final result = SmsParser.parse(buyGoodsMessage) as ParseSuccess;
      expect(result.fields.sourceType, SmsSourceType.buyGoods);
    });
  });

  group('SmsParser.parse — noon/midnight boundary (AM/PM conversion)', () {
    test('12:00 PM is noon (hour 12), not midnight', () {
      const message =
          'UHZ9Z9Z9Z9 Confirmed. Ksh100.00 sent to JOHN KAMAU 0712345678 on '
          '1/1/26 at 12:00 PM. New M-PESA balance is Ksh0.00. Transaction '
          'cost, Ksh10.00.';
      final result = SmsParser.parse(message) as ParseSuccess;
      expect(
        result.fields.transactionOccurredAt,
        DateTime(2026, 1, 1, 12, 0).millisecondsSinceEpoch,
      );
    });

    test('12:00 AM is midnight (hour 0)', () {
      const message =
          'UHZ9Z9Z9Z9 Confirmed. Ksh100.00 sent to JOHN KAMAU 0712345678 on '
          '1/1/26 at 12:00 AM. New M-PESA balance is Ksh0.00. Transaction '
          'cost, Ksh10.00.';
      final result = SmsParser.parse(message) as ParseSuccess;
      expect(
        result.fields.transactionOccurredAt,
        DateTime(2026, 1, 1, 0, 0).millisecondsSinceEpoch,
      );
    });
  });

  group('SmsParser.parse — explicit error on no match', () {
    test('an unrelated, non-M-Pesa message returns ParseResult.error, '
        'not a silent fallback', () {
      const message = 'Hey, are we still meeting for lunch tomorrow at 1pm?';
      final result = SmsParser.parse(message);
      expect(result, isA<ParseError>());
      final error = result as ParseError;
      expect(error.reason, isNotEmpty);
    });

    test('empty input returns ParseResult.error', () {
      final result = SmsParser.parse('   ');
      expect(result, isA<ParseError>());
    });
  });

  // QA fix F8(d)/(e): a matched shape with an impossible value is "not
  // recognised", never a success.
  group('SmsParser.parse — impossible values', () {
    String send({String amount = '200.00', String date = '22/8/26', String time = '10:52 AM', String cost = '7.00'}) =>
        'UHM8E3SB8M Confirmed. Ksh$amount sent to LETRICIA OTIENO 0798630424 '
        'on $date at $time. New M-PESA balance is Ksh0.00. Transaction '
        'cost, Ksh$cost. Amount you can transact within the day is 499,629.00.';

    test('the control message still parses', () {
      expect(SmsParser.parse(send()), isA<ParseSuccess>());
    });

    test('a 0.00 amount is not recognised (was: success with 0 cents)', () {
      expect(SmsParser.parse(send(amount: '0.00')), isA<ParseError>());
    });

    test('a 0.00 fee is still fine', () {
      final r = SmsParser.parse(send(cost: '0.00'));
      expect((r as ParseSuccess).fields.transactionCostCents, 0);
    });

    test('31/2/26 is not recognised (was: rolled to 3 March)', () {
      expect(SmsParser.parse(send(date: '31/2/26')), isA<ParseError>());
    });

    test('other dates and times that do not exist are not recognised', () {
      for (final date in ['0/5/26', '15/13/26', '31/4/26', '29/2/27']) {
        expect(SmsParser.parse(send(date: date)), isA<ParseError>(), reason: date);
      }
      for (final time in ['13:00 PM', '10:75 AM']) {
        expect(SmsParser.parse(send(time: time)), isA<ParseError>(), reason: time);
      }
    });

    test('a real leap day and 12-hour edge times still parse', () {
      final leap = SmsParser.parse(send(date: '29/2/28')) as ParseSuccess;
      expect(leap.fields.transactionOccurredAt, DateTime(2028, 2, 29, 10, 52).millisecondsSinceEpoch);
      final noon = SmsParser.parse(send(time: '12:05 PM')) as ParseSuccess;
      expect(noon.fields.transactionOccurredAt, DateTime(2026, 8, 22, 12, 5).millisecondsSinceEpoch);
      final midnight = SmsParser.parse(send(time: '12:05 AM')) as ParseSuccess;
      expect(midnight.fields.transactionOccurredAt, DateTime(2026, 8, 22, 0, 5).millisecondsSinceEpoch);
    });

    test('the same checks cover Paybill and Buy Goods', () {
      const paybill = 'UHL8E3PJ8Y Confirmed. Ksh0.00 sent to LOOP BIZ for account 464332 '
          'on 22/8/26 at 10:52 AM. New M-PESA balance is Ksh0.00. Transaction cost, Ksh7.00.';
      const buyGoods = 'UHL8E3PJ8Y Confirmed. Ksh50.00 paid to JAVA HOUSE. on 31/2/26 at 10:52 AM. '
          'New M-PESA balance is Ksh0.00. Transaction cost, Ksh0.00.';
      expect(SmsParser.parse(paybill), isA<ParseError>());
      expect(SmsParser.parse(buyGoods), isA<ParseError>());
    });
  });
}
