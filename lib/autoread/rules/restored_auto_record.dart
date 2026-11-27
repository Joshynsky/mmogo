/// §AUTOREAD.RESTORED_AUTO_RECORD - the people a restore brought back at Auto-record who still wait for
/// the person's answer (0.2.2 restore-keeps-rules, PM 26-11, Option B). The UI banner "Auto-record was
/// restored for N people. Keep it?" reads [count] and calls [keepAll] or [turnOffAll]: one tap for all.
///
/// A person is pending when the stored rule is at Auto-record AND carries `autoPending` (the `ap`
/// field). Until Keep, both engines (Dart `decideHardRule`, Kotlin `HardRuleLogic`) act as Ask first,
/// so nothing is recorded with no tap. Ask first rules with the mark (the older review flow) are not
/// counted here. Writes go through `saveRule` (existing rules are always updated, even with details
/// off); one person that fails does not stop the rest.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'rule_model.dart';
import 'rule_store.dart';

/// One waiting person for the banner's list.
class PendingAutoRecordPerson {
  const PendingAutoRecordPerson({required this.name, required this.key, required this.type, this.categoryName});

  final String name;
  final String key;
  final ReceiverType type;

  /// The category the person's rule records into; null when unknown or none.
  final String? categoryName;
}

class RestoredAutoRecord {
  RestoredAutoRecord({
    required RuleStore store,
    Future<String?> Function(int categoryId)? categoryName,
    DateTime Function()? now,
  })  : _store = store,
        _categoryName = categoryName,
        _now = now ?? DateTime.now {
    _sub = _store.changes.listen((_) => refresh());
  }

  final RuleStore _store;
  final Future<String?> Function(int categoryId)? _categoryName;
  final DateTime Function() _now;
  StreamSubscription<void>? _sub;

  /// How many people wait. Updated by [refresh], [keepAll], [turnOffAll] and every store change.
  final ValueNotifier<int> count = ValueNotifier<int>(0);

  static bool isPending(ReceiverRule r) => r.autoPending && r.level == RuleLevel.autoRecord;

  Future<List<ReceiverRule>> _rules() async {
    try {
      return [for (final r in await _store.all()) if (isPending(r)) r];
    } catch (_) {
      return const <ReceiverRule>[];
    }
  }

  /// Re-reads the store and sets [count].
  Future<void> refresh() async {
    final n = (await _rules()).length;
    if (count.value != n) count.value = n;
  }

  Future<List<PendingAutoRecordPerson>> pending() async {
    final out = <PendingAutoRecordPerson>[];
    for (final r in await _rules()) {
      String? cat;
      final id = r.categoryId;
      if (id != null && _categoryName != null) {
        try {
          cat = await _categoryName(id);
        } catch (_) {}
      }
      out.add(PendingAutoRecordPerson(name: r.name, key: r.key, type: r.type, categoryName: cat));
    }
    return out;
  }

  /// Keep: the marker is cleared, the people are real Auto-record.
  Future<void> keepAll() => _apply((r) => r.copyWith(autoPending: false));

  /// Turn off: the people go to Ask first (category and limit stay) and the marker is cleared.
  Future<void> turnOffAll() => _apply((r) => r.copyWith(level: RuleLevel.askFirst, autoPending: false));

  Future<void> _apply(ReceiverRule Function(ReceiverRule) change) async {
    final at = _now().toUtc();
    for (final r in await _rules()) {
      try {
        await _store.saveRule(change(r).copyWith(changed: at));
      } catch (_) {}
    }
    await refresh();
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    count.dispose();
  }
}
