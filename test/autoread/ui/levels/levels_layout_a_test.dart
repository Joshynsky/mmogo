// The Remembered page's second tab with the Auto-record screens on (autoRecordUi forced true).
// 0.2.2 item 2 redesign (U-PAGE, mock-remembered-v2 page-*): REWRITTEN ON PURPOSE from the U5 layout A
// tests (plan section 3 reversal 3): folded groups Suggested / Ask first / Auto-record with ONE open
// (Auto-record at start), no chips, no search, no helper line, rows that say what mmogo does, paused rows
// and their spoken label, the ONE details-off card with B-7 (Settings at the switch) and B-8 (refresh after
// Settings and on resume), the slots (pause switch pinned, bottom bar with Set up, no paused banner), the
// sheet's save (Suggested keeps the rule, ceiling forwarded, the one notice) and the counts-only Forget all
// through C2's forgetEveryone / countEveryone. Invented names only.
import 'dart:ui' show Tristate;

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
import 'package:mmogo/ui/screens/settings/settings_targets.dart';
import 'package:mmogo/ui/shell/app_messenger.dart' show appNavigatorKey;
import 'package:mmogo/ui/shell/routes.dart' show Routes;
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/highlight_pulse.dart';
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
  int forgetEveryoneCalls = 0;
  @override
  Future<bool> setLevel(ReceiverType type, String key,
      {required String name,
      required RuleLevel level,
      int? categoryId,
      int? ceilingCents,
      List<int> chosenCategoryIds = const <int>[],
      required DateTime at}) {
    calls.add((level: level, categoryId: categoryId, ceilingCents: ceilingCents));
    return super.setLevel(type, key,
        name: name,
        level: level,
        categoryId: categoryId,
        ceilingCents: ceilingCents,
        chosenCategoryIds: chosenCategoryIds,
        at: at);
  }

  @override
  Future<int> forgetEveryone() {
    forgetEveryoneCalls++;
    return super.forgetEveryone();
  }
}

const _tim = '0722123555';
const _grace = '0711000222';

/// forgetEveryone fails (C2's erase-everyone call); nothing is erased.
class _ThrowOnForgetAllStore extends _RecStore {
  @override
  Future<int> forgetEveryone() async => throw StateError('store failed');
}

/// A store whose count cannot be taken.
class _FailingCountStore extends _RecStore {
  @override
  Future<int> countEveryone() async => throw StateError('store failed');
}

/// Hides every rule from all() (what B-HIDE does while Record receiver details is off); the C2 calls
/// still see them.
class _HiddenStore extends _RecStore {
  @override
  Future<List<ReceiverRule>> all() async => const [];
}

class _Rig {
  _Rig({_RecStore? store, this.knownPeople = const [KnownPerson(type: ReceiverType.buyGoods, key: '5512', name: 'Mama Mboga')]})
      : store = store ?? _RecStore();
  final _RecStore store;
  final List<KnownPerson> knownPeople;
  final notice = FakeRuleChangeNotice();
  final pause = FakeHardRulePausePort();
  final airtime = AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});
  bool details = true;

  LevelsDeps get deps => LevelsDeps(
        store: store,
        history: FakeHistoryReader(history: {'BG.5512': [2]}),
        categories: _Cats(),
        suggest: FakeSuggestSettings(),
        known: () async => knownPeople,
        now: () => kHardTestNow,
        pause: pause,
        notice: notice,
      );

  /// Tim Auto-record Family with Ksh 2,000, Amina (Buy Goods) Auto-record Bills with no limit, Grace Ask
  /// first Food, KPLC (Paybill) Ask first Bills, Mama Mboga Suggested (known name, no rule).
  Future<void> seed() async {
    await store.saveRule(hardTestRule(_tim, name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 200000));
    await store.saveRule(hardTestRule('Amina', type: ReceiverType.buyGoods, name: 'Amina', level: RuleLevel.autoRecord, categoryId: 3));
    await store.saveRule(hardTestRule(_grace, name: 'Grace', level: RuleLevel.askFirst, categoryId: 2));
    await store.saveRule(hardTestRule('888880', type: ReceiverType.payBill, name: 'KPLC', level: RuleLevel.askFirst, categoryId: 3));
    store.calls.clear();
  }
}

