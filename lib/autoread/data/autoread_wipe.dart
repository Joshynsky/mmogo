/// §AUTOREAD.WIPE — what Delete data does for auto-read (Judge condition 7: a
/// superset of Off). Runs inside the ordered Delete data steps through the
/// device-wipe hook of `ResetEnv`; the standard build never installs it.
///
/// In order: Read off (the receiver is disabled and the platform switch is
/// cleared), every held message and waiting item removed (the notifications go
/// with them), the consent answer removed, then everything read back: off, no
/// held message, no waiting key, no consent key. Any doubt is `false`, which
/// Delete data reports as "did not finish" (fail closed). Only after the
/// read-back is the on-screen list refreshed.
///
/// Nothing here reads a message: counts and flags only. Autoread flavor only.
library;

import '../logic/reading_controller.dart';

class AutoReadWipe {
  AutoReadWipe({
    ReadingController? Function()? controller,
    ReadingPrefs? prefs,
    this.refresh,
  })  : _controller = controller ?? (() => ReadingControllerHolder.instance),
        _prefs = prefs ?? SharedReadingPrefs();

  final ReadingController? Function() _controller;
  final ReadingPrefs _prefs;

  /// Called after a verified wipe so the in-memory rows are rebuilt (the real
  /// waiting repository's `ingest`). A failure here is not a failed wipe: the
  /// data is already gone and the next start or resume looks again.
  final Future<void> Function()? refresh;

  Future<bool> run() async {
    final c = _controller();
    if (c == null) return false; // cannot prove anything: fail closed
    try {
      if (await c.turnOff() != TurnOffResult.off) return false;
      if (!await c.deleteHeld()) return false;
      await _prefs.remove(kReadingConsentKey);
      if ((await _prefs.keys()).contains(kReadingConsentKey)) return false;
      final s = await c.state();
      if (!s.available || s.on || s.heldCount != 0) return false;
    } catch (_) {
      return false;
    }
    try {
      await refresh?.call();
    } catch (_) {}
    return true;
  }
}
