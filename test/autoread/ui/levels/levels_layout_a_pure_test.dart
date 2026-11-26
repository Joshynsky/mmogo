// 0.2.2 U5: the pure parts of the page (search match, row lines, group order); the row and group parts
// rewritten on purpose for the item 2 redesign (U-PAGE). Invented names only.
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

  // 0.2.2 item 2 redesign (U-PAGE): rewritten on purpose. Rows say what mmogo does (mock rows), the
  // identity line is the masked number then the type, the groups are Suggested, Ask first, Auto-record with
  // ONE open (Auto-record at start).
  test('row line: Suggests (chosen) / last 10, Asks, Records up to / never asks first, paused', () {
    expect(levelRowLine(_p('S', RuleLevel.suggested), paused: false), kHardSuggestsFromLast10);
    final chosen = _p('S', RuleLevel.suggested).withChosenFrom(
        hardTestRuleChosen([7, 4]), const {4: 'Bills', 7: 'Family'});
    expect(chosen.chosenCategoryIds, [7, 4]);
    expect(levelRowLine(chosen, paused: false), kHardSuggestsFromLast10); // I2: 0.2.2 always; the chosen line is 0.2.3
    expect(levelRowLine(_p('G', RuleLevel.askFirst, cats: ['Food']), paused: false), hardRowAsks('Food'));
    expect(levelRowLine(_p('G', RuleLevel.askFirst, cats: ['Food']), paused: true), hardRowAsks('Food')); // only Auto-record pauses
    expect(levelRowLine(_p('A', RuleLevel.autoRecord, ceiling: 200000, cats: ['Rent']), paused: false),
        hardRowRecordsUpTo('Rent', 200000));
    expect(levelRowLine(_p('A', RuleLevel.autoRecord, cats: ['Rent']), paused: false), hardRowRecordsNoLimit('Rent'));
    expect(levelRowLine(_p('A', RuleLevel.autoRecord, ceiling: 5, cats: ['Rent']), paused: true), kHardRowPaused);
    expect(levelRowLine(_p('A', RuleLevel.autoRecord), paused: false), kHardNoCategoryYet); // a deleted category
  });

  test('chosen list: kept only at Suggested; a deleted category is left out of the names', () {
    final ask = _p('G', RuleLevel.askFirst).withChosenFrom(hardTestRuleChosen([7]), const {7: 'Family'});
    expect(ask.chosenCategoryIds, isEmpty);
    final gone = _p('S', RuleLevel.suggested).withChosenFrom(hardTestRuleChosen([7, 9]), const {7: 'Family'});
    expect(gone.chosenCategoryIds, [7, 9]);
    expect(gone.chosenCategoryNames, ['Family']);
    expect(_p('S', RuleLevel.suggested).withChosenFrom(null, const {}).chosenCategoryIds, isEmpty);
  });

  test('spoken: a paused Auto-record row says Auto-record and paused, never "Ask first"', () {
    final tim = _p('Tim', RuleLevel.autoRecord, ceiling: 200000, cats: ['Rent']);
    final paused = levelRowSpoken(tim, paused: true);
    expect(paused, contains(kHardLevelAutoRecord));
    expect(paused, contains(kHardRowPaused));
    expect(paused, isNot(contains(kHardLevelAskFirst)));
    expect(paused, contains('number ending 555'));
    expect(paused, isNot(contains('123'))); // hidden digits never spoken
    expect(levelRowSpoken(tim, paused: false), contains(hardRowRecordsUpTo('Rent', 200000)));
  });

  test('identity line: masked number (Send Money only), then the type', () {
    expect(levelRowDetail(_p('T', RuleLevel.suggested, cats: ['Food', 'Fuel'])), '0722***555 · Send Money');
    expect(levelRowDetail(_p('A', RuleLevel.suggested, type: ReceiverType.pochi, key: 'AMINA')), 'Pochi');
  });

  test('groups: Suggested, Ask first, Auto-record; Auto-record open at start, else Ask first; one open at a time', () {
    expect(kLevelGroupOrder, [RuleLevel.suggested, RuleLevel.askFirst, RuleLevel.autoRecord]);
    final all = [_p('zed', RuleLevel.askFirst), _p('Amy', RuleLevel.askFirst), _p('Bo', RuleLevel.suggested)];
    expect(peopleAt(all, RuleLevel.askFirst).map((x) => x.name), ['Amy', 'zed']);
    expect(peopleAt(all, RuleLevel.autoRecord), isEmpty);
    expect(initialOpenGroup([...all, _p('Al', RuleLevel.autoRecord)]), RuleLevel.autoRecord);
    expect(initialOpenGroup(all), RuleLevel.askFirst);
    expect(initialOpenGroup([_p('Bo', RuleLevel.suggested)]), isNull); // Suggested never opens by itself
    expect(toggledGroup(RuleLevel.autoRecord, RuleLevel.askFirst), RuleLevel.askFirst); // opening one closes the other
    expect(toggledGroup(RuleLevel.askFirst, RuleLevel.askFirst), isNull);
    expect(toggledGroup(null, RuleLevel.suggested), RuleLevel.suggested);
  });
}

ReceiverRule hardTestRuleChosen(List<int> ids) => ReceiverRule(
    type: ReceiverType.sendMoney,
    key: '0722123555',
    name: 'S',
    level: RuleLevel.suggested,
    chosenCategoryIds: ids,
    created: DateTime(2026, 11, 25),
    changed: DateTime(2026, 11, 25));
