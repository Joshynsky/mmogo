// 0.2.2 U5: the pure parts of layout A (search match, row lines, section order). Invented names only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_groups.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';
import 'package:mmogo/autoread/ui/levels/levels_search.dart';

LevelPerson _p(String name, RuleLevel l,
        {ReceiverType type = ReceiverType.sendMoney, String key = '0722123555', int? ceiling, List<String> cats = const []}) =>
    LevelPerson(type: type, key: key, name: name, level: l, ceilingCents: ceiling, categoryNames: cats);

void main() {
  test('search: empty matches all; name, kind, masked number, category; any case, trimmed', () {
    final x = _p('Tim Otieno', RuleLevel.autoRecord, cats: ['Family']);
    expect(levelPersonMatches(x, ''), isTrue);
    expect(levelPersonMatches(x, '  '), isTrue);
    for (final q in ['tim', ' OTIENO ', 'send money', '0722***555', '555', 'family']) {
      expect(levelPersonMatches(x, q), isTrue, reason: q);
    }
    expect(levelPersonMatches(x, 'paybill'), isFalse);
    expect(levelPersonMatches(x, 'food'), isFalse);
  });

  test('search (F2): the stored key / full number and hidden digits never match', () {
    final x = _p('Tim', RuleLevel.autoRecord); // key 0722123555, shown as 0722***555
    for (final q in ['0722123555', '123', '2123', '22123']) {
      expect(levelPersonMatches(x, q), isFalse, reason: q);
    }
    // A Paybill / Buy Goods key has no masked form on the row: it is not searchable either.
    final bill = _p('KPLC', RuleLevel.askFirst, type: ReceiverType.payBill, key: '888880');
    expect(levelPersonMatches(bill, '888880'), isFalse);
    expect(levelPersonMatches(bill, 'kplc'), isTrue);
  });

  test('row line: ceiling, no ceiling, paused, Paybill at Ask first only with the screens on', () {
    expect(levelRowLine(_p('A', RuleLevel.autoRecord, ceiling: 200000), paused: false, hard: true), 'Auto-record up to Ksh 2,000');
    expect(levelRowLine(_p('A', RuleLevel.autoRecord), paused: false, hard: true), kHardRowAutoNoCeiling);
    expect(levelRowLine(_p('A', RuleLevel.autoRecord, ceiling: 5), paused: true, hard: true), kHardRowPaused);
    final bill = _p('KPLC', RuleLevel.askFirst, type: ReceiverType.payBill, key: '888880');
    expect(levelRowLine(bill, paused: false, hard: true), kHardRowAskFirstHighest);
    expect(levelRowLine(bill, paused: false, hard: false), isNull);
    expect(levelRowLine(_p('G', RuleLevel.askFirst), paused: true, hard: true), isNull);
    expect(levelRowLine(_p('S', RuleLevel.suggested), paused: false, hard: true), isNull);
  });

  test('pill level: Auto-record reads Ask first while paused, others unchanged', () {
    expect(shownLevel(_p('A', RuleLevel.autoRecord), paused: true), RuleLevel.askFirst);
    expect(shownLevel(_p('A', RuleLevel.autoRecord), paused: false), RuleLevel.autoRecord);
    expect(shownLevel(_p('S', RuleLevel.suggested), paused: true), RuleLevel.suggested);
  });

  test('detail line: kind, masked number (Send Money only), categories or no history', () {
    expect(levelRowDetail(_p('T', RuleLevel.suggested, cats: ['Food', 'Fuel'])), 'Send Money · 0722***555 · Food, Fuel');
    expect(levelRowDetail(_p('A', RuleLevel.suggested, type: ReceiverType.pochi, key: 'AMINA')), 'Pochi · No history yet');
  });

  test('sections: riskiest first, Suggested folded at start, people by name', () {
    expect(kLevelGroupOrder, [RuleLevel.autoRecord, RuleLevel.askFirst, RuleLevel.suggested]);
    expect(kLevelGroupsFoldedAtStart, {RuleLevel.suggested});
    final all = [_p('zed', RuleLevel.askFirst), _p('Amy', RuleLevel.askFirst), _p('Bo', RuleLevel.suggested)];
    expect(peopleAt(all, RuleLevel.askFirst).map((x) => x.name), ['Amy', 'zed']);
    expect(peopleAt(all, RuleLevel.autoRecord), isEmpty);
  });
}
