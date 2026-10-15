// A Timer that never runs by itself: the test fires it by hand. Used for the
// 10 s "slow" marker so no test waits in real time.
import 'dart:async';

class FakeTimer implements Timer {
  FakeTimer(this.after, this._callback);

  final Duration after;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled) return;
    fired = true;
    _callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;
}
