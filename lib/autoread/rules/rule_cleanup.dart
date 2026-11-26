/// AUTOREAD RULES clean-up hooks for the Remembered recipients page and the
/// "Record receiver details" switch. Pochi rules live under the same key as
/// the remembered name (recipient memory), so Forget and Change to Send Money
/// delete them here. Never throws.
///
/// B-HIDE (0.2.2 item 2, PM 25-11): details OFF hides the rules (the store answers empty) and no longer
/// erases them, so the hooks that erase must also reach rules that are hidden right now.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/reading_controller.dart' show ReadingPrefs;
import 'prefs_rule_store.dart';
import 'rule_backup_guard.dart';
import 'rule_codec.dart';
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
  /// `forget` erases whatever the details switch says, so a hidden rule goes too.
  Future<void> onNameForgotten(String key) => _safe(() => _store.forget(ReceiverType.pochi, key));

  /// A remembered Pochi name was changed to Send Money: the Pochi rule would be
  /// an orphan, so it goes. A change to Pochi needs nothing.
  Future<void> onNameChangedToSendMoney(String key) => _safe(() => _store.forget(ReceiverType.pochi, key));

  /// Forget all remembered names: every Pochi rule goes (Send Money, Paybill
  /// and Buy Goods rules are keyed by phone or shop and stay). B-HIDE: while details are OFF the store's
  /// all() is empty, so the stored Pochi rule keys are also read directly; otherwise a forgotten name's
  /// hidden rule would come back at ON.
  Future<void> onAllNamesForgotten() => _safe(() async {
        final keys = <String>{
          for (final r in await _store.all())
            if (r.type == ReceiverType.pochi) r.key,
          ...await _storedPochiKeys(),
        };
        for (final k in keys) {
          await _store.forget(ReceiverType.pochi, k);
        }
      });

  /// The person keys of every stored Pochi rule, hidden or not (a corrupt value has no key and is skipped).
  Future<Set<String>> _storedPochiKeys() async {
    try {
      final p = await _sp();
      await p.reload();
      final prefix = '$kRuleKeyPrefix${ReceiverType.pochi.code}.';
      return {
        for (final k in p.getKeys())
          if (k.startsWith(prefix)) ?decodeRule(p.get(k))?.key,
      };
    } catch (_) {
      return const <String>{};
    }
  }

  /// Launch and resume: when "Record receiver details" is OFF the undone codes and the history summary are
  /// cleared. B-HIDE: the rules are NOT erased any more (they are hidden by the store and come back at ON);
  /// Forget all and Delete data still erase them.
  Future<void> enforceDetailsOff() => _safe(() async {
        final p = await _sp();
        await p.reload();
        if (p.getBool(kReceiverDetailsPrefsKey) == false) await _guard.clearDetailsOffData();
      });

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}
