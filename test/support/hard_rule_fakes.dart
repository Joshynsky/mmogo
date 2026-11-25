// Test fakes and builders for the 0.2.2 Auto-record screens (slice C0). Shared by the U1-U6 / I1 tests so
// no slice writes its own copy.
import 'package:flutter/foundation.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';

import 'category_choices_fake.dart';

/// In-memory pause switch. [failWrites] makes setPaused refuse (the switch must snap back);
/// [failReads] makes isPaused answer paused (fail closed), like the real port on an error.
class FakeHardRulePausePort extends ChangeNotifier implements HardRulePausePort {
  FakeHardRulePausePort({this.paused = false});
  bool paused;
  bool failWrites = false;
  bool failReads = false;
  int setCalls = 0;

  @override
  Future<bool> isPaused() async => failReads ? true : paused;

  @override
  Future<bool> setPaused(bool p) async {
    setCalls++;
    if (!failWrites) paused = p;
    notifyListeners();
    return !failWrites;
  }

  @override
  Listenable get changes => this;
}

/// One recorded [RuleChangeNotice.show] call.
class NoticeCall {
  NoticeCall(this.name, this.level, this.ceilingCents, this.onChangeCeiling);
  final String name;
  final RuleLevel level;
  final int? ceilingCents;
  final VoidCallback? onChangeCeiling;
}

/// Records every notice instead of drawing it.
class FakeRuleChangeNotice implements RuleChangeNotice {
  final List<NoticeCall> calls = [];

  @override
  void show(String name, RuleLevel level, int? ceilingCents, VoidCallback? onChangeCeiling, {String? categoryName}) =>
      calls.add(NoticeCall(name, level, ceilingCents, onChangeCeiling));
}

class FakeSuggestSettings implements SuggestSettingsPort {
  FakeSuggestSettings({this.on = true, this.n = kSuggestAfterDefault});
  bool on;
  int n;
  @override
  Future<bool> enabled() async => on;
  @override
  Future<int> after() async => n;
  @override
  Future<bool> setEnabled(bool v) async {
    on = v;
    return true;
  }

  @override
  Future<bool> setAfter(int v) async {
    n = clampSuggestAfter(v);
    return true;
  }
}

final DateTime kHardTestNow = DateTime.utc(2026, 11, 25, 9);

/// A stored rule with test defaults.
ReceiverRule hardTestRule(
  String key, {
  ReceiverType type = ReceiverType.sendMoney,
  String? name,
  RuleLevel level = RuleLevel.suggested,
  int? categoryId,
  int? ceilingCents,
  bool autoPending = false,
}) =>
    ReceiverRule(
      type: type,
      key: key,
      name: name ?? key,
      level: level,
      categoryId: categoryId,
      ceilingCents: ceilingCents,
      autoPending: autoPending,
      created: kHardTestNow,
      changed: kHardTestNow,
    );

/// A [FakeRuleStore] holding [rules] (written as given).
Future<FakeRuleStore> hardTestStore(Iterable<ReceiverRule> rules) async {
  final s = FakeRuleStore();
  for (final r in rules) {
    await s.saveRule(r);
  }
  return s;
}

/// [LevelsDeps] over fakes; pass the pieces a test inspects.
LevelsDeps hardTestDeps({
  FakeRuleStore? store,
  HardRulePausePort? pause,
  RuleChangeNotice? notice,
  List<String> categories = const ['Food', 'Family & friends', 'Bills'],
}) =>
    LevelsDeps(
      store: store ?? FakeRuleStore(),
      history: FakeHistoryReader(),
      categories: FakeCategoryChoices(categories),
      suggest: FakeSuggestSettings(),
      now: () => kHardTestNow,
      pause: pause,
      notice: notice ?? FakeRuleChangeNotice(),
    );
