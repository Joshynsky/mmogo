// 0.2.2 item 2 redesign, slice I2a: what RulesWiring installs for the redesigned screens.
//  - LevelsDeps gets the real Set up list (LedgerSetupRecipientsSource, B-SRC) and the real chips picker
//    (showCategoryChipsPicker, U-PICK).
//  - The pinned "paused" notice sync (B-PAUSE): install -> set, uninstall -> gone; Delete data rechecks.
//  - U-CTRL MUST: "Reset everyone to Suggested" while paused -> the sync's PM Q1 auto-off switches Pause off
//    by itself (the page's footer leaves it to the sync) and the notice goes.
// Mock preferences, a fake notice bridge (no platform channel), invented data only. Dormant:
// debugAutoRecordUiOverride is set per test and reset in tearDown.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/pause_notice_bridge.dart';
import 'package:mmogo/autoread/data/setup_recipients_source.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/runtime.dart';
import 'package:mmogo/autoread/ui/levels/category_chips_picker.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';
import 'package:mmogo/autoread/wiring/rules_wiring.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for PauseNotice.kt: counts what the sync asks for.
class _Bridge implements PauseNoticeBridge {
  bool visible = false;
  int shows = 0;
  int cancels = 0;

  @override
  Future<bool> show({required String title, required String resume, required String channelName}) async {
    shows++;
    visible = true;
    return true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    visible = false;
  }
}

/// Lets the sync's listeners and passes run (it works on store / port change signals, not on a timer).
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _Bridge bridge;
  final defaultBridge = RulesWiring.pauseNoticeBridge;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RulesWiring.database = () async => throw StateError('no database in this test');
    bridge = _Bridge();
    RulesWiring.pauseNoticeBridge = () => bridge;
  });
  tearDown(() async {
    RulesWiring.uninstall();
    RulesWiring.pauseNoticeBridge = defaultBridge;
    await RulesWiring.pausePort.setPaused(false);
    await AutoReadRuntime.ruleStore.forgetEveryone();
    debugAutoRecordUiOverride = null;
  });

  test('LevelsDeps gets the real Set up list and the real chips picker', () {
    RulesWiring.install();
    final d = LevelsDeps.instance!;
    expect(d.setup, isA<LedgerSetupRecipientsSource>());
    const PickCategories real = showCategoryChipsPicker;
    expect(d.pickCategories, same(real));
  });

  test('the pause notice sync: set by install, kept by a second install, gone after uninstall', () {
    RulesWiring.install();
    final s = RulesWiring.pauseNotice;
    expect(s, isNotNull);
    RulesWiring.install(); // safe to call twice
    expect(RulesWiring.pauseNotice, same(s));
    RulesWiring.uninstall();
    expect(RulesWiring.pauseNotice, isNull);
  });

  test('dormant (flag off): the sync only removes the notice, never posts it', () async {
    debugAutoRecordUiOverride = false;
    await RulesWiring.pausePort.setPaused(true);
    RulesWiring.install();
    await _settle();
    expect(bridge.shows, 0);
    expect(bridge.cancels, greaterThan(0));
  });

  test('paused with one person on Auto-record: the notice shows; Reset everyone -> Pause turns itself off (Q1)',
      () async {
    debugAutoRecordUiOverride = true;
    final store = AutoReadRuntime.ruleStore;
    expect(
        await store.setLevel(ReceiverType.sendMoney, '254700000001',
            name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 200000, at: DateTime(2026, 11, 26)),
        isTrue);
    expect(await RulesWiring.pausePort.setPaused(true), isTrue);
    RulesWiring.install();
    await _settle();
    expect(bridge.visible, isTrue);
    expect(await RulesWiring.pausePort.isPaused(), isTrue);

    // The page's "Reset everyone to Suggested" (the footer's bulk op over the wiring's store).
    expect(await LevelsDeps.instance!.bulk.resetAllToSuggested(), 1);
    await _settle();
    expect(await RulesWiring.pausePort.isPaused(), isFalse);
    expect(bridge.visible, isFalse);
    expect((await store.get(ReceiverType.sendMoney, '254700000001'))!.level, RuleLevel.suggested);
  });

  test('Delete data removes the pause key directly: afterDeleteData rechecks and the notice goes', () async {
    debugAutoRecordUiOverride = true;
    await AutoReadRuntime.ruleStore.setLevel(ReceiverType.sendMoney, '254700000002',
        name: 'Grace', level: RuleLevel.autoRecord, categoryId: 1, at: DateTime(2026, 11, 26));
    await RulesWiring.pausePort.setPaused(true);
    RulesWiring.install();
    await _settle();
    expect(bridge.visible, isTrue);
    final p = await SharedPreferences.getInstance();
    await p.remove('autoread_hard_paused'); // what AutoReadWipe does, not through the port
    await RulesWiring.afterDeleteData();
    expect(bridge.visible, isFalse);
  });
}
