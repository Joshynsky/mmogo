/// AUTOREAD RULES engine: counts records in a row with the same category per
/// person and offers "Ask first next time?". 0.2.1: only Suggested people are
/// counted and offered; Ask first and Auto-record people are never counted.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_rule_store.dart';
import 'rule_engine.dart';
import 'rule_model.dart';

const String kSuggestEnabledKey = 'autoread_suggest_enabled';
const String kSuggestAfterKey = 'autoread_suggest_after';
const int kSuggestAfterDefault = 3;
const int kSuggestAfterMin = 2;
const int kSuggestAfterMax = 10;

class PrefsRuleEngine implements RuleEngine {
  PrefsRuleEngine(this._store, {Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;

  final PrefsRuleStore _store;
  final Future<SharedPreferences> Function() _prefs;

  @override
  Future<void> onRecorded(ReceiverType type, String key,
      {required String name, required int categoryId, required DateTime at}) async {
    final t = at.toUtc();
    final r = await _store.get(type, key);
    if (r == null) {
      await _store.saveRule(ReceiverRule(
        type: type,
        key: key,
        name: name,
        run: 1,
        runCategoryId: categoryId,
        created: t,
        changed: t,
        lastRecorded: t,
      ));
      return;
    }
    if (r.level != RuleLevel.suggested) {
      // Ask first / Auto-record: not counted; only the last-recorded time moves.
      if (r.level == RuleLevel.askFirst) await _store.saveRule(r.copyWith(lastRecorded: t));
      return;
    }
    final same = r.runCategoryId == categoryId;
    await _store.saveRule(r.copyWith(name: name, run: same ? r.run + 1 : 1, runCategoryId: categoryId, lastRecorded: t));
  }

  /// Undo: the run starts again. An Undo of a row recorded with no tap
  /// ([recordedAutomatically]) for a person on Auto-record drops that rule to
  /// Suggested: run 0, ceiling and autoPending cleared, no category.
  @override
  Future<void> onUndone(ReceiverType type, String key, {bool recordedAutomatically = false}) async {
    final r = await _store.get(type, key);
    if (r == null) return;
    if (recordedAutomatically && r.level == RuleLevel.autoRecord) {
      await _store.saveRule(ReceiverRule(
        type: r.type,
        key: r.key,
        name: r.name,
        level: RuleLevel.suggested,
        created: r.created,
        changed: DateTime.now().toUtc(),
        lastRecorded: r.lastRecorded,
      ));
      return;
    }
    if (r.level != RuleLevel.suggested || r.run == 0) return;
    await _store.saveRule(r.copyWith(run: 0));
  }

  /// A recorded entry's category was changed: the run starts again from the new
  /// category (the next record in it is 1 in a row).
  @override
  Future<void> onCategoryChanged(ReceiverType type, String key, {required int categoryId}) async {
    final r = await _store.get(type, key);
    if (r == null || r.level != RuleLevel.suggested) return;
    await _store.saveRule(r.copyWith(run: 0, runCategoryId: categoryId));
  }

  @override
  Future<void> notNow(ReceiverType type, String key) async {
    final r = await _store.get(type, key);
    if (r == null || r.level != RuleLevel.suggested || r.run == 0) return;
    await _store.saveRule(r.copyWith(run: 0));
  }

  @override
  Future<List<Offer>> pendingOffers() async {
    if (!await suggestEnabled()) return const [];
    final after = await suggestAfter();
    final due = [
      for (final r in await _store.all())
        if (r.level == RuleLevel.suggested && r.runCategoryId != null && r.run >= after) r
    ]..sort((a, b) => b.changed.compareTo(a.changed));
    return [for (final r in due) Offer(type: r.type, key: r.key, name: r.name, categoryId: r.runCategoryId!, run: r.run)];
  }

  @override
  Future<int> suggestAfter() async {
    final p = await _prefs();
    await p.reload();
    final v = p.getInt(kSuggestAfterKey);
    if (v == null) return kSuggestAfterDefault;
    return v.clamp(kSuggestAfterMin, kSuggestAfterMax);
  }

  @override
  Future<bool> suggestEnabled() async {
    final p = await _prefs();
    await p.reload();
    return p.getBool(kSuggestEnabledKey) ?? true;
  }

  /// Setting writers for the Settings page (extra to the interface).
  Future<void> setSuggestAfter(int n) async {
    final p = await _prefs();
    await p.setInt(kSuggestAfterKey, n.clamp(kSuggestAfterMin, kSuggestAfterMax));
  }

  Future<void> setSuggestEnabled(bool on) async {
    final p = await _prefs();
    await p.setBool(kSuggestEnabledKey, on);
  }
}
