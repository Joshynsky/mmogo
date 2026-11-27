// Widget tests for the Remembered page's second tab (Suggest and auto-record),
// on the S0 fakes. Invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart' show debugAutoRecordUiOverride;
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/autoread/ui/auto_record_copy.dart' show kAutoRecordExplainLater, kAutoRecordExplainUndo;
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/levels_help.dart';
import 'package:mmogo/autoread/ui/levels/levels_tab.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

class _Cats implements CategoryChoices {
  @override
  Future<List<CategoryChoice>> categories() async => const [
    CategoryChoice(id: '1', name: 'Family'),
    CategoryChoice(id: '2', name: 'Food'),
    CategoryChoice(id: '3', name: 'Fuel'),
  ];
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

final _at = DateTime(2026, 11, 19, 9);

class _Rig {
  final store = FakeRuleStore();
  final history = FakeHistoryReader(
    history: {
      'SM.0711': [2, 3],
      'SM.0722': [1],
    },
  );
  final airtime = AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});
  List<KnownPerson> known = const [
    KnownPerson(type: ReceiverType.sendMoney, key: '0711', name: 'Tim'),
    KnownPerson(type: ReceiverType.sendMoney, key: '0722', name: 'Grace'),
    KnownPerson(type: ReceiverType.pochi, key: 'Amina', name: 'Amina'),
  ];
  LevelsDeps get deps =>
      LevelsDeps(store: store, history: history, categories: _Cats(), suggest: _Port(), known: () async => known, now: () => _at);
}

Future<void> _pump(WidgetTester t, _Rig r, {double scale = 1, double width = 390, LevelsDeps? deps, bool noDeps = false}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: LevelsTab(controller: r.airtime, deps: noDeps ? null : (deps ?? r.deps)),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

double _y(WidgetTester t, String key) => t.getTopLeft(find.byKey(Key(key))).dy;

/// Opens the closed Suggested group (closed at start).
Future<void> _openSuggested(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('levelGroupToggle.suggested')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('levelGroupToggle.suggested')));
  await t.pumpAndSettle();
}

