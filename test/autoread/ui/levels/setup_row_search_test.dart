// Pure rules of the Set up sheet (0.2.2 item 2 redesign, slice U-SETUP): the search matches the shown name only
// (F2: never the key, never hidden digits), and the row's words (end slot, line, tag, spoken label) never carry
// the key. Invented names and numbers only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_search.dart';
import 'package:mmogo/autoread/ui/levels/setup_row.dart';
import 'package:mmogo/autoread/ui/levels/setup_type_chips.dart';

import '../../../support/redesign_fakes.dart';

void main() {
  final bob = setupTestRecipient('0722123555', name: 'Bob Otieno', maskedNumber: '0722***555', paymentCount: 18);
  final masked = setupTestRecipient('0712345678', name: '0712***678', maskedNumber: '0712***678', paymentCount: 2);
  final bill = setupTestRecipient('KPLC PREPAID#1234567',
      type: ReceiverType.payBill, name: 'KPLC Prepaid', maskedNumber: null, paymentCount: 1, level: RuleLevel.askFirst);

  group('setupRecipientMatches (names only, F2)', () {
    test('empty or blank matches everyone', () {
      expect(setupRecipientMatches(bob, ''), isTrue);
      expect(setupRecipientMatches(bob, '   '), isTrue);
    });

    test('the name, any case, trimmed', () {
      for (final q in ['bob', ' OTIENO ', 'b otieno'.substring(2), 'Bob Otieno']) {
        expect(setupRecipientMatches(bob, q), isTrue, reason: q);
      }
    });

    test('never the key, a typed phone number, hidden digits, the type, or a Paybill account', () {
      for (final q in ['0722123555', '+254722123555', '254722123555', '0722123', '123', '0722***555', '555', 'send money']) {
        expect(setupRecipientMatches(bob, q), isFalse, reason: q);
      }
      for (final q in ['1234567', '#', 'paybill', 'kplc prepaid#']) {
        expect(setupRecipientMatches(bill, q), isFalse, reason: q);
      }
      expect(setupRecipientMatches(bill, 'kplc'), isTrue);
    });

    test('a masked name: only its shown digits can match, never the hidden ones', () {
      expect(setupRecipientMatches(masked, '0712'), isTrue);
      expect(setupRecipientMatches(masked, '0712345678'), isFalse);
      expect(setupRecipientMatches(masked, '345'), isFalse);
    });
  });

  group('row words', () {
    test('Send Money: number at the end, type and payments on the line, no tag without a rule', () {
      expect(setupRowEnd(bob), '0722***555');
      expect(setupRowLine(bob), '${setupTypeChip(ReceiverType.sendMoney).$2} · ${hardPaymentsCount(18)}');
      expect(setupRowTag(bob), isNull);
    });

    test('no number: payments at the end, the type alone on the line; Ask first tagged', () {
      expect(setupRowEnd(bill), hardPaymentsCount(1));
      expect(setupRowLine(bill), setupTypeChip(ReceiverType.payBill).$2);
      expect(setupRowTag(bill), RuleLevel.askFirst);
    });

    test('Suggested has no tag; Auto-record is tagged', () {
      final s = setupTestRecipient('0711000111', level: RuleLevel.suggested);
      final a = setupTestRecipient('0711000112', level: RuleLevel.autoRecord);
      expect(setupRowTag(s), isNull);
      expect(setupRowTag(a), RuleLevel.autoRecord);
    });

    test('the spoken label is the visible words and never the key', () {
      expect(setupRowSpoken(bob),
          'Bob Otieno, 0722***555, ${setupTypeChip(ReceiverType.sendMoney).$2}, ${hardPaymentsCount(18)}');
      expect(setupRowSpoken(bill),
          'KPLC Prepaid, ${setupTypeChip(ReceiverType.payBill).$2}, ${hardPaymentsCount(1)}, $kHardLevelAskFirst');
      for (final r in [bob, masked, bill]) {
        for (final s in [setupRowSpoken(r), setupRowEnd(r), setupRowLine(r)]) {
          expect(s.contains(r.key), isFalse, reason: s);
        }
      }
      expect(setupRowSpoken(bill).contains('1234567'), isFalse);
    });

    test('chip table: every receiver type has a chip; Airtime is the fifth', () {
      for (final t in ReceiverType.values) {
        expect(setupTypeChip(t).$2, isNotEmpty);
      }
      expect(setupAirtimeChip, kHardTypeChips[4]);
      expect(kSetupChipTypes, hasLength(ReceiverType.values.length));
    });
  });
}
