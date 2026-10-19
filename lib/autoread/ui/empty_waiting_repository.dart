/// §AUTOREAD.EMPTY_WAITING — a waiting repository with nothing in it, placed
/// by `main.dart` until the integration slice supplies the real one.
library;

import '../model/waiting_item.dart';
import '../model/waiting_repository.dart';

class EmptyWaitingRepository implements AutoReadWaitingRepository {
  const EmptyWaitingRepository();

  @override
  Stream<List<WaitingItem>> watch() => Stream.value(const <WaitingItem>[]);

  @override
  Future<ParseOutcome> parse(String id) async => ParseOutcome.gone;

  @override
  Future<void> saveCategory(String id, String categoryId) async {}

  @override
  Future<void> remove(String id) async {}
}
