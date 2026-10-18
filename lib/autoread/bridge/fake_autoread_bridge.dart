/// In-memory [AutoReadBridge] for tests. Same rules as the real one: an expired
/// item (per `heldExpired`) reads as null, an invalid id reads as null, and a
/// claim is exclusive until ack or release.
library;

import '../../autoread/held_window.dart';
import '../model/waiting_item.dart';
import 'autoread_bridge.dart';

class FakeAutoReadBridge implements AutoReadBridge {
  FakeAutoReadBridge({required DateTime Function() now, int generation = 1})
      : _now = now,
        _generation = generation;

  final DateTime Function() _now;
  int _generation;
  final Map<String, HeldMessage> _held = {};
  final Set<String> _claimed = {};

  /// Every call made, as `method:id`, for assertions (never holds a body).
  final List<String> calls = [];

  /// When set, [ackHeld] throws it (crash simulation).
  Object? ackError;

  /// When set, [peekHeld] waits for it before answering (concurrency tests).
  Future<void>? peekGate;

  /// Test helper: hold a message.
  void hold(String id, String body, DateTime heldAt) {
    _held[id] = HeldMessage(id: id, body: body, heldAt: heldAt);
  }

  bool isHeld(String id) => _held.containsKey(id);
  bool isClaimed(String id) => _claimed.contains(id);
  set generation(int g) => _generation = g;

  @override
  Future<HeldMessage?> peekHeld(String id) async {
    calls.add('peekHeld:$id');
    final gate = peekGate;
    if (gate != null) await gate;
    if (!isValidHeldId(id)) return null;
    final m = _held[id];
    if (m == null) return null;
    if (heldExpired(m.heldAt, _now())) return null;
    return m;
  }

  @override
  Future<bool> claim(String id) async {
    calls.add('claim:$id');
    if (!isValidHeldId(id)) return false;
    return _claimed.add(id);
  }

  @override
  Future<void> release(String id) async {
    calls.add('release:$id');
    _claimed.remove(id);
  }

  @override
  Future<void> ackHeld(String id, {required int generation}) async {
    calls.add('ackHeld:$id');
    final e = ackError;
    if (e != null) throw e;
    if (generation != _generation) return;
    _held.remove(id);
    _claimed.remove(id);
  }

  @override
  Future<List<String>> listHeldIds() async {
    calls.add('listHeldIds');
    final now = _now();
    return [
      for (final m in _held.values)
        if (!heldExpired(m.heldAt, now)) m.id
    ];
  }

  @override
  Future<int> readGeneration() async {
    calls.add('readGeneration');
    return _generation;
  }
}
