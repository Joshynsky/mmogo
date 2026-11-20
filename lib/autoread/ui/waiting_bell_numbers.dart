/// §AUTOREAD.BELL_NUMBERS — the two waiting numbers the bell shows, from the
/// waiting repository. Pill = waiting for a category; diamond = ready to
/// parse (readable ready items only, as the Parse chip counts them).
///
/// 0.2.1: the ONE "N withdrawals need a decision" item adds ONE to the pill
/// whenever at least one withdrawal is undecided (the same rule as the To do chip).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show Listenable, ValueListenable;

import '../../data/db/analytics_dao.dart' show AnalyticsTransactionRow;
import '../../ui/shell/bell_counts.dart';
import '../logic/waiting_logic.dart';
import '../model/waiting_item.dart';
import '../model/waiting_repository.dart';

/// [undecided] is the live list of undecided withdrawals (null = none, as before 0.2.1). A change
/// of either source emits again.
///
/// 0.2.1 rules: [offers] is the live "Ask first next time?" offers; each one adds ONE to the pill (the
/// same rule as the To do chip). An Ask first row is a waiting item and is already counted.
Stream<WaitingBellNumbers> waitingBellNumbers(
  AutoReadWaitingRepository repo,
  DateTime Function() now, {
  ValueListenable<List<AnalyticsTransactionRow>>? undecided,
  Listenable? offersChanged,
  int Function()? offerCount,
}) {
  if (undecided == null && offersChanged == null) {
    return repo.watch().map((items) => _numbers(items, now(), 0, 0));
  }
  late StreamController<WaitingBellNumbers> c;
  StreamSubscription<List<WaitingItem>>? sub;
  List<WaitingItem>? items;
  void emit() {
    if (items != null && !c.isClosed) c.add(_numbers(items!, now(), undecided?.value.length ?? 0, offerCount?.call() ?? 0));
  }

  c = StreamController<WaitingBellNumbers>(
    onListen: () {
      sub = repo.watch().listen((v) {
        items = v;
        emit();
      }, onError: c.addError);
      undecided?.addListener(emit);
      offersChanged?.addListener(emit);
    },
    onCancel: () {
      undecided?.removeListener(emit);
      offersChanged?.removeListener(emit);
      return sub?.cancel();
    },
  );
  return c.stream;
}

WaitingBellNumbers _numbers(List<WaitingItem> items, DateTime t, int undecided, int offers) =>
    WaitingBellNumbers(categorizeCount(items, t) + (undecided > 0 ? 1 : 0) + offers, parseCount(items, t));
