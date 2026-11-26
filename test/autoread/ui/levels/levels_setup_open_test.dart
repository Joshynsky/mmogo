// 0.2.2 item 2 redesign, slice I2a: the Remembered page's second tab with the REAL slots (hardRuleSlotsFor):
//  - the bottom bar's Set up opens the Set up sheet; a row opens that person's sheet with the row's
//    "{k} payments"; back on the Set up sheet when it closes; the tab reloads after the sheet closes;
//  - the Airtime chip closes the sheet and brings the tab's Airtime switches into view (PM Q3);
//  - no Set up list -> no Set up button; Record receiver details OFF -> no bottom bar at all;
//  - a page row tap (levels_tab `_openSheet`) gets the chips picker (with the person's name) and the count.
// Fakes only, invented names. Dormant: debugAutoRecordUiOverride set per test and reset in tearDown.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_slots.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/levels_setup_open.dart';
import 'package:mmogo/autoread/ui/levels/levels_tab.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';
import 'package:mmogo/autoread/ui/levels/setup_row.dart';
import 'package:mmogo/ui/shell/app_messenger.dart' show appNavigatorKey;
import 'package:mmogo/ui/theme/app_palette_scope.dart';

import '../../../support/hard_rule_fakes.dart';
import '../../../support/redesign_fakes.dart';

const _tim = '0722123555';
const _mary = '0733444777';

/// Tim on Ask first plus 14 more Ask first people, so the Airtime switches start below the screen.
Future<FakeRuleStore> _store() => hardTestStore([
      hardTestRule(_tim, name: 'Tim', level: RuleLevel.askFirst, categoryId: 1),
      for (var i = 0; i < 14; i++)
        hardTestRule('07000000${i.toString().padLeft(2, '0')}', name: 'Person $i', level: RuleLevel.askFirst, categoryId: 1),
    ]);

FakeSetupRecipientsSource _setup() => FakeSetupRecipientsSource([
      setupTestRecipient(_tim, name: 'Tim', paymentCount: 12, level: RuleLevel.askFirst),
      setupTestRecipient(_mary, name: 'Mary Wanjiku', maskedNumber: '0733***777', paymentCount: 3),
    ]);

Future<void> _pump(WidgetTester t, LevelsDeps deps, {bool details = true}) async {
  t.view.physicalSize = const Size(390, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final airtime = AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', 'light'),
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      home: Scaffold(
        body: LevelsTab(controller: airtime, deps: deps, detailsOn: () async => details, slots: hardRuleSlotsFor(deps)),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Finder _setupRow(String name) => find.byWidgetPredicate((w) => w is SetupRow && w.recipient.displayName == name);

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() => debugAutoRecordUiOverride = null);

  testWidgets('Set up -> the sheet -> a row -> the person sheet with "{k} payments"; back -> the Set up sheet', (t) async {
    final setup = _setup();
    final deps = redesignTestDeps(store: await _store(), pause: FakeHardRulePausePort(), setup: setup);
    await _pump(t, deps);
    final button = find.byKey(const Key('hardSetUpButton'));
    expect(button, findsOneWidget);
    expect(t.getSize(button).height, greaterThanOrEqualTo(44));
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('setupSheet')), findsOneWidget);
    expect(setup.calls, hasLength(1));

    await t.tap(_setupRow('Mary Wanjiku'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('personSheet')), findsOneWidget);
    expect(find.text(hardPaymentsCount(3)), findsOneWidget); // the row's count, given by the Set up row

    await t.tap(find.byKey(const Key('personBack')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('personSheet')), findsNothing);
    expect(find.byKey(const Key('setupSheet')), findsOneWidget); // the Set up sheet is still there
    expect(setup.calls, hasLength(2)); // and read its list again
  });

  testWidgets('the Airtime chip closes the sheet and scrolls the tab to the Airtime switches', (t) async {
    final deps = redesignTestDeps(store: await _store(), pause: FakeHardRulePausePort(), setup: _setup());
    await _pump(t, deps);
    expect(find.byKey(kLevelsAirtimeHeaderKey).hitTestable(), findsNothing); // below the screen at first
    await t.tap(find.byKey(const Key('hardSetUpButton')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('setupType.airtime')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('setupSheet')), findsNothing);
    expect(find.byKey(kLevelsAirtimeHeaderKey).hitTestable(), findsOneWidget);
  });

  testWidgets('no Set up list: the bar has no Set up button; details OFF: no bottom bar at all', (t) async {
    final store = await _store();
    await _pump(t, redesignTestDeps(store: store, pause: FakeHardRulePausePort()));
    expect(find.byKey(const Key('slotBottomBar')), findsOneWidget);
    expect(find.byKey(const Key('hardSetUpButton')), findsNothing);

    await t.pumpWidget(const SizedBox()); // a fresh tab (the details are read when the tab starts)
    await _pump(t, redesignTestDeps(store: store, pause: FakeHardRulePausePort(), setup: _setup()), details: false);
    expect(find.byKey(const Key('slotBottomBar')), findsNothing);
    expect(find.byKey(const Key('hardSetUpButton')), findsNothing);
  });

  testWidgets('a page row tap: the person sheet gets the chips picker (with the name) and the count', (t) async {
    final picker = FakeCategoryPicker(answer: [1]);
    final store = await hardTestStore([hardTestRule(_tim, name: 'Tim', level: RuleLevel.askFirst, categoryId: 1)]);
    final deps = redesignTestDeps(store: store, pause: FakeHardRulePausePort(), setup: _setup(), pickCategories: picker.pick);
    await _pump(t, deps);
    await t.tap(find.byKey(const Key('levelButton.SM.$_tim')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('personSheet')), findsOneWidget);
    expect(find.text(hardPaymentsCount(12)), findsOneWidget); // read from the Set up list
    await t.tap(find.byKey(const Key('personChooseCategory')));
    await t.pumpAndSettle();
    expect(picker.calls.single.mode, CategoryPickMode.one);
    expect(picker.calls.single.name, 'Tim');
  });

  test('setUpActionFor: null without a Set up list', () {
    expect(setUpActionFor(redesignTestDeps()), isNull);
    expect(setUpActionFor(redesignTestDeps(setup: _setup())), isNotNull);
  });
}
