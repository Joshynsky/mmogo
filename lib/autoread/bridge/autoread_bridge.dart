/// §AUTOREAD.BRIDGE — the Dart side of the hand-off from the Kotlin held store.
///
/// This is an INTERFACE only. The real MethodChannel implementation comes after
/// the Kotlin slices; until then the existing Kotlin `AutoReadBridge` answers
/// notImplemented and tests use `FakeAutoReadBridge`.
library;

/// One held message, as handed across the bridge.
///
/// [body] is the raw SMS text. It must NEVER be logged, printed, put in an
/// exception message, or stored anywhere (not in a field of a longer-lived
/// object, a file, preferences or a database). It crosses to Dart once, through
/// [AutoReadBridge.peekHeld], is parsed, and is dropped.
class HeldMessage {
  final String id;
  final String body;
  final DateTime heldAt;

  const HeldMessage({required this.id, required this.body, required this.heldAt});

  /// Never includes [body].
  @override
  String toString() => 'HeldMessage($id, heldAt: $heldAt)';
}

abstract class AutoReadBridge {
  /// The held message [id], or null when the id is invalid, missing or expired.
  /// The raw body crosses to Dart ONCE, through this call.
  Future<HeldMessage?> peekHeld(String id);

  /// Per-id in-flight guard. True when the caller now owns [id]; false when it
  /// is already claimed. A claim is released by [ackHeld] or [release].
  Future<bool> claim(String id);

  /// Releases a claim without deleting the held message (a parse that did not
  /// finish leaves the message held).
  Future<void> release(String id);

  /// Deletes the held message [id], called only after the Dart write was read
  /// back. Also releases the claim. [generation] is the store generation the
  /// write was made under.
  Future<void> ackHeld(String id, {required int generation});

  /// The ids of all held messages that have not expired.
  Future<List<String>> listHeldIds();

  /// The current generation (bumped when the held store is wiped).
  Future<int> readGeneration();
}
