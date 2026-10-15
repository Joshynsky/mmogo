// 0.1.2 S8c-2: the plain pieces behind the name-only ask, the chooser and the
// fee hint (no page needed).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/name_only_resolver.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/screens/add/fee_hint.dart';
import 'package:mmogo/ui/screens/add/name_only_state.dart';
import 'package:mmogo/ui/screens/add/recipient_chooser.dart';

RecipientEntry _e(String key, SmsSourceType t, int at) => RecipientEntry(key, RecipientRule(type: t, at: at));

void main() {
  group('NameOnlyState.shouldRemember (switch ON and tick ON and decided and changed)', () {
    NameOnlyState state({bool pending = false, bool tick = true, String key = 'JANE SAMPLE', RecipientRule? remembered}) =>
        NameOnlyState()
          ..start(name: 'Jane Sample', key: key)
          ..pending = pending
          ..tick = tick
          ..remembered = remembered;

    test('the happy path remembers', () {
      expect(state().shouldRemember(captureOn: true, type: SmsSourceType.pochi), isTrue);
      expect(state().shouldRemember(captureOn: true, type: SmsSourceType.sendMoney), isTrue);
    });
    test('switch off: never', () {
      expect(state().shouldRemember(captureOn: false, type: SmsSourceType.pochi), isFalse);
    });
    test('tick off: never', () {
      expect(state(tick: false).shouldRemember(captureOn: true, type: SmsSourceType.pochi), isFalse);
    });
    test('still undecided: never', () {
      expect(state(pending: true).shouldRemember(captureOn: true, type: SmsSourceType.pochi), isFalse);
    });
    test('a type that cannot be remembered, or an empty key: never', () {
      expect(state().shouldRemember(captureOn: true, type: SmsSourceType.buyGoods), isFalse);
      expect(state().shouldRemember(captureOn: true, type: null), isFalse);
      expect(state(key: '').shouldRemember(captureOn: true, type: SmsSourceType.pochi), isFalse);
    });
    test('an unchanged remembered answer writes nothing; a changed one does', () {
      const r = RecipientRule(type: SmsSourceType.pochi, at: 1);
      expect(state(remembered: r).shouldRemember(captureOn: true, type: SmsSourceType.pochi), isFalse);
      expect(state(remembered: r).shouldRemember(captureOn: true, type: SmsSourceType.sendMoney), isTrue);
    });
    test('not a name-only form: never; reset clears everything', () {
      expect(NameOnlyState().shouldRemember(captureOn: true, type: SmsSourceType.pochi), isFalse);
      final s = state(remembered: const RecipientRule(type: SmsSourceType.pochi, at: 1))..how = 'memory';
      s.reset();
      expect((s.active, s.pending, s.name, s.key, s.how, s.tick, s.remembered), (false, false, '', '', null, true, null));
    });
  });

  group('recipientChooserEntries', () {
    final all = [
      _e('JACKLINE DEMO', SmsSourceType.pochi, 5),
      _e('TOM SAMPLE', SmsSourceType.sendMoney, 4),
      _e('JABARI EXAMPLE', SmsSourceType.pochi, 3),
      _e('MAJA ONE', SmsSourceType.sendMoney, 2),
      _e('JAMES TWO', SmsSourceType.sendMoney, 1),
      _e('JANE THREE', SmsSourceType.sendMoney, 0),
    ];
    List<String> keys(String typed, SmsSourceType t) =>
        recipientChooserEntries(all, typed: typed, currentType: t).map((e) => e.key).toList();

    test('case-insensitive contains, order kept (newest first), at most 4', () {
      expect(keys('JA', SmsSourceType.sendMoney), ['JACKLINE DEMO', 'JABARI EXAMPLE', 'MAJA ONE', 'JAMES TWO']);
      expect(keys('ja', SmsSourceType.sendMoney), keys('JA', SmsSourceType.sendMoney));
      expect(keys('sample', SmsSourceType.pochi), ['TOM SAMPLE']);
    });
    test('empty or blank typed text shows nothing', () {
      expect(keys('', SmsSourceType.pochi), isEmpty);
      expect(keys('   ', SmsSourceType.pochi), isEmpty);
    });
    test('an exact name with the SAME type is hidden, with another type it shows', () {
      expect(keys('tom sample', SmsSourceType.sendMoney), isEmpty);
      expect(keys('tom sample', SmsSourceType.pochi), ['TOM SAMPLE']);
    });
    test('the text of the status line is the mock\'s', () {
      expect(recipientTypeChangedText('JACKLINE DEMO', SmsSourceType.pochi),
          'Type changed to Pochi, because JACKLINE DEMO is remembered as Pochi.');
      expect(recipientTypeName(SmsSourceType.sendMoney), 'Send Money');
    });
  });

  group('fee hint texts', () {
    test('whole shillings with thousands commas, no decimals (the fee table is in cents)', () {
      expect(feeHintKsh(200000), '2,000');
      expect(feeHintKsh(2900), '29');
      expect(feeHintKsh(25000000), '250,000');
    });
    test('the signed strings, with U+2019', () {
      expect(feeHintLineText(200000), 'Safaricom’s usual fee for Ksh 2,000. Tap to use it.');
      expect(feeHintLineLabel(200000, 2900), 'Safaricom’s usual fee for Ksh 2,000 is Ksh 29. Tap to use it.');
      expect(feeDiffersNoteText(200000, 2900),
          'Safaricom’s usual fee for Ksh 2,000 is Ksh 29 (as of 04-08-2026). Check your message.');
      expect(feeDiffersNoteText(200000, 2900), contains('’'));
      expect(feeDiffersNoteText(200000, 2900), isNot(contains("'")));
    });
    test('what the field gets', () {
      expect(feeHintFieldText(2900), '29.00');
    });
  });
}
