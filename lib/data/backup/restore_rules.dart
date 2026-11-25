/// §DATA.RESTORE.RULES - restore of the `receiver_rules` section (0.2.2 item 2, S-4b), the pure and
/// database side. Rules live in the phone's PREFERENCES, not the database, so the restore writes
/// them AFTER the database commit, through the [RuleRestoreSink] seam (plain data in, counts out:
/// `lib/data` must not import `lib/autoread/`; the sink lives in
/// `lib/autoread/rules/rule_restore.dart`).
///
/// This file: maps each rule's category back to the phone's NEW id (a built-in by `cat_seed`, the
/// person's own by `cat_name`; not found = the rule still restores, with no category), degrades
/// Auto-record to Ask first with the `autoPending` marker (Paybill cannot hold Auto-record at all:
/// Ask first, no marker), and plans Replace (all rules replace the phone's) or Merge (the sink adds
/// only for receivers with no rule). Data only: no wording. Never touches the pause switch.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_validator.dart' show ValidatedBackup;
import 'restore_types.dart' show RestoreMode;

/// One rule ready to write (already degraded; category already a phone id or null).
class RestoredRule {
  const RestoredRule({
    required this.type,
    required this.key,
    required this.name,
    required this.level,
    this.categoryId,
    this.ceilingCents,
    this.autoPending = false,
    this.wasAutoRecord = false,
    this.wasPaybillAuto = false,
  });

  /// `ReceiverType.code` (`SM`, `PB`, `BG`, `PO`).
  final String type;
  final String key;
  final String name;

  /// 0 Suggested or 1 Ask first only: never 2.
  final int level;
  final int? categoryId;
  final int? ceilingCents;

  /// Came back as Ask first from Auto-record (or was already pending): waits for the person.
  final bool autoPending;

  /// The file had Auto-record here (counted as "Auto-record restored as Ask first").
  final bool wasAutoRecord;

  /// The file had Auto-record on a Paybill (counted separately: it can never be Auto-record).
  final bool wasPaybillAuto;
}

/// What the sink is asked to do.
class RulesRestorePlan {
  const RulesRestorePlan({required this.replace, required this.hasSection, required this.rows});

  /// Replace: the phone's rules are replaced by [rows] (none = the phone ends with no rules).
  /// Merge: the phone's rules stay; a row is added only for a receiver (type + key) with none.
  final bool replace;

  /// The file carried a `receiver_rules` section (schema >= 9).
  final bool hasSection;
  final List<RestoredRule> rows;
}

/// What happened to the rules, counts only (the sentence is held UI).
class RulesRestoreOutcome {
  const RulesRestoreOutcome({
    this.added = 0,
    this.keptPhone = 0,
    this.droppedForPrivacy = 0,
    this.skippedOverCap = 0,
    this.refused = 0,
    this.autoRecordAsAskFirst = 0,
    this.paybillAsAskFirst = 0,
    this.phoneRulesCleared = false,
    this.failed = false,
  });

  /// Nothing happened to the rules (Merge of a file with no rules).
  static const RulesRestoreOutcome none = RulesRestoreOutcome();

  /// Rules written.
  final int added;

  /// Merge: file rules not added because the phone already has a rule for that receiver.
  final int keptPhone;

  /// File rules not stored because "Record receiver details" is OFF.
  final int droppedForPrivacy;

  /// Merge: file rules left out because the phone is at the rule cap.
  final int skippedOverCap;

  /// Rules the store refused for another reason (should not happen).
  final int refused;

  /// Written rules that were Auto-record in the file and are now Ask first, waiting.
  final int autoRecordAsAskFirst;

  /// Written Paybill rules that were Auto-record in the file and are now Ask first.
  final int paybillAsAskFirst;

  /// Replace: the phone's own rules were removed first.
  final bool phoneRulesCleared;

  /// The rules could not be written. The ledger is restored; on Replace the rules are EMPTY (never
  /// a half set that could auto-record), on Merge the phone's rules are as they were plus any
  /// already added (all Ask first or lower).
  final bool failed;

