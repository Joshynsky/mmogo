// Widget tests for the Remembered page's second tab (Suggest and auto-record),
// on the S0 fakes. Invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
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
  final history = FakeHistoryReader(history: {
    'SM.0711': [2, 3],
    'SM.0722': [1],
  });
  final airtime = AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});
  List<KnownPerson> known = const [
    KnownPerson(type: ReceiverType.sendMoney, key: '0711', name: 'Tim'),
    KnownPerson(type: ReceiverType.sendMoney, key: '0722', name: 'Grace'),
    KnownPerson(type: ReceiverType.pochi, key: 'Amina', name: 'Amina'),
  ];
  LevelsDeps get deps => LevelsDeps(
        store: store,
        history: history,
        categories: _Cats(),
        suggest: _Port(),
        known: () async => known,
        now: () => _at,
      );
}

Future<void> _pump(WidgetTester t, _Rig r, {double scale = 1, double width = 390, LevelsDeps? deps, bool noDeps = false}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', 'light'),
    child: MaterialApp(
      home: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: LevelsTab(controller: r.airtime, deps: noDeps ? null : (deps ?? r.deps))),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

double _y(WidgetTester t, String key) => t.getTopLeft(find.byKey(Key(key))).dy;

void main() {
  testWidgets('empty: no people yet shows the empty line, airtime switches still there', (t) async {
    final r = _Rig()..known = const [];
    await _pump(t, r);
    expect(find.text(kLevelsEmpty), findsOneWidget);
    expect(find.byKey(const Key('autoRecordMyself')), findsNothing); // Send Money is open, not Airtime
  });

  testWidgets('list order: Ask first before Suggested, then by name; history names under Suggested', (t) async {
    final r = _Rig();
    await r.store.setLevel(ReceiverType.sendMoney, '0722', name: 'Grace', level: RuleLevel.askFirst, categoryId: 2, at: _at);
    await _pump(t, r);
    expect(_y(t, 'levelRow.SM.0722'), lessThan(_y(t, 'levelRow.SM.0711')));
    expect(find.text('Food'), findsOneWidget); // Grace's rule category
    expect(find.text('Food, Fuel'), findsOneWidget); // Tim: history, most used first
    await t.tap(find.byKey(const Key('typeChipP')));
    await t.pumpAndSettle();
    expect(find.text(kLevelsNoHistory), findsOneWidget); // Amina
  });

  testWidgets('filter: Ask first only, Suggested only, All; empty filter line', (t) async {
    final r = _Rig();
    await r.store.setLevel(ReceiverType.sendMoney, '0722', name: 'Grace', level: RuleLevel.askFirst, categoryId: 2, at: _at);
    await _pump(t, r);
    await t.tap(find.byKey(const Key('levelFilteraskFirst')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.SM.0722')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.SM.0711')), findsNothing);
    await t.tap(find.byKey(const Key('levelFiltersuggested')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.SM.0722')), findsNothing);
    expect(find.byKey(const Key('levelRow.SM.0711')), findsOneWidget);
    await t.tap(find.byKey(const Key('levelFilterall')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.SM.0722')), findsOneWidget);
    // Nobody at Ask first: the filter line.
    await r.store.forget(ReceiverType.sendMoney, '0722');
    await t.tap(find.byKey(const Key('levelFilteraskFirst')));
    await t.pumpAndSettle();
    expect(find.text(kLevelsFilterEmpty), findsOneWidget);
  });

  testWidgets('type chips: money out first, no All chip, readable names, Send Money open by default', (t) async {
    await _pump(t, _Rig());
    final order = ['typeChipSM', 'typeChipPB', 'typeChipBG', 'typeChipP', 'typeChipW', 'typeChipAirtime'];
    final pos = [for (final k in order) t.getTopLeft(find.byKey(Key(k)))];
    for (var i = 1; i < pos.length; i++) {
      final before = pos[i - 1];
      expect(pos[i].dy > before.dy || (pos[i].dy == before.dy && pos[i].dx > before.dx), isTrue, reason: order[i]);
    }
    for (final n in ['Send Money', 'Paybill', 'Buy Goods', 'Pochi', 'Withdrawals', 'Airtime']) {
      expect(find.descendant(of: find.byKey(const Key('levelsTab')), matching: find.text(n)), findsOneWidget, reason: n);
    }
    expect(find.byKey(const Key('typeChipAll')), findsNothing);
    expect(find.text('All'), findsOneWidget); // only the level filter's own All
    expect(find.byKey(const Key('levelRow.SM.0711')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.PO.Amina')), findsNothing);
    expect(find.byKey(const Key('autoRecordMyself')), findsNothing);
  });

  testWidgets('type chips: one type at a time; tapping the open one keeps it open', (t) async {
    await _pump(t, _Rig());
    await t.tap(find.byKey(const Key('typeChipP')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.PO.Amina')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.SM.0711')), findsNothing);
    await t.tap(find.byKey(const Key('typeChipP')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.PO.Amina')), findsOneWidget);
    await t.tap(find.byKey(const Key('typeChipPB')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.PO.Amina')), findsNothing);
    expect(find.text(kLevelsEmpty), findsOneWidget);
  });

  testWidgets('Airtime view: only the two switches, no rule paragraphs, no rows', (t) async {
    await _pump(t, _Rig());
    await t.tap(find.byKey(const Key('typeChipAirtime')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('autoRecordMyself')), findsOneWidget);
    expect(find.byKey(const Key('autoRecordOther')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.SM.0711')), findsNothing);
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(find.textContaining('You tap Parse on each message'), findsNothing);
    expect(find.text(kAutoRecordExplainUndo), findsNothing);
    expect(find.text(kAutoRecordExplainLater), findsNothing);
  });

  testWidgets('withdrawal chip is muted and does nothing', (t) async {
    final sem = t.ensureSemantics();
    final r = _Rig();
    await _pump(t, r);
    await t.tap(find.byKey(const Key('typeChipW')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.SM.0711')), findsOneWidget);
    expect(t.getSemantics(find.byKey(const Key('typeChipW'))).label, 'Withdrawals, coming later');
    sem.dispose();
  });

  testWidgets('Pochi shows only remembered names, even when a rule exists', (t) async {
    final r = _Rig();
    await r.store.setLevel(ReceiverType.pochi, 'Zed', name: 'Zed', level: RuleLevel.askFirst, categoryId: 1, at: _at);
    await _pump(t, r);
    await t.tap(find.byKey(const Key('typeChipP')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.PO.Amina')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.PO.Zed')), findsNothing);
  });

  testWidgets('level sheet: Suggested to Ask first needs a category, saves a rule', (t) async {
    final r = _Rig();
    await _pump(t, r);
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
    // The row now says Ask first and the list re-ordered.
    expect(find.text(kLevelAskFirst), findsWidgets);
  });

  testWidgets('level sheet: no category chosen blocks Save; Suggested forgets the rule', (t) async {
    final r = _Rig();
    await _pump(t, r);
    await t.tap(find.byKey(const Key('typeChipP')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelButton.PO.Amina'))); // no history
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byKey(const Key('levelSheetSave'))).onPressed, isNull);
    expect(find.text(kLevelSheetPickCategory), findsOneWidget);
    await t.tap(find.byKey(const Key('levelSheetCancel')));
    await t.pumpAndSettle();
    expect(await r.store.all(), isEmpty);
    // Existing rule: choosing Suggested and Save removes it.
    await r.store.setLevel(ReceiverType.sendMoney, '0711', name: 'Tim', level: RuleLevel.askFirst, categoryId: 2, at: _at);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('typeChipSM')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelButton.SM.0711')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoicesuggested')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    expect(await r.store.get(ReceiverType.sendMoney, '0711'), isNull);
  });

  testWidgets('level sheet: the 300 cap shows a message and keeps the sheet', (t) async {
    final r = _Rig();
    for (var i = 0; i < kRuleCapForTest; i++) {
      await r.store.setLevel(ReceiverType.buyGoods, 'S$i', name: 'S$i', level: RuleLevel.askFirst, categoryId: 1, at: _at);
    }
    await _pump(t, r);
    await t.tap(find.byKey(const Key('typeChipSM')));
    await t.pumpAndSettle();
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

  testWidgets('no Auto-record level, tag or confirm anywhere in 0.2.1', (t) async {
    final r = _Rig();
    await _pump(t, r);
    expect(find.textContaining('Auto-record'), findsNothing);
    await t.tap(find.byKey(const Key('levelButton.SM.0711')));
    await t.pumpAndSettle();
    expect(find.textContaining('Auto-record'), findsNothing);
  });

  testWidgets('no deps (standard wiring gap): only the airtime switches', (t) async {
    await _pump(t, _Rig(), noDeps: true);
    expect(find.byKey(const Key('autoRecordMyself')), findsOneWidget);
    expect(find.byKey(const Key('levelFilterall')), findsNothing);
  });

  for (final c in [(1.3, 390.0), (2.0, 390.0), (1.3, 500.0)]) {
    testWidgets('large text ${c.$1} at ${c.$2.toInt()} px wide: no overflow, rows and sheet fit', (t) async {
      final r = _Rig();
      await r.store.setLevel(ReceiverType.sendMoney, '0722', name: 'Grace Wanjiru Long Name Here', level: RuleLevel.askFirst, categoryId: 2, at: _at);
      await _pump(t, r, scale: c.$1, width: c.$2);
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(find.byKey(const Key('levelButton.SM.0711')), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('levelButton.SM.0711')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}

const int kRuleCapForTest = 300;
