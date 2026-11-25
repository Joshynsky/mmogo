/// §AUTOREAD.HARD_RULE_ARRIVAL - 0.2.2 item 2 (B2d): the import re-check of an automatic mark.
///
/// Kotlin wrote the mark because ITS decision (HardRuleLogic.mayRecord) said record when the message arrived. When
/// mmogo opens, [arrivalMayRecord] runs the same decision again from the values stored NOW: the rule is still
/// Auto-record for the same person with the same category, not paused, the ceiling still allows the amount,
/// "Record receiver details" is on, the kind may hold Auto-record. Any failed check = false: the mark is dropped
/// and the item keeps waiting as Ask first. Kotlin mirror: HardRuleLogic.mayRecord (same case table,
/// test/autoread/hard_rule_parity_cases.json). Reads only; never writes a rule.
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/prefs/app_prefs.dart' show AppPrefs;
import '../model/rule_hint.dart';
import '../model/waiting_item.dart';
import '../rules/hard_rule_decision.dart';
import '../rules/prefs_hard_rule_pause.dart' show kHardPausedPrefsKey;
import '../rules/rule_codec.dart';
import '../rules/rule_model.dart';

/// The whole re-check of one item may take at most this long; past it the answer is false (Ask first).
const Duration kArrivalRecheckBound = Duration(seconds: 2);

/// PURE. True only when [item] may be recorded with no tap, judged from [read] (a stored preference value by its
/// Dart key, raw). See the library comment for the checks.
bool arrivalMayRecord(WaitingItem? item, Object? Function(String key) read) {
  try {
    final p = item?.parsed;
    final RuleHint? hint = item?.hint;
    if (item == null || item.kind != WaitingKind.waitingCategory || p == null || hint == null) return false;
    if (hint.level != RuleLevel.autoRecord || hint.suggested.isEmpty) return false;
    final kind = ruleKindOfSource(p.sourceType);
    if (kind == null || kind != hint.type) return false;
    final rule = decodeRule(read(ruleStorageKey(kind, hint.key)));
    if (rule == null || rule.key != hint.key) return false;
    final d = decideHardRule(
      rule: rule,
      kind: kind,
      amountCents: p.amountCents,
      paused: hardPausedFromRaw(read(kHardPausedPrefsKey)),
      detailsOn: hardDetailsOnFromRaw(read(AppPrefs.keyCaptureIdentityPreference)),
    );
    return d == HardRuleDecision.record && rule.categoryId == hint.suggested.first;
  } catch (_) {
    return false;
  }
}

/// [arrivalMayRecord] over fresh preferences (reloaded first). Never throws; a failure or a slow read is false.
class HardRuleRecheck {
  HardRuleRecheck({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _prefs;

  Future<bool> passes(WaitingItem item) async {
    try {
      final p = await _prefs().timeout(kArrivalRecheckBound);
      await p.reload().timeout(kArrivalRecheckBound);
      return arrivalMayRecord(item, p.get);
    } catch (_) {
      return false;
    }
  }
}
