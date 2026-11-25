// 0.2.2 item 2, slice I1: the screens wired together. The Remembered page (the app's own wiring,
// rememberedPageFor) fills the second tab's slots with the pause card, paused banner, review line and
// reset footer only while the Auto-record screens are on and details are on (flag off = the 0.2.1 tab);
// the To do page gets the paused banner and passes the hint so the paused tag shows; the one pill is the
// notice after a save and its Change ceiling (level page and offers) opens the sheet with the ceiling
// field focused. Invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_engine.dart' show Offer;
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_paused_banner.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_slots.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet.dart';
import 'package:mmogo/autoread/ui/levels/level_sheet_open.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/levels_person_row.dart';
import 'package:mmogo/autoread/ui/notifications/rule_change_pill.dart';
import 'package:mmogo/autoread/ui/remembered_wiring.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/ui/shell/app_messenger.dart' show appNavigatorKey;
import 'package:mmogo/ui/shell/routes.dart' show RememberedRouteArgs;
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/collapsing_padding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_delete_data.dart';
import '../../support/hard_rule_fakes.dart';
import '../../support/news_fakes.dart';
import '../../support/waiting_fakes.dart';

class _Cats implements CategoryChoices {
  @override
  Future<List<CategoryChoice>> categories() async => const [
        CategoryChoice(id: '1', name: 'Family'),
        CategoryChoice(id: '2', name: 'Food'),
      ];
  @override
  Future<CategoryChoice> create(String name) => throw UnimplementedError();
}

const _tim = '0722123555';

LevelsDeps _deps(FakeRuleStore store, {HardRulePausePort? pause, RuleChangeNotice? notice}) => LevelsDeps(
      store: store,
      history: FakeHistoryReader(),
      categories: _Cats(),
      suggest: FakeSuggestSettings(),
      now: () => kHardTestNow,
      pause: pause,
      notice: notice ?? FakeRuleChangeNotice(),
    );

Future<FakeRuleStore> _store({bool pending = false}) => hardTestStore([
      hardTestRule(_tim, name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 200000),
      if (pending) hardTestRule('0711000222', name: 'Grace', level: RuleLevel.askFirst, categoryId: 2, autoPending: true),
    ]);

AirtimeAutoController _airtime() =>
    AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});

Future<void> _app(WidgetTester t, Widget home, {double scale = 1, String mode = 'light'}) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', mode),
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      home: Builder(
        builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: home),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _remembered(WidgetTester t, LevelsDeps d, {bool details = true, double scale = 1, String mode = 'light'}) async {
  SharedPreferences.setMockInitialValues({});
  final mem = RecipientMemory(nowMs: () => 1000);
  await _app(
      t,
      rememberedPageFor(_airtime(),
          args: const RememberedRouteArgs(openAutoRecord: true), memory: mem, levels: d, detailsOn: () async => details),
      scale: scale,
      mode: mode);
}

// 0.2.2 item 2 redesign (U-PAGE): the slots group was REWRITTEN ON PURPOSE: the tab now takes the pause
// switch (pinned top), the review line and the bottom bar; there is NO paused banner on this page.
const _slotKeys = [Key('slotPauseSwitch'), Key('slotReviewLine'), Key('slotBottomBar')];

