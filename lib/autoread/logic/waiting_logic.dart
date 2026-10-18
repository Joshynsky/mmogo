/// §AUTOREAD.WAITING.LOGIC — pure sort, count and expiry rules for waiting
/// items. Every function takes `now`; nothing reads the clock.
library;

import '../held_window.dart';
import '../model/waiting_item.dart';

/// The kind an item really has at [now].
///
/// A held message (ready, unreadable) past the held window is [WaitingKind.gone]
/// even if its file still exists (Judge condition 3); a skewed-future `heldAt`
/// counts as gone too (via `heldExpired`).
///
/// A [WaitingKind.waitingCategory] row is already parsed and is never turned
/// into gone by age: records are never discarded in 0.1.2 (signed mock notes).
/// If the orchestrator wants the literal "anything past the window", change
/// [_expiresWithAge] only.
WaitingKind effectiveKind(WaitingItem item, DateTime now) {
  if (item.kind == WaitingKind.gone) return WaitingKind.gone;
  if (_expiresWithAge(item.kind) && heldExpired(item.heldAt, now)) {
    return WaitingKind.gone;
  }
  return item.kind;
}

bool _expiresWithAge(WaitingKind k) => k != WaitingKind.waitingCategory;

bool _isParseGroup(WaitingKind k) =>
    k == WaitingKind.readyToParse || k == WaitingKind.unreadable || k == WaitingKind.gone;

/// The to-parse group (stored kind ready, unreadable or gone), ordered:
/// readable ready items first, expiring soonest first; then unreadable and
/// gone rows last (oldest first). Waiting-category items are left out.
List<WaitingItem> sortReadyToParse(Iterable<WaitingItem> items, DateTime now) {
  final list = items.where((i) => _isParseGroup(i.kind)).toList();
  int rank(WaitingItem i) => effectiveKind(i, now) == WaitingKind.readyToParse ? 0 : 1;
  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final t = a.expiresAt.compareTo(b.expiresAt);
    if (t != 0) return t;
    return a.id.compareTo(b.id);
  });
  return list;
}

/// The to-categorize group, newest transaction first. The transaction time is
/// the parsed `transactionOccurredAt`; [WaitingItem.heldAt] is the fallback.
List<WaitingItem> sortWaitingCategory(Iterable<WaitingItem> items, DateTime now) {
  final list = items.where((i) => i.kind == WaitingKind.waitingCategory).toList();
  int when(WaitingItem i) =>
      i.parsed?.transactionOccurredAt ?? i.heldAt.millisecondsSinceEpoch;
  list.sort((a, b) {
    final t = when(b).compareTo(when(a));
    return t != 0 ? t : a.id.compareTo(b.id);
  });
  return list;
}

/// Parse chip count: readable ready items only (gone and unreadable are not
/// counted).
int parseCount(Iterable<WaitingItem> items, DateTime now) =>
    items.where((i) => effectiveKind(i, now) == WaitingKind.readyToParse).length;

/// Categorize chip count: waiting-category items only.
int categorizeCount(Iterable<WaitingItem> items, DateTime now) =>
    items.where((i) => effectiveKind(i, now) == WaitingKind.waitingCategory).length;

/// Whole hours left before the held message runs out, rounded UP (the mock's
/// "expires in N h"): 0 when it has already run out or is not a held message.
/// Use [expiresUnderOneHour] to word the last hour as "under 1 h".
int expiresInHours(WaitingItem item, DateTime now) {
  final left = _remaining(item, now);
  if (left == null || left <= Duration.zero) return 0;
  return (left.inMinutes + 59) ~/ 60;
}

/// True when a readable ready item has less than one hour left.
bool expiresUnderOneHour(WaitingItem item, DateTime now) {
  final left = _remaining(item, now);
  return left != null && left > Duration.zero && left < const Duration(hours: 1);
}

Duration? _remaining(WaitingItem item, DateTime now) {
  if (effectiveKind(item, now) != WaitingKind.readyToParse) return null;
  return item.expiresAt.difference(now);
}
