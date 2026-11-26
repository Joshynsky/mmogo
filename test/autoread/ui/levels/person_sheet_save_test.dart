// U-PERSON (0.2.2 item 2 redesign): the person sheet's ONE save (saveLevelChoice) and its call into the pill.
// - Suggested keeps the stored chosen Suggest list (plan 9b: it was wiped on every save) and the category.
// - Ask first / Auto-record keep the category and the limit.
// - CALL-SITE: what reaches the pill (RuleChangeNotice.show) is the plain name with no masked number and no
//   digits, plus the category name (FakeCategoryRuleChangeNotice, redesign_fakes.dart).
// - openLevelSheetFor: the chips picker and the "{k} payments" count from the Set up source reach the sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/category_chips_picker.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet_open.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

import '../../../support/hard_rule_fakes.dart';
import '../../../support/redesign_fakes.dart';

/// Numeric ids (the shared FakeCategoryChoices uses 'c1', which no rule can hold).
class _Cats implements CategoryChoices {
  _Cats({this.fail = false});
  final bool fail;
  @override
  Future<List<CategoryChoice>> categories() async {
    if (fail) throw StateError('categories');
    return const [
      CategoryChoice(id: '1', name: 'Family & friends'),
      CategoryChoice(id: '2', name: 'Food'),
      CategoryChoice(id: '3', name: 'Bills'),
    ];
  }

  @override
  Future<CategoryChoice> create(String name) => throw UnimplementedError();
}

const _timKey = '0722000555';
const _tim = LevelPerson(type: ReceiverType.sendMoney, key: _timKey, name: 'Tim Otieno', level: RuleLevel.suggested);

LevelsDeps _deps(
  FakeRuleStore store,
  FakeCategoryRuleChangeNotice notice, {
  SetupRecipientsSource? setup,
  PickCategories? pick,
  bool catsFail = false,
}) => LevelsDeps(
  store: store,
  history: FakeHistoryReader(),
  categories: _Cats(fail: catsFail),
  suggest: FakeSuggestSettings(),
  now: () => kHardTestNow,
  notice: notice,
  setup: setup,
  pickCategories: pick,
);

ReceiverRule _rule(RuleLevel level, {int? cat, int? ceiling, List<int> chosen = const []}) => ReceiverRule(
  type: ReceiverType.sendMoney,
  key: _timKey,
  name: 'Tim Otieno',
  level: level,
  categoryId: cat,
  ceilingCents: ceiling,
  chosenCategoryIds: chosen,
  created: kHardTestNow,
  changed: kHardTestNow,
);

/// Nothing a person could read as a phone number: no digit at all, no mask stars.
void _expectNoNumber(String s) {
  expect(s, isNot(contains('***')));
  expect(s, isNot(contains(_timKey)));
  expect(RegExp(r'\d').hasMatch(s), isFalse, reason: s);
}

