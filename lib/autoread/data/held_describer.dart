/// §AUTOREAD.HELD_DESCRIBER - the in-memory descriptions of held messages.
///
/// One look per held id per page visit ([describe]); the answer, including "no
/// description", is kept in a map in memory and nowhere else: no preferences,
/// file, database, backup, clipboard or log, and nothing is sent back to the
/// phone side. The look runs through [runLocked] (the repository's queue) so a
/// Parse can never find the message claimed by a look. A look that fails, is
/// busy, gone or ignored gives null and the row keeps its plain title.
///
/// The map is emptied by [clear] (page closed, app hidden, Delete data) and
/// [sync] drops every id that left the list or changed kind (Parse, Remove,
/// expiry). Nothing in here prints or builds an error from a message.
library;

import '../logic/held_describe.dart';
import '../model/held_description.dart';
import '../model/waiting_item.dart';
import '../service/autoread_service.dart';

class HeldDescriber {
  HeldDescriber({
    required AutoReadService service,
    required Future<HeldDescription?> Function(Future<HeldDescription?> Function() body) runLocked,
    required WaitingKind? Function(String id) kindOf,
  })  : _service = service,
        _runLocked = runLocked,
        _kindOf = kindOf;

  final AutoReadService _service;
  final Future<HeldDescription?> Function(Future<HeldDescription?> Function() body) _runLocked;

  /// The kind the list holds for [id] now, or null when it is not listed.
  final WaitingKind? Function(String id) _kindOf;

  final Map<String, Future<HeldDescription?>> _looks = {};
  final Map<String, WaitingKind> _kinds = {};
  int _epoch = 0;

  /// How many ids hold an answer (tests and the leave-the-list rule).
  int get cachedCount => _looks.length;

  /// The description of held message [id], or null. At most one look per id
  /// until [clear] or until the id leaves the list or changes kind.
  Future<HeldDescription?> describe(String id) {
    final kind = _kindOf(id);
    if (kind != WaitingKind.readyToParse && kind != WaitingKind.unreadable) return Future.value(null);
    final epoch = _epoch;
    return _looks.putIfAbsent(id, () {
      _kinds[id] = kind!;
      return _runLocked(() => _look(id, epoch)).catchError((_) => null);
    });
  }

  Future<HeldDescription?> _look(String id, int epoch) async {
    // Still listed, still the same kind, and not cleared while this waited.
    if (epoch != _epoch || _kindOf(id) != _kinds[id]) return null;
    final look = await _service.lookForDetails(id);
    if (epoch != _epoch) return null;
    switch (look.look) {
      case HeldLook.readable:
        final f = look.fields;
        if (f == null) return null;
        return HeldDescription(what: describeReadable(f));
      case HeldLook.unreadable:
        final l = look.light;
        return (l == null || l.isEmpty) ? null : l;
      case HeldLook.gone:
      case HeldLook.duplicate:
      case HeldLook.busy:
      case HeldLook.ignored:
        return null;
    }
  }

  /// Forgets every answer (page closed, app hidden, Delete data).
  void clear() {
    _epoch++;
    _looks.clear();
    _kinds.clear();
  }

  /// Drops each id that is no longer in [now] or whose kind changed.
  void sync(Map<String, WaitingKind> now) {
    for (final id in _looks.keys.toList()) {
      if (now[id] != _kinds[id]) {
        _looks.remove(id);
        _kinds.remove(id);
      }
    }
  }
}
