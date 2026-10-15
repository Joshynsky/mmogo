// AI3 parser half + WD1 (0.1.2 S8a): length cap, six-by-six cross-matrix,
// adversarial inputs with a time bound, and an env-gated local corpus test.
// Invented data only; the corpus (if any) is private and never committed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/rules/airtime_rule.dart';
import 'package:mmogo/domain/parsing/rules/buy_goods_rule.dart';
import 'package:mmogo/domain/parsing/rules/name_only_rule.dart';
import 'package:mmogo/domain/parsing/rules/paybill_rule.dart';
import 'package:mmogo/domain/parsing/rules/send_money_rule.dart';
import 'package:mmogo/domain/parsing/rules/withdrawal_rule.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

import 'sample_messages.dart';

/// Each rule as "does it claim this text".
final Map<String, bool Function(String)> _rules = {
  'sendMoney': (t) => SendMoneyRule.tryParse(t) != null,
  'paybill': (t) => PaybillRule.tryParse(t) != null,
  'buyGoods': (t) => BuyGoodsRule.tryParse(t) != null,
  'withdrawal': (t) => WithdrawalRule.tryParse(t) != null,
  'airtime': (t) => AirtimeRule.tryParse(t) != null,
  'nameOnly': (t) => NameOnlyRule.tryParse(t) != null,
};

final Map<String, String> _samples = {
  'sendMoney': kSampleSendMoney,
  'paybill': kSamplePaybill,
  'buyGoods': kSampleBuyGoods,
  'withdrawal': kSampleWithdrawal,
  'airtime': kSampleAirtime,
  'nameOnly': kSampleNameOnly,
};

/// Adversarial 2,000-character strings for one rule: its own opening, then a
/// long filler that never reaches the closing words (and one where the fee is
/// missing), the shapes that make a lazy pattern backtrack.
List<String> _adversarial(String sample) {
  final head = sample.substring(0, sample.indexOf(' on ') > 0 ? sample.indexOf(' on ') : 40);
  String pad(String unit) {
    final b = StringBuffer(head)..write(' ');
    while (b.length < kSmsMaxChars) {
      b.write(unit);
    }
    return b.toString().substring(0, kSmsMaxChars);
  }

  final noFee = sample.replaceAll(RegExp(r'Transaction cost.*'), '');
  return [
    pad(' '),
    pad('A '),
    pad('a b c '),
    pad('1 '),
    pad('Transaction cost, Ksh '),
    (noFee + ' x' * 1000).substring(0, kSmsMaxChars),
  ];
}