void main() {
  setUp(useFakeDeleteData);
  tearDown(() {
    debugAutoRecordUiOverride = null;
    LevelsDeps.instance = null;
    RuleChangePill.dismissNow();
  });

  group('Remembered page slots (rememberedPageFor)', () {
    testWidgets('flag on, details on, paused: switch, review line, bottom bar in place; no paused banner on this page', (t) async {
      debugAutoRecordUiOverride = true;
      await _remembered(t, _deps(await _store(pending: true), pause: FakeHardRulePausePort(paused: true)));
      for (final k in _slotKeys) {
        expect(find.byKey(k), findsOneWidget, reason: '$k');
      }
      expect(find.byKey(const Key('hardPauseCard')), findsOneWidget);
      expect(find.byType(HardRulePausedBanner), findsNothing);
      expect(find.text(hardPausedBanner(1)), findsNothing);
      expect(find.text(hardReviewLine(1)), findsOneWidget);
      expect(find.byKey(const Key('hardResetButton')), findsOneWidget);
      double y(Key k) => t.getTopLeft(find.byKey(k)).dy;
      expect(y(const Key('slotPauseSwitch')), lessThan(y(const Key('slotReviewLine'))));
      expect(y(const Key('slotReviewLine')), lessThan(y(const Key('slotBottomBar'))));
    });

    testWidgets('not paused, nobody pending: the review line takes no room', (t) async {
      debugAutoRecordUiOverride = true;
      await _remembered(t, _deps(await _store(), pause: FakeHardRulePausePort()));
      expect(find.byKey(const Key('reviewLine')), findsNothing);
      expect(t.getSize(find.byKey(const Key('slotReviewLine'), skipOffstage: false)).height, 0);
      expect(find.byKey(const Key('hardPauseCard')), findsOneWidget);
    });

    testWidgets('flag off: no slot drawn, details-off page not used (no Auto-record controls)', (t) async {
      debugAutoRecordUiOverride = false;
      await _remembered(t, _deps(await _store(pending: true), pause: FakeHardRulePausePort(paused: true)), details: false);
      for (final k in _slotKeys) {
        expect(find.byKey(k), findsNothing, reason: '$k');
      }
      expect(find.byKey(const Key('levelsDetailsOff')), findsNothing);
      expect(find.byType(HardRulePausedBanner), findsNothing);
    });

    testWidgets('flag on, details OFF: the details-off card, no slots', (t) async {
      debugAutoRecordUiOverride = true;
      await _remembered(t, _deps(await _store(pending: true), pause: FakeHardRulePausePort(paused: true)), details: false);
      expect(find.byKey(const Key('levelsDetailsOff')), findsOneWidget);
      for (final k in _slotKeys) {
        expect(find.byKey(k), findsNothing, reason: '$k');
      }
    });

    for (final mode in ['light', 'dark']) {
      testWidgets('200% text, $mode: no overflow with every slot drawn', (t) async {
        debugAutoRecordUiOverride = true;
        await _remembered(t, _deps(await _store(pending: true), pause: FakeHardRulePausePort(paused: true)),
            scale: 2, mode: mode);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('hardResetButton')), findsOneWidget);
      });
    }

    test('hardRuleSlotsFor: empty while the flag is off or without deps; no pause port = no switch; Set up left to I2', () async {
      final d = _deps(FakeRuleStore());
      debugAutoRecordUiOverride = false;
      final off = hardRuleSlotsFor(d);
      expect([off.pauseSwitch, off.reviewLine, off.bottomBar, off.onSetUp], everyElement(isNull));
      debugAutoRecordUiOverride = true;
      final none = hardRuleSlotsFor(null);
      expect([none.pauseSwitch, none.reviewLine, none.bottomBar, none.onSetUp], everyElement(isNull));
      final noPause = hardRuleSlotsFor(d);
      expect(noPause.pauseSwitch, isNull);
      expect(noPause.reviewLine, isNotNull);
      expect(noPause.bottomBar, isNotNull);
      expect(noPause.onSetUp, isNull);
    });
  });

  group('To do page', () {
    WaitingItem item() {
      final at = kFakeNow.subtract(const Duration(minutes: 20));
      return WaitingItem(id: heldIdFor(1), kind: WaitingKind.waitingCategory, heldAt: at, parsed: sampleFields(0, at));
    }

    Widget section({HardRulePausePort? pause}) => Scaffold(
          body: SingleChildScrollView(
            child: WaitingSection(
              waiting: [item()],
              now: kFakeNow,
              pause: pause,
              actions: WaitingActions(
                ruleHintFor: (_) => const RuleHint(
                    level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: _tim, suggested: [5], fromAutoRecord: true),
                categoryNameOf: (id) => id == 5 ? 'Family & friends' : null,
                onAskFirstYes: (w, h) async {},
                onAskFirstChange: (w, h) {},
                onAskFirstLater: (w, h) {},
              ),
            ),
          ),
        );

    testWidgets('flag on, paused: the banner on top and the tag on the To confirm row', (t) async {
      debugAutoRecordUiOverride = true;
      await _app(t, section(pause: FakeHardRulePausePort(paused: true)));
      expect(find.text(hardPausedBanner(0)), findsOneWidget);
      expect(find.byKey(const Key('ask-first-paused-tag')), findsOneWidget);
      expect(t.getTopLeft(find.byKey(const Key('todoPausedBanner'))).dy,
          lessThan(t.getTopLeft(find.byKey(const Key('ask-first-paused-tag'))).dy));
    });

    testWidgets('the app\'s port (LevelsDeps.instance) is used when none is given', (t) async {
      debugAutoRecordUiOverride = true;
      LevelsDeps.instance = _deps(await _store(), pause: FakeHardRulePausePort(paused: true));
      await _app(t, section());
      expect(find.text(hardPausedBanner(1)), findsOneWidget);
      expect(find.byKey(const Key('ask-first-paused-tag')), findsOneWidget);
    });

    testWidgets('not paused: no banner, no gap, no tag', (t) async {
      debugAutoRecordUiOverride = true;
      await _app(t, section(pause: FakeHardRulePausePort()));
      expect(find.byKey(const Key('hardPausedBanner')), findsNothing);
      expect(t.getSize(find.byType(CollapsingPadding)).height, 0);
      expect(find.byKey(const Key('ask-first-paused-tag')), findsNothing);
    });

    testWidgets('flag off: today\'s To do (no banner widget at all, no tag)', (t) async {
      debugAutoRecordUiOverride = false;
      await _app(t, section(pause: FakeHardRulePausePort(paused: true)));
      expect(find.byType(HardRulePausedBanner), findsNothing);
      expect(find.byKey(const Key('ask-first-paused-tag')), findsNothing);
    });

    testWidgets('200% text, dark, paused: no overflow', (t) async {
      debugAutoRecordUiOverride = true;
      await _app(t, section(pause: FakeHardRulePausePort(paused: true)), scale: 2, mode: 'dark');
      expect(t.takeException(), isNull);
    });
  });

  group('the one pill as the notice, Change ceiling opens the sheet focused', () {
    testWidgets('a level-page save shows the pill; Auto-record expands; Change ceiling opens the sheet focused',
        (t) async {
      debugAutoRecordUiOverride = true;
      final store = await _store();
      final d = _deps(store, notice: const RuleChangePill());
      await _app(t, const Scaffold(body: SizedBox()));
      const x = LevelPerson(type: ReceiverType.sendMoney, key: _tim, name: 'Tim', level: RuleLevel.askFirst, categoryId: 1);
      final r = await saveLevelChoice(d, x, RuleLevel.autoRecord, 1, 50000,
          notify: true, onChangeCeiling: () => openCeilingSheetOnApp(d, ReceiverType.sendMoney, _tim, 'Tim'));
      expect(r, LevelSaveResult.ok);
      await t.pump();
      expect(find.text(hardPillStage1(levelWho(x), RuleLevel.autoRecord)), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1600));
      await t.pumpAndSettle();
      expect(find.text(kHardPillChangeCeiling), findsOneWidget);
      await t.tap(find.text(kHardPillChangeCeiling));
      await t.pumpAndSettle();
      final sheet = t.widget<LevelSheet>(find.byType(LevelSheet));
      expect(sheet.focusCeiling, isTrue);
      expect(sheet.person.ceilingCents, 50000);
      final input = t.widget<EditableText>(
          find.descendant(of: find.byKey(const Key('ceilingInput')), matching: find.byType(EditableText)));
      expect(input.focusNode.hasFocus, isTrue);
    });

    testWidgets('Ask first save: stage 1 only, no Change ceiling', (t) async {
      debugAutoRecordUiOverride = true;
      final d = _deps(await _store(), notice: const RuleChangePill());
      await _app(t, const Scaffold(body: SizedBox()));
      const x = LevelPerson(type: ReceiverType.sendMoney, key: _tim, name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1);
      await saveLevelChoice(d, x, RuleLevel.askFirst, 1, null, notify: true, onChangeCeiling: () {});
      await t.pump();
      expect(find.text(hardPillStage1(levelWho(x), RuleLevel.askFirst)), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1600));
      expect(find.text(kHardPillChangeCeiling), findsNothing);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
    });

    testWidgets('notify false (flag off): no pill', (t) async {
      final d = _deps(await _store(), notice: const RuleChangePill());
      await _app(t, const Scaffold(body: SizedBox()));
      const x = LevelPerson(type: ReceiverType.sendMoney, key: _tim, name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1);
      await saveLevelChoice(d, x, RuleLevel.askFirst, 1, null, notify: false);
      await t.pump();
      expect(RuleChangePill.isShowing, isFalse);
    });

    testWidgets('the offers\' Change ceiling: the person\'s sheet from the store, ceiling focused', (t) async {
      debugAutoRecordUiOverride = true;
      LevelsDeps.instance = _deps(await _store());
      await _app(t, const Scaffold(body: SizedBox()));
      openOfferCeilingSheet(const Offer(type: ReceiverType.sendMoney, key: _tim, name: 'Tim', categoryId: 1, run: 3));
      await t.pumpAndSettle();
      final sheet = t.widget<LevelSheet>(find.byType(LevelSheet));
      expect(sheet.focusCeiling, isTrue);
      expect(sheet.person.level, RuleLevel.autoRecord);
      expect(sheet.person.ceilingCents, 200000);
      expect(sheet.person.categoryNames, ['Family']);
    });

    testWidgets('no app deps: the offers\' Change ceiling does nothing', (t) async {
      await _app(t, const Scaffold(body: SizedBox()));
      openOfferCeilingSheet(const Offer(type: ReceiverType.sendMoney, key: _tim, name: 'Tim', categoryId: 1, run: 3));
      await t.pumpAndSettle();
      expect(find.byType(LevelSheet), findsNothing);
    });
  });

  group('CollapsingPadding', () {
    testWidgets('an empty child takes no room; a drawn one gets the padding (RTL mirrors start/end)', (t) async {
      await t.pumpWidget(const Directionality(
        textDirection: TextDirection.rtl,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CollapsingPadding(key: Key('empty'), padding: EdgeInsets.all(10), child: SizedBox.shrink()),
          CollapsingPadding(
              key: Key('full'),
              padding: EdgeInsetsDirectional.fromSTEB(4, 6, 20, 8),
              child: SizedBox(key: Key('box'), height: 30)),
        ]),
      ));
      expect(t.getSize(find.byKey(const Key('empty'))).height, 0);
      expect(t.getSize(find.byKey(const Key('full'))).height, 44);
      final box = t.getTopLeft(find.byKey(const Key('box')));
      expect(box.dy, 6);
      expect(box.dx, 20); // RTL: end (20) is on the left
    });
  });
}
