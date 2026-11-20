/// The background Parse's store: it forwards everything to the real [PendingItemsStore], and on `put` first
/// asks the [RuleLabeler] for a hint and stores the item with it. This is how the background only LABELS an
/// item: no new write path, no interface change, no database. A labelling failure stores the item unlabelled.
///
/// Also: [UndoneCodeLookup] makes a message whose M-Pesa code the user already undid (24 h list) count as a
/// duplicate, so it is not offered again.
library;

import '../data/pending_items_store.dart';
import '../history/rule_labeler.dart';
import '../model/waiting_item.dart';
import '../rules/undone_codes.dart';
import '../service/autoread_service.dart';

class LabellingPendingStore implements PendingItemsStore {
  LabellingPendingStore(this._inner, this._labeler);

  final PendingItemsStore _inner;
  final RuleLabeler _labeler;

  @override
  Future<StoreResult> put(WaitingItem item, {required int generation}) async {
    var toStore = item;
    final parsed = item.parsed;
    if (parsed != null && item.hint == null) {
      try {
        final hint = await _labeler.label(parsed);
        if (hint != null) {
          toStore = WaitingItem(
            id: item.id,
            kind: item.kind,
            heldAt: item.heldAt,
            parsed: parsed,
            sameCodeDifferentDetails: item.sameCodeDifferentDetails,
            hint: hint,
          );
        }
      } catch (_) {}
    }
    return _inner.put(toStore, generation: generation);
  }

  @override
  Future<List<WaitingItem>> list() => _inner.list();

  @override
  Future<void> remove(String id) => _inner.remove(id);

  @override
  Future<int> readGeneration() => _inner.readGeneration();

  @override
  Future<int> bumpGeneration() => _inner.bumpGeneration();

  @override
  Future<bool> containsCode(String displayCode) => _inner.containsCode(displayCode);

  @override
  Future<int> count() => _inner.count();
}

/// A [CodeLookup] that answers true for a code in the undone list (unexpired) and false otherwise. A lookup
/// failure answers false (the item is then offered normally).
class UndoneCodeLookup implements CodeLookup {
  const UndoneCodeLookup(this._undone, this._now);
  final UndoneCodes _undone;
  final DateTime Function() _now;

  @override
  Future<bool> contains(String displayCode) async {
    try {
      return await _undone.contains(displayCode, now: _now());
    } catch (_) {
      return false;
    }
  }
}
