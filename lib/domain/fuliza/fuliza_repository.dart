/// §DOMAIN.FULIZA.REPOSITORY — what the Fuliza ledger needs from storage
/// (0.2.0 slice 3). An interface plus an in-memory fake only: the real
/// `fuliza_events` table is a schema change and waits for the PM and the
/// Judge CRITICAL note (rules file, slice 12). Nothing here touches a database.
library;

enum FulizaEventKind { draw, repayFull, repayPartial }

/// One stored Fuliza message. The message text is never kept (privacy rule);
/// only these figures. [at] is the phone's receive time: a draw has no time of
/// its own in the text.
class FulizaEvent {
  const FulizaEvent({
    required this.kind,
    required this.code,
    required this.at,
    required this.amountCents,
    this.feeCents = 0,
    this.printedTotalCents,
  });

  final FulizaEventKind kind;
  final String code;
  final DateTime at;

  /// Draw amount, or the amount repaid.
  final int amountCents;

  /// Fee on a draw (Interest or Access Fee). 0 for repayments.
  final int feeCents;

  /// "Total Fuliza M-PESA outstanding amount" on a draw; null for repayments.
  final int? printedTotalCents;
}

abstract class FulizaRepository {
  /// Adds the event. Returns false (and stores nothing) when an event with the
  /// same (code, kind) is already there: the same message read twice. The
  /// check is on (code, kind), never on the code alone, because a draw shares
  /// its code with the ordinary payment it funded.
  Future<bool> addEvent(FulizaEvent event);

  /// Every stored event, in insertion order.
  Future<List<FulizaEvent>> events();

  /// Transaction codes of the ordinary payments saved or waiting. A draw pairs
  /// with one of these by code, in either arrival order, so the join is made
  /// at read time and nothing is linked at insert time.
  Future<Set<String>> paymentCodes();

  /// Last limit printed by a limit notice or a repayment, or null.
  Future<int?> limitCents();
  Future<void> setLimitCents(int cents);
}

/// The fake used by tests and by the UI slice until the real table exists.
class InMemoryFulizaRepository implements FulizaRepository {
  final List<FulizaEvent> _events = [];
  final Set<String> _payments = {};
  int? _limit;

  /// Test/UI hook: an ordinary payment with this code now exists.
  void addPaymentCode(String code) => _payments.add(code);

  @override
  Future<bool> addEvent(FulizaEvent event) async {
    final dup = _events.any((e) => e.code == event.code && e.kind == event.kind);
    if (dup) return false;
    _events.add(event);
    return true;
  }

  @override
  Future<List<FulizaEvent>> events() async => List.unmodifiable(_events);

  @override
  Future<Set<String>> paymentCodes() async => Set.unmodifiable(_payments);

  @override
  Future<int?> limitCents() async => _limit;

  @override
  Future<void> setLimitCents(int cents) async => _limit = cents;
}
