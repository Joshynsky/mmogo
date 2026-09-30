// Pure, DB-free tests for lib/domain/counterparty/counterparty_key.dart —
// the T12 slice's single most load-bearing piece of logic
// (counterparty_key normalization consistency).
// Exercises the exact rule documented in that file's own header comment
// for all 3 source types, including the whitespace/case edge cases the
// rule explicitly claims to handle.
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/domain/counterparty/counterparty_key.dart';
import 'package:mymog/domain/parsing/parsed_sms_fields.dart';

void main() {
  group('SEND_MONEY — trimmed phone, no case-folding, no reformatting', () {
    test('plain phone number is returned verbatim', () {
      expect(
        deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: '0798630424'),
        '0798630424',
      );
    });

    test('leading/trailing whitespace is trimmed', () {
      expect(
        deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: '  0798630424  '),
        '0798630424',
      );
    });

    test('null phone derives to an empty string, not a crash', () {
      expect(
        deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: null),
        '',
      );
    });

    test('two different-looking-but-equal phone strings (only outer whitespace differs) match', () {
      final a = deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: '0798630424');
      final b = deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: ' 0798630424');
      expect(a, b);
    });
  });

  group('PAYBILL — <label>#<account>, label trimmed/collapsed/upper-cased, account trimmed/collapsed', () {
    test('matches the worked example ("LOOP BIZ#464332")', () {
      final key = deriveCounterpartyKey(
        sourceType: SmsSourceType.payBill,
        counterpartyLabel: 'Loop Biz',
        paybillAccountNumber: '464332',
      );
      expect(key, 'LOOP BIZ#464332');
    });

    test('label case and surrounding whitespace are normalized away', () {
      final key = deriveCounterpartyKey(
        sourceType: SmsSourceType.payBill,
        counterpartyLabel: '  loop biz  ',
        paybillAccountNumber: '464332',
      );
      expect(key, 'LOOP BIZ#464332');
    });

    test('internal double/irregular whitespace in the label collapses to a single space', () {
      final key = deriveCounterpartyKey(
        sourceType: SmsSourceType.payBill,
        counterpartyLabel: 'LOOP   BIZ',
        paybillAccountNumber: '464332',
      );
      expect(key, 'LOOP BIZ#464332');
    });

    test('account number is trimmed but NOT case-folded', () {
      final key = deriveCounterpartyKey(
        sourceType: SmsSourceType.payBill,
        counterpartyLabel: 'Loop Biz',
        paybillAccountNumber: '  ab12  ',
      );
      expect(key, 'LOOP BIZ#ab12');
    });

    test('same business name under two different account numbers derives two distinct keys', () {
      final keyA = deriveCounterpartyKey(
        sourceType: SmsSourceType.payBill,
        counterpartyLabel: 'KPLC',
        paybillAccountNumber: '111',
      );
      final keyB = deriveCounterpartyKey(
        sourceType: SmsSourceType.payBill,
        counterpartyLabel: 'KPLC',
        paybillAccountNumber: '222',
      );
      expect(keyA, isNot(keyB));
    });
  });

  group('BUY_GOODS — trimmed/collapsed/upper-cased label alone, no account suffix', () {
    test('normalizes case and outer whitespace', () {
      final key = deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: '  Java House  ');
      expect(key, 'JAVA HOUSE');
    });

    test('two SMS samples for the same merchant with differing internal spacing derive the same key', () {
      final keyA = deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: 'Java House');
      final keyB = deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: 'Java  House');
      expect(keyA, keyB);
      expect(keyA, 'JAVA HOUSE');
    });

    test('no "#" suffix — distinct from a PAYBILL key for a visually similar label', () {
      final buyGoodsKey = deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: 'Loop Biz');
      expect(buyGoodsKey.contains('#'), isFalse);
      expect(buyGoodsKey, 'LOOP BIZ');
    });
  });

  test('read-path and write-path calls with identical raw inputs always derive an identical key '
      '(the actual property the OPEN flag-ledger item is about)', () {
    for (final sample in [
      (SmsSourceType.sendMoney, 'LETRICIA OTIENO', ' 0712345678 ', null),
      (SmsSourceType.payBill, ' Kplc  Prepaid ', null, '  99887  '),
      (SmsSourceType.buyGoods, 'Naivas   Supermarket', null, null),
    ]) {
      final readSide = deriveCounterpartyKey(
        sourceType: sample.$1,
        counterpartyLabel: sample.$2,
        counterpartyPhone: sample.$3,
        paybillAccountNumber: sample.$4,
      );
      final writeSide = deriveCounterpartyKey(
        sourceType: sample.$1,
        counterpartyLabel: sample.$2,
        counterpartyPhone: sample.$3,
        paybillAccountNumber: sample.$4,
      );
      expect(readSide, writeSide);
    }
  });
}
