/// §AUTOREAD.LEVELS.RESTORED_PORT: what the "Auto-record was restored for N people. Keep it?" banner needs
/// (0.2.2 restore, Option B). The banner codes against [RestoredAutoRecordPort]; slice A's real
/// `RestoredAutoRecord` (lib/autoread/rules/) implements it and replaces [StoreRestoredAutoRecord].
library;

import 'package:flutter/foundation.dart';

import '../../rules/restored_auto_record.dart';
import 'hard_rule_ports.dart' show RuleBulkOps;

/// The contract members the UI uses. [count] must keep itself current (it changes when a restore leaves
/// people waiting, and after [keepAll] / [turnOffAll]). The banner draws nothing at 0.
abstract class RestoredAutoRecordPort {
  /// How many restored Auto-record people wait for Keep or Turn off.
  ValueNotifier<int> get count;

  /// Clears the waiting mark: the people become real Auto-record.
  Future<void> keepAll();

  /// Sets the waiting people to Ask first and clears the mark.
  Future<void> turnOffAll();

  /// Stops listening (the banner calls it for a port it created itself).
  void dispose();
}

/// The default port: slice A's [RestoredAutoRecord] over the same rule store the bulk ops use. Pending =
/// Auto-record with the `autoPending` mark (a restored person waiting for Keep); both engines act as
/// Ask first meanwhile. Keep clears the mark; Turn off sets Ask first.
class StoreRestoredAutoRecord implements RestoredAutoRecordPort {
  StoreRestoredAutoRecord(RuleBulkOps bulk, {DateTime Function()? now})
      : _inner = RestoredAutoRecord(store: bulk.store, now: now) {
    _inner.refresh();
  }

  final RestoredAutoRecord _inner;

  @override
  ValueNotifier<int> get count => _inner.count;

  @override
  Future<void> keepAll() => _inner.keepAll();

  @override
  Future<void> turnOffAll() => _inner.turnOffAll();

  @override
  void dispose() => _inner.dispose();
}
