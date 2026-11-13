// §AUTOREAD.HELD_DESCRIBE: the words for a held message. Invented bodies only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/held_describe.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

import '../../domain/parsing/sample_messages.dart';

const String kSentinel = 'zebraquartz';

ParsedSmsFields _parse(String body) => (SmsParser.parse(body) as ParseSuccess).fields;

void main() {
  group('describeReadable', () {
    test('send money always names the other person', () {
      expect(describeReadable(_parse(kSampleSendMoney)), 'Sent Ksh 500 to JANE DOE');
    });
    test('paybill and buy goods say Paid; withdrawal says from', () {
      expect(describeReadable(_parse(kSamplePaybill)), matches(r'^Paid Ksh [\d,]+ to .+'));
      expect(describeReadable(_parse(kSampleBuyGoods)), matches(r'^Paid Ksh [\d,]+ to .+'));
      expect(describeReadable(_parse(kSampleWithdrawal)), startsWith('Withdrew Ksh 2,000 from '));
    });
    test('airtime: myself and another number, the other number is never shown', () {
      expect(describeReadable(_parse(kSampleAirtime)), 'Airtime Ksh 200 for myself');
      final o = describeReadable(_parse(kSampleAirtimeOtherReal));
      expect(o, 'Airtime Ksh 5 for another number');
      expect(o.contains('0712345678'), isFalse);
    });
  });

  group('lightRead', () {
    test('full: code, amount, time as 24 h', () {
      final d = lightRead('Ref UFGH123456 Ksh5.00 of airtime on 11/11/26 at 2:08 PM $kSentinel');
      expect(d.code, 'UFGH123456');
      expect(d.amount, 'Ksh 5');
      expect(d.time, '14:08');
      expect(d.what, isNull);
    });
    test('am and midnight, thousands, cents kept', () {
      expect(lightRead('at 12:05 AM').time, '00:05');
      expect(lightRead('at 12:30 PM').time, '12:30');
      expect(lightRead('Ksh 1,250.50').amount, 'Ksh 1,250.50');
      expect(lightRead('Ksh2,000.00').amount, 'Ksh 2,000');
    });
    test('code only, amount only, time missing, neither', () {
      expect(lightRead('UFGH123456 $kSentinel').code, 'UFGH123456');
      expect(lightRead('UFGH123456 $kSentinel').amount, isNull);
      expect(lightRead('you got Ksh 70 $kSentinel').amount, 'Ksh 70');
      expect(lightRead('you got Ksh 70 $kSentinel').code, isNull);
      expect(lightRead('UFGH123456 Ksh 70').time, isNull);
      expect(lightRead('Hello there $kSentinel').isEmpty, isTrue);
    });
    test('words that look like a code are not taken (all letters, all digits, wrong length)', () {
      expect(lightRead('CONFIRMEDX 0712345678 ABCDEFGHIJK').code, isNull);
      expect(lightRead('AB1CD2EF3').code, isNull);
    });
    test('only the matched pieces come back, never the text around them', () {
      final d = lightRead('The $kSentinel UFGH123456 secret Ksh 5 words at 2:08 PM more $kSentinel');
      for (final s in [d.code, d.amount, d.time, d.what]) {
        expect(s?.contains(kSentinel), isNot(true));
        expect(s?.contains('secret'), isNot(true));
      }
    });
  });
}
