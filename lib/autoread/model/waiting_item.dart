/// §AUTOREAD.WAITING — one waiting auto-read item (pure Dart, no widgets).
///
/// Lives under `lib/autoread/` so the standard build drops it. It reuses the
/// existing parser result type ([ParsedSmsFields]); there is no second money
/// type or second parser result.
library;

import '../../domain/parsing/parsed_sms_fields.dart';
import '../held_window.dart';

/// What state a waiting item is in, as stored.
///
/// - [readyToParse]: a held M-Pesa message nobody has parsed yet.
/// - [waitingCategory]: parsed, not yet categorized, not yet a ledger entry.
/// - [unreadable]: the held message could not be read; the user can paste it.
/// - [gone]: the held message is no longer available; the user can paste it.
enum WaitingKind { readyToParse, waitingCategory, unreadable, gone }

final RegExp _heldIdPattern = RegExp(r'^[0-9a-f]{32}$');

/// True for a valid held id: exactly 32 lowercase hex characters. Judge
/// condition 3: validate before any file access.
bool isValidHeldId(String id) => _heldIdPattern.hasMatch(id);

class WaitingItem {
  /// 32 lowercase hex characters; checked by [isValidHeldId].
  final String id;
  final WaitingKind kind;

  /// When the message was held (readyToParse, unreadable, gone) or, for a
  /// waiting-category row, when it was received.
  final DateTime heldAt;

  /// The parsed fields. Required for [WaitingKind.waitingCategory]; null for
  /// the other kinds (nothing was read).
  final ParsedSmsFields? parsed;

  /// The same M-Pesa code is already held or saved with different fields.
  /// Both are kept and this one is flagged ("same code, different details").
  final bool sameCodeDifferentDetails;

  WaitingItem({
    required this.id,
    required this.kind,
    required this.heldAt,
    this.parsed,
    this.sameCodeDifferentDetails = false,
  }) {
    if (!isValidHeldId(id)) {
      throw ArgumentError.value(id, 'id', 'must be 32 lowercase hex characters');
    }
    if (kind == WaitingKind.waitingCategory && parsed == null) {
      throw ArgumentError.value(kind, 'kind', 'a waiting-category item needs parsed fields');
    }
  }

  /// When the held message runs out: [heldAt] plus [kHeldWindow]. Whether it
  /// has run out is decided by `heldExpired` (which also treats a skewed
  /// future [heldAt] as gone), never by comparing this value alone.
  DateTime get expiresAt => heldAt.add(kHeldWindow);

  /// True when [heldAt] says this item is past the held window at [now].
  bool isExpiredAt(DateTime now) => heldExpired(heldAt, now);

  @override
  String toString() => 'WaitingItem($id, $kind, heldAt: $heldAt)';
}
