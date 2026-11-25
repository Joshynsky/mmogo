// U1: the 0.2.2 level sheet (mock lvl-tim, lvl-amina, lvl-mboga, lvl-kplc, lvl-agent): third option
// Auto-record behind autoRecordUi, greyed for Paybill, the ceiling field, the confirm dialog only for a
// NEW Auto-record, Cancel keeps the sheet, cap/failed results, focusCeiling, 200% text, flag off = 0.2.1.
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/phone_mask.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';
import 'package:mmogo/domain/format/money.dart' show kshTrim;
import 'package:mmogo/ui/theme/app_palette_scope.dart';

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

// Mock people (invented names).
const tim = LevelPerson(
    type: ReceiverType.sendMoney, key: '0722000555', name: 'Tim Otieno', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 200000);
const amina = LevelPerson(type: ReceiverType.pochi, key: 'Amina', name: 'Amina Wanjiku', level: RuleLevel.autoRecord, categoryId: 1);
const mboga = LevelPerson(type: ReceiverType.buyGoods, key: '5512000', name: 'Mama Mboga', level: RuleLevel.askFirst, categoryId: 2);
const kplc = LevelPerson(type: ReceiverType.payBill, key: '888000', name: 'KPLC Prepaid', level: RuleLevel.askFirst, categoryId: 3);

