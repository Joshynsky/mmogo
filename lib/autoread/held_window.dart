/// §AUTOREAD.HELD — how long a waiting auto-read item is kept, in ONE place.
///
/// Judge condition 3 (18-10-2026): the window is one constant; expiry is
/// checked on receive and on launch (not by a timer); an expired item counts as
/// gone on every read, even if its file still exists. The user-facing copy is
/// built from the constant so the two cannot disagree.
library;

/// The held window. Nothing else in the code names a number of hours.
const Duration kHeldWindow = Duration(hours: 24);

/// How far in the future a `heldAt` may be before clock skew counts as gone.
const Duration kHeldClockSkew = Duration(minutes: 5);

/// True when the item is gone: held for the whole [window] or longer, or
/// stamped in the future by more than [kHeldClockSkew] (a clock that was set
/// back must never keep an item alive).
bool heldExpired(DateTime heldAt, DateTime now, {Duration window = kHeldWindow}) {
  final age = now.difference(heldAt);
  if (age >= window) return true;
  if (-age > kHeldClockSkew) return true;
  return false;
}

/// The user-visible sentence for a held window. The hour count comes from
/// [window]; do not type it anywhere else.
String heldWindowCopy([Duration window = kHeldWindow]) {
  final h = window.inHours;
  final unit = h == 1 ? 'hour' : 'hours';
  return 'Kept up to $h $unit, removed the next time mmogo runs after that.';
}

/// [heldWindowCopy] for [kHeldWindow].
final String kHeldWindowCopy = heldWindowCopy();
