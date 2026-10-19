/// §AUTOREAD.BELL_NUMBERS — the two waiting numbers the bell shows, from the
/// waiting repository. Pill = waiting for a category; diamond = ready to
/// parse (readable ready items only, as the Parse chip counts them).
library;

import '../../ui/shell/bell_counts.dart';
import '../logic/waiting_logic.dart';
import '../model/waiting_repository.dart';

Stream<WaitingBellNumbers> waitingBellNumbers(AutoReadWaitingRepository repo, DateTime Function() now) =>
    repo.watch().map((items) {
      final t = now();
      return WaitingBellNumbers(categorizeCount(items, t), parseCount(items, t));
    });
