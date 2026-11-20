/// AUTOREAD RULES Suggest settings over SharedPreferences: the offer switch and the "Suggest after"
/// count, behind the port the Settings rows read. Same keys the rule engine reads, so a change here is
/// seen by the engine at once. [onChanged] runs after a successful write (the offers list refreshes).
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../ui/levels/levels_deps.dart';
import 'prefs_rule_engine.dart' show kSuggestAfterKey, kSuggestEnabledKey;

class PrefsSuggestSettings implements SuggestSettingsPort {
  PrefsSuggestSettings({Future<SharedPreferences> Function()? prefs, this.onChanged})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;
  final void Function()? onChanged;

  Future<SharedPreferences> _fresh() async {
    final p = await _prefs();
    await p.reload();
    return p;
  }

  @override
  Future<bool> enabled() async => (await _fresh()).getBool(kSuggestEnabledKey) ?? true;

  @override
  Future<int> after() async => clampSuggestAfter((await _fresh()).getInt(kSuggestAfterKey) ?? kSuggestAfterDefault);

  @override
  Future<bool> setEnabled(bool on) async {
    final ok = await (await _prefs()).setBool(kSuggestEnabledKey, on);
    if (ok) onChanged?.call();
    return ok;
  }

  @override
  Future<bool> setAfter(int n) async {
    final ok = await (await _prefs()).setInt(kSuggestAfterKey, clampSuggestAfter(n));
    if (ok) onChanged?.call();
    return ok;
  }
}
