/// AUTOREAD RULES clean-up hooks for the Remembered recipients page and the
/// "Record receiver details" switch. Pochi rules live under the same key as
/// the remembered name (recipient memory), so Forget and Change to Send Money
/// delete them here. Never throws.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/reading_controller.dart' show ReadingPrefs;
import 'prefs_rule_store.dart';
import 'rule_backup_guard.dart';
import 'rule_model.dart';
import 'rule_store.dart';

class RuleCleanup {
  RuleCleanup(this._store, {ReadingPrefs? prefs, RuleBackupGuard? guard, Future<SharedPreferences> Function()? sharedPrefs})
      : _sp = sharedPrefs ?? SharedPreferences.getInstance,
        _guard = guard ?? RuleBackupGuard(prefs: prefs);

  final RuleStore _store;
  final Future<SharedPreferences> Function() _sp;
  final RuleBackupGuard _guard;

  /// A remembered name was forgotten (Forget on the Remembered page): its rule
  /// goes. [key] is the recipient-memory key (the rule key for a Pochi).
  Future<void> onNameForgotten(String key) => _safe(() => _store.forget(ReceiverType.pochi, key));

  /// A remembered Pochi name was changed to Send Money: the Pochi rule would be
  /// an orphan, so it goes. A change to Pochi needs nothing.
  Future<void> onNameChangedToSendMoney(String key) => _safe(() => _store.forget(ReceiverType.pochi, key));

  /// Forget all remembered names: every Pochi rule goes (Send Money, Paybill
  /// and Buy Goods rules are keyed by phone or shop and stay).
  Future<void> onAllNamesForgotten() => _safe(() async {
        for (final r in await _store.all()) {
          if (r.type == ReceiverType.pochi) await _store.forget(r.type, r.key);
        }
      });

  /// Launch and resume: when "Record receiver details" is OFF nothing may be
  /// kept, so every rule, undone code and history summary is wiped.
  Future<void> enforceDetailsOff() => _safe(() async {
        final p = await _sp();
        await p.reload();
        if (p.getBool(kReceiverDetailsPrefsKey) == false) await _guard.wipe();
      });

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}
