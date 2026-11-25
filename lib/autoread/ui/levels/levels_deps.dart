/// §AUTOREAD.LEVELS.DEPS: what the Remembered page's second tab and the
/// Suggest settings rows read and write. Interfaces only (the rules store,
/// history reader and category list come from slices S0, S2a and S2b); the
/// app's wiring fills [LevelsDeps.instance] once at start.
library;

import '../../history/history_reader.dart';
import '../../rules/rule_model.dart';
import '../../rules/rule_store.dart';
import '../category_choices.dart';
import 'hard_rule_ports.dart';
import 'setup_ports.dart';

/// A remembered person or account the page may list even before a rule exists.
class KnownPerson {
  final ReceiverType type;
  final String key;
  final String name;
  const KnownPerson({required this.type, required this.key, required this.name});
}

/// The two Suggest settings: the "ask first" offer switch and its count.
/// The rules engine only reads them; whoever wires the app writes them.
abstract class SuggestSettingsPort {
  Future<bool> enabled();
  Future<int> after();
  Future<bool> setEnabled(bool on);

  /// Stores [n] clamped to 2..10.
  Future<bool> setAfter(int n);
}

/// Lowest and highest "Suggest after" value; the default is 3.
const int kSuggestAfterMin = 2;
const int kSuggestAfterMax = 10;
const int kSuggestAfterDefault = 3;

/// Any stored number brought into 2..10.
int clampSuggestAfter(int n) => n < kSuggestAfterMin ? kSuggestAfterMin : (n > kSuggestAfterMax ? kSuggestAfterMax : n);

class LevelsDeps {
  const LevelsDeps({
    required this.store,
    required this.history,
    required this.categories,
    required this.suggest,
    this.categoriesFor,
    this.known,
    this.now = DateTime.now,
    this.pause,
    this.notice = const PillToastRuleChangeNotice(),
    RuleBulkOps? bulk,
    this.setup,
    this.pickCategories,
  }) : _bulk = bulk;

  final RuleStore store;
  final HistoryReader history;
  final CategoryChoices categories;
  final SuggestSettingsPort suggest;

  /// The categories of one receiver's group, the same ones the Categorize sheet offers for that type
  /// (the level sheet's picker). Null = [categories] for every type (tests only).
  final CategoryChoices Function(ReceiverType type)? categoriesFor;

  /// What the level sheet offers for [type].
  CategoryChoices choicesFor(ReceiverType type) => categoriesFor?.call(type) ?? categories;

  /// Remembered people to list at Suggested (null = rules only). Pochi names
  /// are listed only when they appear here.
  final Future<List<KnownPerson>> Function()? known;
  final DateTime Function() now;

  /// The "Pause all Auto-record" switch (0.2.2). Null = no pause control is drawn (standard build, tests).
  final HardRulePausePort? pause;

  /// The notice after every level change (0.2.2; the real two-stage pill replaces the plain default).
  final RuleChangeNotice notice;

  final RuleBulkOps? _bulk;

  /// The Set up sheet's list (0.2.2 item 2 redesign; real one from slice B-SRC). Null = no Set up.
  final SetupRecipientsSource? setup;

  /// The category chips picker (0.2.2 item 2 redesign; real one from slice U-PICK). Null = no picker
  /// (the person sheet keeps its older picker or offers no "Categories I choose").
  final PickCategories? pickCategories;

  /// Page-wide rule operations (0.2.2); built over [store] and [now] unless given.
  RuleBulkOps get bulk => _bulk ?? RuleBulkOps(store, now: now);

  /// Set once by the app's wiring; null in the standard build and in tests that
  /// pass their own deps.
  static LevelsDeps? instance;
}
