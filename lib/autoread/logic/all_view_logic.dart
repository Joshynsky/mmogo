/// §AUTOREAD.ALLVIEW - the number on the To do chip.
library;

import '../model/waiting_item.dart';
import 'waiting_logic.dart';

/// The To do chip number: To parse + To categorize (the two bell numbers added).
/// News, Could not read and the trail are not in it.
int todoCount(Iterable<WaitingItem> waiting, DateTime now) =>
    parseCount(waiting, now) + categorizeCount(waiting, now);
