/// §AUTOREAD.AIRTIME_AUTO — Airtime recorded without the Categorize tap
/// (the switches live in Settings > Remembered > Recorded automatically).
/// Pure Dart plus one small observable ([AirtimeAutoController]); no widgets.
///
/// Rules: Airtime only; ONE preference, default OFF; the user still taps
/// Parse; each entry has an Undo (moves it to Recently deleted) and a visible
/// trail row. Stored: the preference, the ledger entry, and for 24 hours the
/// trail's row numbers and times (one preference, `kAirtimeTrailPrefKey`; see
/// `data/airtime_trail_store.dart`).
library;

import 'package:flutter/foundation.dart';

import '../../data/maintenance/device_keys.dart' show kAirtimeTrailPrefsKey;
import '../../domain/airtime/airtime_kind.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../model/waiting_item.dart';

/// `shared_preferences` key of the one preference. NOT in the backup key table
/// (`backup_setting_keys.dart`), so a backup file can never turn it on.
/// Existing key: auto-record for airtime bought FOR MYSELF only (people who opted
/// in when only that kind existed; their consent does not extend to the other kind).
const String kAirtimeAutoPrefKey = 'autoread_airtime_auto_record';

/// Second key: auto-record for airtime bought FOR ANOTHER NUMBER.
/// Default OFF. Also outside the backup table.
const String kAirtimeAutoOtherPrefKey = 'autoread_airtime_auto_record_other';

/// Third key: the 24 h "Recorded automatically" trail, `[[rowId, atMs], ...]`
/// and nothing else. NOT in the backup key table, never read from a restore
/// file. The same string as `kAirtimeTrailPrefsKey` (`device_keys.dart`, which
/// the standard build also compiles for Delete data and Restore).
const String kAirtimeTrailPrefKey = kAirtimeTrailPrefsKey;

/// How long an entry stays on the trail, counted from its own recording time.
const Duration kTrailWindow = Duration(hours: 24);

/// The most entries the trail keeps (the newest).
const int kTrailMaxEntries = 200;

/// True when an entry recorded at [at] is no longer shown at [now]: an age of
/// 24 h or more, or a time later than [now] (zero tolerance for a clock that
/// moved back).
bool trailExpired(DateTime at, DateTime now) => at.isAfter(now) || now.difference(at) >= kTrailWindow;

/// True for a parsed Airtime item that waits for a category: the only kind this
/// feature may ever record.
bool isParsedAirtime(WaitingItem item) =>
    item.kind == WaitingKind.waitingCategory && item.parsed?.sourceType == SmsSourceType.airtime;

/// True when [item] is a parsed Airtime item AND the switch for its own kind is
/// ON ([myselfOn] for a plain purchase, [otherOn] for `for <number>`): the only
/// items auto-record may ever write.
bool isAutoRecordEligible(WaitingItem item, {required bool myselfOn, required bool otherOn}) =>
    isParsedAirtime(item) && (item.parsed!.airtimeOther ? otherOn : myselfOn);

/// How many stored items still wait for the user to pick a category. A parsed
/// airtime item whose own switch is ON is left out: it will be added by the
/// app on its own, so it is not waiting for anything from the user. With a
/// switch OFF the same item counts.
int waitingCategoryCount(Iterable<WaitingItem> items, {required bool myselfOn, required bool otherOn}) =>
    items.where((i) => !isAutoRecordEligible(i, myselfOn: myselfOn, otherOn: otherOn)).length;

/// The items the Notifications list, the bell and the chips show: every stored
/// item except parsed airtime that the app will add by itself (its own switch
/// is ON). [stuckIds] are ones the app tried and could not add; they stay
/// visible so they are never lost. One list feeds the rows and every number,
/// so they cannot disagree.
List<WaitingItem> visibleWaiting(
  Iterable<WaitingItem> items, {
  required bool myselfOn,
  required bool otherOn,
  Set<String> stuckIds = const {},
}) =>
    [
      for (final i in items)
        if (stuckIds.contains(i.id) || !isAutoRecordEligible(i, myselfOn: myselfOn, otherOn: otherOn)) i,
    ];

/// One trail row, built from the stored row number and time plus the ledger row.
class AutoRecorded {
  AutoRecorded({
    required this.rowId,
    required this.amountCents,
    required this.at,
    this.airtimeOther = false,
    this.inRecentlyDeleted = false,
  });

