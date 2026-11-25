// Test fakes for the 0.2.2 item 2 redesign (slice C2): the Set up list source, the category chips picker and a
// notice that records the category name. Shared by the wave-1 tests so no slice writes its own copy.
// Read-only in wave 1 (build plan section 2).
import 'package:flutter/widgets.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';

import 'category_choices_fake.dart';
import 'hard_rule_fakes.dart';

/// In-memory Set up list. [list] filters by type and keeps the given order. [fail] makes it throw;
/// [detailsOn] = false makes it answer empty, like the real source.
class FakeSetupRecipientsSource implements SetupRecipientsSource {
  FakeSetupRecipientsSource([Iterable<SetupRecipient> recipients = const []]) : recipients = [...recipients];

  final List<SetupRecipient> recipients;
  bool detailsOn = true;
  bool fail = false;

  /// The `type` of every call (null = all).
  final List<ReceiverType?> calls = [];

  @override
  Future<List<SetupRecipient>> list({ReceiverType? type}) async {
    calls.add(type);
    if (fail) throw StateError('FakeSetupRecipientsSource.fail');
    if (!detailsOn) return const [];
    return List.unmodifiable([for (final r in recipients) if (type == null || r.type == type) r]);
  }
}

/// A Set up row with test defaults (number already masked).
SetupRecipient setupTestRecipient(
  String key, {
  ReceiverType type = ReceiverType.sendMoney,
  String? name,
  String? maskedNumber = '0722***555',
  int paymentCount = 1,
  RuleLevel? level,
}) =>
    SetupRecipient(
      type: type,
      key: key,
      displayName: name ?? key,
      maskedNumber: maskedNumber,
      paymentCount: paymentCount,
      level: level,
    );

/// One recorded picker call.
class PickCall {
  PickCall(this.mode, this.choices, this.initial, this.usedBefore);
  final CategoryPickMode mode;
  final List<CategoryChoice> choices;
  final List<int> initial;
  final Set<int> usedBefore;
}

/// Stands in for the chips picker: records each call and answers with [answer] (null = closed without a
/// choice). Use [pick] as LevelsDeps.pickCategories.
class FakeCategoryPicker {
  FakeCategoryPicker({this.answer});

  List<int>? answer;
  final List<PickCall> calls = [];

  Future<List<int>?> pick(
    BuildContext context, {
    required CategoryPickMode mode,
    required List<CategoryChoice> choices,
    required List<int> initial,
    required Set<int> usedBefore,
  }) async {
    calls.add(PickCall(mode, List.unmodifiable(choices), List.unmodifiable(initial), Set.unmodifiable(usedBefore)));
    return answer == null ? null : List<int>.unmodifiable(answer!);
  }
}

/// One recorded [RuleChangeNotice.show] call, with the category name.
class CategoryNoticeCall {
  CategoryNoticeCall(this.name, this.level, this.ceilingCents, this.onChangeCeiling, this.categoryName);
  final String name;
  final RuleLevel level;
  final int? ceilingCents;
  final VoidCallback? onChangeCeiling;
  final String? categoryName;
}

/// Records every notice (with [CategoryNoticeCall.categoryName]) instead of drawing it.
class FakeCategoryRuleChangeNotice implements RuleChangeNotice {
  final List<CategoryNoticeCall> calls = [];

  @override
  void show(String name, RuleLevel level, int? ceilingCents, VoidCallback? onChangeCeiling, {String? categoryName}) =>
      calls.add(CategoryNoticeCall(name, level, ceilingCents, onChangeCeiling, categoryName));
}

/// [LevelsDeps] over fakes with the redesign ports; like hardTestDeps plus [setup] and [pickCategories].
LevelsDeps redesignTestDeps({
  FakeRuleStore? store,
  HardRulePausePort? pause,
  RuleChangeNotice? notice,
  SetupRecipientsSource? setup,
  PickCategories? pickCategories,
  List<String> categories = const ['Food', 'Family & friends', 'Bills'],
}) =>
    LevelsDeps(
      store: store ?? FakeRuleStore(),
      history: FakeHistoryReader(),
      categories: FakeCategoryChoices(categories),
      suggest: FakeSuggestSettings(),
      now: () => kHardTestNow,
      pause: pause,
      notice: notice ?? FakeCategoryRuleChangeNotice(),
      setup: setup,
      pickCategories: pickCategories,
    );