/// What the fake Settings page saw: the highlight id taken when it opened.
final List<String?> _settingsOpened = [];

Future<void> _pump(WidgetTester t, _Rig r,
    {double scale = 1,
    bool dark = false,
    TextDirection dir = TextDirection.ltr,
    LevelsSlots slots = const LevelsSlots(),
    Size size = const Size(390, 1400)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', dark ? 'dark' : 'light'),
    child: MaterialApp(
      onGenerateRoute: (s) => s.name == Routes.settings
          ? MaterialPageRoute<void>(builder: (_) {
              _settingsOpened.add(HighlightRequest.take());
              return const Scaffold(key: Key('fakeSettings'), body: Center(child: BackButton(key: Key('fakeSettingsBack'))));
            })
          : null,
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

String _toggleText(WidgetTester t, RuleLevel l) => t.widget<Text>(find.byKey(Key('levelGroupToggle.${l.name}'))).data!;

Future<void> _tapGroup(WidgetTester t, RuleLevel l) async {
  await t.ensureVisible(find.byKey(Key('levelGroupToggle.${l.name}')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key('levelGroupToggle.${l.name}')));
  await t.pumpAndSettle();
}

/// Test slots: a 60 px pause switch, a 10 px review line, a bottom bar with a Set up button when the tab
/// gives it one ([seen] records what the bar received).
LevelsSlots _testSlots({List<VoidCallback?>? seen, Future<void> Function(BuildContext)? onSetUp}) => LevelsSlots(
      pauseSwitch: (_) => const SizedBox(key: Key('slotPause'), height: 60),
      reviewLine: (_) => const SizedBox(key: Key('slotReview'), height: 10),
      bottomBar: (_, setUp) {
        seen?.add(setUp);
        return SizedBox(
          key: const Key('slotBar'),
          height: 56,
          child: setUp == null
              ? null
              : TextButton(key: const Key('slotBarSetUp'), onPressed: setUp, child: const Text(kHardSetUpButton)),
        );
      },
      onSetUp: onSetUp,
    );

void main() {
  setUp(() {
    debugAutoRecordUiOverride = true;
    _settingsOpened.clear();
  });
  tearDown(() {
    debugAutoRecordUiOverride = null;
    HighlightRequest.take();
  });

  testWidgets('groups: Suggested, Ask first, Auto-record with counts; Auto-record open, the others closed; no search, chips or helper',
      (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    final sug = _y(t, const Key('levelGroup.suggested'));
    final ask = _y(t, const Key('levelGroup.askFirst'));
    final auto = _y(t, const Key('levelGroup.autoRecord'));
    expect(sug < ask && ask < auto, isTrue);
    expect(_toggleText(t, RuleLevel.suggested), hardGroupShow(1));
    expect(_toggleText(t, RuleLevel.askFirst), hardGroupShow(2));
    expect(_toggleText(t, RuleLevel.autoRecord), kHardGroupHide);
    expect(find.byKey(const Key('levelRow.SM.$_tim')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.SM.$_grace')), findsNothing);
    expect(find.byKey(const Key('levelRow.BG.5512')), findsNothing);
    // Auto-record rows by name (Amina, Tim), under their header.
    final amina = _y(t, const Key('levelRow.BG.Amina'));
    final tim = _y(t, const Key('levelRow.SM.$_tim'));
    expect(auto < amina && amina < tim, isTrue);
    for (final k in ['levelsSearch', 'levelsHelper', 'levelFilterall', 'typeChipSM', 'typeChipAll']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
    expect(find.text(kHardPageHelper), findsNothing);
    expect(find.text(kHardSearchPlaceholder), findsNothing);
  });

  testWidgets('one open at a time: opening Ask first closes Auto-record (page-open); Hide closes it; Suggested opens alone',
      (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await _tapGroup(t, RuleLevel.askFirst);
    expect(find.byKey(const Key('levelRow.SM.$_grace')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.SM.$_tim')), findsNothing);
    expect(_toggleText(t, RuleLevel.autoRecord), hardGroupShow(2));
    expect(_toggleText(t, RuleLevel.askFirst), kHardGroupHide);
    await _tapGroup(t, RuleLevel.askFirst);
    expect(find.byKey(const Key('levelRow.SM.$_grace')), findsNothing);
    expect(find.text(kHardGroupHide), findsNothing);
    await _tapGroup(t, RuleLevel.suggested);
    expect(find.byKey(const Key('levelRow.BG.5512')), findsOneWidget);
    expect(find.text(kHardGroupHide), findsOneWidget);
  });

  testWidgets('fold headers announce the level, the count and "Show n" / "Hide", with the expanded state', (t) async {
    final sem = t.ensureSemantics();
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    final sug = t.getSemantics(find.byKey(const Key('levelGroup.suggested')));
    expect(sug.label, '${hardGroupName(RuleLevel.suggested)}, 1, ${hardGroupShow(1)}');
    final sd = sug.getSemanticsData().flagsCollection;
    expect(sd.isHeader, isTrue);
    expect(sd.isButton, isTrue);
    expect(sd.isExpanded, Tristate.isFalse);
    final auto = t.getSemantics(find.byKey(const Key('levelGroup.autoRecord')));
    expect(auto.label, '${hardGroupName(RuleLevel.autoRecord)}, 2, $kHardGroupHide');
    expect(auto.getSemanticsData().flagsCollection.isExpanded, Tristate.isTrue);
    sem.dispose();
  });

  testWidgets('rows say what mmogo does: Records up to / never asks first, Asks; identity line masked then type', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    expect(_inRow('SM.$_tim', find.text(hardRowRecordsUpTo('Family', 200000))), findsOneWidget);
    expect(_inRow('SM.$_tim', find.text('${maskPhone(_tim)} · Send Money')), findsOneWidget);
    expect(_inRow('BG.Amina', find.text(hardRowRecordsNoLimit('Bills'))), findsOneWidget);
    expect(_inRow('SM.$_tim', find.textContaining('123')), findsNothing); // hidden digits never drawn
    await _tapGroup(t, RuleLevel.askFirst);
    expect(_inRow('SM.$_grace', find.text(hardRowAsks('Food'))), findsOneWidget);
    expect(_inRow('PB.888880', find.text(hardRowAsks('Bills'))), findsOneWidget);
    expect(t.getSize(find.byKey(const Key('levelButton.SM.$_grace'))).height, greaterThanOrEqualTo(44));
  });

  // I2: in 0.2.2 a stored chosen list (a restored `sc`) does NOT change the row line (chosen lists are 0.2.3).
  testWidgets('Suggested lists every Suggested person; every row says "Suggests from last 10 payments", a chosen list too',
      (t) async {
    final r = _Rig();
    await r.seed();
    await r.store.saveRule(hardTestRule(_grace, name: 'Grace', categoryId: 2).copyWith(chosenCategoryIds: [3, 1]));
    await _pump(t, r);
    await _tapGroup(t, RuleLevel.suggested);
    expect(_inRow('BG.5512', find.text(kHardSuggestsFromLast10)), findsOneWidget);
    expect(_inRow('SM.$_grace', find.text(kHardSuggestsFromLast10)), findsOneWidget);
    expect(_inRow('SM.$_grace', find.text(hardRowSuggests('Bills, Family'))), findsNothing); // 0.2.3
    expect(_toggleText(t, RuleLevel.suggested), kHardGroupHide);
  });

  testWidgets('paused: Auto-record rows say "Paused: asking first"; spoken = Auto-record + paused, never "Ask first"; resume',
      (t) async {
    final sem = t.ensureSemantics();
    final r = _Rig();
    await r.seed();
    r.pause.paused = true;
    await _pump(t, r);
    expect(_inRow('SM.$_tim', find.text(kHardRowPaused)), findsOneWidget);
    expect(_inRow('BG.Amina', find.text(kHardRowPaused)), findsOneWidget);
    final label = t.getSemantics(find.byKey(const Key('levelButton.SM.$_tim'))).label;
    expect(label, contains(kHardLevelAutoRecord));
    expect(label, contains(kHardRowPaused));
    expect(label, isNot(contains(kHardLevelAskFirst)));
    await _tapGroup(t, RuleLevel.askFirst);
    expect(_inRow('SM.$_grace', find.text(kHardRowPaused)), findsNothing); // Ask first people are not paused
    await _tapGroup(t, RuleLevel.autoRecord);
    await r.pause.setPaused(false);
    await t.pumpAndSettle();
    expect(find.text(kHardRowPaused), findsNothing);
    expect(_inRow('SM.$_tim', find.text(hardRowRecordsUpTo('Family', 200000))), findsOneWidget);
    sem.dispose();
  });

  testWidgets('pause read fails: rows fail closed (paused)', (t) async {
    final r = _Rig();
    await r.seed();
    r.pause.failReads = true;
    await _pump(t, r);
    expect(_inRow('SM.$_tim', find.text(kHardRowPaused)), findsOneWidget);
  });

  testWidgets('nobody on Auto-record: no Auto-record group, Ask first opens at start', (t) async {
    final r = _Rig();
    await r.store.saveRule(hardTestRule(_grace, name: 'Grace', level: RuleLevel.askFirst, categoryId: 2));
    await _pump(t, r);
    expect(find.byKey(const Key('levelGroup.autoRecord')), findsNothing);
    expect(find.byKey(const Key('levelRow.SM.$_grace')), findsOneWidget);
    expect(find.byKey(const Key('levelRow.BG.5512')), findsNothing);
  });

  testWidgets('first time, nobody at all: the first-time line (a live region), no groups; the bottom bar keeps Set up', (t) async {
    final sem = t.ensureSemantics();
    final r = _Rig(knownPeople: const []);
    await _pump(t, r, slots: _testSlots(onSetUp: (_) async {}));
    expect(find.text(kHardPageFirstTime), findsOneWidget);
    expect(t.getSemantics(find.byKey(const Key('levelsEmpty'))).getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(find.byKey(const Key('levelGroup.suggested')), findsNothing);
    expect(find.byKey(const Key('slotBarSetUp')), findsOneWidget);
    sem.dispose();
  });

  testWidgets('details OFF: ONE card (signed text) + Turn it on in Settings (44 px); no groups, no slots', (t) async {
    final r = _Rig()..details = false;
    await r.seed();
    await _pump(t, r, slots: _testSlots(onSetUp: (_) async {}));
    expect(find.byKey(const Key('levelsDetailsOff')), findsOneWidget);
    expect(find.text(kHardDetailsOffCard), findsOneWidget);
    expect(find.text(kHardTurnOnInSettings), findsOneWidget);
    expect(find.text(kHardOpenSettings), findsNothing);
    expect(t.getSize(find.byKey(const Key('levelsOpenSettings'))).height, greaterThanOrEqualTo(44));
    expect(find.byKey(const Key('levelGroup.autoRecord')), findsNothing);
    expect(find.byKey(const Key('levelRow.SM.$_tim')), findsNothing);
    for (final k in ['slotPause', 'slotReview', 'slotBar', 'slotBarSetUp']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
  });

  testWidgets('B-7 + B-8: Turn it on opens Settings at the Record receiver details switch; back from Settings the page reloads',
      (t) async {
    final r = _Rig()..details = false;
    await r.seed();
    await _pump(t, r);
    await t.tap(find.byKey(const Key('levelsOpenSettings')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('fakeSettings')), findsOneWidget);
    expect(_settingsOpened, [kSettingsTargetCaptureReceiver]);
    r.details = true; // the user turns it on in Settings
    await t.tap(find.byKey(const Key('fakeSettingsBack')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelsDetailsOff')), findsNothing);
    expect(find.byKey(const Key('levelRow.SM.$_tim')), findsOneWidget); // Auto-record opens at the first showing
  });

  testWidgets('B-8: the app resumed reloads (details and pause read again)', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    expect(find.byKey(const Key('levelsDetailsOff')), findsNothing);
    r.details = false;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('levelsDetailsOff')), findsOneWidget);
    r.details = true;
    r.pause.paused = true; // changed elsewhere, no change event heard here
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(_inRow('SM.$_tim', find.text(kHardRowPaused)), findsOneWidget);
  });

  testWidgets('slots: pause switch pinned at the top, review line first in the list, bottom bar pinned at the bottom', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r, slots: _testSlots(), size: const Size(390, 600));
    expect(_y(t, const Key('slotPause')), lessThan(_y(t, const Key('slotReview'))));
    expect(_y(t, const Key('slotReview')), lessThan(_y(t, const Key('levelGroup.suggested'))));
    expect(_y(t, const Key('slotBar')), greaterThan(_y(t, const Key('levelGroup.autoRecord'))));
    expect(find.descendant(of: find.byKey(const Key('levelsTab')), matching: find.byKey(const Key('slotPause'))), findsNothing);
    final pauseY = _y(t, const Key('slotPause'));
    final barY = _y(t, const Key('slotBar'));
    await t.drag(find.byKey(const Key('levelsTab')), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(_y(t, const Key('slotPause')), pauseY); // pinned
    expect(_y(t, const Key('slotBar')), barY); // pinned
    expect(find.byKey(const Key('slotReview')), findsNothing); // scrolled away with the list
  });

  testWidgets('slots on a short screen: the pause switch scrolls with the list', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r, slots: _testSlots(), size: const Size(390, 420));
    expect(find.descendant(of: find.byKey(const Key('levelsTab')), matching: find.byKey(const Key('slotPause'))), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets("Set up slot: null = the bar gets no Set up; given = the bar's Set up runs it and the page reloads", (t) async {
    final r = _Rig();
    await r.seed();
    final seen = <VoidCallback?>[];
    await _pump(t, r, slots: _testSlots(seen: seen));
    expect(seen.last, isNull);
    expect(find.byKey(const Key('slotBarSetUp')), findsNothing);
    var opened = 0;
    await _pump(t, r, slots: _testSlots(seen: seen, onSetUp: (c) async {
      opened++;
      await r.store.saveRule(hardTestRule('0733000111', name: 'Wanjiru', level: RuleLevel.autoRecord, categoryId: 2));
    }));
    expect(seen.last, isNotNull);
    await t.tap(find.byKey(const Key('slotBarSetUp')));
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(find.byKey(const Key('levelRow.SM.0733000111')), findsOneWidget);
  });

  testWidgets('sheet save, Suggested: KEEPS the rule at Suggested with the stored category passed; the notice follows', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await _tapGroup(t, RuleLevel.askFirst);
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
    expect(r.notice.calls.single.name, 'Grace'); // U-PERSON: the pill gets the plain name, no mask
    expect(r.notice.calls.single.level, RuleLevel.suggested);
    expect(r.notice.calls.single.onChangeCeiling, isNull);
    // Grace is listed in the closed Suggested group now.
    expect(find.byKey(const Key('levelRow.SM.$_grace')), findsNothing);
    expect(_toggleText(t, RuleLevel.suggested), hardGroupShow(2));
  });

  testWidgets('sheet save, Suggested for someone with no rule writes nothing and shows no notice', (t) async {
    final r = _Rig();
    await r.seed();
    await _pump(t, r);
    await _tapGroup(t, RuleLevel.suggested);
    await t.tap(find.byKey(const Key('levelButton.BG.5512')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    expect(r.store.calls, isEmpty);
    expect(await r.store.get(ReceiverType.buyGoods, '5512'), isNull);
    expect(r.notice.calls, isEmpty); // nothing saved = no pill
    expect(find.byKey(const Key('levelSheetTitle')), findsNothing); // the sheet still closed
  });

  testWidgets('sheet save, Auto-record limit change: forwarded, category kept, notice with Change reopening the sheet', (t) async {
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
    expect(call.name, 'Tim'); // U-PERSON: the pill gets the plain name, no mask
    expect(_inRow('SM.$_tim', find.text(hardRowRecordsUpTo('Family', 50000))), findsOneWidget); // the group stayed open
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
    expect(_inRow('SM.$_grace', find.text(hardRowAsks('Food'))), findsOneWidget);
    await t.tap(find.byKey(const Key('levelButton.SM.$_grace')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoiceautoRecord')));
    await t.pumpAndSettle();
    expect(find.text('700'), findsOneWidget);
  });

  testWidgets('flag off: the 0.2.1 helper line stays; the save sends no notice', (t) async {
    debugAutoRecordUiOverride = false;
    final r = _Rig();
    await r.store.saveRule(hardTestRule(_grace, name: 'Grace', level: RuleLevel.askFirst, categoryId: 2));
    await _pump(t, r);
    expect(find.byKey(const Key('levelsHelper')), findsOneWidget);
    await t.tap(find.byKey(const Key('levelButton.SM.$_grace')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelChoicesuggested')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('levelSheetSave')));
    await t.pumpAndSettle();
    expect(r.notice.calls, isEmpty);
    expect((await r.store.get(ReceiverType.sendMoney, _grace))!.level, RuleLevel.suggested);
  });

  for (final c in [
    (2.0, false, TextDirection.ltr),
    (2.0, true, TextDirection.ltr),
    (2.0, true, TextDirection.rtl),
    (2.0, false, TextDirection.rtl),
    (1.0, true, TextDirection.ltr),
  ]) {
    testWidgets('text ${c.$1}, ${c.$2 ? 'dark' : 'light'}, ${c.$3.name}: no overflow, each group open, paused, every slot drawn',
        (t) async {
      final r = _Rig();
      await r.seed();
      r.pause.paused = true;
      await _pump(t, r, scale: c.$1, dark: c.$2, dir: c.$3, slots: _testSlots(onSetUp: (_) async {}), size: const Size(390, 800));
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byKey(const Key('levelButton.SM.$_tim'))).height, greaterThanOrEqualTo(44));
      for (final l in [RuleLevel.suggested, RuleLevel.askFirst, RuleLevel.autoRecord]) {
        await _tapGroup(t, l);
        expect(t.takeException(), isNull, reason: l.name);
        expect(t.getSize(find.byKey(Key('levelGroup.${l.name}'))).height, greaterThanOrEqualTo(44));
      }
      await t.ensureVisible(find.byKey(const Key('levelButton.SM.$_tim'))); // the last tap opened Auto-record
      await t.pumpAndSettle();
      if (c.$3 == TextDirection.rtl) {
        // RTL: the name starts on the right of the row, the chevron sits on the left.
        final row = t.getRect(find.byKey(const Key('levelButton.SM.$_tim')));
        final name = t.getRect(find.descendant(of: find.byKey(const Key('levelButton.SM.$_tim')), matching: find.text('Tim')));
        final chev = t.getRect(
            find.descendant(of: find.byKey(const Key('levelButton.SM.$_tim')), matching: find.byIcon(Icons.chevron_right)));
        expect(name.right, greaterThan(row.center.dx));
        expect(chev.left, lessThan(row.center.dx));
      }
    });
  }

  testWidgets('details-off card at 200%, dark and RTL: no overflow', (t) async {
    final r = _Rig()..details = false;
    await _pump(t, r, scale: 2, dark: true, dir: TextDirection.rtl, size: const Size(390, 800));
    expect(t.takeException(), isNull);
    expect(find.text(kHardTurnOnInSettings), findsOneWidget);
  });

  group('Forget all: counts only, through forgetEveryone / countEveryone (C2)', () {
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

    testWidgets('flag on, the erase fails: no success toast, the save-failed toast, every rule stays listed', (t) async {
      final store = _ThrowOnForgetAllStore();
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
      expect(find.text(hardForgetToast(6)), findsNothing);
      expect(find.text(forgotRecipientsText(2)), findsNothing);
      expect(await r.store.all(), hasLength(4));
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
      expect(await r.store.countEveryone(), 0);
      expect(r.store.forgetEveryoneCalls, 1);
      expect(r.pause.setCalls, 0); // the pause switch is not touched
      await drainToasts(t);
    });

    testWidgets('flag on, rules hidden (details OFF, all() empty): the count and the erase still take them (B-HIDE ready)', (t) async {
      final r = _Rig(store: _HiddenStore());
      await r.seed();
      final m = await seeded();
      await pumpPage(t, r, m);
      await t.tap(find.byKey(const Key('rememberedForgetAll')));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('forgetAllDialog')), matching: find.text(hardForgetTitle(6))), findsOneWidget);
      await t.tap(find.byKey(const Key('forgetAllConfirm')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(await r.store.countEveryone(), 0);
      await drainToasts(t);
    });

    testWidgets('flag on: the count cannot be taken (store fails) -> no dialog, nothing forgotten', (t) async {
      final r = _Rig(store: _FailingCountStore());
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
      expect(r.store.forgetEveryoneCalls, 0);
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
      expect(r.store.forgetEveryoneCalls, 0);
      await drainToasts(t);
    });
  });
}
