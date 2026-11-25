import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/phone_mask.dart';

void main() {
  group('maskPhone', () {
    test('07 form', () => expect(maskPhone('0722000555'), '0722***555'));
    test('+254 form', () => expect(maskPhone('+254722000555'), '0722***555'));
    test('254 form', () => expect(maskPhone('254722000555'), '0722***555'));
    test('spaces and dashes', () => expect(maskPhone('0722 000-555'), '0722***555'));
    test('already masked is unchanged', () => expect(maskPhone('0722***555'), '0722***555'));
    test('short number hides everything', () {
      expect(maskPhone('12345'), '***');
      expect(maskPhone('1234567'), '***');
    });
    test('8 digits', () => expect(maskPhone('12345678'), '1234***678'));
    test('no digits / null / empty', () {
      expect(maskPhone('abc'), '');
      expect(maskPhone(null), '');
      expect(maskPhone('  '), '');
    });
  });

  group('nameOrMask (name wins)', () {
    test('name present, number ignored', () => expect(nameOrMask('LUCY AKINYI', '0722000555'), 'LUCY AKINYI'));
    test('no name shows the mask', () => expect(nameOrMask(null, '0722000555'), '0722***555'));
    test('number-only name is masked', () => expect(nameOrMask('0722000555', null), '0722***555'));
    test('nothing', () => expect(nameOrMask('', ''), ''));
  });

  group('nameWithMask', () {
    test('name and mask', () => expect(nameWithMask('LUCY AKINYI', '0722000555'), 'LUCY AKINYI 0722***555'));
    test('+254 key', () => expect(nameWithMask('LUCY', '+254733000555'), 'LUCY 0733***555'));
    test('name without digits', () => expect(nameWithMask('LUCY', ''), 'LUCY'));
    test('name with unusable number only', () => expect(nameWithMask('LUCY', 'x'), 'LUCY'));
    test('no name', () => expect(nameWithMask('', '0722000555'), '0722***555'));
    test('number-only name', () => expect(nameWithMask('0722000555', '0722000555'), '0722***555'));
    test('never contains the raw middle', () => expect(nameWithMask('A', '0722000555').contains('000'), isFalse));
  });
}
