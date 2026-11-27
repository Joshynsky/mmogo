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
///
/// Chosen Suggest categories (`sc`, 0.2.2 item 2 B-BK): for a rule that is Suggested in the file,
/// each entry is mapped to the phone's id the same way, entries that are not an ACTIVE category
/// after the restore are dropped, an id twice is kept once, and at most
/// [kBackupMaxChosenCategories] are kept in order. Above Suggested the list is always empty. A
/// missing, null or unreadable `sc` (or entry) restores as empty: never a refused rule.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_limits.dart' show kBackupMaxChosenCategories;
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
    this.chosenCategoryIds = const <int>[],
  });

  /// `ReceiverType.code` (`SM`, `PB`, `BG`, `PO`).
  final String type;
  final String key;
  final String name;

  /// 0 Suggested, 1 Ask first, or 2 Auto-record (always with [autoPending]; never 2 on a Paybill).
  final int level;
  final int? categoryId;
  final int? ceilingCents;

  /// Level 2 restored from the file, or Ask first that was already pending: waits for the person
  /// (acts as Ask first until Keep).
  final bool autoPending;

  /// The file had Auto-record here (counted in `autoRecordAsAskFirst`: restored, waiting for Keep).
  final bool wasAutoRecord;

  /// The file had Auto-record on a Paybill (counted separately: it can never be Auto-record).
  final bool wasPaybillAuto;

  /// Chosen Suggest categories as phone ids (active only, at most 2, no id twice). Always empty
  /// unless [level] is 0.
  final List<int> chosenCategoryIds;
}

/// What the sink is asked to do.
class RulesRestorePlan {
  const RulesRestorePlan({required this.replace, required this.hasSection, required this.rows});

  /// Replace: the phone's rules are replaced by [rows] (none = the phone ends with no rules).
  /// Merge: the phone's rules stay, except a phone rule at Suggested, which the file's row replaces;
  /// a row is added for a receiver with none; a phone Ask first / Auto-record rule is never touched.
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
    this.replaced = 0,
    this.keptLocalNames = const <String>[],
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

  /// Merge: file rules not used because the phone already has an Ask first or Auto-record rule for
  /// that receiver (the phone's stays). Equals [keptLocalNames].length.
  final int keptPhone;

  /// Merge: phone rules at Suggested that the file's rule replaced (not counted in [added]).
  final int replaced;

  /// Merge: the people whose phone rule stayed (display name, in file order), for the result sheet.
  final List<String> keptLocalNames;

  /// File rules not stored because "Record receiver details" is OFF.
  final int droppedForPrivacy;

  /// Merge: file rules left out because the phone is at the rule cap.
  final int skippedOverCap;

  /// Rules the store refused for another reason (should not happen).
  final int refused;

  /// Written rules that were Auto-record in the file: restored at Auto-record, waiting for Keep
  /// (behave as Ask first meanwhile). The name is kept from 0.2.1; it is the banner's N.
  final int autoRecordAsAskFirst;

  /// Written Paybill rules that were Auto-record in the file and are Ask first (a Paybill never holds it).
  final int paybillAsAskFirst;

  /// Replace: the phone's own rules were removed first.
  final bool phoneRulesCleared;

  /// The rules could not be written. The ledger is restored; on Replace the rules are EMPTY (never
  /// a half set that could auto-record), on Merge the phone's rules are as they were plus any
  /// already added (all Ask first or lower).
  final bool failed;

  @override
  String toString() => 'RulesRestoreOutcome(added: $added, keptPhone: $keptPhone, replaced: $replaced, '
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
  const RuleCategoryLookup({this.idBySeed = const {}, this.idByName = const {}, this.activeIds = const {}});

  /// `seed_key` -> id.
  final Map<String, int> idBySeed;

  /// Name of a user-made category -> id (an active row wins, else the lowest id).
  final Map<String, int> idByName;

  /// Ids of the ACTIVE categories (`active = 1`). A chosen Suggest category must be one of these;
  /// the rule's own category is not checked here (unchanged since S-4b).
  final Set<int> activeIds;

  static Future<RuleCategoryLookup> load(DatabaseExecutor ex) async {
    final seed = <String, int>{};
    final byName = <String, int>{};
    final active = <String>{};
    final activeIds = <int>{};
    final rows = await ex.rawQuery('SELECT id, seed_key, name, active FROM classifications ORDER BY id');
    for (final r in rows) {
      final id = r['id']! as int;
      if (r['active'] == 1) activeIds.add(id);
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
    return RuleCategoryLookup(idBySeed: seed, idByName: byName, activeIds: activeIds);
  }

  /// The phone id for one `sc` entry (a map with exactly one of `cat_seed` / `cat_name`), or null
  /// when the entry is unreadable, not found, or not an active category.
  int? chosenId(Object? entry) {
    if (entry is! Map || entry.length != 1) return null;
    final seed = entry['cat_seed'];
    final name = entry['cat_name'];
    final id = seed is String ? idBySeed[seed] : (name is String ? idByName[name] : null);
    return id != null && activeIds.contains(id) ? id : null;
  }
}

/// The phone ids for a file row's `sc` value. PURE and never throws: not a list = empty; each
/// unreadable, unknown or inactive entry dropped; an id twice kept once; at most
/// [kBackupMaxChosenCategories], file order kept.
List<int> restoredChosenIds(Object? sc, RuleCategoryLookup cats) {
  if (sc is! List) return const <int>[];
  final out = <int>[];
  for (final e in sc) {
    if (out.length == kBackupMaxChosenCategories) break;
    final id = cats.chosenId(e);
    if (id != null && !out.contains(id)) out.add(id);
  }
  return List<int>.unmodifiable(out);
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
    final level = auto && !canAuto ? 1 : lv;
    rows.add(RestoredRule(
      type: type,
      key: r['k']! as String,
      name: r['name']! as String,
      level: level,
      categoryId: cat,
      ceilingCents: r['ceil'] as int?,
      autoPending: wasAuto || (level == 1 && canAuto && r['ap'] == 1),
      wasAutoRecord: wasAuto,
      wasPaybillAuto: auto && !canAuto,
      chosenCategoryIds: level == 0 ? restoredChosenIds(r['sc'], cats) : const <int>[],
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