Future<void> _open(WidgetTester t, LevelPerson p, _Saver s,
    {double scale = 1, bool focusCeiling = false, String theme = 'light', double height = 800}) async {
  t.view.physicalSize = Size(390, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', theme),
    child: MaterialApp(
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            key: const Key('open'),
            onPressed: () => showLevelSheet(c, person: p, categories: _Cats(), onSave: s.call, focusCeiling: focusCeiling),
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

SemanticsNode _node(WidgetTester t, String title) => t.getSemantics(find.bySemanticsLabel(RegExp('^${RegExp.escape(title)}\\. ')));

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() => debugAutoRecordUiOverride = null);

  testWidgets('lvl-tim: three options, Auto-record chosen, ceiling 2000 in the field, hint line', (t) async {
    final s = _Saver();
    await _open(t, tim, s);
    expect(find.text(hardSheetTitle(nameWithMask('Tim Otieno', '0722000555'))), findsOneWidget);
    for (final l in RuleLevel.values) {
      expect(_opt(l), findsOneWidget);
    }
    expect(find.text(kHardSheetNoteAutoRecord), findsOneWidget);
    expect(find.text(hardSheetNoteSuggested('Tim Otieno')), findsOneWidget);
    expect(find.text(hardSheetNoteAskFirst('Family & friends')), findsOneWidget);
    expect(find.text(kHardCeilingLabel), findsOneWidget);
    expect(find.text(kHardCeilingPrefix), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const Key('ceilingInput'))).controller!.text, '2000');
    expect(find.text(kHardCeilingHint), findsOneWidget);
    final sem = t.ensureSemantics();
    expect(_node(t, kHardLevelAutoRecord).flagsCollection.isChecked, CheckedState.isTrue);
    expect(_node(t, kHardLevelAskFirst).flagsCollection.isChecked, CheckedState.isFalse);
    expect(_node(t, kHardLevelAutoRecord).flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    sem.dispose();
    for (final l in RuleLevel.values) {
      expect(t.getSize(_opt(l)).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('lvl-tim: ceiling-only change saves with no confirm and passes the new ceiling', (t) async {
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

  testWidgets('lvl-tim: saving unchanged keeps the stored ceiling exactly (even with cents)', (t) async {
    final s = _Saver();
    const odd = LevelPerson(
        type: ReceiverType.sendMoney, key: '0722000555', name: 'Tim Otieno', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 150050);
    await _open(t, odd, s);
    await _save(t);
    expect(s.calls.single.ceiling, 150050);
  });

  testWidgets('lvl-tim: clearing the field saves no ceiling', (t) async {
    final s = _Saver();
    await _open(t, tim, s);
    await t.enterText(find.byKey(const Key('ceilingInput')), '');
    await _save(t);
    expect(s.calls.single.ceiling, isNull);
    expect(s.calls.single.level, RuleLevel.autoRecord);
  });

  testWidgets('lvl-amina: Pochi on Auto-record, empty field with the No ceiling placeholder', (t) async {
    final s = _Saver();
    await _open(t, amina, s);
    expect(t.widget<TextField>(find.byKey(const Key('ceilingInput'))).controller!.text, '');
    expect(find.text(kHardCeilingPlaceholder), findsOneWidget);
    await _save(t);
    expect(s.calls.single.ceiling, isNull);
    expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
  });

  testWidgets('lvl-mboga: pick Auto-record; bad text shows the error and Save does nothing', (t) async {
    final s = _Saver();
    await _open(t, mboga, s);
    expect(find.byKey(const Key('ceilingInput')), findsNothing); // field only for Auto-record
    await _tap(t, _opt(RuleLevel.autoRecord));
    expect(find.byKey(const Key('ceilingInput')), findsOneWidget);
    for (final bad in ['abc', '0', '1.5']) {
      await t.enterText(find.byKey(const Key('ceilingInput')), bad);
      await _save(t);
      expect(find.text(kHardCeilingError), findsOneWidget, reason: bad);
      expect(find.text(kHardCeilingHint), findsNothing);
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
      expect(s.calls, isEmpty);
      expect(_sheetOpen(), isTrue);
    }
    final sem = t.ensureSemantics();
    expect(t.getSemantics(find.byKey(const Key('ceilingError'))).flagsCollection.isLiveRegion, isTrue);
    sem.dispose();
    // Typing clears the error line.
    await t.enterText(find.byKey(const Key('ceilingInput')), '5');
    await t.pump();
    expect(find.text(kHardCeilingError), findsNothing);
    // Above the cap: its own (placeholder) line.
    await t.enterText(find.byKey(const Key('ceilingInput')), '1,000,001');
    await _save(t);
    expect(find.text(kTodoHardCeilingTooHigh), findsOneWidget);
    expect(s.calls, isEmpty);
  });

  testWidgets('lvl-mboga: a NEW Auto-record asks first; Cancel keeps the sheet; Turn on saves', (t) async {
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

  testWidgets('a NEW Auto-record with no ceiling uses the no-ceiling body', (t) async {
    final s = _Saver();
    await _open(t, mboga, s);
    await _tap(t, _opt(RuleLevel.autoRecord));
    await _save(t);
    expect(find.text(hardConfirmBodyNoCeiling('Mama Mboga', 'Food')), findsOneWidget);
    await t.tap(find.byKey(const Key('hardConfirmOk')));
    await t.pumpAndSettle();
    expect(s.calls.single.ceiling, isNull);
  });

  testWidgets('lvl-kplc: Paybill Auto-record is greyed, disabled, gives the reason, and cannot be picked', (t) async {
    final s = _Saver();
    await _open(t, kplc, s);
    expect(find.text(kHardWhyNotPaybill), findsOneWidget);
    expect(find.text(kHardSheetNoteAutoRecord), findsNothing);
    expect(find.textContaining('yet'), findsNothing);
    final sem = t.ensureSemantics();
    final n = _node(t, kHardLevelAutoRecord);
    expect(n.flagsCollection.isEnabled.name, 'isFalse');
    expect(n.flagsCollection.isChecked, CheckedState.isFalse);
    sem.dispose();
    await _tap(t, _opt(RuleLevel.autoRecord));
    expect(find.byKey(const Key('ceilingInput')), findsNothing);
    await _save(t);
    expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
    expect(s.calls.single.level, RuleLevel.askFirst);
    expect(s.calls.single.cat, 3);
    expect(s.calls.single.ceiling, isNull);
  });

  testWidgets('lvl-kplc: a Paybill stored at Auto-record (never written by the store) opens on Ask first', (t) async {
    final s = _Saver();
    const bad = LevelPerson(type: ReceiverType.payBill, key: '888000', name: 'KPLC Prepaid', level: RuleLevel.autoRecord, categoryId: 3);
    await _open(t, bad, s);
    final sem = t.ensureSemantics();
    expect(_node(t, kHardLevelAskFirst).flagsCollection.isChecked, CheckedState.isTrue);
    sem.dispose();
    await _save(t);
    expect(s.calls.single.level, RuleLevel.askFirst);
  });

  test('lvl-agent: only Paybill is refused among rule types; the store refuses Paybill level 2 if the UI were bypassed', () async {
    for (final type in ReceiverType.values) {
      expect(autoRecordWhyNot(type), type == ReceiverType.payBill ? kHardWhyNotPaybill : isNull, reason: type.name);
    }
    final store = FakeRuleStore();
    final ok = await store.setLevel(ReceiverType.payBill, '888000',
        name: 'KPLC Prepaid', level: RuleLevel.autoRecord, categoryId: 3, at: DateTime.utc(2026, 11, 25));
    expect(ok, isFalse);
    expect(await store.get(ReceiverType.payBill, '888000'), isNull);
  });

  testWidgets('Auto-record to Suggested saves Suggested with no category and no ceiling', (t) async {
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

  testWidgets('Auto-record to Ask first passes no ceiling and no confirm', (t) async {
    final s = _Saver();
    await _open(t, tim, s);
    await _tap(t, _opt(RuleLevel.askFirst));
    await _save(t);
    expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
    expect(s.calls.single.level, RuleLevel.askFirst);
    expect(s.calls.single.ceiling, isNull);
  });

  testWidgets('autoPending person: Ask first chosen, the stored ceiling waits in the field, Auto-record confirms', (t) async {
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
    expect(_node(t, kHardLevelAskFirst).flagsCollection.isChecked, CheckedState.isTrue);
    sem.dispose();
    await _tap(t, _opt(RuleLevel.autoRecord));
    expect(t.widget<TextField>(find.byKey(const Key('ceilingInput'))).controller!.text, '3000');
    await _save(t);
    expect(find.byKey(const Key('hardConfirmTitle')), findsOneWidget);
    await t.tap(find.byKey(const Key('hardConfirmOk')));
    await t.pumpAndSettle();
    expect(s.calls.single.ceiling, 300000);
  });

  for (final r in [LevelSaveResult.capReached, LevelSaveResult.failed]) {
    testWidgets('a ${r.name} result keeps the sheet open with its line', (t) async {
      final s = _Saver()..result = r;
      await _open(t, tim, s);
      await _save(t);
      expect(_sheetOpen(), isTrue);
      expect(find.text(r == LevelSaveResult.capReached ? kLevelSheetCapReached : kLevelSheetSaveFailed), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('levelSheetSave'))).onPressed, isNotNull);
    });
  }

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

  for (final theme in ['light', 'dark']) {
    testWidgets('200% text ($theme): no overflow, error shown, Save reachable', (t) async {
      final s = _Saver();
      await _open(t, mboga, s, scale: 2, theme: theme, height: 700);
      expect(t.takeException(), isNull);
      await _tap(t, _opt(RuleLevel.autoRecord));
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
  }

  group('flag false', () {
    setUp(() => debugAutoRecordUiOverride = false);

    testWidgets('today\'s two choices, today\'s notes, no Auto-record and no field', (t) async {
      final s = _Saver();
      await _open(t, kplc, s);
      expect(_opt(RuleLevel.suggested), findsOneWidget);
      expect(_opt(RuleLevel.askFirst), findsOneWidget);
      expect(_opt(RuleLevel.autoRecord), findsNothing);
      expect(find.text(kLevelSheetAskFirstNote), findsOneWidget);
      expect(find.text(kHardWhyNotPaybill), findsNothing);
      expect(find.text(levelSheetTitle('KPLC Prepaid')), findsOneWidget);
      await _save(t);
      expect(s.calls.single.level, RuleLevel.askFirst);
      expect(s.calls.single.cat, 3);
      expect(s.calls.single.ceiling, isNull);
    });

    testWidgets('a stored Auto-record person opens on Suggested as in 0.2.1, nothing about ceilings', (t) async {
      final s = _Saver();
      await _open(t, tim, s);
      expect(_opt(RuleLevel.autoRecord), findsNothing);
      expect(find.byKey(const Key('ceilingInput')), findsNothing);
      expect(find.text(levelSheetSuggestedNote('Tim Otieno')), findsOneWidget);
      await _save(t);
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
      expect(s.calls.single.level, RuleLevel.suggested);
      expect(s.calls.single.ceiling, isNull);
    });
  });
}
