// U-PERSON: the person sheet's pure choices (person_sheet_rules.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';
import 'package:mmogo/autoread/ui/levels/person_sheet_rules.dart';

LevelPerson _p({
  ReceiverType type = ReceiverType.sendMoney,
  RuleLevel level = RuleLevel.suggested,
  int? cat,
  List<int> top = const [],
}) => LevelPerson(type: type, key: 'k', name: 'Bob', level: level, categoryId: cat, topIds: top);

void main() {
  test('start level: as stored, except a Paybill at Auto-record opens on Ask first', () {
    for (final l in RuleLevel.values) {
      expect(personSheetStartLevel(_p(level: l)), l);
      expect(personSheetStartLevel(_p(type: ReceiverType.buyGoods, level: l)), l);
    }
    expect(personSheetStartLevel(_p(type: ReceiverType.payBill, level: RuleLevel.autoRecord)), RuleLevel.askFirst);
  });

  test('start category: the rule\'s, else the most used (pre-filled), else none', () {
    expect(personSheetStartCategory(_p(cat: 4, top: [1])), (id: 4, fromHistory: false));
    expect(personSheetStartCategory(_p(top: [1, 2])), (id: 1, fromHistory: true));
    expect(personSheetStartCategory(_p()), (id: null, fromHistory: false));
  });

  test('fit to the person\'s group: kept when offered, else the first offered most-used one, else none', () {
    final x = _p(cat: 9, top: [7, 2]);
    expect(personSheetFitCategory(x, (id: 9, fromHistory: false), {9, 2}), (id: 9, fromHistory: false));
    expect(personSheetFitCategory(x, (id: 9, fromHistory: false), {2}), (id: 2, fromHistory: true));
    expect(personSheetFitCategory(x, (id: 9, fromHistory: false), {5}), (id: null, fromHistory: false));
  });

  test('category hint: most used / none / waiting / need', () {
    expect(personSheetCategoryHint(hasCategory: true, fromHistory: true, name: 'Bob'), kHardCategoryMostUsed);
    expect(personSheetCategoryHint(hasCategory: true, fromHistory: false, name: 'Bob'), isNull);
    expect(
      personSheetCategoryHint(hasCategory: false, fromHistory: false, name: 'Bob', paymentCount: 1),
      hardCategoryWaiting('Bob'),
    );
    expect(
      personSheetCategoryHint(hasCategory: false, fromHistory: false, name: 'Bob', paymentCount: 2),
      kHardCategoryNeed,
    );
    expect(personSheetCategoryHint(hasCategory: false, fromHistory: false, name: 'Bob'), kHardCategoryNeed);
  });

  test('the How box per level; Suggested uses no "How Suggest works" text (plan section 11)', () {
    expect(personSheetHowTitle(RuleLevel.suggested), kHardSuggestHowTitle);
    expect(personSheetHowTitle(RuleLevel.askFirst), kHardAskHowTitle);
    expect(personSheetHowTitle(RuleLevel.autoRecord), kHardAutoHowTitle);
    expect(personSheetHowText(RuleLevel.suggested, 'Bob', 'Food'), hardSheetNoteSuggested('Bob'));
    expect(personSheetHowText(RuleLevel.suggested, 'Bob', null), isNot(hardSuggestHowLast10('Bob')));
    expect(personSheetHowText(RuleLevel.askFirst, 'Bob', 'Food'), hardAskHow('Bob', 'Food'));
    expect(personSheetHowText(RuleLevel.askFirst, 'Bob', null), hardAskHow('Bob', kPersonSheetNoCategoryMark));
    expect(personSheetHowText(RuleLevel.autoRecord, 'Bob', 'Food'), hardAutoHow('Bob', 'Food'));
  });

  test('level button words', () {
    expect(personSheetLevelButton(RuleLevel.suggested), kHardLevelSuggestButton);
    expect(personSheetLevelButton(RuleLevel.askFirst), kHardLevelAskFirst);
    expect(personSheetLevelButton(RuleLevel.autoRecord), kHardLevelAutoRecord);
  });

  test('one height share for every level, below full screen', () {
    expect(kPersonSheetHeightFactor, greaterThan(0.5));
    expect(kPersonSheetHeightFactor, lessThan(1));
  });
}
