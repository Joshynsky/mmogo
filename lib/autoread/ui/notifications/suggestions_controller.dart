/// §AUTOREAD.SUGGESTIONS_CONTROLLER - holds the offers "Ask first next time?" for the To do page.
/// Reads [RuleEngine.pendingOffers]; Not now goes to [RuleEngine.notNow]; the confirm sets the
/// person to Ask first in the [RuleStore]. The page owns it (create, dispose). Autoread build only.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../rules/rule_engine.dart';
import '../../rules/rule_model.dart';
import '../../rules/rule_store.dart';

class SuggestionsController extends ChangeNotifier {
  SuggestionsController({required this.engine, required this.store, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _sub = store.changes.listen((_) => refresh());
    refresh();
  }

  final RuleEngine engine;
  final RuleStore store;
  final DateTime Function() _clock;
  StreamSubscription<void>? _sub;
  List<Offer> _offers = const [];
  bool _disposed = false;

  List<Offer> get offers => _offers;

  /// Reads the offers again (none while suggestions are switched off).
  Future<void> refresh() async {
    try {
      final next = await engine.suggestEnabled() ? await engine.pendingOffers() : const <Offer>[];
      if (_disposed) return;
      _offers = next;
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
  Future<bool> confirm(Offer o) async {
    final ok = await store.setLevel(o.type, o.key, name: o.name, level: RuleLevel.askFirst, categoryId: o.categoryId, at: _clock());
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
