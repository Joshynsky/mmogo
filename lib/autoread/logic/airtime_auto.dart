/// §AUTOREAD.AIRTIME_AUTO — Airtime recorded without the Categorize tap
/// (0.2.0 S6, J2 note: `_pipeline/v0.2.0/judge-notes/J2-airtime-auto-record.md`).
/// Pure Dart plus one small observable ([AirtimeAutoController]); no widgets.
///
/// Rules (J2): Airtime only; ONE preference, default OFF; the user still taps
/// Parse; each entry has an Undo (moves it to Recently deleted) and a visible
/// trail row; nothing is stored beyond the preference and the ledger entry.
library;

import 'package:flutter/foundation.dart';

import '../../domain/parsing/parsed_sms_fields.dart';
import '../model/waiting_item.dart';

/// `shared_preferences` key of the one preference. NOT in the backup key table
/// (`backup_setting_keys.dart`), so a backup file can never turn it on.
/// Existing key: auto-record for airtime bought FOR MYSELF only (people who opted
/// in when only that kind existed; their consent does not extend to the other kind).
const String kAirtimeAutoPrefKey = 'autoread_airtime_auto_record';

/// New key (WBS row 17): auto-record for airtime bought FOR ANOTHER NUMBER.
/// Default OFF. Also outside the backup table.
const String kAirtimeAutoOtherPrefKey = 'autoread_airtime_auto_record_other';

/// True for a parsed Airtime item that waits for a category: the only kind this
/// feature may ever record.
bool isParsedAirtime(WaitingItem item) =>
    item.kind == WaitingKind.waitingCategory && item.parsed?.sourceType == SmsSourceType.airtime;

/// True when [item] is a parsed Airtime item AND the switch for its own kind is
/// ON ([myselfOn] for a plain purchase, [otherOn] for `for <number>`): the only
/// items auto-record may ever write.
bool isAutoRecordEligible(WaitingItem item, {required bool myselfOn, required bool otherOn}) =>
    isParsedAirtime(item) && (item.parsed!.airtimeOther ? otherOn : myselfOn);

/// One entry recorded automatically, kept in memory for the trail.
class AutoRecorded {
  AutoRecorded({required this.rowId, required this.amountCents, required this.at});

  /// The ledger row (`transactions.id`) that was written.
  final int rowId;
  final int amountCents;
  final DateTime at;

  /// Undo was used: the entry sits in Recently deleted.
  bool undone = false;

  /// Undo was tried and changed nothing (the row was purged or wiped).
  bool undoFailed = false;
}

/// What the Notifications page needs: the switch, the trail and two actions.
/// The repository owns the logic and calls the `_`-free setters below.
class AirtimeAutoController extends ChangeNotifier {
  AirtimeAutoController({
    required this.onSwitch,
    required this.onUndo,
    this.onSwitchOther,
  });

  /// Called when the user flips the switch for airtime for another number.
  final Future<void> Function(bool on)? onSwitchOther;

  /// Called when the user flips the switch.
  final Future<void> Function(bool on) onSwitch;

  /// Called when the user taps Undo on a trail row.
  final Future<void> Function(AutoRecorded entry) onUndo;

  bool _on = false;
  bool _onOther = false;
  final List<AutoRecorded> _trail = [];

  /// The switch for airtime bought for myself (the original switch).
  bool get on => _on;

  /// The switch for airtime bought for another number (default OFF).
  bool get onOther => _onOther;
  List<AutoRecorded> get trail => List.unmodifiable(_trail);

  /// Newest first, for display.
  List<AutoRecorded> get trailNewestFirst => _trail.reversed.toList();

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

  void add(AutoRecorded e) {
    _trail.add(e);
    notifyListeners();
  }

  void changed() => notifyListeners();

  /// Clears the in-memory trail (Delete data).
  void clearTrail() {
    _trail.clear();
    notifyListeners();
  }
}

// WORDING-DRAFT: all labels below are new UI text for the PM to review (from
// the mock's "Auto-record airtime" block and the "Recorded automatically" row).
const String kAutoAirtimeTitle = 'Auto-record airtime';
const String kAutoAirtimeBody =
    'mmogo will record airtime purchases for you. You can turn this off here any time.';
const String kAutoAirtimeOnTail = ' Each one can be undone.';
const String kAutoAirtimeOffTail = ' Until you turn it on, airtime waits in To categorize like the rest.';
const String kAutoRecordedHeading = 'Recorded automatically';
String autoRecordedTitle(String amount) => 'Recorded as Airtime, $amount';
const String kAutoRecordedFoot = 'counted in your totals';
const String kAutoRecordedUndone = 'Moved to Recently deleted. You can restore it there within 1 hour.';
const String kAutoRecordedUndoFailed = 'Could not undo. It may already be gone from Recently deleted.';
const String kAutoRecordedUndo = 'Undo';
String autoRecordedToast(String amount) => 'Recorded as Airtime, $amount.';
const String kAutoRecordedUndoneToast = 'Airtime moved to Recently deleted';
const String kAutoAirtimeOnToast =
    'Auto-record airtime is on. Airtime purchases are recorded for you; Undo stays on each one.';
const String kAutoAirtimeOffToast =
    'Auto-record airtime is off. Airtime goes through To categorize like the rest.';
const String kToastParsedAirtimeRecorded = 'Parsed. Airtime was recorded; the rest is in To categorize.';
