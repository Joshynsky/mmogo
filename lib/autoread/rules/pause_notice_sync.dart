/// §AUTOREAD.PAUSE_NOTICE_SYNC - 0.2.2 item 2 (B-PAUSE): keeps the pinned "Auto-record is paused" phone notice in
/// step with the pause switch and the people on Auto-record. It listens to the ONE pause port
/// (`RulesWiring.pausePort`) and to the rule store's changes, and runs once at start (app open) and on every app
/// resume, so a notice the user swiped away (Android 14+ allows it for anything that is not a foreground service)
/// comes back the next time mmogo opens. Closing the app or [dispose] never removes the notice.
///
/// The rule ([pauseNoticeStep], table-tested):
///  - Auto-record screens off ([autoRecordUi] false, the dormant build): the notice goes; nothing else is done.
///  - Not paused: the notice goes.
///  - Paused and at least one person on Auto-record: the notice is (re)posted.
///  - Paused and nobody on Auto-record, details ON: PM Q1 (25-11) - Pause switches itself OFF, through the pause
///    port (so every pause control follows), and the notice goes. Otherwise the next person put on Auto-record
///    would be paused without knowing it.
///  - Paused and nobody visible because "Record receiver details" is OFF: the rules are only hidden (B-HIDE), so
///    the pause is KEPT (it must still hold when details come back ON); the notice goes.
///  - The people could not be counted cleanly (a read failed, or details changed while reading): nothing is
///    changed, neither the notice nor the pause (fail closed).
///
/// Resume from the shade (PauseActionReceiver.kt) writes the key with mmogo closed or in the background. On the
/// next resume this sync sees paused -> not paused and stores "not paused" again through the port, which fires the
/// port's change signal so the switch, the rows and the banners re-read.
///
/// Delete data removes the key directly and Read off is handled in Kotlin (FeatureHooks cancels the notice); the
/// wiring calls [recheck] after Delete data so the Dart side agrees at once. Installed by RulesWiring (I2).
library;

import 'dart:async';

import '../bridge/pause_notice_bridge.dart';
import '../ui/levels/hard_rule_copy.dart' show kHardPausedNoticeTitle, kHardResume;
import '../ui/levels/hard_rule_ports.dart' show HardRulePausePort, autoRecordUi;
import 'rule_model.dart';
import 'rule_store.dart';

// The phone's notification settings list the notice's channel by this name.
// WORDING-MISSING -> W2 (candidate: kHardPauseTitle "Pause all Auto-record", draft).
const String _kTodoPauseChannelName = '[PM to write: name of the paused notice in phone notification settings]';

/// What one sync pass does.
enum PauseNoticeStep {
  /// Post (or silently re-post) the notice.
  show,

  /// Remove the notice.
  cancel,

  /// PM Q1: switch Pause off (through the port), then remove the notice.
  autoOff,

  /// Change nothing (the people could not be counted cleanly).
  keep,
}

/// The rule. [autoPeople] = people on Auto-record, null when they could not be counted cleanly; [detailsOn] =
/// "Record receiver details" read as ON before AND after the count.
PauseNoticeStep pauseNoticeStep({
  required bool enabled,
  required bool paused,
  required int? autoPeople,
  required bool detailsOn,
}) {
  if (!enabled) return PauseNoticeStep.cancel;
  if (!paused) return PauseNoticeStep.cancel;
  if (autoPeople == null) return PauseNoticeStep.keep;
  if (autoPeople > 0) return PauseNoticeStep.show;
  return detailsOn ? PauseNoticeStep.autoOff : PauseNoticeStep.cancel;
}

class PauseNoticeSync {
  PauseNoticeSync({
    required HardRulePausePort pause,
    required RuleStore store,
    required PauseNoticeBridge bridge,
    required Future<bool> Function() detailsOn,
    bool Function()? enabled,
  })  : _pause = pause,
        _store = store,
        _bridge = bridge,
        _detailsOn = detailsOn,
        _enabled = enabled ?? (() => autoRecordUi);

  final HardRulePausePort _pause;
  final RuleStore _store;
  final PauseNoticeBridge _bridge;
  final Future<bool> Function() _detailsOn;
  final bool Function() _enabled;

  StreamSubscription<void>? _rules;
  bool _listening = false;
  bool _disposed = false;

  Future<void>? _running;
  bool _again = false;
  bool _resumeAsked = false;

  /// The pause as this sync last read it (null = not read yet in this run of the app).
  bool? _lastPaused;

  /// Starts listening and runs once (app open). Safe to call twice.
  Future<void> start() {
    if (_disposed) return Future<void>.value();
    if (!_listening) {
      _listening = true;
      _pause.changes.addListener(_onChange);
      _rules = _store.changes.listen((_) => _onChange());
    }
    return recheck();
  }

  /// The app came back to the front: re-read everything, re-post a swiped notice, follow a shade Resume.
  Future<void> resumed() => _kick(resume: true);

  /// Re-reads everything and acts (after Delete data, or any time).
  Future<void> recheck() => _kick();

  /// Stops listening. Leaves the notice as it is (it must stay while mmogo is closed).
  void dispose() {
    _disposed = true;
    if (_listening) {
      _pause.changes.removeListener(_onChange);
      _listening = false;
    }
    unawaited(_rules?.cancel());
    _rules = null;
  }

  void _onChange() => unawaited(_kick());

  /// One pass at a time; a request during a pass runs one more pass after it (coalesced).
  Future<void> _kick({bool resume = false}) {
    if (_disposed) return Future<void>.value();
    if (resume) _resumeAsked = true;
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _running = _loop();
    return run;
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        final resume = _resumeAsked;
        _resumeAsked = false;
        await _once(resume: resume);
      } while (_again && !_disposed);
    } finally {
      _running = null;
    }
  }

  Future<void> _once({required bool resume}) async {
    try {
      if (!_enabled()) {
        await _bridge.cancel();
        return;
      }
      final paused = await _pause.isPaused(); // fail closed: doubt reads as paused
      final before = _lastPaused;
      _lastPaused = paused;
      if (resume && before == true && !paused) {
        // Resumed from the shade while mmogo was away: store "not paused" again THROUGH the port, so every
        // pause control re-reads (the port fires its change signal; the value is the same, so nothing changes).
        await _pause.setPaused(false);
      }

      int? autoPeople;
      var detailsOn = false;
      try {
        final on1 = await _detailsOn();
        final rules = await _store.all();
        final on2 = await _detailsOn();
        if (on1 == on2) {
          detailsOn = on1;
          autoPeople = rules.where((r) => r.level == RuleLevel.autoRecord).length;
        }
      } catch (_) {
        autoPeople = null;
      }

      switch (pauseNoticeStep(enabled: true, paused: paused, autoPeople: autoPeople, detailsOn: detailsOn)) {
        case PauseNoticeStep.show:
          await _bridge.show(title: kHardPausedNoticeTitle, resume: kHardResume, channelName: _kTodoPauseChannelName);
        case PauseNoticeStep.cancel:
          await _bridge.cancel();
        case PauseNoticeStep.autoOff:
          if (await _pause.setPaused(false)) _lastPaused = false;
          await _bridge.cancel();
        case PauseNoticeStep.keep:
          break;
      }
    } catch (_) {
      // A sync pass never throws; the next change, resume or open tries again.
    }
  }
}
