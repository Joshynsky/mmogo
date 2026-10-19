/// §AUTOREAD.INGESTING_LAUNCH_SOURCE — wraps the launch source so a notification
/// tap first makes the waiting repository look at what is held, THEN reaches the
/// launch router. Without it the router would look for the tapped id in a list
/// that does not know the new message yet.
library;

import '../ui/launch_router.dart';
import 'real_waiting_repository.dart';

class IngestingLaunchSource implements AutoReadLaunchSource {
  IngestingLaunchSource(this._inner, this._repo);

  final AutoReadLaunchSource _inner;
  final RealWaitingRepository _repo;

  @override
  Future<String?> takeLaunchId() => _inner.takeLaunchId();

  @override
  Stream<String> get tapped => _inner.tapped.asyncMap((id) async {
        try {
          await _repo.ingest();
        } catch (_) {
          // The router falls back to Categorize.
        }
        return id;
      });
}
