// 0.2.2 U5: the Remembered page's second tab, layout A, with the Auto-record screens on (autoRecordUi
// forced true): sections, fold, search, row lines, pause look, details OFF, slots, the sheet's save
// (Suggested keeps the rule, ceiling forwarded, the one notice) and the counts-only Forget all.
// Invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/logic/phone_mask.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_cleanup.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/levels_tab.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/copy/settings_copy.dart';
import 'package:mmogo/ui/screens/remembered/remembered_screen.dart';
import 'package:mmogo/ui/shell/app_messenger.dart' show appNavigatorKey;
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/hard_rule_fakes.dart';

class _Cats implements CategoryChoices {
  @override
  Future<List<CategoryChoice>> categories() async => const [
        CategoryChoice(id: '1', name: 'Family'),
        CategoryChoice(id: '2', name: 'Food'),
        CategoryChoice(id: '3', name: 'Bills'),
      ];
  @override
  Future<CategoryChoice> create(String name) => throw UnimplementedError();
}

/// Records what the tab passes to setLevel (the fake keeps an old category on null, so a test of
/// "passed explicitly" needs the call itself).
class _RecStore extends FakeRuleStore {
  final List<({RuleLevel level, int? categoryId, int? ceilingCents})> calls = [];
  @override
  Future<bool> setLevel(ReceiverType type, String key,
      {required String name, required RuleLevel level, int? categoryId, int? ceilingCents, required DateTime at}) {
    calls.add((level: level, categoryId: categoryId, ceilingCents: ceilingCents));
    return super.setLevel(type, key, name: name, level: level, categoryId: categoryId, ceilingCents: ceilingCents, at: at);
  }
}

const _tim = '0722123555';
const _grace = '0711000222';

/// Forgets [okForgets] rules, then every forget throws (a store failing part way).
class _ThrowAfterStore extends _RecStore {
  _ThrowAfterStore(this.okForgets);
  int okForgets;
  @override
  Future<void> forget(ReceiverType type, String key) async {
    if (okForgets-- <= 0) throw StateError('store failed');
    return super.forget(type, key);
  }
}

/// A store whose list cannot be read.
class _FailingAllStore extends _RecStore {
  @override
  Future<List<ReceiverRule>> all() async => throw StateError('store failed');
}

class _Rig {
  _Rig({_RecStore? store}) : store = store ?? _RecStore();
  final _RecStore store;
  final notice = FakeRuleChangeNotice();
  final pause = FakeHardRulePausePort();
  final airtime = AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});
  bool details = true;

  LevelsDeps get deps => LevelsDeps(
        store: store,
        history: FakeHistoryReader(history: {'BG.5512': [2]}),
        categories: _Cats(),
        suggest: FakeSuggestSettings(),
        known: () async => const [KnownPerson(type: ReceiverType.buyGoods, key: '5512', name: 'Mama Mboga')],
        now: () => kHardTestNow,
        pause: pause,
        notice: notice,
      );

  /// Tim Auto-record with Ksh 2,000, Amina (Pochi rule) Auto-record no ceiling, Grace Ask first,
  /// KPLC (Paybill) Ask first, Mama Mboga Suggested (known name, no rule).
  Future<void> seed() async {
    await store.saveRule(hardTestRule(_tim, name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 200000));
    await store.saveRule(hardTestRule('Amina', type: ReceiverType.buyGoods, name: 'Amina', level: RuleLevel.autoRecord, categoryId: 3));
    await store.saveRule(hardTestRule(_grace, name: 'Grace', level: RuleLevel.askFirst, categoryId: 2));
    await store.saveRule(hardTestRule('888880', type: ReceiverType.payBill, name: 'KPLC', level: RuleLevel.askFirst, categoryId: 3));
    store.calls.clear();
  }
}