  @override
  String toString() => 'RulesRestoreOutcome(added: $added, keptPhone: $keptPhone, '
      'droppedForPrivacy: $droppedForPrivacy, overCap: $skippedOverCap, refused: $refused, '
      'autoAsAskFirst: $autoRecordAsAskFirst, paybill: $paybillAsAskFirst, '
      'cleared: $phoneRulesCleared, failed: $failed)';
}

/// Writes the plan into the phone's rule storage. Reports a storage problem as `failed: true`;
/// the service also guards it.
abstract class RuleRestoreSink {
  Future<RulesRestoreOutcome> apply(RulesRestorePlan plan);
}

/// The phone's categories as the restore needs them to map a rule.
class RuleCategoryLookup {
  const RuleCategoryLookup({this.idBySeed = const {}, this.idByName = const {}});

  /// `seed_key` -> id.
  final Map<String, int> idBySeed;

  /// Name of a user-made category -> id (an active row wins, else the lowest id).
  final Map<String, int> idByName;

  static Future<RuleCategoryLookup> load(DatabaseExecutor ex) async {
    final seed = <String, int>{};
    final byName = <String, int>{};
    final active = <String>{};
    final rows = await ex.rawQuery('SELECT id, seed_key, name, active FROM classifications ORDER BY id');
    for (final r in rows) {
      final id = r['id']! as int;
      final sk = r['seed_key'] as String?;
      if (sk != null) {
        seed[sk] = id;
        continue;
      }
      final name = r['name']! as String;
      final isActive = r['active'] == 1;
      if (!byName.containsKey(name) || (isActive && !active.contains(name))) {
        byName[name] = id;
        if (isActive) active.add(name);
      }
    }
    return RuleCategoryLookup(idBySeed: seed, idByName: byName);
  }
}

/// Builds the plan from a validated file. PURE.
RulesRestorePlan planRulesRestore(ValidatedBackup file, RestoreMode mode, RuleCategoryLookup cats) {
  final rows = <RestoredRule>[];
  for (final r in file.receiverRules) {
    final type = r['t']! as String;
    final lv = r['lv']! as int;
    final seed = r['cat_seed'] as String?;
    final name = r['cat_name'] as String?;
    final cat = lv == 0 ? null : (seed != null ? cats.idBySeed[seed] : (name != null ? cats.idByName[name] : null));
    final canAuto = type != 'PB';
    final auto = lv == 2;
    final wasAuto = auto && canAuto;
    final level = auto ? 1 : lv;
    rows.add(RestoredRule(
      type: type,
      key: r['k']! as String,
      name: r['name']! as String,
      level: level,
      categoryId: cat,
      ceilingCents: r['ceil'] as int?,
      autoPending: level == 1 && (wasAuto || (!auto && canAuto && r['ap'] == 1)),
      wasAutoRecord: wasAuto,
      wasPaybillAuto: auto && !canAuto,
    ));
  }
  return RulesRestorePlan(replace: mode == RestoreMode.replace, hasSection: file.hasRulesSection, rows: rows);
}

/// Runs the rules step after a COMMITTED restore. Never throws. [sink] null = not wired (the
/// rules are left as the existing Replace hook leaves them). Merge of a file with no rules (no
/// section, or an empty one) does not call the sink at all: the phone's rules are not touched.
Future<RulesRestoreOutcome?> restoreRulesAfterCommit({
  required RuleRestoreSink? sink,
  required Database db,
  required ValidatedBackup file,
  required RestoreMode mode,
}) async {
  if (sink == null) return null;
  final replace = mode == RestoreMode.replace;
  if (!replace && file.receiverRules.isEmpty) return RulesRestoreOutcome.none;
  RulesRestorePlan plan;
  try {
    plan = planRulesRestore(file, mode, await RuleCategoryLookup.load(db));
  } catch (_) {
    // Cannot map categories: write no rule at all (on Replace the sink still empties the phone's).
    plan = RulesRestorePlan(replace: replace, hasSection: file.hasRulesSection, rows: const []);
    try {
      final o = await sink.apply(plan);
      return RulesRestoreOutcome(phoneRulesCleared: o.phoneRulesCleared, failed: true);
    } catch (_) {
      return const RulesRestoreOutcome(failed: true);
    }
  }
  try {
    return await sink.apply(plan);
  } catch (_) {
    return const RulesRestoreOutcome(failed: true);
  }
}
