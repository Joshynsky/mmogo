/// §AUTOREAD.SUGGESTIONS_CONTROLLER - holds the offers "Ask first next time?" for the To do page.
/// Reads [RuleEngine.pendingOffers]; Not now goes to [RuleEngine.notNow]; the confirm sets the
/// person to Ask first in the [RuleStore] (flag on: then the notice). 0.2.2 (U2): [confirmAuto] sets Auto-record (only while
/// `autoRecordUi`, only for kinds that can hold it) and shows the one [RuleChangeNotice].
/// The page owns it (create, dispose). Autoread build only.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../rules/rule_engine.dart';
import '../../rules/rule_model.dart';
import '../../rules/rule_store.dart';
import '../levels/hard_rule_ports.dart';

class SuggestionsController extends ChangeNotifier {
  SuggestionsController({
    required this.engine,
    required this.store,
    DateTime Function()? clock,
    RuleChangeNotice? notice,
    this.onChangeCeiling,
  })  : _clock = clock ?? DateTime.now,
        notice = notice ?? const PillToastRuleChangeNotice() {
    _sub = store.changes.listen((_) => refresh());
    refresh();
  }

  final RuleEngine engine;
  final RuleStore store;

  /// Shown after a successful [confirmAuto]. Default: the C0 stand-in (I1 passes the real pill).
  final RuleChangeNotice notice;

  /// Opens the level sheet for [Offer]'s person (the pill's "Change ceiling"). Null: the pill offers no
  /// Change ceiling button (I1 wires it).
  final void Function(Offer offer)? onChangeCeiling;

  final DateTime Function() _clock;
  StreamSubscription<void>? _sub;
  List<Offer> _offers = const [];
  int? _suggestAfter;
  bool _disposed = false;

  List<Offer> get offers => _offers;

  /// The Settings "Suggest after" number (the N in the Auto-record offer body); null until read.
  int? get suggestAfter => _suggestAfter;

  /// Reads the offers again (none while suggestions are switched off).
  Future<void> refresh() async {
    try {
      final next = await engine.suggestEnabled() ? await engine.pendingOffers() : const <Offer>[];
      int? after;
      try {
        after = await engine.suggestAfter();
      } catch (_) {
        after = _suggestAfter;
      }
      if (_disposed) return;
      _offers = next;
      _suggestAfter = after;
      notifyListeners();
    } catch (_) {
      // Keep what is shown; the next change tries again.
    }
  }

  Future<void> notNow(Offer o) async {
    await engine.notNow(o.type, o.key);
    await refresh();
  }

  /// Sets the person to Ask first with the offered category. False when refused (list full).
  /// While `autoRecordUi` (PM 24-11: one pill for every level change) a success shows the notice
  /// (stage 1); with the flag off nothing is shown, as before.
  Future<bool> confirm(Offer o) async {
    final ok = await store.setLevel(o.type, o.key, name: o.name, level: RuleLevel.askFirst, categoryId: o.categoryId, at: _clock());
    if (ok && autoRecordUi) notice.show(o.name, RuleLevel.askFirst, null, null);
    await refresh();
    return ok;
  }

  /// Sets the person to Auto-record with the offered category and no ceiling, after the caller's confirm
  /// dialog. Refused without touching the store while `autoRecordUi` is off or for a kind that cannot
  /// hold Auto-record (Paybill). False when refused or the store fails; true shows the notice.
  Future<bool> confirmAuto(Offer o) async {
    if (!autoRecordUi || !canHoldAutoRecord(o.type)) return false;
    var ok = false;
    try {
      ok = await store.setLevel(o.type, o.key,
          name: o.name, level: RuleLevel.autoRecord, categoryId: o.categoryId, ceilingCents: null, at: _clock());
    } catch (_) {
      ok = false;
    }
    if (ok) {
      final change = onChangeCeiling;
      notice.show(o.name, RuleLevel.autoRecord, null, change == null ? null : () => change(o));
    }
    await refresh();
    return ok;
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
