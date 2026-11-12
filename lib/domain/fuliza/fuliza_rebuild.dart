/// §DOMAIN.FULIZA.REBUILD — 0.2.0 S12 slice C. "Rebuild from my messages".
///
/// Rule (Judge C5): Rebuild only ADDS events. It relies on `FulizaRepository.addEvent` returning false for a
/// (kind, code) that is already stored, so running it twice adds nothing the second time, and it never
/// deletes a stored event. It can only use messages mmogo still holds.
///
/// The hook is set by the parse-path slice (it re-reads the held messages and calls `addEvent` for each
/// Fuliza message) and returns how many events it ADDED. No hook = nothing to read = 0.
class FulizaRebuild {
  FulizaRebuild._();

  /// Re-reads the held messages; returns the number of events added. Null in a build with no reader.
  static Future<int> Function()? hook;

  /// Number of events added. Never throws: a failing hook counts as 0 added.
  static Future<int> run() async {
    final h = hook;
    if (h == null) return 0;
    try {
      final n = await h();
      return n < 0 ? 0 : n;
    } catch (_) {
      return 0;
    }
  }
}