  /// The ledger row (`transactions.id`) that was written.
  final int rowId;
  final int amountCents;
  final DateTime at;

  /// Airtime bought for another number (false: for myself).
  final bool airtimeOther;

  /// The row has `deleted_at` set (Undo, or deleted from Home): it sits in
  /// Recently deleted. Read from the ledger, never stored.
  final bool inRecentlyDeleted;
}

/// What the Notifications page needs: the switch, the trail and two actions.
/// The repository owns the logic and calls the `_`-free setters below.
class AirtimeAutoController extends ChangeNotifier {
  AirtimeAutoController({
    required this.onSwitch,
    required this.onUndo,
    this.onSwitchOther,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Called when the user flips the switch for airtime for another number.
  final Future<void> Function(bool on)? onSwitchOther;

  /// Called when the user flips the switch.
  final Future<void> Function(bool on) onSwitch;

  /// Called when the user taps Undo on a trail row.
  final Future<void> Function(AutoRecorded entry) onUndo;

  bool _on = false;
  bool _onOther = false;
  List<AutoRecorded> _trail = [];
  int _recordedCount = 0;
  AutoRecorded? _lastRecorded;

  /// The switch for airtime bought for myself (the original switch).
  bool get on => _on;

  /// The switch for airtime bought for another number (default OFF).
  bool get onOther => _onOther;

  /// Entries still inside the 24 h window, oldest first. Expired ones are left
  /// out here even when the stored list was not purged.
  List<AutoRecorded> get trail {
    final t = _now();
    return List.unmodifiable([
      for (final e in _trail)
        if (!trailExpired(e.at, t)) e,
    ]);
  }

  /// Newest first, for display.
  List<AutoRecorded> get trailNewestFirst => trail.reversed.toList();

  /// How many entries the app has recorded since start. Only goes up, so a
  /// caller can tell "something was recorded during this call" without
  /// comparing list lengths (a capped, purged or reloaded list has no growth).
  int get recordedCount => _recordedCount;

  /// The entry recorded last (null before the first).
  AutoRecorded? get lastRecorded => _lastRecorded;

  void setOn(bool value) {
    if (_on == value) return;
    _on = value;
    notifyListeners();
  }

  void setOnOther(bool value) {
    if (_onOther == value) return;
    _onOther = value;
    notifyListeners();
  }

  /// Replaces the shown list (built from the stored list and the ledger).
  void setTrail(List<AutoRecorded> entries) {
    _trail = [...entries]..sort((a, b) => a.at.compareTo(b.at));
    notifyListeners();
  }

  /// Counts one recording (for the toast) without touching the list.
  void noteRecorded(AutoRecorded e) {
    _recordedCount++;
    _lastRecorded = e;
  }

  /// Shows [e] and counts it as recorded.
  void add(AutoRecorded e) {
    _trail = [..._trail, e];
    noteRecorded(e);
    notifyListeners();
  }

  void changed() => notifyListeners();

  /// Clears the in-memory trail (Delete data, Replace restore). The stored list
  /// is removed by those operations themselves.
  void clearTrail() {
    _trail = [];
    notifyListeners();
  }
}

// SIGNED (PM 13-11-2026): the trail's heading, foot, Undo and toast words.
const String kAutoRecordedHeading = 'Recorded automatically';
const String kAutoRecordedFoot = 'counted in your totals';
const String kAutoRecordedUndone = 'Moved to Recently deleted. You can restore it there within 1 hour.';
const String kAutoRecordedUndo = 'Undo';
String autoRecordedToast(String amount) => 'Recorded as Airtime, $amount.';
const String kAutoRecordedUndoneToast = 'Airtime moved to Recently deleted';
const String kToastParsedAirtimeRecorded = 'Parsed. Airtime was recorded; the rest is in To categorize.';

// SIGNED (PM 13-11-2026): the trail row's words.
/// Trail row title ("Airtime for myself, Ksh 5"), built from the signed kind names.
String autoRecordedTitle(String amount, {bool other = false}) =>
    'Airtime ${(other ? kAirtimeNameOther : kAirtimeNameMyself).toLowerCase()}, $amount';
// SIGNED (PM 13-11-2026)
const String kAutoRecordedSub = 'Recorded automatically.';
// SIGNED (PM 13-11-2026)
const String kAutoRecordedChangeInSettings = 'Change in Settings';
