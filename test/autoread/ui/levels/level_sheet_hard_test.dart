// U-PERSON (0.2.2 item 2 redesign): the person sheet behind autoRecordUi (mock-remembered-v2 p-sug, p-ask,
// p-ask-err, p-wait, p-auto, p-auto-err, p-auto-confirm, p-paybill, p-buygoods, chk-200-p). One height for
// every level, back arrow and no X, name + masked number + "{k} payments", Suggest with no "Suggest from:",
// Ask first must choose (pre-filled from history), Auto-record category + limit + confirm only for a NEW
// Auto-record, Paybill greyed, the chips picker in single mode, 200% text light and dark, RTL.
// Flag off = the 0.2.1 sheet (group at the end).
// Rewritten on purpose from the U1 level sheet test (the radio-card layout is replaced by the redesign).
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';
import 'package:mmogo/autoread/ui/levels/person_sheet_rules.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';
import 'package:mmogo/domain/format/money.dart' show kshTrim;
import 'package:mmogo/ui/theme/app_palette_scope.dart';

import '../../../support/redesign_fakes.dart';

class _Cats implements CategoryChoices {
  @override
  Future<List<CategoryChoice>> categories() async =>
      const [CategoryChoice(id: '1', name: 'Family & friends'), CategoryChoice(id: '2', name: 'Food'), CategoryChoice(id: '3', name: 'Bills')];
  @override
  Future<CategoryChoice> create(String name) => throw UnimplementedError();
}

class _Call {
  _Call(this.level, this.cat, this.ceiling);
  final RuleLevel level;
  final int? cat;
  final int? ceiling;
}

class _Saver {
  final calls = <_Call>[];
  LevelSaveResult result = LevelSaveResult.ok;
  Future<LevelSaveResult> call(RuleLevel l, int? c, {int? ceilingCents}) async {
    calls.add(_Call(l, c, ceilingCents));
    return result;
  }
}

// Mock people (invented names and numbers).
const bob = LevelPerson(
    type: ReceiverType.sendMoney, key: '0723000789', name: 'Bob Otieno', level: RuleLevel.suggested, topIds: [1, 2]);
const peter = LevelPerson(type: ReceiverType.sendMoney, key: '0745000310', name: 'Peter Mwangi', level: RuleLevel.suggested);
const tim = LevelPerson(
    type: ReceiverType.sendMoney, key: '0722000555', name: 'Tim Otieno', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 200000);
const amina = LevelPerson(type: ReceiverType.pochi, key: 'Amina', name: 'Amina Wanjiku', level: RuleLevel.autoRecord, categoryId: 1);
const mboga = LevelPerson(type: ReceiverType.buyGoods, key: '5512000', name: 'Mama Mboga', level: RuleLevel.askFirst, categoryId: 2);
const kplc = LevelPerson(type: ReceiverType.payBill, key: '888000', name: 'KPLC Prepaid', level: RuleLevel.askFirst, categoryId: 3);

