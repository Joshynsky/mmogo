/// §AUTOREAD.RULE_RESTORE - writes a restored `receiver_rules` plan into the rule store (0.2.2 item
/// 2, S-4b). The sink behind `RestoreService(rules:)`; runs only AFTER the database commit.
///
/// Replace: the phone's rules are removed (rules only: never the undone codes, history summary or
/// the pause switch), then the file's are written. Merge: the phone's rules stay; a file rule is
/// added only for a receiver (type + key) that has none, up to the rule cap. With "Record receiver
/// details" OFF nothing is stored and the count of dropped rules is reported. Every restored rule
/// is Suggested or Ask first: Auto-record comes back as Ask first with `autoPending` (cleared when
/// the person sets any level). A storage failure on Replace leaves the rules EMPTY, never partial.
/// Chosen Suggest categories (0.2.2 item 2 B-BK) are written only at Suggested and always through
/// `clampChosenCategoryIds` (at most 2, no id twice): `saveRule` does not re-check the list, and a
/// stored invalid list would make a later `setLevel` at Suggested (Reset everyone, which keeps the
/// list, PM 25-11 Q2) refuse that person.
/// Dormant: not passed to the app's `RestoreService` yet.
library;

import '../../data/backup/restore_rules.dart';
import 'rule_model.dart';
import 'rule_store.dart';

class RuleRestoreApplier implements RuleRestoreSink {
  RuleRestoreApplier({
    required RuleStore store,
    required Future<bool> Function() detailsOn,
    DateTime Function()? now,
  })  : _store = store,
        _detailsOn = detailsOn,
        _now = now ?? DateTime.now;

  final RuleStore _store;
  final Future<bool> Function() _detailsOn;
  final DateTime Function() _now;

  static ReceiverType? _typeOf(String code) {
    for (final t in ReceiverType.values) {
      if (t.code == code) return t;
    }
    return null;
  }

  @override
  Future<RulesRestoreOutcome> apply(RulesRestorePlan plan) async {
    var cleared = false;
    try {
      if (plan.replace) {
        await _store.wipeAll();
        cleared = true;
      }
      if (plan.rows.isEmpty) return RulesRestoreOutcome(phoneRulesCleared: cleared);
      if (!await _detailsOn()) {
        return RulesRestoreOutcome(droppedForPrivacy: plan.rows.length, phoneRulesCleared: cleared);
      }
      final have = <String>{
        if (!plan.replace)
          for (final r in await _store.all()) '${r.type.code}\u0000${r.key}',
      };
      var room = kRuleCap - have.length;
      var added = 0, kept = 0, overCap = 0, refused = 0, autoAsk = 0, paybill = 0;
      final at = _now().toUtc();
      for (final row in plan.rows) {
        final type = _typeOf(row.type);
        if (type == null || row.level < 0 || row.level > 1) {
          refused++;
          continue;
        }
        if (have.contains('${row.type}\u0000${row.key}')) {
          kept++;
          continue;
        }
        if (room <= 0) {
          overCap++;
          continue;
        }
        final ok = await _store.saveRule(ReceiverRule(
          type: type,
          key: row.key,
          name: row.name,
          level: row.level == 0 ? RuleLevel.suggested : RuleLevel.askFirst,
          categoryId: row.level == 0 ? null : row.categoryId,
          created: at,
          changed: at,
          ceilingCents: row.ceilingCents,
          autoPending: row.autoPending,
          chosenCategoryIds: row.level == 0 ? clampChosenCategoryIds(row.chosenCategoryIds) : const <int>[],
        ));
        if (!ok) {
          refused++;
          continue;
        }
        added++;
        room--;
        have.add('${row.type}\u0000${row.key}');
        if (row.wasAutoRecord) autoAsk++;
        if (row.wasPaybillAuto) paybill++;
      }
      return RulesRestoreOutcome(
        added: added,
        keptPhone: kept,
        skippedOverCap: overCap,
        refused: refused,
        autoRecordAsAskFirst: autoAsk,
        paybillAsAskFirst: paybill,
        phoneRulesCleared: cleared,
      );
    } catch (_) {
      var empty = false;
      if (plan.replace) {
        try {
          await _store.wipeAll();
          empty = true;
        } catch (_) {}
      }
      return RulesRestoreOutcome(phoneRulesCleared: cleared || empty, failed: true);
    }
  }
}
