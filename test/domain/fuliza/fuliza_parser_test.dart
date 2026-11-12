// 0.2.0 slice 2: Fuliza parser. Every text below is INVENTED (codes, amounts).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/fuliza_parser.dart';

String drawText({
  String code = 'AB12CD34EF',
  String amount = '100.00',
  String wording = 'Interest',
  String fee = '1.00',
  String total = '101.00',
  String due = '14/11/26',
}) =>
    '$code Confirmed. Fuliza M-PESA amount is Ksh $amount. $wording charged Ksh $fee. '
    'Total Fuliza M-PESA outstanding amount is Ksh $total due on $due. '
    'To check daily charges dial *234#.';

String repayText(String how, {String code = 'GH56IJ78KL', String amount = '101.00'}) =>
    '$code Confirmed.\nKsh $amount from your M-PESA has been used to $how pay your outstanding '
    'Fuliza M-PESA. Available Fuliza M-PESA limit is Ksh 1,000.00.';

void main() {
  group('draw', () {
    test('Interest wording', () {
      final m = FulizaParser.parse(drawText());
      expect(m, isA<FulizaDraw>());
      final d = m as FulizaDraw;
      expect(d.code, 'AB12CD34EF');
      expect(d.drawCents, 10000);
      expect(d.feeCents, 100);
      expect(d.printedTotalCents, 10100);
      expect(d.dueDate, DateTime(2026, 11, 14));
      expect(d.feeWordingIsAccessFee, isFalse);
    });

    test('Access Fee wording', () {
      final d = FulizaParser.parse(drawText(wording: 'Access Fee')) as FulizaDraw;
      expect(d.feeWordingIsAccessFee, isTrue);
      expect(d.feeCents, 100);
    });

    test('no space after Ksh and thousands separators', () {
      const t = 'AB12CD34EF Confirmed. Fuliza M-PESA amount is Ksh1,200.00. Interest charged Ksh12.00. '
          'Total Fuliza M-PESA outstanding amount is Ksh1,212.00 due on 3/12/2026.';
      final d = FulizaParser.parse(t) as FulizaDraw;
      expect(d.drawCents, 120000);
      expect(d.printedTotalCents, 121200);
      expect(d.dueDate, DateTime(2026, 12, 3));
    });

    test('zero fee is fine, zero draw or an impossible date is unrecognised', () {
      expect(FulizaParser.parse(drawText(fee: '0.00')), isA<FulizaDraw>());
      expect(FulizaParser.parse(drawText(amount: '0.00')), isA<FulizaUnrecognised>());
      expect(FulizaParser.parse(drawText(due: '31/2/26')), isA<FulizaUnrecognised>());
    });
  });

  group('repayment', () {
    test('full', () {
      final r = FulizaParser.parse(repayText('fully')) as FulizaRepayment;
      expect(r.isFull, isTrue);
      expect(r.amountCents, 10100);
      expect(r.code, 'GH56IJ78KL');
      expect(r.availableLimitCents, 100000);
    });

    test('partial prints no amount owed and still reads', () {
      final r = FulizaParser.parse(repayText('partially', amount: '400.00')) as FulizaRepayment;
      expect(r.isFull, isFalse);
      expect(r.amountCents, 40000);
    });

    test('limit line missing gives null limit', () {
      const t = 'GH56IJ78KL Confirmed.\nKsh 50.00 from your M-PESA has been used to fully pay '
          'your outstanding Fuliza M-PESA.';
      expect((FulizaParser.parse(t) as FulizaRepayment).availableLimitCents, isNull);
    });
  });

  group('notices', () {
    test('limit notice', () {
      const t = 'Dear Customer, your Fuliza M-PESA limit is KSH 2,500.00. '
          'Keep using M-PESA to grow your limit.';
      expect((FulizaParser.parse(t) as FulizaLimitNotice).limitCents, 250000);
    });

    test('failed: insufficient funds as well as Fuliza', () {
      const t = 'Failed. Insufficient funds in your M-PESA account as well as Fuliza. '
          'Available Fuliza limit KSH 30.00.';
      final f = FulizaParser.parse(t) as FulizaFailedNotice;
      expect(f.kind, FulizaFailedKind.insufficientFunds);
      expect(f.availableLimitCents, 3000);
    });

    test('failed: not opted in', () {
      const t = 'Failed. Your M-PESA balance is too low. Dial *234# to register for the '
          'M-PESA overdraw Services Fuliza.';
      expect((FulizaParser.parse(t) as FulizaFailedNotice).kind, FulizaFailedKind.notOptedIn);
    });

    test('outstanding Fuliza ... try again later', () {
      const t = 'Dear Customer, you have an outstanding Fuliza M-PESA transaction, '
          'please try again later.';
      final f = FulizaParser.parse(t) as FulizaFailedNotice;
      expect(f.kind, FulizaFailedKind.outstandingRequest);
      expect(f.availableLimitCents, isNull);
    });
  });

  group('never matched', () {
    test('an airtime advert containing the word Fuliza', () {
      const t = 'AB12CD34EF confirmed.You bought Ksh20.00 of airtime on 3/11/26 at 2:01 PM.'
          'New M-PESA balance is Ksh500.00. Transaction cost, Ksh0.00. Opt in to FULIZA and enjoy more.';
      expect(FulizaParser.parse(t), isA<FulizaUnrecognised>());
    });

    test('a withdraw advert with Join FULIZA / Lipa Fuliza', () {
      const t = 'AB12CD34EF Confirmed. on 3/11/26 at 2:01 PM Withdraw Ksh500.00 from 123456 - Shop. '
          'Join FULIZA, Lipa Fuliza, Withdraw your Fuliza.';
      expect(FulizaParser.parse(t), isA<FulizaUnrecognised>());
    });

    test('the bare word, empty, null, huge, and truncated draws never throw', () {
      for (final t in <String?>[
        'Fuliza',
        '',
        '   ',
        null,
        'x' * 5000,
        'AB12CD34EF Confirmed. Fuliza M-PESA amount is Ksh 100.00.',
        'AB12CD34EF Confirmed. Fuliza M-PESA amount is Ksh abc. Interest charged Ksh 1.00.',
        'Failed',
      ]) {
        expect(FulizaParser.parse(t), isA<FulizaUnrecognised>(), reason: '$t');
      }
    });

    test('an ordinary payment is unrecognised', () {
      const t = 'AB12CD34EF Confirmed. Ksh100.00 sent to JANE DOE 0700000000 on 3/11/26 at 2:01 PM. '
          'New M-PESA balance is Ksh500.00. Transaction cost, Ksh7.00.';
      expect(FulizaParser.parse(t), isA<FulizaUnrecognised>());
    });
  });
}