Future<void> _pump(WidgetTester t, _Rig r,
    {double scale = 1, bool dark = false, TextDirection dir = TextDirection.ltr, LevelsSlots slots = const LevelsSlots()}) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', dark ? 'dark' : 'light'),
    child: MaterialApp(
      home: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: dir,
            child: Scaffold(
              body: LevelsTab(controller: r.airtime, deps: r.deps, detailsOn: () async => r.details, slots: slots),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

double _y(WidgetTester t, Key k) => t.getTopLeft(find.byKey(k)).dy;

Finder _inRow(String id, Finder f) => find.descendant(of: find.byKey(Key('levelRow.$id')), matching: f);

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() => debugAutoRecordUiOverride = null);

  testWidgets('sections: Auto-record, Ask first, Suggested in that order; counts; Suggested folded with "Show n"', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    expect(find.text(kHardPageHelper), findsOneWidget);
    final auto = _y(t, const Key('levelGroup.autoRecord'));
    final ask = _y(t, const Key('levelGroup.askFirst'));
    final sug = _y(t, const Key('levelGroup.suggested'));
    expect(auto, lessThan(ask));
    expect(ask, lessThan(sug));
    expect(find.bySemanticsLabel('${hardGroupName(RuleLevel.autoRecord)}, 2'), findsOneWidget);
    expect(find.bySemanticsLabel('${hardGroupName(RuleLevel.askFirst)}, 2'), findsOneWidget);
    expect(find.text(hardGroupShow(1)), findsOneWidget);
    expect(find.byKey(const Key('levelRow.BG.5512')), findsNothing);
    // Auto-record rows sit between the Auto-record and Ask first headers, by name (Amina, Tim).
    final amina = _y(t, const Key('levelRow.BG.Amina'));
    final tim = _y(t, const Key('levelRow.SM.$_tim'));
    expect(auto < amina && amina < tim && tim < ask, isTrue);
  });

  testWidgets('fold: Show n opens Suggested, Hide folds it; the other sections fold too', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await t.tap(find.text(hardGroupShow(1)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.BG.5512')), findsOneWidget);
    expect(find.text(kHardGroupHide), findsNWidgets(3));
    await t.tap(find.byKey(const Key('levelGroupToggle.autoRecord')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.SM.$_tim')), findsNothing);
    expect(find.text(hardGroupShow(2)), findsOneWidget);
  });

  testWidgets('row lines: ceiling on the row, no ceiling, Paybill at Ask first says it is the highest', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    expect(_inRow('SM.$_tim', find.text('Auto-record up to Ksh 2,000')), findsOneWidget);
    expect(_inRow('BG.Amina', find.text(kHardRowAutoNoCeiling)), findsOneWidget);
    expect(_inRow('PB.888880', find.text(kHardRowAskFirstHighest)), findsOneWidget);
    expect(_inRow('SM.$_grace', find.byKey(const Key('levelRowLine'))), findsNothing);
    expect(_inRow('SM.$_tim', find.text('Send Money · ${maskPhone(_tim)} · Family')), findsOneWidget);
    expect(_inRow('SM.$_tim', find.text(kHardLevelAutoRecord)), findsOneWidget);
  });

  testWidgets('paused: Auto-record rows say "Paused: asking first", the pill reads Ask first and is dashed; resume puts it back', (t) async {
    final r = _Rig();
    await r.seed();
    r.pause.paused = true;
    await _pump(t, r);
    expect(_inRow('SM.$_tim', find.text(kHardRowPaused)), findsOneWidget);
    expect(_inRow('SM.$_tim', find.text(kHardLevelAskFirst)), findsOneWidget);
    expect(find.byKey(const Key('levelPillPaused')), findsNWidgets(2));
    expect(_inRow('SM.$_grace', find.byKey(const Key('levelPillPaused'))), findsNothing);
    await r.pause.setPaused(false);
    await t.pumpAndSettle();
    expect(find.text(kHardRowPaused), findsNothing);
    expect(find.byKey(const Key('levelPillPaused')), findsNothing);
    expect(_inRow('SM.$_tim', find.text('Auto-record up to Ksh 2,000')), findsOneWidget);
  });

  testWidgets('pause read fails: rows fail closed (paused)', (t) async {
    final r = _Rig();
    await r.seed();
    r.pause.failReads = true;
    await _pump(t, r);
    expect(_inRow('SM.$_tim', find.text(kHardRowPaused)), findsOneWidget);
  });

  testWidgets('search: by category and by number; a search opens the folded section; empty line is a live region', (t) async {
    final sem = t.ensureSemantics();
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await t.enterText(find.byKey(const Key('levelsSearch')), 'food');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.SM.$_grace')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.BG.5512')), findsOneWidget); // Suggested opened (Food from history)
    expect(find.byKey(const Key('levelRow.SM.$_tim')), findsNothing);
    expect(find.byKey(const Key('levelGroup.autoRecord')), findsNothing); // no match there: no header
    await t.enterText(find.byKey(const Key('levelsSearch')), '555');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelRow.SM.$_tim')), findsOneWidget); // visible digits of 0722***555
    // F2: the hidden digits (0722[123]555) and the full number never match.
    for (final q in ['123', '0722123555', '2123']) {
      await t.enterText(find.byKey(const Key('levelsSearch')), q);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('levelRow.SM.$_tim')), findsNothing, reason: q);
    }
    await t.enterText(find.byKey(const Key('levelsSearch')), 'zzz');
    await t.pumpAndSettle();
    expect(find.text(kHardSearchEmpty), findsOneWidget);
    expect(t.getSemantics(find.byKey(const Key('levelsSearchEmpty'))).getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    sem.dispose();
  });

  testWidgets('details OFF: the line, Open Settings, the empty line; no search, no rows, no slots', (t) async {
    final r = _Rig()..details = false;
    await r.seed();
    await _pump(t, r,
        slots: LevelsSlots(
          pauseCard: (_) => const SizedBox(key: Key('slotPause')),
          pausedBanner: (_) => const SizedBox(key: Key('slotBanner')),
          resetFooter: (_) => const SizedBox(key: Key('slotReset')),
          reviewLine: (_) => const SizedBox(key: Key('slotReview')),
        ));
    expect(find.text(kHardDetailsOffLine), findsOneWidget);
    expect(find.text(kHardOpenSettings), findsOneWidget);
    expect(t.getSize(find.byKey(const Key('levelsOpenSettings'))).height, greaterThanOrEqualTo(44));
    expect(find.text(kHardDetailsOffEmpty), findsOneWidget);
    expect(find.byKey(const Key('levelsSearch')), findsNothing);
    expect(find.byKey(const Key('levelRow.SM.$_tim')), findsNothing);
    for (final k in ['slotPause', 'slotBanner', 'slotReset', 'slotReview']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
  });

  testWidgets('slots: each drawn only when given; banner and review on top, reset footer at the bottom', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    expect(find.byKey(const Key('slotPause')), findsNothing);
    await _pump(t, r,
        slots: LevelsSlots(
          pauseCard: (_) => const SizedBox(key: Key('slotPause'), height: 10),
          pausedBanner: (_) => const SizedBox(key: Key('slotBanner'), height: 10),
          resetFooter: (_) => const SizedBox(key: Key('slotReset'), height: 10),
          reviewLine: (_) => const SizedBox(key: Key('slotReview'), height: 10),
        ));
    expect(_y(t, const Key('slotBanner')), lessThan(_y(t, const Key('slotReview'))));
    expect(_y(t, const Key('slotReview')), lessThan(_y(t, const Key('levelsHelper'))));
    expect(_y(t, const Key('levelsHelper')), lessThan(_y(t, const Key('slotPause'))));
    expect(_y(t, const Key('slotPause')), lessThan(_y(t, const Key('levelsSearch'))));
    expect(_y(t, const Key('slotReset')), greaterThan(_y(t, const Key('levelsAirtimeHeader'))));
  });

  testWidgets('sheet save, Suggested: KEEPS the rule at Suggested with the stored category passed; the notice follows', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await t.tap(find.byKey(const Key('levelButton.SM.$_grace')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoicesuggested')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    final kept = await r.store.get(ReceiverType.sendMoney, _grace);
    expect(kept, isNotNull);
    expect(kept!.level, RuleLevel.suggested);
    expect(kept.categoryId, 2);
    expect(r.store.calls.single, (level: RuleLevel.suggested, categoryId: 2, ceilingCents: null));
    expect(r.notice.calls.single.name, nameWithMask('Grace', _grace));
    expect(r.notice.calls.single.level, RuleLevel.suggested);
    expect(r.notice.calls.single.onChangeCeiling, isNull);
    // Grace is listed in the folded Suggested section now.
    expect(find.byKey(const Key('levelRow.SM.$_grace')), findsNothing);
    expect(find.text(hardGroupShow(2)), findsOneWidget);
  });

  testWidgets('sheet save, Suggested for someone with no rule writes nothing and shows no notice', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await t.tap(find.text(hardGroupShow(1)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelButton.BG.5512')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    expect(r.store.calls, isEmpty);
    expect(await r.store.get(ReceiverType.buyGoods, '5512'), isNull);
    expect(r.notice.calls, isEmpty); // nothing saved = no pill
    expect(find.byKey(const Key('levelSheetTitle')), findsNothing); // the sheet still closed
  });

  testWidgets('sheet save, Auto-record ceiling change: ceiling forwarded, category kept, notice with Change ceiling reopening the sheet', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await t.tap(find.byKey(const Key('levelButton.SM.$_tim')));
    await t.pumpAndSettle();
    expect(find.text('2000'), findsOneWidget); // LevelPerson.ceilingCents filled from the rule
    await t.enterText(find.byKey(const Key('ceilingInput')), '500');
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    expect(r.store.calls.single, (level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 50000));
    final rule = (await r.store.get(ReceiverType.sendMoney, _tim))!;
    expect(rule.ceilingCents, 50000);
    expect(rule.categoryId, 1);
    final call = r.notice.calls.single;
    expect(call.level, RuleLevel.autoRecord);
    expect(call.ceilingCents, 50000);
    expect(call.name, nameWithMask('Tim', _tim));
    expect(_inRow('SM.$_tim', find.text('Auto-record up to Ksh 500')), findsOneWidget);
    call.onChangeCeiling!();
    await t.pumpAndSettle();
    expect(find.text('500'), findsOneWidget);
    final field = find.descendant(of: find.byKey(const Key('ceilingInput')), matching: find.byType(EditableText));
    expect(t.widget<EditableText>(field.evaluate().isEmpty ? find.byKey(const Key('ceilingInput')) : field).focusNode.hasFocus, isTrue);
  });

  testWidgets('sheet save, Auto-record to Ask first: the ceiling is cleared, category passed', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await t.tap(find.byKey(const Key('levelButton.SM.$_tim')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoiceaskFirst')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    expect(r.store.calls.single, (level: RuleLevel.askFirst, categoryId: 1, ceilingCents: null));
    expect((await r.store.get(ReceiverType.sendMoney, _tim))!.ceilingCents, isNull);
    expect(r.notice.calls.single.onChangeCeiling, isNull);
  });

  testWidgets('autoPending person: listed at Ask first and the sheet keeps the stored ceiling', (t) async {
    final r = _Rig();
    await r.store.saveRule(hardTestRule(_grace, name: 'Grace', level: RuleLevel.askFirst, categoryId: 2, ceilingCents: 70000, autoPending: true));
    await _pump(t, r);
    expect(find.byKey(const Key('levelGroup.autoRecord')), findsNothing);
    expect(_inRow('SM.$_grace', find.text(kHardLevelAskFirst)), findsOneWidget);
    await t.tap(find.byKey(const Key('levelButton.SM.$_grace')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoiceautoRecord')));
    await t.pumpAndSettle();
    expect(find.text('700'), findsOneWidget);
  });

  testWidgets('flag off: the save sends no notice', (t) async {
    debugAutoRecordUiOverride = false;
    final r = _Rig();
    await r.store.saveRule(hardTestRule(_grace, name: 'Grace', level: RuleLevel.askFirst, categoryId: 2));
    await _pump(t, r);
    await t.tap(find.byKey(const Key('levelButton.SM.$_grace')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoicesuggested')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    expect(r.notice.calls, isEmpty);
    expect((await r.store.get(ReceiverType.sendMoney, _grace))!.level, RuleLevel.suggested);
  });

  for (final c in [(2.0, false, TextDirection.ltr), (2.0, true, TextDirection.rtl), (1.0, true, TextDirection.ltr)]) {
    testWidgets('text ${c.$1}, ${c.$2 ? 'dark' : 'light'}, ${c.$3.name}: no overflow, open and paused', (t) async {
      final r = _Rig();
      await r.seed();
      r.pause.paused = true;
      await _pump(t, r, scale: c.$1, dark: c.$2, dir: c.$3);
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byKey(const Key('levelButton.SM.$_tim'))).height, greaterThanOrEqualTo(44));
      expect(t.getSize(find.byKey(const Key('levelsSearch'))).height, greaterThanOrEqualTo(44));
      await t.ensureVisible(find.byKey(const Key('levelGroupToggle.suggested')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('levelGroupToggle.suggested')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byKey(const Key('levelGroup.suggested'))).height, greaterThanOrEqualTo(44));
      expect(find.byKey(const Key('levelRow.BG.5512')), findsOneWidget);
    });
  }

  group('Forget all (moved here from U4): counts only', () {
    Future<RecipientMemory> seeded() async {
      SharedPreferences.setMockInitialValues({});
      var clock = 1000;
      final m = RecipientMemory(nowMs: () => clock++);
      await m.remember('JANE ATIENO', SmsSourceType.pochi, recordDetailsOn: true);
      await m.remember('ZED STORES', SmsSourceType.sendMoney, recordDetailsOn: true);
      return m;
    }

    Future<void> pumpPage(WidgetTester t, _Rig r, RecipientMemory m, {RuleCleanup? cleanup}) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(AppPaletteScope(
        controller: AppPaletteController('ocean', 'light'),
        child: MaterialApp(
          navigatorKey: appNavigatorKey, // the pill toasts live on this navigator's overlay
          home: RememberedScreen(memory: m, extraTab: levelsExtraTab(r.airtime, deps: r.deps, cleanup: cleanup)),
        ),
      ));
      await t.pumpAndSettle();
    }

    /// Lets every toast timer run out (PillToast holds at least 6 s).
    Future<void> drainToasts(WidgetTester t) async {
      await t.pump(const Duration(seconds: 15));
      await t.pumpAndSettle();
    }

    testWidgets('flag on, a rule removal fails part way: no success toast, the save-failed toast, the rest stays listed', (t) async {
      final store = _ThrowAfterStore(1);
      final r = _Rig(store: store);
      await r.seed();
      final m = await seeded();
      await pumpPage(t, r, m);
      await t.tap(find.byKey(const Key('rememberedForgetAll')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('forgetAllConfirm')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(kLevelSheetSaveFailed), findsOneWidget);
      expect(find.text(hardForgetToast(2)), findsNothing);
      expect(find.text(forgotRecipientsText(2)), findsNothing);
      expect(await r.store.all(), hasLength(3)); // one removed, then the store failed
      await t.tap(find.byKey(const Key('rememberedTab1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('levelGroup.askFirst')), findsOneWidget); // what remains is still listed
      await drainToasts(t);
    });

    testWidgets('flag on: 2 names + 4 rules sharing 1 person -> the dialog says 5, no name; after it all are gone', (t) async {
      final r = _Rig();
      // 4 rules; the Pochi one is the remembered name JANE ATIENO (same person, counted once).
      await r.store.saveRule(hardTestRule('JANE ATIENO', type: ReceiverType.pochi, name: 'JANE ATIENO', level: RuleLevel.askFirst, categoryId: 1));
      await r.store.saveRule(hardTestRule(_tim, name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 200000));
      await r.store.saveRule(hardTestRule(_grace, name: 'Grace', level: RuleLevel.askFirst, categoryId: 2));
      await r.store.saveRule(hardTestRule('888880', type: ReceiverType.payBill, name: 'KPLC', level: RuleLevel.askFirst, categoryId: 3));
      final m = await seeded(); // JANE ATIENO (Pochi) and ZED STORES (Send Money)
      await pumpPage(t, r, m);
      await t.tap(find.byKey(const Key('rememberedForgetAll')));
      await t.pumpAndSettle();
      final dlg = find.byKey(const Key('forgetAllDialog'));
      expect(find.descendant(of: dlg, matching: find.text(hardForgetTitle(5))), findsOneWidget);
      expect(find.descendant(of: dlg, matching: find.text(kHardForgetBody)), findsOneWidget);
      expect(find.descendant(of: dlg, matching: find.text(kHardForgetOk)), findsOneWidget);
      expect(find.descendant(of: dlg, matching: find.text(kLevelsForgetAllNote)), findsNothing);
      for (final name in ['JANE', 'ZED', 'Tim', 'Grace', 'Amina', 'KPLC']) {
        expect(find.descendant(of: dlg, matching: find.textContaining(name)), findsNothing, reason: name);
      }
      await t.tap(find.byKey(const Key('forgetAllConfirm')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(hardForgetToast(5)), findsOneWidget); // the toast says the same true count
      expect(await m.list(), isEmpty);
      expect(await r.store.all(), isEmpty);
      expect(r.pause.setCalls, 0); // the pause switch is not touched
      await drainToasts(t);
    });

    testWidgets('flag on: the count cannot be taken (store fails) -> no dialog, nothing forgotten', (t) async {
      final r = _Rig(store: _FailingAllStore());
      final m = await seeded();
      await pumpPage(t, r, m);
      await t.tap(find.byKey(const Key('rememberedForgetAll')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('forgetAllDialog')), findsNothing);
      expect(await m.list(), hasLength(2));
    });

    testWidgets('flag on, Cancel: nothing forgotten', (t) async {
      final r = _Rig();
      await r.seed();
      final m = await seeded();
      await pumpPage(t, r, m);
      await t.tap(find.byKey(const Key('rememberedForgetAll')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('forgetAllCancel')));
      await t.pumpAndSettle();
      expect(await m.list(), hasLength(2));
      expect(await r.store.all(), hasLength(4));
    });

    testWidgets("flag off: today's dialog and today's clean-up through the real RuleCleanup (Pochi rules only)", (t) async {
      debugAutoRecordUiOverride = false;
      final r = _Rig();
      await r.seed();
      await r.store.saveRule(hardTestRule('JANE ATIENO', type: ReceiverType.pochi, name: 'JANE ATIENO', level: RuleLevel.askFirst, categoryId: 1));
      final m = await seeded();
      await pumpPage(t, r, m, cleanup: RuleCleanup(r.store));
      await t.tap(find.byKey(const Key('rememberedForgetAll')));
      await t.pumpAndSettle();
      expect(find.text(kForgetAllTitle), findsOneWidget);
      expect(find.text(kLevelsForgetAllNote), findsOneWidget);
      await t.tap(find.byKey(const Key('forgetAllConfirm')));
      await t.pumpAndSettle();
      expect(await m.list(), isEmpty);
      final left = await r.store.all();
      expect(left.where((x) => x.type == ReceiverType.pochi), isEmpty); // the clean-up ran
      expect(left, hasLength(4)); // Send Money, Buy Goods and Paybill rules stay (today's behaviour)
      await drainToasts(t);
    });
  });
}