// 0.2.2 U5 (PM D3): layout A replaced the 0.2.1 level filter and type chips. The filter and chip tests
// were rewritten on purpose for the sections, the fold and the search; the flag-off (0.2.1) promises stay.
// 0.2.2 item 2 redesign (U-PAGE): the group and search tests were rewritten on purpose again (folded groups,
// one open, no search on the page).
void main() {
  // The Auto-record screens are live since the 0.2.2 flip; these tests cover the Ask first / Suggested screens.
  setUp(() => debugAutoRecordUiOverride = false);
  tearDown(() => debugAutoRecordUiOverride = null);

  testWidgets('empty: no people yet shows the empty line, airtime switches still there', (t) async {
    final r = _Rig()..known = const [];
    await _pump(t, r);
    expect(find.text(kLevelsEmpty), findsOneWidget);
    expect(find.byKey(const Key('levelsSearch')), findsNothing);
    expect(find.byKey(const Key('autoRecordMyself')), findsOneWidget); // no type chips: the switches sit under the list
  });

  // 0.2.2 item 2 redesign (U-PAGE): rewritten on purpose. Groups Suggested, Ask first, Auto-record with
  // one open (Ask first here: nobody is on Auto-record); rows say what mmogo does.
  testWidgets('groups: Suggested above Ask first; Ask first open (no Auto-record people), Suggested closed; by name', (t) async {
    final r = _Rig();
    await r.store.setLevel(ReceiverType.sendMoney, '0722', name: 'Grace', level: RuleLevel.askFirst, categoryId: 2, at: _at);
    await _pump(t, r);
    expect(_y(t, 'levelGroup.suggested'), lessThan(_y(t, 'levelGroup.askFirst')));
    expect(find.byKey(const Key('levelRow.SM.0722')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.SM.0711')), findsNothing); // closed
    expect(find.text(hardRowAsks('Food')), findsOneWidget); // Grace's rule category
    await _openSuggested(t);
    expect(find.byKey(const Key('levelRow.SM.0722')), findsNothing); // opening one closes the other
    expect(_y(t, 'levelRow.PO.Amina'), lessThan(_y(t, 'levelRow.SM.0711'))); // by name: Amina, Tim
    expect(find.text(kHardSuggestsFromLast10), findsNWidgets(2)); // Tim and Amina, no chosen list
    expect(find.text('Pochi'), findsOneWidget); // Amina's identity line: the type only
  });

  testWidgets('no search on the page (search lives in the Set up sheet)', (t) async {
    final r = _Rig();
    await r.store.setLevel(ReceiverType.sendMoney, '0722', name: 'Grace', level: RuleLevel.askFirst, categoryId: 2, at: _at);
    await _pump(t, r);
    expect(find.byKey(const Key('levelsSearch')), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('D3: no level filter and no type chips; every kind in one list', (t) async {
    await _pump(t, _Rig());
    for (final k in ['levelFilterall', 'levelFilteraskFirst', 'typeChipSM', 'typeChipP', 'typeChipW', 'typeChipAirtime']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
    await _openSuggested(t);
    expect(find.byKey(const Key('levelRow.SM.0711')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.PO.Amina')), findsOneWidget);
  });

  testWidgets('Airtime: its heading and the two switches under the people; no rule paragraphs', (t) async {
    await _pump(t, _Rig());
    await t.ensureVisible(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelsAirtimeHeader')), findsOneWidget);
    expect(find.byKey(const Key('autoRecordMyself')), findsOneWidget);
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(find.textContaining('You tap Parse on each message'), findsNothing);
    expect(find.text(kAutoRecordExplainUndo), findsNothing);
    expect(find.text(kAutoRecordExplainLater), findsNothing);
  });

  testWidgets('Pochi shows only remembered names, even when a rule exists', (t) async {
    final r = _Rig();
    await r.store.setLevel(ReceiverType.pochi, 'Zed', name: 'Zed', level: RuleLevel.askFirst, categoryId: 1, at: _at);
    await _pump(t, r);
    await _openSuggested(t);
    expect(find.byKey(const Key('levelRow.PO.Amina')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.PO.Zed')), findsNothing);
  });

  testWidgets('level sheet: Suggested to Ask first needs a category, saves a rule', (t) async {
    final r = _Rig();
    await _pump(t, r);
    await _openSuggested(t);
    await t.tap(find.byKey(const Key('levelButton.SM.0711')));
    await t.pumpAndSettle();
    expect(find.text(levelSheetTitle('Tim ***')), findsOneWidget);
    expect(find.byKey(const Key('levelChoiceautoRecord')), findsNothing); // two levels only
    await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
    await t.pumpAndSettle();
    // Tim's most-used category is preselected: save works at once.
    expect(t.widget<FilledButton>(find.byKey(const Key('levelSheetSave'))).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('levelCategoryRow')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelCat.1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    final rule = await r.store.get(ReceiverType.sendMoney, '0711');
    expect(rule!.level, RuleLevel.askFirst);
    expect(rule.categoryId, 1);
    expect(rule.name, 'Tim');
    expect(find.text(levelSheetTitle('Tim ***')), findsNothing);
    // The row moved to the Ask first group (closed while Suggested is open; opening it shows Tim).
    expect(find.byKey(const Key('levelRow.SM.0711')), findsNothing);
    await t.tap(find.byKey(const Key('levelGroupToggle.askFirst')));
    await t.pumpAndSettle();
    expect(find.text(kLevelAskFirst), findsWidgets);
    expect(find.byKey(const Key('levelRow.SM.0711')), findsOneWidget);
  });

  testWidgets('level sheet: no category chosen blocks Save; Suggested now KEEPS the rule (PM 25-11)', (t) async {
    final r = _Rig();
    await _pump(t, r);
    await _openSuggested(t);
    await t.tap(find.byKey(const Key('levelButton.PO.Amina'))); // no history
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byKey(const Key('levelSheetSave'))).onPressed, isNull);
    expect(find.text(kLevelSheetPickCategory), findsOneWidget);
    await t.tap(find.byKey(const Key('levelSheetCancel')));
    await t.pumpAndSettle();
    expect(await r.store.all(), isEmpty);
    // Existing rule: choosing Suggested and Save keeps the rule at Suggested (0.2.1 removed it).
    await r.store.setLevel(ReceiverType.sendMoney, '0711', name: 'Tim', level: RuleLevel.askFirst, categoryId: 2, at: _at);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelGroupToggle.askFirst'))); // Tim is in the Ask first group now
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelButton.SM.0711')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoicesuggested')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    final kept = await r.store.get(ReceiverType.sendMoney, '0711');
    expect(kept, isNotNull);
    expect(kept!.level, RuleLevel.suggested);
    expect(kept.categoryId, 2);
  });

  testWidgets('level sheet: the 300 cap shows a message and keeps the sheet', (t) async {
    final r = _Rig();
    for (var i = 0; i < kRuleCapForTest; i++) {
      await r.store.setLevel(ReceiverType.buyGoods, 'S$i', name: 'S$i', level: RuleLevel.askFirst, categoryId: 1, at: _at);
    }
    await _pump(t, r);
    await _openSuggested(t); // the long Ask first list closes
    await t.tap(find.byKey(const Key('levelButton.SM.0711')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    expect(find.text(kLevelSheetCapReached), findsOneWidget);
  });

  testWidgets('the tab has no question mark of its own; its help text holds levels and the airtime rules', (t) async {
    await _pump(t, _Rig());
    expect(find.byKey(const Key('levelsHelpButton')), findsNothing);
    expect(find.text('?'), findsNothing);
    final h = levelsHelp();
    expect(h.title, kLevelsHelpTitle);
    final all = h.paragraphs.join('\n');
    expect(all, contains('Suggested'));
    expect(all, contains('Ask first'));
    for (final head in ['Send Money', 'Paybill', 'Buy Goods', 'Pochi', 'Withdrawals', 'Airtime']) {
      expect(h.paragraphs, contains(head));
    }
    expect(all, contains(kLevelsHelpAirtimeTap));
    expect(all, contains(kAutoRecordExplainUndo));
    expect(all, contains(kAutoRecordExplainLater));
  });

  testWidgets('no Auto-record level, tag or confirm anywhere while the flag is off', (t) async {
    final r = _Rig();
    await r.store.setLevel(ReceiverType.payBill, '888', name: 'Power', level: RuleLevel.askFirst, categoryId: 1, at: _at);
    await _pump(t, r);
    await _openSuggested(t);
    expect(find.textContaining('Auto-record'), findsNothing);
    expect(find.text(kLevelsHelper), findsOneWidget); // the 0.2.1 helper, not the Auto-record one
    await t.tap(find.byKey(const Key('levelButton.SM.0711')));
    await t.pumpAndSettle();
    expect(find.textContaining('Auto-record'), findsNothing);
  });

  testWidgets('no deps (standard wiring gap): only the airtime switches', (t) async {
    await _pump(t, _Rig(), noDeps: true);
    expect(find.byKey(const Key('autoRecordMyself')), findsOneWidget);
    expect(find.byKey(const Key('levelsSearch')), findsNothing);
  });

  for (final c in [(1.3, 390.0), (2.0, 390.0), (1.3, 500.0)]) {
    testWidgets('large text ${c.$1} at ${c.$2.toInt()} px wide: no overflow, rows and sheet fit', (t) async {
      final r = _Rig();
      await r.store.setLevel(
        ReceiverType.sendMoney,
        '0722',
        name: 'Grace Wanjiru Long Name Here',
        level: RuleLevel.askFirst,
        categoryId: 2,
        at: _at,
      );
      await _pump(t, r, scale: c.$1, width: c.$2);
      expect(t.takeException(), isNull);
      await _openSuggested(t);
      await t.ensureVisible(find.byKey(const Key('levelButton.SM.0711')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('levelButton.SM.0711')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}

const int kRuleCapForTest = 300;
