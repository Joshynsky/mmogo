/// §AUTOREAD.BELL_NUMBERS — the two waiting numbers the bell shows, from the
/// waiting repository. Pill = waiting for a category; diamond = ready to
/// parse (readable ready items only, as the Parse chip counts them).
///
/// 0.2.1: the ONE "N withdrawals need a decision" item adds ONE to the pill
/// whenever at least one withdrawal is undecided (the same rule as the To do chip).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;

import '../../data/db/analytics_dao.dart' show AnalyticsTransactionRow;
import '../../ui/shell/bell_counts.dart';
import '../logic/waiting_logic.dart';
import '../model/waiting_item.dart';
import '../model/waiting_repository.dart';

/// [undecided] is the live list of undecided withdrawals (null = none, as before 0.2.1). A change
/// of either source emits again.
Stream<WaitingBellNumbers> waitingBellNumbers(
  AutoReadWaitingRepository repo,
  DateTime Function() now, {
  ValueListenable<List<AnalyticsTransactionRow>>? undecided,
}) {
  if (undecided == null) {
    return repo.watch().map((items) => _numbers(items, now(), 0));
  }
  late StreamController<WaitingBellNumbers> c;
  StreamSubscription<List<WaitingItem>>? sub;
  List<WaitingItem>? items;
  void emit() {
    if (items != null && !c.isClosed) c.add(_numbers(items!, now(), undecided.value.length));
  }

  c = StreamController<WaitingBellNumbers>(
    onListen: () {
      sub = repo.watch().listen((v) {
        items = v;
        emit();
      }, onError: c.addError);
      undecided.addListener(emit);
    },
    onCancel: () {
      undecided.removeListener(emit);
      return sub?.cancel();
    },
  );
  return c.stream;
}

WaitingBellNumbers _numbers(List<WaitingItem> items, DateTime t, int undecided) =>
    WaitingBellNumbers(categorizeCount(items, t) + (undecided > 0 ? 1 : 0), parseCount(items, t));