Future<void> _open(WidgetTester t, LevelPerson p, _Saver s,
    {double scale = 1,
    bool focusCeiling = false,
    String theme = 'light',
    double height = 800,
    int? count,
    PickCategories? pick,
    TextDirection dir = TextDirection.ltr}) async {
  t.view.physicalSize = Size(390, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', theme),
    child: MaterialApp(
      builder: (c, w) => Directionality(
        textDirection: dir,
        child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            key: const Key('open'),
            onPressed: () => showLevelSheet(c,
                person: p,
                categories: _Cats(),
                onSave: s.call,
                focusCeiling: focusCeiling,
                paymentCount: count,
                pickCategories: pick),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
}

Finder _opt(RuleLevel l) => find.byKey(Key('levelChoice${l.name}'));
bool _sheetOpen() => find.byKey(const Key('levelSheetTitle')).evaluate().isNotEmpty;

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.pumpAndSettle(); // let the text field finish bringing its caret into view first
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _save(WidgetTester t) => _tap(t, find.byKey(const Key('levelSheetSave')));

SemanticsNode _node(WidgetTester t, RuleLevel l) => t.getSemantics(_opt(l));

String _howText(WidgetTester t) {
  final texts = t.widgetList<Text>(find.descendant(of: find.byKey(const Key('personHow')), matching: find.byType(Text)));
  return texts.map((w) => w.data ?? '').join('\n');
}

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() => debugAutoRecordUiOverride = null);

  group('p-sug', () {
    testWidgets('header: back arrow, no X, name, masked number, "{k} payments"; Suggest chosen with its note', (t) async {
      await _open(t, bob, _Saver(), count: 18);
      expect(find.text('Bob Otieno'), findsOneWidget);
      expect(find.text('0723***789'), findsOneWidget);
      expect(find.text(hardPaymentsCount(18)), findsOneWidget);
      expect(find.byKey(const Key('personBack')), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text(kHardSetTo), findsOneWidget);
      expect(find.text('✓ $kHardLevelSuggestButton'), findsOneWidget); // check mark, not colour only
      expect(find.text(kHardSuggestsFromLast10), findsOneWidget);
      expect(_howText(t), contains(hardSheetNoteSuggested('Bob Otieno')));
      expect(_howText(t), contains(kHardSuggestHowTitle));
      // PM 25-11 (plan section 11): no "Suggest from:" choice and no "Categories I choose" in 0.2.2.
      for (final gone in [kHardSuggestFrom, kHardSuggestLast10, kHardSuggestChoose, kHardSuggestAlertPreview, kHardSuggestNoneChosen]) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
      expect(find.textContaining(hardSuggestHowLast10('Bob Otieno')), findsNothing);
      // The full number never shows.
      expect(find.textContaining('0723000789'), findsNothing);
      final sem = t.ensureSemantics();
      expect(_node(t, RuleLevel.suggested).flagsCollection.isChecked, CheckedState.isTrue);
      expect(_node(t, RuleLevel.suggested).flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(find.byTooltip(kHardBack), findsOneWidget);
      expect(t.getSemantics(find.byKey(const Key('personBack'))).getSemanticsData().tooltip, kHardBack);
      sem.dispose();
    });

    testWidgets('no count known: the payments line is left out', (t) async {
      await _open(t, bob, _Saver());
      expect(find.byKey(const Key('personCount')), findsNothing);
    });

    testWidgets('Save at Suggested passes Suggested with no category and no limit', (t) async {
      final s = _Saver();
      await _open(t, bob, s);
      await _save(t);
      expect(s.calls.single.level, RuleLevel.suggested);
      expect(s.calls.single.cat, isNull);
      expect(s.calls.single.ceiling, isNull);
      expect(_sheetOpen(), isFalse);
    });

    testWidgets('the back arrow closes the sheet with nothing saved', (t) async {
      final s = _Saver();
      await _open(t, bob, s);
      await _tap(t, find.byKey(const Key('personBack')));
      expect(_sheetOpen(), isFalse);
      expect(s.calls, isEmpty);
    });
  });

  group('p-ask', () {
    testWidgets('history: the most-used category is pre-filled and visible before Save, with its line', (t) async {
      final s = _Saver();
      await _open(t, bob, s, count: 18);
      await _tap(t, _opt(RuleLevel.askFirst));
      expect(find.textContaining('Family & friends'), findsWidgets);
      expect(t.widget<Text>(find.byKey(const Key('levelCategoryLine'))).textSpan!.toPlainText(), '$kHardCategoryLabel: Family & friends');
      expect(find.text(kHardCategoryMostUsed), findsOneWidget);
      expect(_howText(t), contains(hardAskHow('Bob Otieno', 'Family & friends')));
      expect(find.byKey(const Key('personChooseCategory')), findsOneWidget);
      await _save(t);
      expect(s.calls.single.level, RuleLevel.askFirst);
      expect(s.calls.single.cat, 1);
      expect(s.calls.single.ceiling, isNull);
    });

    testWidgets('a stored category shows with no "most used" line', (t) async {
      await _open(t, mboga, _Saver());
      expect(t.widget<Text>(find.byKey(const Key('levelCategoryLine'))).textSpan!.toPlainText(), '$kHardCategoryLabel: Food');
      expect(find.text(kHardCategoryMostUsed), findsNothing);
    });
  });

  group('p-ask-err and p-wait', () {
    testWidgets('no history: "No category yet", the choose line; Save shows the error (announced) and saves nothing',
        (t) async {
      final s = _Saver();
      final picker = FakeCategoryPicker(answer: [2]);
      await _open(t, peter, s, count: 3, pick: picker.pick);
      await _tap(t, _opt(RuleLevel.askFirst));
      expect(t.widget<Text>(find.byKey(const Key('levelCategoryLine'))).textSpan!.toPlainText(),
          '$kHardCategoryLabel: $kHardNoCategoryYet');
      expect(find.text(kHardCategoryNeed), findsOneWidget);
      expect(_howText(t), contains(hardAskHow('Peter Mwangi', kPersonSheetNoCategoryMark)));
      await _save(t);
      expect(s.calls, isEmpty);
      expect(_sheetOpen(), isTrue);
      expect(find.text(kHardCategoryError), findsOneWidget);
      final sem = t.ensureSemantics();
      expect(t.getSemantics(find.byKey(const Key('levelCategoryError'))).flagsCollection.isLiveRegion, isTrue);
      sem.dispose();
      // Choosing clears the error; Save then passes the choice.
      await _tap(t, find.byKey(const Key('personChooseCategory')));
      expect(picker.calls.single.mode, CategoryPickMode.one);
      expect(find.text(kHardCategoryError), findsNothing);
      await _save(t);
      expect(s.calls.single.level, RuleLevel.askFirst);
      expect(s.calls.single.cat, 2);
    });

    testWidgets('p-wait: exactly one payment and no category: the "still waiting" line', (t) async {
      await _open(t, peter, _Saver(), count: 1);
      await _tap(t, _opt(RuleLevel.askFirst));
      expect(find.text(hardCategoryWaiting('Peter Mwangi')), findsOneWidget);
      expect(find.text(kHardCategoryNeed), findsNothing);
    });
  });

  group('the category picker', () {
    testWidgets('single mode with the group, the current one and the used-before ids; the answer is kept', (t) async {
      final picker = FakeCategoryPicker(answer: [3]);
      await _open(t, bob, _Saver(), pick: picker.pick);
      await _tap(t, _opt(RuleLevel.askFirst));
      await _tap(t, find.byKey(const Key('personChooseCategory')));
      final c = picker.calls.single;
      expect(c.mode, CategoryPickMode.one);
      expect(c.choices.map((x) => x.id), ['1', '2', '3']);
      expect(c.initial, [1]);
      expect(c.usedBefore, {1, 2});
      expect(t.widget<Text>(find.byKey(const Key('levelCategoryLine'))).textSpan!.toPlainText(), '$kHardCategoryLabel: Bills');
      expect(find.text(kHardCategoryMostUsed), findsNothing); // chosen, not pre-filled any more
    });

    testWidgets('closed without a choice: the category stays', (t) async {
      final picker = FakeCategoryPicker();
      await _open(t, bob, _Saver(), pick: picker.pick);
      await _tap(t, _opt(RuleLevel.askFirst));
      await _tap(t, find.byKey(const Key('personChooseCategory')));
      expect(t.widget<Text>(find.byKey(const Key('levelCategoryLine'))).textSpan!.toPlainText(),
          '$kHardCategoryLabel: Family & friends');
    });

    testWidgets('no chips picker given: the older list sheet opens', (t) async {
      await _open(t, bob, _Saver());
      await _tap(t, _opt(RuleLevel.askFirst));
      await _tap(t, find.byKey(const Key('personChooseCategory')));
      expect(find.byKey(const Key('categoryPickTitle')), findsOneWidget);
    });
  });

  group('p-auto', () {
    testWidgets('Auto-record: category button, limit 2000 in the field, its help, the "Ask first above" box', (t) async {
      await _open(t, tim, _Saver(), count: 7);
      expect(find.text('✓ $kHardLevelAutoRecord'), findsOneWidget);
      expect(_howText(t), contains(hardAutoHow('Tim Otieno', 'Family & friends')));
      expect(t.widget<Text>(find.byKey(const Key('levelCategoryValue'))).data, 'Family & friends');
      expect(t.widget<TextField>(find.byKey(const Key('ceilingInput'))).controller!.text, '2000');
      expect(find.text(kHardCeilingLabel), findsOneWidget);
      expect(find.text(kHardLimitEmptyHint), findsOneWidget);
      expect(find.text(kHardLimitHelpTitle), findsOneWidget);
      expect(find.text(kHardLimitHelp), findsOneWidget);
      expect(find.byKey(const Key('personChooseCategory')), findsNothing); // only Save in the footer
      final sem = t.ensureSemantics();
      expect(_node(t, RuleLevel.autoRecord).flagsCollection.isChecked, CheckedState.isTrue);
      expect(_node(t, RuleLevel.askFirst).flagsCollection.isChecked, CheckedState.isFalse);
      sem.dispose();
    });

    testWidgets('a limit-only change saves with no confirm and passes the new limit and the category', (t) async {
      final s = _Saver();
      await _open(t, tim, s);
      await t.enterText(find.byKey(const Key('ceilingInput')), '2,500');
      await _save(t);
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
      expect(s.calls.single.level, RuleLevel.autoRecord);
      expect(s.calls.single.cat, 1);
      expect(s.calls.single.ceiling, 250000);
      expect(_sheetOpen(), isFalse);
    });

    testWidgets('saving unchanged keeps the stored limit exactly (even with cents) and the category', (t) async {
      final s = _Saver();
      const odd = LevelPerson(
          type: ReceiverType.sendMoney, key: '0722000555', name: 'Tim Otieno', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 150050);
      await _open(t, odd, s);
      await _save(t);
      expect(s.calls.single.ceiling, 150050);
      expect(s.calls.single.cat, 1);
    });

    testWidgets('clearing the field saves no limit', (t) async {
      final s = _Saver();
      await _open(t, tim, s);
      await t.enterText(find.byKey(const Key('ceilingInput')), '');
      await _save(t);
      expect(s.calls.single.ceiling, isNull);
      expect(s.calls.single.level, RuleLevel.autoRecord);
    });

    testWidgets('Pochi on Auto-record with no limit: empty field shows "Not set"', (t) async {
      final s = _Saver();
      await _open(t, amina, s);
      expect(t.widget<TextField>(find.byKey(const Key('ceilingInput'))).controller!.text, '');
      expect(find.text(kHardLimitNotSet), findsOneWidget);
      await _save(t);
      expect(s.calls.single.ceiling, isNull);
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
    });

    testWidgets('the category button opens the picker in single mode', (t) async {
      final picker = FakeCategoryPicker(answer: [2]);
      final s = _Saver();
      await _open(t, tim, s, pick: picker.pick);
      await _tap(t, find.byKey(const Key('levelCategoryRow')));
      expect(picker.calls.single.mode, CategoryPickMode.one);
      expect(picker.calls.single.initial, [1]);
      expect(t.widget<Text>(find.byKey(const Key('levelCategoryValue'))).data, 'Food');
      await _save(t);
      expect(s.calls.single.cat, 2);
    });

    testWidgets('no category: Save shows the error and the button is marked; nothing saved', (t) async {
      final s = _Saver();
      await _open(t, peter, s);
      await _tap(t, _opt(RuleLevel.autoRecord));
      expect(t.widget<Text>(find.byKey(const Key('levelCategoryValue'))).data, kHardNoCategoryYet);
      await _save(t);
      expect(find.text(kHardCategoryError), findsOneWidget);
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
      expect(s.calls, isEmpty);
    });
  });

  group('p-auto-err', () {
    testWidgets('bad text shows the error (announced), Save does nothing; typing clears it; above the cap', (t) async {
      final s = _Saver();
      await _open(t, mboga, s);
      expect(find.byKey(const Key('ceilingInput')), findsNothing); // field only for Auto-record
      await _tap(t, _opt(RuleLevel.autoRecord));
      expect(find.byKey(const Key('ceilingInput')), findsOneWidget);
      for (final bad in ['abc', '0', '1.5']) {
        await t.enterText(find.byKey(const Key('ceilingInput')), bad);
        await _save(t);
        expect(find.text(kHardCeilingError), findsOneWidget, reason: bad);
        expect(find.text(kHardLimitEmptyHint), findsNothing);
        expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
        expect(s.calls, isEmpty);
        expect(_sheetOpen(), isTrue);
      }
      final sem = t.ensureSemantics();
      expect(t.getSemantics(find.byKey(const Key('ceilingError'))).flagsCollection.isLiveRegion, isTrue);
      sem.dispose();
      await t.enterText(find.byKey(const Key('ceilingInput')), '5');
      await t.pump();
      expect(find.text(kHardCeilingError), findsNothing);
      await t.enterText(find.byKey(const Key('ceilingInput')), '1,000,001');
      await _save(t);
      expect(find.text(kTodoHardCeilingTooHigh), findsOneWidget);
      expect(s.calls, isEmpty);
    });
  });

  group('p-auto-confirm', () {
    testWidgets('a NEW Auto-record asks first (plain name); Cancel keeps the sheet; Turn on saves', (t) async {
      final s = _Saver();
      await _open(t, mboga, s);
      await _tap(t, _opt(RuleLevel.autoRecord));
      await t.enterText(find.byKey(const Key('ceilingInput')), '500');
      await _save(t);
      expect(find.text(hardConfirmTitle('Mama Mboga')), findsOneWidget);
      expect(find.text(hardConfirmBodyCeiling('Mama Mboga', 'Food', 50000)), findsOneWidget);
      expect(find.textContaining(kshTrim(50000)), findsOneWidget);
      await t.tap(find.byKey(const Key('hardConfirmCancel')));
      await t.pumpAndSettle();
      expect(s.calls, isEmpty);
      expect(_sheetOpen(), isTrue);
      expect(t.widget<FilledButton>(find.byKey(const Key('levelSheetSave'))).onPressed, isNotNull);
      await _save(t);
      await t.tap(find.byKey(const Key('hardConfirmOk')));
      await t.pumpAndSettle();
      expect(s.calls.single.level, RuleLevel.autoRecord);
      expect(s.calls.single.cat, 2);
      expect(s.calls.single.ceiling, 50000);
      expect(_sheetOpen(), isFalse);
    });

    testWidgets('a Send Money person: the confirm carries no number', (t) async {
      await _open(t, bob, _Saver());
      await _tap(t, _opt(RuleLevel.autoRecord));
      await _save(t);
      expect(find.text(hardConfirmTitle('Bob Otieno')), findsOneWidget);
      expect(find.textContaining('***'), findsOneWidget); // the header's mask only
    });

    testWidgets('a NEW Auto-record with no limit uses the no-limit body', (t) async {
      final s = _Saver();
      await _open(t, mboga, s);
      await _tap(t, _opt(RuleLevel.autoRecord));
      await _save(t);
      expect(find.text(hardConfirmBodyNoCeiling('Mama Mboga', 'Food')), findsOneWidget);
      await t.tap(find.byKey(const Key('hardConfirmOk')));
      await t.pumpAndSettle();
      expect(s.calls.single.ceiling, isNull);
    });

    testWidgets('autoPending person: Ask first chosen, the stored limit waits in the field, Auto-record confirms', (t) async {
      final s = _Saver();
      const pending = LevelPerson(
          type: ReceiverType.sendMoney,
          key: '0733000981',
          name: 'Gary Kamau',
          level: RuleLevel.askFirst,
          categoryId: 1,
          ceilingCents: 300000,
          autoPending: true);
      await _open(t, pending, s);
      final sem = t.ensureSemantics();
      expect(_node(t, RuleLevel.askFirst).flagsCollection.isChecked, CheckedState.isTrue);
      sem.dispose();
      await _tap(t, _opt(RuleLevel.autoRecord));
      expect(t.widget<TextField>(find.byKey(const Key('ceilingInput'))).controller!.text, '3000');
      await _save(t);
      expect(find.byKey(const Key('hardConfirmTitle')), findsOneWidget);
      await t.tap(find.byKey(const Key('hardConfirmOk')));
      await t.pumpAndSettle();
      expect(s.calls.single.ceiling, 300000);
    });
  });

  group('p-paybill and p-buygoods', () {
    testWidgets('Paybill: Auto-record greyed, disabled, the Paybill line; a tap does nothing; Save = Ask first', (t) async {
      final s = _Saver();
      await _open(t, kplc, s);
      expect(find.text(kHardPaybillAlwaysAsks), findsOneWidget);
      final sem = t.ensureSemantics();
      final n = _node(t, RuleLevel.autoRecord);
      expect(n.flagsCollection.isEnabled.name, 'isFalse');
      expect(n.flagsCollection.isChecked, CheckedState.isFalse);
      expect(n.label, contains(kHardPaybillAlwaysAsks)); // the reason is spoken, not colour only
      sem.dispose();
      await _tap(t, _opt(RuleLevel.autoRecord));
      expect(find.byKey(const Key('ceilingInput')), findsNothing);
      await _save(t);
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
      expect(s.calls.single.level, RuleLevel.askFirst);
      expect(s.calls.single.cat, 3);
      expect(s.calls.single.ceiling, isNull);
    });

    testWidgets('a Paybill stored at Auto-record (never written by the store) opens on Ask first', (t) async {
      final s = _Saver();
      const bad = LevelPerson(type: ReceiverType.payBill, key: '888000', name: 'KPLC Prepaid', level: RuleLevel.autoRecord, categoryId: 3);
      await _open(t, bad, s);
      final sem = t.ensureSemantics();
      expect(_node(t, RuleLevel.askFirst).flagsCollection.isChecked, CheckedState.isTrue);
      sem.dispose();
      await _save(t);
      expect(s.calls.single.level, RuleLevel.askFirst);
    });

    testWidgets('Buy Goods: Auto-record allowed, no Paybill line', (t) async {
      await _open(t, mboga, _Saver());
      expect(find.text(kHardPaybillAlwaysAsks), findsNothing);
      final sem = t.ensureSemantics();
      expect(_node(t, RuleLevel.autoRecord).flagsCollection.isEnabled.name, 'isTrue');
      sem.dispose();
    });

    test('only Paybill is refused among rule types; the store refuses Paybill Auto-record if the UI were bypassed', () async {
      for (final type in ReceiverType.values) {
        expect(autoRecordWhyNot(type), type == ReceiverType.payBill ? kHardPaybillAlwaysAsks : isNull, reason: type.name);
      }
      final store = FakeRuleStore();
      final ok = await store.setLevel(ReceiverType.payBill, '888000',
          name: 'KPLC Prepaid', level: RuleLevel.autoRecord, categoryId: 3, at: DateTime.utc(2026, 11, 25));
      expect(ok, isFalse);
      expect(await store.get(ReceiverType.payBill, '888000'), isNull);
    });
  });

  group('level changes', () {
    testWidgets('Auto-record to Suggested saves Suggested with no category and no limit', (t) async {
      final s = _Saver();
      await _open(t, tim, s);
      await _tap(t, _opt(RuleLevel.suggested));
      expect(find.byKey(const Key('ceilingInput')), findsNothing);
      expect(find.byKey(const Key('levelCategoryRow')), findsNothing);
      await _save(t);
      expect(s.calls.single.level, RuleLevel.suggested);
      expect(s.calls.single.cat, isNull);
      expect(s.calls.single.ceiling, isNull);
    });

    testWidgets('Auto-record to Ask first keeps the category, passes no limit and no confirm', (t) async {
      final s = _Saver();
      await _open(t, tim, s);
      await _tap(t, _opt(RuleLevel.askFirst));
      await _save(t);
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
      expect(s.calls.single.level, RuleLevel.askFirst);
      expect(s.calls.single.cat, 1);
      expect(s.calls.single.ceiling, isNull);
    });

    testWidgets('one height: the sheet does not change size between the three levels', (t) async {
      await _open(t, bob, _Saver(), count: 18);
      final sheet = find.byKey(const Key('personSheet'));
      final h = t.getSize(sheet).height;
      expect(h, closeTo(800 * kPersonSheetHeightFactor, 1));
      for (final l in [RuleLevel.askFirst, RuleLevel.autoRecord, RuleLevel.suggested]) {
        await _tap(t, _opt(l));
        expect(t.getSize(sheet).height, h, reason: l.name);
      }
    });

    for (final r in [LevelSaveResult.capReached, LevelSaveResult.failed]) {
      testWidgets('a ${r.name} result keeps the sheet open with its line (announced)', (t) async {
        final s = _Saver()..result = r;
        await _open(t, tim, s);
        await _save(t);
        expect(_sheetOpen(), isTrue);
        expect(find.text(r == LevelSaveResult.capReached ? kLevelSheetCapReached : kLevelSheetSaveFailed), findsOneWidget);
        expect(t.widget<FilledButton>(find.byKey(const Key('levelSheetSave'))).onPressed, isNotNull);
      });
    }
  });

  group('focus', () {
    testWidgets('focusCeiling: the field has focus on open; ignored when Auto-record is not chosen', (t) async {
      await _open(t, tim, _Saver(), focusCeiling: true);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const Key('ceilingInput'))).focusNode!.hasFocus, isTrue);
      Navigator.of(t.element(find.byKey(const Key('levelSheetTitle')))).pop();
      await t.pumpAndSettle();
      await _open(t, mboga, _Saver(), focusCeiling: true);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('ceilingInput')), findsNothing);
    });

    testWidgets('focusCeiling off: the field does not take focus', (t) async {
      await _open(t, tim, _Saver());
      expect(t.widget<TextField>(find.byKey(const Key('ceilingInput'))).focusNode!.hasFocus, isFalse);
    });
  });

  group('quality bar', () {
    testWidgets('tap targets: level buttons, back, Save and Choose category are at least 44 high', (t) async {
      await _open(t, bob, _Saver());
      await _tap(t, _opt(RuleLevel.askFirst));
      for (final l in RuleLevel.values) {
        expect(t.getSize(_opt(l)).height, greaterThanOrEqualTo(44), reason: l.name);
      }
      for (final k in ['personBack', 'levelSheetSave', 'personChooseCategory']) {
        final s = t.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
      }
    });

    for (final theme in ['light', 'dark']) {
      testWidgets('chk-200-p ($theme): 200% text, no overflow, buttons stacked, error shown, Save reachable', (t) async {
        final s = _Saver();
        await _open(t, mboga, s, scale: 2, theme: theme, height: 700, count: 9);
        expect(t.takeException(), isNull);
        // Stacked: the three level buttons sit one under the other.
        expect(t.getRect(_opt(RuleLevel.askFirst)).top, greaterThan(t.getRect(_opt(RuleLevel.suggested)).bottom - 1));
        await _tap(t, _opt(RuleLevel.autoRecord));
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byKey(const Key('personSheet'))).height, closeTo(700 * kPersonSheetHeightFactor, 1));
        await t.enterText(find.byKey(const Key('ceilingInput')), 'abc');
        await _save(t);
        expect(t.takeException(), isNull);
        expect(find.text(kHardCeilingError), findsOneWidget);
        await t.enterText(find.byKey(const Key('ceilingInput')), '1,500');
        await _save(t);
        await _tap(t, find.byKey(const Key('hardConfirmOk')));
        expect(t.takeException(), isNull);
        expect(s.calls.single.ceiling, 150000);
      });

      testWidgets('200% text ($theme): Ask first with the two footer buttons, no overflow', (t) async {
        await _open(t, peter, _Saver(), scale: 2, theme: theme, height: 700, count: 1);
        await _tap(t, _opt(RuleLevel.askFirst));
        await _save(t);
        expect(t.takeException(), isNull);
        expect(find.text(kHardCategoryError), findsOneWidget);
        final choose = t.getRect(find.byKey(const Key('personChooseCategory')));
        final save = t.getRect(find.byKey(const Key('levelSheetSave')));
        expect(save.top, greaterThanOrEqualTo(choose.bottom)); // stacked
        expect(save.bottom, lessThanOrEqualTo(700));
      });
    }

    testWidgets('RTL: the back arrow sits on the right of the name; no overflow', (t) async {
      await _open(t, tim, _Saver(), dir: TextDirection.rtl, count: 7);
      expect(t.takeException(), isNull);
      expect(t.getRect(find.byKey(const Key('personBack'))).left,
          greaterThan(t.getRect(find.byKey(const Key('levelSheetTitle'))).left));
    });
  });

  group('flag false', () {
    setUp(() => debugAutoRecordUiOverride = false);

    testWidgets('today\'s two choices, today\'s notes, no Auto-record and no field', (t) async {
      final s = _Saver();
      await _open(t, kplc, s);
      expect(_opt(RuleLevel.suggested), findsOneWidget);
      expect(_opt(RuleLevel.askFirst), findsOneWidget);
      expect(_opt(RuleLevel.autoRecord), findsNothing);
      expect(find.text(kLevelSheetAskFirstNote), findsOneWidget);
      expect(find.text(kHardPaybillAlwaysAsks), findsNothing);
      expect(find.byKey(const Key('personSheet')), findsNothing);
      expect(find.text(levelSheetTitle('KPLC Prepaid')), findsOneWidget);
      await _save(t);
      expect(s.calls.single.level, RuleLevel.askFirst);
      expect(s.calls.single.cat, 3);
      expect(s.calls.single.ceiling, isNull);
    });

    testWidgets('a stored Auto-record person opens on Suggested as in 0.2.1, nothing about limits', (t) async {
      final s = _Saver();
      await _open(t, tim, s, count: 7);
      expect(_opt(RuleLevel.autoRecord), findsNothing);
      expect(find.byKey(const Key('ceilingInput')), findsNothing);
      expect(find.byKey(const Key('personCount')), findsNothing);
      expect(find.text(levelSheetSuggestedNote('Tim Otieno')), findsOneWidget);
      await _save(t);
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
      expect(s.calls.single.level, RuleLevel.suggested);
      expect(s.calls.single.ceiling, isNull);
    });
  });
}
