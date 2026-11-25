/// §AUTOREAD.SUGGESTIONS_CONTROLLER - holds the offers "Ask first next time?" for the To do page.
/// Reads [RuleEngine.pendingOffers]; Not now goes to [RuleEngine.notNow]; the confirm sets the
/// person to Ask first in the [RuleStore] (flag on: then the notice). 0.2.2 (U2): [confirmAuto] sets Auto-record (only while
/// `autoRecordUi`, only for kinds that can hold it) and shows the one [RuleChangeNotice].
/// 0.2.2 item 2 (U-OFFER, B-1): an answered offer leaves [offers] at once (before the store write) and stays
/// gone after the write, whatever a late or stale read says; a failed write brings it back. The notice gets the
/// plain name (never the number) and the category name.
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
  List<Offer> _visible = const [];
  int? _suggestAfter;
  bool _disposed = false;

  /// Offers being saved right now (hidden while the write runs).
  final Set<String> _saving = {};

  /// Offers saved: id -> the read number current when the save finished. Hidden until a read that started
  /// after the save no longer lists the person (then the store has caught up and the mark is dropped).
  final Map<String, int> _answered = {};

  /// Read numbers: [_reads] counts started reads, [_shownRead] is the newest read applied. A read that
  /// finishes after a newer one is dropped, so an old list never brings an answered card back.
  int _reads = 0;
  int _shownRead = 0;

  static String _id(Offer o) => '${o.type.code}.${o.key}';

  /// The offers to show: every pending offer except the ones answered (or being answered) here.
  List<Offer> get offers => _visible;

  /// The Settings "Suggest after" number (the N in the Auto-record offer body); null until read.
  int? get suggestAfter => _suggestAfter;

  void _publish() {
    if (_disposed) return;
    _visible = List.unmodifiable([
      for (final o in _offers)
        if (!_saving.contains(_id(o)) && !_answered.containsKey(_id(o))) o,
    ]);
    notifyListeners();
  }

  /// Reads the offers again (none while suggestions are switched off).
  Future<void> refresh() async {
    final read = ++_reads;
    try {
      final next = await engine.suggestEnabled() ? await engine.pendingOffers() : const <Offer>[];
      int? after;
      try {
        after = await engine.suggestAfter();
      } catch (_) {
        after = _suggestAfter;
      }
      if (_disposed || read < _shownRead) return;
      _shownRead = read;
      _offers = next;
      _suggestAfter = after;
      _answered.removeWhere((id, savedAt) => read > savedAt && !next.any((o) => _id(o) == id));
      _publish();
    } catch (_) {
      // Keep what is shown; the next change tries again.
    }
  }

  Future<void> notNow(Offer o) async {
    await engine.notNow(o.type, o.key);
    await refresh();
  }

  /// Hides [o] at once, runs [save], then keeps it hidden on success or shows it again on failure
  /// (a refusal or a throw both count as failure).
  Future<bool> _answer(Offer o, Future<bool> Function() save) async {
    final id = _id(o);
    _saving.add(id);
    _publish();
    var ok = false;
    try {
      ok = await save();
    } catch (_) {
      ok = false;
    }
    _saving.remove(id);
    if (ok) _answered[id] = _reads;
    _publish();
    return ok;
  }

  /// Sets the person to Ask first with the offered category. False when refused (list full) or the store
  /// fails; the card then comes back and the caller shows today's toast. While `autoRecordUi` (PM 24-11: one
  /// pill for every level change) a success shows the notice (stage 1) with the plain name and
  /// [categoryName]; with the flag off nothing is shown, as before.
  Future<bool> confirm(Offer o, {String? categoryName}) async {
    final ok = await _answer(
      o,
      () => store.setLevel(o.type, o.key, name: o.name, level: RuleLevel.askFirst, categoryId: o.categoryId, at: _clock()),
    );
    if (ok && autoRecordUi) notice.show(o.name, RuleLevel.askFirst, null, null, categoryName: categoryName);
    await refresh();
    return ok;
  }

  /// Sets the person to Auto-record with the offered category and no ceiling, after the caller's confirm
  /// dialog. Refused without touching the store (and without hiding the card) while `autoRecordUi` is off or
  /// for a kind that cannot hold Auto-record (Paybill). False when refused or the store fails; true shows
  /// the notice with the plain name and [categoryName].
  Future<bool> confirmAuto(Offer o, {String? categoryName}) async {
    if (!autoRecordUi || !canHoldAutoRecord(o.type)) return false;
    final ok = await _answer(
      o,
      () => store.setLevel(o.type, o.key,
          name: o.name, level: RuleLevel.autoRecord, categoryId: o.categoryId, ceilingCents: null, at: _clock()),
    );
    if (ok) {
      final change = onChangeCeiling;
      notice.show(o.name, RuleLevel.autoRecord, null, change == null ? null : () => change(o), categoryName: categoryName);
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
