/// §DATA.MAINTENANCE.GATE — one in-process mutex for the operations that
/// rewrite the whole database or the whole device state: restore, undo of a
/// restore, Delete my transactions, Reset app. A second one that arrives
/// while the first runs is refused (the caller reports "busy"), never queued.
///
/// Take it with [tryAcquire] and release it in a `finally`.
class DataOpGate {
  DataOpGate();

  /// The one the app uses. Tests build their own.
  static final DataOpGate instance = DataOpGate();

  bool _held = false;

  bool get isHeld => _held;

  /// True when the caller now holds the gate.
  bool tryAcquire() {
    if (_held) return false;
    _held = true;
    return true;
  }

  /// Releases the gate (a no-op when it is free).
  void release() => _held = false;
}
