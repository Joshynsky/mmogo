import 'dart:async';

import 'restore_types.dart';

/// Makes a timer. Tests pass one they can fire by hand (no real waiting).
typedef RestoreTimerFactory = Timer Function(Duration after, void Function() fire);

/// §DATA.RESTORE.STEPS — 0.1.2 S10a (BP2). Turns the fixed steps of a restore
/// into real events for the progress list: `started`, then `done` or `failed`,
/// and `slow` once if a step is still running after [slowAfter] (10 s). The
/// callback is the UI's; it can never break a restore (a throw is ignored).
class RestoreStepReporter {
  RestoreStepReporter(
    this._onStep, {
    this.slowAfter = const Duration(seconds: 10),
    RestoreTimerFactory? timer,
  }) : _timer = timer ?? Timer.new;

  final void Function(RestoreStepEvent event)? _onStep;
  final Duration slowAfter;
  final RestoreTimerFactory _timer;

  void _emit(RestoreStep step, RestoreStepPhase phase) {
    try {
      _onStep?.call(RestoreStepEvent(step, phase));
    } catch (_) {}
  }

  /// Runs [body] as [step].
  Future<T> run<T>(RestoreStep step, Future<T> Function() body) async {
    _emit(step, RestoreStepPhase.started);
    final slow = _timer(slowAfter, () => _emit(step, RestoreStepPhase.slow));
    try {
      final r = await body();
      _emit(step, RestoreStepPhase.done);
      return r;
    } catch (_) {
      _emit(step, RestoreStepPhase.failed);
      rethrow;
    } finally {
      slow.cancel();
    }
  }
}
