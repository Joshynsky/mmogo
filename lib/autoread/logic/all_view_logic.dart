/// §AUTOREAD.ALLVIEW - the number on the To do chip.
library;

import '../model/waiting_item.dart';
import 'waiting_logic.dart';

/// The To do chip number: To parse + To categorize (the two bell numbers added).
/// Could not read is left out ON PURPOSE (it is the "unreadable" rule above; pinned by test).
/// News and the trail are not in it. 0.2.1: the "N withdrawals need a decision" item counts as
/// ONE (as in the To categorize heading): pass [undecidedWithdrawals], the number waiting.
///
/// 0.2.1 rules: an Ask first row is a waiting item, so it is already in To categorize; each "Ask first
/// next time?" offer counts as ONE more ([offers]).
int todoCount(Iterable<WaitingItem> waiting, DateTime now, {int undecidedWithdrawals = 0, int offers = 0}) =>
    parseCount(waiting, now) + categorizeCount(waiting, now) + (undecidedWithdrawals > 0 ? 1 : 0) + offers;
