// 0.2.2 item 2 U-FORGET (B-5) with the real Levels tab: the page's Forget all count (names + the tab's
// extra people) and the tab's own dialog count (countEveryone) agree, each person once, also while
// Record receiver details is OFF and the rules are hidden. I2: the real tab (levelsExtraTab, as the app
// wires it) implements RememberedForgetAllCount itself; the U-FORGET test wrapper is gone.
// Dormant: debugAutoRecordUiOverride is set per test and reset in tearDown. Invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart' show kLevelsForgetAllLabel;
import 'package:mmogo/autoread/ui/levels/levels_extra_tab.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/screens/remembered/remembered_extra_tab.dart';
import 'package:mmogo/ui/screens/remembered/remembered_screen.dart';
import 'package:mmogo/ui/shell/app_messenger.dart' show appNavigatorKey;
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/hard_rule_fakes.dart';

Future<RecipientMemory> _memory({bool names = true}) async {
  SharedPreferences.setMockInitialValues({});
  var clock = 1000;
  final m = RecipientMemory(nowMs: () => clock++);
  if (names) {
    await m.remember('JANE ATIENO', SmsSourceType.pochi, recordDetailsOn: true);
    await m.remember('ZED STORES', SmsSourceType.sendMoney, recordDetailsOn: true);
  }
  return m;
}

/// Three people with a rule: JANE ATIENO (Pochi, the same person as the remembered name) and two numbers.
Future<FakeRuleStore> _store() => hardTestStore([
  hardTestRule('JANE ATIENO', type: ReceiverType.pochi, name: 'JANE ATIENO', level: RuleLevel.askFirst, categoryId: 1),
  hardTestRule('254700000001', name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 200000),
  hardTestRule('254700000002', name: 'Grace', level: RuleLevel.askFirst, categoryId: 2),
]);

RememberedExtraTab? _tab;

Future<void> _pump(WidgetTester t, RecipientMemory m, FakeRuleStore store) async {
  t.view.physicalSize = const Size(400, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final deps = hardTestDeps(store: store);
  final airtime = AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        home: RememberedScreen(
          memory: m,
          extraTab: _tab = levelsExtraTab(airtime, deps: deps),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  // The page opens on the people tab when it holds people (0.2.2); these tests use the recipients tab.
  await t.tap(find.byKey(const Key('rememberedTab0')));
  await t.pumpAndSettle();
}

final _bar = find.byKey(const Key('rememberedForgetAll'));
bool _enabled(WidgetTester t) => t.widget<OutlinedButton>(_bar).onPressed != null;
Finder _inDialog(String text) => find.descendant(of: find.byKey(const Key('forgetAllDialog')), matching: find.text(text));

Future<void> _drainToasts(WidgetTester t) async {
  await t.pump(const Duration(seconds: 15));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() => debugAutoRecordUiOverride = null);

  testWidgets('details OFF, rules hidden, no names: enabled; the dialog counts the hidden people; all erased; then disabled', (t) async {
    final store = await _store();
    store.detailsOn = false; // all() is empty now, countEveryone still sees 3
    expect(await store.all(), isEmpty);
    await _pump(t, await _memory(names: false), store);
    expect(_enabled(t), isTrue);
    await t.tap(_bar);
    await t.pumpAndSettle();
    expect(_inDialog(hardForgetTitle(3)), findsOneWidget);
    expect(_inDialog(kHardForgetBody), findsOneWidget);
    await t.tap(find.byKey(const Key('forgetAllConfirm')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(hardForgetToast(3)), findsOneWidget);
    expect(await store.countEveryone(), 0);
    await _drainToasts(t);
    expect(_enabled(t), isFalse); // a true 0 now
  });

  testWidgets('details ON, 2 names + 3 rule people sharing JANE: the dialog says 4 (JANE once); the button is enabled', (t) async {
    final store = await _store();
    await _pump(t, await _memory(), store);
    expect(_enabled(t), isTrue);
    await t.tap(_bar);
    await t.pumpAndSettle();
    expect(_inDialog(hardForgetTitle(4)), findsOneWidget);
    expect(await rememberedForgetAllExtra(_tab, const ['JANE ATIENO', 'ZED STORES']), 2); // 2 names + 2 = 4
    expect(_inDialog(hardForgetTitle(5)), findsNothing);
    await t.tap(find.byKey(const Key('forgetAllCancel')));
    await t.pumpAndSettle();
  });

  testWidgets('details ON, rules only: the page count (0 names + extra) equals the dialog count', (t) async {
    final store = await _store();
    await _pump(t, await _memory(names: false), store);
    expect(_enabled(t), isTrue);
    expect(_tab, isA<RememberedForgetAllCount>()); // the real tab, no wrapper
    expect(await rememberedForgetAllExtra(_tab, const []), 3); // the page's count
    await t.tap(_bar);
    await t.pumpAndSettle();
    expect(_inDialog(hardForgetTitle(3)), findsOneWidget);
    await t.tap(find.byKey(const Key('forgetAllCancel')));
    await t.pumpAndSettle();
  });

  testWidgets('flag off: rules only and no names -> disabled, as in 0.2.1', (t) async {
    debugAutoRecordUiOverride = false;
    await _pump(t, await _memory(names: false), await _store());
    expect(_enabled(t), isFalse);
    expect(find.text(kLevelsForgetAllLabel), findsOneWidget); // the 0.2.1 label
  });

  testWidgets('flag on: the button reads the signed "Forget all people"', (t) async {
    await _pump(t, await _memory(names: false), await _store());
    expect(find.text(kHardForgetButton), findsOneWidget);
  });
}
