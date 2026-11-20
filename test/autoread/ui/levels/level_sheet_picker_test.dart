// The level sheet's category picker: only the person's own group, pre-selected,
// Save off until a category is chosen, Save and Cancel pinned under a long list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart' show kLevelSheetNoneChosen;
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';
import 'package:mmogo/autoread/ui/levels/levels_tab.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

class _Cats implements CategoryChoices {
  _Cats(this.list);
  final List<CategoryChoice> list;
  @override
  Future<List<CategoryChoice>> categories() async => list;
  @override
  Future<CategoryChoice> create(String name) => throw UnimplementedError();
}

class _Port implements SuggestSettingsPort {
  @override
  Future<bool> enabled() async => true;
  @override
  Future<int> after() async => 3;
  @override
  Future<bool> setEnabled(bool on) async => true;
  @override
  Future<bool> setAfter(int n) async => true;
}

Future<void> _show(WidgetTester t, LevelPerson p, CategoryChoices cats, {double height = 700, Future<LevelSaveResult> Function(RuleLevel, int?)? onSave}) async {
  t.view.physicalSize = Size(390, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', 'light'),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            key: const Key('open'),
            onPressed: () => showLevelSheet(c, person: p, categories: cats, onSave: onSave ?? (_, _) async => LevelSaveResult.ok),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
  await t.pumpAndSettle();
}

bool _on(WidgetTester t, String key) => t.widget<FilledButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  const tim = LevelPerson(type: ReceiverType.sendMoney, key: '0711', name: 'Tim', level: RuleLevel.suggested, topIds: [2, 1]);

  testWidgets('level sheet is short and shows the current category on its row; Save is on', (t) async {
    final many = [for (var i = 1; i <= 60; i++) CategoryChoice(id: '$i', name: 'Category number $i')];
    await _show(t, tim, _Cats(many), height: 800);
    expect(find.text('Category number 2'), findsOneWidget); // most-used, shown on the row
    expect(find.byKey(const Key('levelCat.1')), findsNothing); // the list is not in this sheet
    expect(_on(t, 'levelSheetSave'), isTrue);
    final sheet = t.getRect(find.byKey(const Key('levelSheetTitle')));
    expect(800 - sheet.top, lessThan(800 * 0.6)); // never grows to full height
    expect(t.getRect(find.byKey(const Key('levelSheetSave'))).bottom, lessThanOrEqualTo(800));
  });

  testWidgets('category sheet: opens on the row, current one marked, a tap chooses and closes it', (t) async {
    await _show(t, tim, _Cats(const [CategoryChoice(id: '1', name: 'Family'), CategoryChoice(id: '2', name: 'Food')]));
    await t.tap(find.byKey(const Key('levelCategoryRow')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('categoryPickTitle')), findsOneWidget);
    final sem = t.ensureSemantics();
    expect(t.getSemantics(find.byKey(const Key('levelCat.2'))).flagsCollection.isSelected.name, 'isTrue');
    expect(t.getSemantics(find.byKey(const Key('levelCat.1'))).flagsCollection.isSelected.name, isNot('isTrue'));
    sem.dispose();
    await t.tap(find.byKey(const Key('levelCat.1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('categoryPickTitle')), findsNothing);
    expect(t.widget<Text>(find.byKey(const Key('levelCategoryValue'))).data, 'Family');
  });

  testWidgets('a rule category from another group is not offered and not kept; Save waits for a choice', (t) async {
    const grace = LevelPerson(type: ReceiverType.sendMoney, key: '0722', name: 'Grace', level: RuleLevel.askFirst, categoryId: 99);
    await _show(t, grace, _Cats(const [CategoryChoice(id: '1', name: 'Family'), CategoryChoice(id: '2', name: 'Food')]));
    expect(_on(t, 'levelSheetSave'), isFalse);
    expect(t.widget<Text>(find.byKey(const Key('levelCategoryValue'))).data, kLevelSheetNoneChosen);
    await t.tap(find.byKey(const Key('levelCategoryRow')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelCat.99')), findsNothing);
    expect(find.byKey(const Key('levelCat.1')), findsOneWidget);
    await t.tap(find.byKey(const Key('levelCat.1')));
    await t.pumpAndSettle();
    expect(_on(t, 'levelSheetSave'), isTrue);
  });

  testWidgets('no history and no rule: nothing chosen, Save off', (t) async {
    const amina = LevelPerson(type: ReceiverType.pochi, key: 'Amina', name: 'Amina', level: RuleLevel.suggested);
    await _show(t, amina, _Cats(const [CategoryChoice(id: '5', name: 'Gifts')]));
    expect(_on(t, 'levelSheetSave'), isFalse);
  });

  testWidgets('category sheet: a long list scrolls inside a compact sheet, title pinned; a very long name does not overflow', (t) async {
    final many = [
      const CategoryChoice(id: '1', name: 'Very long category name with symbols %26 %2F %3F %23 %25 and more words that keep going past the edge of the screen again and again'),
      for (var i = 2; i <= 60; i++) CategoryChoice(id: '$i', name: 'Category number $i'),
    ];
    await _show(t, tim, _Cats(many), height: 640);
    await t.tap(find.byKey(const Key('levelCategoryRow')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final title = t.getRect(find.byKey(const Key('categoryPickTitle')));
    expect(640 - title.top, lessThanOrEqualTo(640 * 0.6 + 1));
    await t.drag(find.byKey(const Key('categoryPickList')), const Offset(0, -3000));
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const Key('categoryPickTitle'))), title); // pinned
    expect(find.byKey(const Key('levelCat.60')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a very long chosen name is cut on the level sheet row without overflow', (t) async {
    const longName = 'Very long category name with symbols %26 %2F %3F %23 %25 and more words that keep going past the edge of the screen again and again';
    await _show(t, tim, _Cats(const [CategoryChoice(id: '2', name: longName)]));
    expect(t.takeException(), isNull);
    expect(t.getRect(find.byKey(const Key('levelCategoryRow'))).right, lessThanOrEqualTo(390));
  });

  testWidgets('the tab asks for the categories of the person\'s own group', (t) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final asked = <ReceiverType>[];
    final deps = LevelsDeps(
      store: FakeRuleStore(),
      history: FakeHistoryReader(history: const {}),
      categories: _Cats(const [CategoryChoice(id: '1', name: 'Everything'), CategoryChoice(id: '2', name: 'Everything')]),
      categoriesFor: (type) {
        asked.add(type);
        return _Cats([CategoryChoice(id: '7', name: 'Pochi only')]);
      },
      suggest: _Port(),
      known: () async => const [KnownPerson(type: ReceiverType.pochi, key: 'Amina', name: 'Amina')],
    );
    final c = AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});
    await t.pumpWidget(AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(home: Scaffold(body: LevelsTab(controller: c, deps: deps))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('typeChipP')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelButton.PO.Amina')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelCategoryRow')));
    await t.pumpAndSettle();
    expect(asked, [ReceiverType.pochi]);
    expect(find.text('Pochi only'), findsOneWidget);
    expect(find.text('Everything'), findsNothing);
  });
}