void main() {
  group('WD1 length cap', () {
    test('kSmsMaxChars is 2000', () => expect(kSmsMaxChars, 2000));

    test('2,001 characters returns the too-long error and runs no regex', () {
      // A valid message padded to 2,001 chars: still refused, so the cap runs
      // before any pattern could have matched it.
      final padded = kSampleSendMoney + ' ' * (kSmsMaxChars + 1 - kSampleSendMoney.length);
      expect(padded.length, 2001);
      final r = SmsParser.parse(padded);
      expect(r, isA<ParseTooLong>());
      expect(r, isA<ParseError>());
      expect((r as ParseError).reason, kSmsTooLongReason);
      expect(r.reason, isNot(SmsParser.kSmsNoMatchReason));
    });

    test('exactly 2,000 characters is still read', () {
      final padded = kSampleSendMoney + ' ' * (kSmsMaxChars - kSampleSendMoney.length);
      expect(padded.length, 2000);
      expect(SmsParser.parse(padded), isA<ParseSuccess>());
    });

    test('a huge input is refused fast', () {
      final sw = Stopwatch()..start();
      final r = SmsParser.parse('A ' * 500000);
      sw.stop();
      expect(r, isA<ParseTooLong>());
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('too-long is distinct from not-recognised', () {
      final tooLong = SmsParser.parse('x' * 2001);
      final noMatch = SmsParser.parse('hello');
      expect(tooLong, isA<ParseTooLong>());
      expect(noMatch, isNot(isA<ParseTooLong>()));
      expect(noMatch, isA<ParseError>());
    });
  });

  group('AI3 cross-matrix: each sample is claimed by exactly one rule', () {
    for (final s in _samples.keys) {
      test('$s sample', () {
        final claimed = [for (final r in _rules.keys) if (_rules[r]!(_samples[s]!)) r];
        expect(claimed, [s]);
      });
    }

    test('a Paybill with an all-letters account is claimed only by paybill', () {
      final alpha = kSamplePaybill.replaceFirst('998877', 'ABCDEF');
      expect([for (final r in _rules.keys) if (_rules[r]!(alpha)) r], ['paybill']);
    });

    test('the "another number" airtime sample is claimed only by airtime', () {
      expect([for (final r in _rules.keys) if (_rules[r]!(kSampleAirtimeOther)) r], ['airtime']);
    });

    test('full dispatch gives the right type for each sample', () {
      const expected = {
        'sendMoney': SmsSourceType.sendMoney,
        'paybill': SmsSourceType.payBill,
        'buyGoods': SmsSourceType.buyGoods,
        'withdrawal': SmsSourceType.agentWithdrawal,
        'airtime': SmsSourceType.airtime,
      };
      expected.forEach((k, t) {
        final r = SmsParser.parse(_samples[k]!);
        expect((r as ParseSuccess).fields.sourceType, t, reason: k);
      });
      expect(SmsParser.parse(kSampleNameOnly), isA<ParseNeedsType>());
    });
  });

  group('adversarial 2,000-character inputs finish fast (no backtracking blow-up)', () {
    for (final s in _samples.keys) {
      test('$s rule and the whole parser', () {
        for (final adv in _adversarial(_samples[s]!)) {
          expect(adv.length, lessThanOrEqualTo(kSmsMaxChars));
          final sw = Stopwatch()..start();
          for (final r in _rules.values) {
            r(adv);
          }
          final res = SmsParser.parse(adv);
          sw.stop();
          expect(sw.elapsedMilliseconds, lessThan(1500),
              reason: '$s: ${adv.substring(0, 30)}');
          // The last variant is the message with its fee line cut off: for
          // airtime that is a LEGAL message (fee defaults to zero), so only
          // the time bound applies to it.
          if (adv != _adversarial(_samples[s]!).last) {
            expect(res, isNot(isA<ParseSuccess>()));
          }
        }
      });
    }
  });

  test('no parser ever throws on odd input', () {
    for (final t in ['', ' ', '\n\n', '\u0000', 'Confirmed.', 'Ksh', '💸' * 100,
        kSampleWithdrawal.replaceFirst('2,000.00', '99999999999999999999999.00'),
        kSampleAirtime.replaceFirst('2:01', '99:99')]) {
      expect(() => SmsParser.parse(t), returnsNormally);
    }
  });

  group('local corpus (private data, env-gated)', () {
    // Point MMOGO_SMS_CORPUS (environment variable, or --dart-define) at a
    // text file with messages separated by a blank line. The file is read
    // only if the variable is set; nothing is created and nothing is printed
    // from the messages themselves, only counts.
    final path = const String.fromEnvironment('MMOGO_SMS_CORPUS').isNotEmpty
        ? const String.fromEnvironment('MMOGO_SMS_CORPUS')
        : (Platform.environment['MMOGO_SMS_CORPUS'] ?? '');
    final missing = path.isEmpty || !File(path).existsSync();
    if (missing) {
      // ignore: avoid_print
      print('SKIPPED local corpus test: MMOGO_SMS_CORPUS is not set (or the '
          'file is missing). This is expected on CI and clean checkouts.');
    }

    test('every message parses without throwing; counts are printed', () {
      final blocks = File(path)
          .readAsStringSync()
          .split(RegExp(r'\r?\n\s*\r?\n'))
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .toList();
      final counts = <String, int>{};
      for (final b in blocks) {
        final r = SmsParser.parse(b);
        final key = switch (r) {
          ParseSuccess(:final fields) => fields.sourceType.name,
          ParseNeedsType() => 'needsType',
          ParseTooLong() => 'tooLong',
          ParseError() => 'notParsed',
        };
        counts[key] = (counts[key] ?? 0) + 1;
      }
      // ignore: avoid_print
      print('corpus: ${blocks.length} messages -> $counts');
      expect(counts.values.fold<int>(0, (a, b) => a + b), blocks.length);
    },
        skip: missing
            ? 'MMOGO_SMS_CORPUS not set: private corpus not available here'
            : false);
  });
}
