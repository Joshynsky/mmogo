/// §AUTOREAD.LEVELS.HARD_RULE_PORTS: the seams the 0.2.2 Auto-record screens share, so no two screen
/// slices edit the same file: the pause switch ([HardRulePausePort]), the one notice after a level change
/// ([RuleChangeNotice]), the page-wide rule operations ([RuleBulkOps]) and the one UI flag ([autoRecordUi]).
/// All built on the existing RuleStore (`all` / `setLevel`); the RuleStore interface is not changed.
library;

import 'package:flutter/foundation.dart';

import '../../../ui/widgets/pill_toast.dart';
import '../../rules/hard_rule_decision.dart' show autoRecordLive;
import '../../rules/prefs_hard_rule_pause.dart';
import '../../rules/rule_model.dart';
import '../../rules/rule_store.dart';
import 'hard_rule_copy.dart';

// ---------------------------------------------------------------- the UI flag

/// Test-only override of [autoRecordUi]. Null = follow [autoRecordLive]. Never set in app code.
@visibleForTesting
bool? debugAutoRecordUiOverride;

/// Whether the screens show anything Auto-record. The ONE place screens read `autoRecordLive`.
bool get autoRecordUi => debugAutoRecordUiOverride ?? autoRecordLive;

// ---------------------------------------------------------------- pause

/// The one "Pause all Auto-record" switch as the screens see it.
abstract class HardRulePausePort {
  /// True when paused. Any failure reads as paused (fail closed).
  Future<bool> isPaused();

  /// Stores [paused]; true only when it was stored and read back. Fires [changes] either way, so a
  /// switch re-reads and snaps back after a failure.
  Future<bool> setPaused(bool paused);

  /// Fires after every [setPaused] call.
  Listenable get changes;
}

class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// The real port over [PrefsHardRulePause] (key `autoread_hard_paused`, survives restart).
class PrefsHardRulePausePort implements HardRulePausePort {
  PrefsHardRulePausePort({PrefsHardRulePause? pause}) : _pause = pause ?? PrefsHardRulePause();

  final PrefsHardRulePause _pause;
  final _Signal _changes = _Signal();

  @override
  Future<bool> isPaused() async {
    try {
      return await _pause.isPaused();
    } catch (_) {
      return true;
    }
  }

  @override
  Future<bool> setPaused(bool paused) async {
    var ok = false;
    try {
      ok = await _pause.setPaused(paused);
    } catch (_) {
      ok = false;
    }
    _changes.fire();
    return ok;
  }

  @override
  Listenable get changes => _changes;
}

// ---------------------------------------------------------------- the notice after a level change

/// Shown after every successful level change. [onChangeCeiling] is offered only for Auto-record.
abstract class RuleChangeNotice {
  void show(String name, RuleLevel level, int? ceilingCents, VoidCallback? onChangeCeiling);
}

/// Plain stand-in until the real two-stage pill (slice U3): one PillToast with the stage 1 line.
class PillToastRuleChangeNotice implements RuleChangeNotice {
  const PillToastRuleChangeNotice();

  @override
  void show(String name, RuleLevel level, int? ceilingCents, VoidCallback? onChangeCeiling) =>
      PillToast.show(hardPillStage1(name, level));
}

// ---------------------------------------------------------------- page-wide operations

/// Rule operations for the whole Remembered page. "Forget all recipients" is NOT here: it stays as today
/// (the Remembered page's own Forget all flow).
class RuleBulkOps {
  RuleBulkOps(this.store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final RuleStore store;
  final DateTime Function() _now;

  /// A rule the reset would change: any level above Suggested, a ceiling, or a pending restore mark.
  static bool needsReset(ReceiverRule r) => r.level != RuleLevel.suggested || r.ceilingCents != null || r.autoPending;

  /// How many people "Reset everyone to Suggested" would change (the dialog's count).
  Future<int> resetCount() async => (await store.all()).where(needsReset).length;

  /// Sets every rule that [needsReset] to Suggested through `setLevel` (clears the ceiling and the
  /// pending mark). Rules stay (the person stays remembered); nobody is raised; the pause switch is not
  /// touched. Returns how many were changed; a refused or failed one is not counted.
  Future<int> resetAllToSuggested() async {
    var n = 0;
    for (final r in await store.all()) {
      if (!needsReset(r)) continue;
      try {
        if (await store.setLevel(r.type, r.key, name: r.name, level: RuleLevel.suggested, at: _now())) n++;
      } catch (_) {}
    }
    return n;
  }

  /// People per stored level (every level present, zero when none).
  Future<Map<RuleLevel, int>> countByLevel() async {
    final m = {for (final l in RuleLevel.values) l: 0};
    for (final r in await store.all()) {
      m[r.level] = m[r.level]! + 1;
    }
    return m;
  }

  /// People restored from a backup at Auto-record and waiting for a review (the `autoPending` mark is
  /// the only source: someone on Ask first by their own choice is never in this list).
  Future<List<ReceiverRule>> pendingAutoPeople() async => [for (final r in await store.all()) if (r.autoPending) r];
}