void main() {
  group('Suggested keeps the rule', () {
    test('a stored chosen Suggest list and category survive a save at Suggested (plan 9b)', () async {
      final store = FakeRuleStore();
      await store.saveRule(_rule(RuleLevel.suggested, cat: 2, chosen: const [3, 1]));
      final notice = FakeCategoryRuleChangeNotice();
      final r = await saveLevelChoice(_deps(store, notice), _tim, RuleLevel.suggested, null, null, notify: true);
      expect(r, LevelSaveResult.ok);
      final after = await store.get(ReceiverType.sendMoney, _timKey);
      expect(after!.level, RuleLevel.suggested);
      expect(after.chosenCategoryIds, [3, 1]);
      expect(after.categoryId, 2);
      expect(notice.calls.single.level, RuleLevel.suggested);
      expect(notice.calls.single.categoryName, isNull);
    });

    test('Ask first to Suggested: back at Suggested, the category kept, the list stays empty', () async {
      final store = FakeRuleStore();
      await store.saveRule(_rule(RuleLevel.askFirst, cat: 1));
      await saveLevelChoice(
        _deps(store, FakeCategoryRuleChangeNotice()),
        _tim,
        RuleLevel.suggested,
        null,
        null,
        notify: false,
      );
      final after = await store.get(ReceiverType.sendMoney, _timKey);
      expect(after!.level, RuleLevel.suggested);
      expect(after.categoryId, 1);
      expect(after.chosenCategoryIds, isEmpty);
    });

    test('nobody without a rule gets one for Suggested; no notice', () async {
      final store = FakeRuleStore();
      final notice = FakeCategoryRuleChangeNotice();
      await saveLevelChoice(_deps(store, notice), _tim, RuleLevel.suggested, null, null, notify: true);
      expect(await store.get(ReceiverType.sendMoney, _timKey), isNull);
      expect(notice.calls, isEmpty);
    });
  });

  group('category and limit kept', () {
    test('Auto-record stores the category and the limit', () async {
      final store = FakeRuleStore();
      await saveLevelChoice(
        _deps(store, FakeCategoryRuleChangeNotice()),
        _tim,
        RuleLevel.autoRecord,
        2,
        150000,
        notify: false,
      );
      final after = await store.get(ReceiverType.sendMoney, _timKey);
      expect(after!.level, RuleLevel.autoRecord);
      expect(after.categoryId, 2);
      expect(after.ceilingCents, 150000);
    });

    test('Ask first with no category passed keeps the stored one and drops the limit', () async {
      final store = FakeRuleStore();
      await store.saveRule(_rule(RuleLevel.autoRecord, cat: 3, ceiling: 50000));
      await saveLevelChoice(
        _deps(store, FakeCategoryRuleChangeNotice()),
        _tim,
        RuleLevel.askFirst,
        null,
        70000,
        notify: false,
      );
      final after = await store.get(ReceiverType.sendMoney, _timKey);
      expect(after!.level, RuleLevel.askFirst);
      expect(after.categoryId, 3);
      expect(after.ceilingCents, isNull);
    });
  });

  group('CALL-SITE: what reaches the pill', () {
    for (final level in RuleLevel.values) {
      test('${level.name}: plain name, no masked number, no digits; the category name when there is one', () async {
        final store = FakeRuleStore();
        await store.saveRule(_rule(RuleLevel.askFirst, cat: 1)); // so Suggested stores a change too
        final notice = FakeCategoryRuleChangeNotice();
        var opened = 0;
        await saveLevelChoice(
          _deps(store, notice),
          _tim,
          level,
          2,
          level == RuleLevel.autoRecord ? 150000 : null,
          notify: true,
          onChangeCeiling: () => opened++,
        );
        final c = notice.calls.single;
        expect(c.name, 'Tim Otieno');
        _expectNoNumber(c.name);
        expect(c.level, level);
        switch (level) {
          case RuleLevel.suggested:
            expect(c.categoryName, isNull);
            expect(c.onChangeCeiling, isNull);
          case RuleLevel.askFirst:
            expect(c.categoryName, 'Food');
            expect(c.onChangeCeiling, isNull);
          case RuleLevel.autoRecord:
            expect(c.categoryName, 'Food');
            expect(c.ceilingCents, 150000);
            c.onChangeCeiling!();
            expect(opened, 1);
        }
        _expectNoNumber(c.categoryName ?? '');
      });
    }

    test('a name stored with spaces around it reaches the pill trimmed', () async {
      final notice = FakeCategoryRuleChangeNotice();
      const padded = LevelPerson(
        type: ReceiverType.sendMoney,
        key: _timKey,
        name: '  Tim Otieno ',
        level: RuleLevel.suggested,
      );
      await saveLevelChoice(_deps(FakeRuleStore(), notice), padded, RuleLevel.askFirst, 1, null, notify: true);
      expect(notice.calls.single.name, 'Tim Otieno');
    });

    test('the category list cannot be read: the save stands and the pill still shows, with no category', () async {
      final store = FakeRuleStore();
      final notice = FakeCategoryRuleChangeNotice();
      final r = await saveLevelChoice(
        _deps(store, notice, catsFail: true),
        _tim,
        RuleLevel.askFirst,
        1,
        null,
        notify: true,
      );
      expect(r, LevelSaveResult.ok);
      expect((await store.get(ReceiverType.sendMoney, _timKey))!.level, RuleLevel.askFirst);
      expect(notice.calls.single.categoryName, isNull);
      expect(notice.calls.single.name, 'Tim Otieno');
    });

    test('a refused write: no pill', () async {
      final store = FakeRuleStore()..refuseWrites = true;
      final notice = FakeCategoryRuleChangeNotice();
      final r = await saveLevelChoice(_deps(store, notice), _tim, RuleLevel.askFirst, 1, null, notify: true);
      expect(r, LevelSaveResult.capReached);
      expect(notice.calls, isEmpty);
    });

    test('levelNoticeName never carries the mask that levelWho adds', () {
      expect(levelWho(_tim), contains('***'));
      expect(levelNoticeName(_tim), 'Tim Otieno');
    });
  });

  group('openLevelSheetFor (the 0.2.2 sheet)', () {
    setUp(() => debugAutoRecordUiOverride = true);
    tearDown(() => debugAutoRecordUiOverride = null);

    Future<void> openFor(WidgetTester t, LevelsDeps d, {int? count}) async {
      t.view.physicalSize = const Size(390, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        AppPaletteScope(
          controller: AppPaletteController('ocean', 'light'),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  key: const Key('open'),
                  onPressed: () =>
                      openLevelSheetFor(c, d, ReceiverType.sendMoney, _timKey, 'Tim Otieno', paymentCount: count),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('open')));
      await t.pumpAndSettle();
    }

    testWidgets('the count comes from the Set up source; the picker choice is saved and named on the pill', (t) async {
      final store = FakeRuleStore();
      final notice = FakeCategoryRuleChangeNotice();
      final picker = FakeCategoryPicker(answer: [3]);
      final setup = FakeSetupRecipientsSource([setupTestRecipient(_timKey, name: 'Tim Otieno', paymentCount: 12)]);
      await openFor(t, _deps(store, notice, setup: setup, pick: picker.pick));
      expect(find.text(hardPaymentsCount(12)), findsOneWidget);
      await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('personChooseCategory')));
      await t.pumpAndSettle();
      expect(picker.calls.single.mode, CategoryPickMode.one);
      expect(picker.calls.single.name, 'Tim Otieno'); // I2: the person's plain name goes to the picker title
      await t.tap(find.byKey(const Key('levelSheetSave')));
      await t.pumpAndSettle();
      final after = await store.get(ReceiverType.sendMoney, _timKey);
      expect(after!.level, RuleLevel.askFirst);
      expect(after.categoryId, 3);
      expect(notice.calls.single.categoryName, 'Bills');
      expect(notice.calls.single.name, 'Tim Otieno');
    });

    testWidgets('I2: the real chips picker (the installed port) titles itself with the person name', (t) async {
      await openFor(t, _deps(FakeRuleStore(), FakeCategoryRuleChangeNotice(), pick: showCategoryChipsPicker));
      await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('personChooseCategory')));
      await t.pumpAndSettle();
      expect(find.text(hardPickerTitleOne('Tim Otieno')), findsOneWidget);
    });

    testWidgets('a given count wins over the Set up source; a failing source shows no count', (t) async {
      final setup = FakeSetupRecipientsSource([setupTestRecipient(_timKey, paymentCount: 12)]);
      await openFor(t, _deps(FakeRuleStore(), FakeCategoryRuleChangeNotice(), setup: setup), count: 4);
      expect(find.text(hardPaymentsCount(4)), findsOneWidget);
      Navigator.of(t.element(find.byKey(const Key('levelSheetTitle')))).pop();
      await t.pumpAndSettle();
      setup.fail = true;
      await openFor(t, _deps(FakeRuleStore(), FakeCategoryRuleChangeNotice(), setup: setup));
      expect(find.byKey(const Key('personCount')), findsNothing);
      expect(find.byKey(const Key('levelSheetTitle')), findsOneWidget);
    });
  });
}
