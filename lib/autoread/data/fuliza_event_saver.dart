/// §AUTOREAD.FULIZA_EVENT_SAVER — 0.2.0 S12 slice D. Turns one held message
/// body into at most one stored Fuliza event, before the body is dropped.
///
/// Only the exact wording of [FulizaParser] writes anything (a draw or a
/// repayment); adverts, refusals, notices and any other text write nothing
/// (a limit notice or a repayment's available limit only updates the limit,
/// as [FulizaLedger.ingest] does). The body is never stored or logged. A
/// repeat of the same (kind, code) adds nothing (the repository says false).
/// [save] never throws: a failure just means the event is not saved.
library;


import '../../domain/fuliza/fuliza_ledger.dart';
import '../../domain/fuliza/fuliza_repository.dart';
import '../../domain/parsing/fuliza_parser.dart';

class FulizaEventSaver {
  FulizaEventSaver(this._repo);

  /// The repository to write to, looked up on each save (the database may not
  /// be open yet when the saver is built).
  final Future<FulizaRepository> Function() _repo;

  /// True when a new event was stored. [at] is the time the message was held.
  Future<bool> save(String body, DateTime at) async {
    try {
      final m = FulizaParser.parse(body);
      if (m is FulizaUnrecognised) return false;
      return await FulizaLedger(await _repo()).ingest(m, at);
    } catch (_) {
      return false;
    }
  }
}
