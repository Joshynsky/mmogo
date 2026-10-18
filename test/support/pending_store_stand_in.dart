// TEMPORARY stand-in for the A3a store (slice A3b). The interface itself
// (StoreResult, PendingItemsStore) is a temporary copy at
// lib/autoread/data/pending_items_store.dart; the orchestrator swaps both for
// the real A3a files. This file holds only the in-memory implementation.
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';

class InMemoryPendingStore implements PendingItemsStore {
  InMemoryPendingStore({this.capacity = 200, int generation = 1}) : _generation = generation;

  final int capacity;
  int _generation;
  final List<WaitingItem> _items = [];

  /// Number of put calls that stored something (for no-second-write asserts).
  int writes = 0;

  @override
  Future<StoreResult> put(WaitingItem item, {required int generation}) async {
    if (generation != _generation) return StoreResult.staleGeneration;
    final code = item.parsed?.code;
    var flagged = false;
    if (code != null) {
      for (final e in _items) {
        if (e.parsed?.code != code) continue;
        if (e.parsed == item.parsed) return StoreResult.duplicate;
        flagged = true;
      }
    }
    if (_items.length >= capacity) return StoreResult.full;
    _items.add(WaitingItem(
      id: item.id,
      kind: item.kind,
      heldAt: item.heldAt,
      parsed: item.parsed,
      sameCodeDifferentDetails: flagged || item.sameCodeDifferentDetails,
    ));
    writes++;
    return flagged ? StoreResult.storedFlagged : StoreResult.stored;
  }

  @override
  Future<List<WaitingItem>> list() async => List.unmodifiable(_items);

  @override
  Future<void> remove(String id) async => _items.removeWhere((i) => i.id == id);

  @override
  Future<int> readGeneration() async => _generation;

  @override
  Future<int> bumpGeneration() async {
    _items.clear();
    return ++_generation;
  }

  @override
  Future<bool> containsCode(String displayCode) async =>
      _items.any((i) => i.parsed?.code == displayCode);

  @override
  Future<int> count() async => _items.length;
}
