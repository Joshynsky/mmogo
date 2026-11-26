/// §AUTOREAD.LEVELS.EXTRA_TAB: the page object the Remembered screen takes as its second tab (split out
/// of levels_tab.dart, 0.2.2 item 2 U-PAGE): the tab's labels and help, its body ([LevelsTab]), and the
/// hooks that make the recipients list's Forget / Change to Send Money / Forget all reach the rules. Flag
/// on, Forget all erases EVERY rule with C2's `forgetEveryone` (the hidden ones too while Record receiver
/// details is off) and its dialog counts everyone with `countEveryone`, each person once. The same count
/// ([RememberedForgetAllCount]) enables the page's button for people with only a rule (U-FORGET, B-5).
library;

import 'package:flutter/widgets.dart';

import '../../../ui/screens/remembered/remembered_extra_tab.dart';
import '../../../ui/widgets/pill_toast.dart';
import '../../logic/airtime_auto.dart';
import '../../rules/rule_cleanup.dart';
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'levels_copy.dart';
import 'levels_deps.dart';
import 'levels_help.dart';
import 'levels_tab.dart' show LevelsSlots, LevelsTab;

/// The page object the Remembered screen takes as its second tab.
///
/// [cleanup] (optional) makes a Forget, a Change to Send Money and a Forget all on the recipients list
/// also remove the person's rule. [detailsOn] reads "Record receiver details" (null = treated as on).
RememberedExtraTab levelsExtraTab(AirtimeAutoController controller,
        {LevelsDeps? deps, RuleCleanup? cleanup, Future<bool> Function()? detailsOn, LevelsSlots slots = const LevelsSlots()}) =>
    _LevelsExtraTab(controller, deps, cleanup, detailsOn, slots);

class _LevelsExtraTab
    implements RememberedExtraTab, RememberedForgetHooks, RememberedForgetAllCopy, RememberedForgetAllCount {
  _LevelsExtraTab(this.c, this.deps, this.cleanup, this.detailsOn, this.slots);
  final AirtimeAutoController c;
  final LevelsDeps? deps;
  final RuleCleanup? cleanup;
  final Future<bool> Function()? detailsOn;
  final LevelsSlots slots;

  @override
  Future<void> onNameForgotten(String key) async => cleanup?.onNameForgotten(key);
  @override
  Future<void> onNameChangedToSendMoney(String key) async => cleanup?.onNameChangedToSendMoney(key);
  @override
  Future<void> onAllNamesForgotten() async {
    await cleanup?.onAllNamesForgotten();
    // 0.2.2: the Forget all words say Auto-record settings are forgotten too, so every rule goes (not only
    // the Pochi ones), the hidden ones included while Record receiver details is off (C2 forgetEveryone).
    // The pause switch is not a rule and stays.
    final d = deps;
    if (!autoRecordUi || d == null) return;
    try {
      await d.store.forgetEveryone();
    } catch (_) {
      // Say so (the existing save-failed toast) and throw, so the page shows no "Forgot n" success toast;
      // it marks the run failed and reloads, and the rules still stored stay listed here.
      PillToast.show(kLevelSheetSaveFailed);
      rethrow;
    }
  }

  /// Flag on (U-FORGET B-5): how many people Forget all removes ON TOP of the remembered names [nameKeys]:
  /// every person with a rule (C2 countEveryone: the hidden ones too), minus the Pochi rules that live
  /// under one of those names' keys (that person is already counted as a name). The page enables its
  /// button with names + this, and the dialog below uses the same sum, so both agree. Flag off: 0.
  @override
  Future<int> forgetAllExtraPeople(List<String> nameKeys) async {
    if (!autoRecordUi) return 0;
    final d = deps;
    if (d == null) return 0;
    final names = nameKeys.toSet();
    final everyone = await d.store.countEveryone(); // a failure throws: the count is not known
    final shared = (await d.store.all()).where((r) => r.type == ReceiverType.pochi && names.contains(r.key)).length;
    return everyone - shared;
  }

  /// Flag on (PM 25-11): the TRUE count of everyone Forget all removes: every remembered name plus
  /// [forgetAllExtraPeople], each once. Flag off: null = today's dialog.
  @override
  Future<RememberedForgetAllText?> forgetAllText(List<String> nameKeys) async {
    if (!autoRecordUi) return null;
    final n = nameKeys.toSet().length + await forgetAllExtraPeople(nameKeys); // a failure throws: no dialog
    return RememberedForgetAllText(title: hardForgetTitle(n), body: kHardForgetBody, ok: kHardForgetOk, toast: hardForgetToast(n));
  }

  @override
  Listenable get listenable => c;
  @override
  String get pageTitle => 'Remembered';
  @override
  String get recipientsTabLabel => kLevelsRecipientsTab;
  @override
  String tabLabel() => kLevelsTabLabel;
  @override
  String get forgetAllLabel => autoRecordUi ? kHardForgetButton : kLevelsForgetAllLabel;
  @override
  String get forgetAllNote => kLevelsForgetAllNote;
  @override
  RememberedExtraHelp get help => levelsHelp();
  @override
  Widget buildBody(BuildContext context) => LevelsTab(controller: c, deps: deps, detailsOn: detailsOn, slots: slots);
}
