/// §DATA.BACKUP.RULES - the `receiver_rules` section, exporter side (0.2.2 item 2, S-4a):
/// the seam the export reads rules through, and the pure step that turns them into file rows.
///
/// PURE and import-light on purpose: `lib/data` must never import `lib/autoread/` (the standard
/// build drops that folder), so the seam speaks plain data. The adapter from the rule store lives
/// in `lib/autoread/rules/rule_backup_source.dart`. Dormant: `BackupService` has no source by
/// default (no rules travel) until a later slice wires one in.
library;

import 'backup_limits.dart';
import 'backup_repair.dart' show BackupRepair, BackupSkippedRow;

/// One remembered person's rule as the export receives it. [categoryId] is a DATABASE id: it is
/// turned into a seed key or a name here and never written.
class BackupRuleInput {
  const BackupRuleInput({
    required this.type,
    required this.key,
    required this.name,
    required this.level,
    this.categoryId,
    this.ceilingCents,
    this.autoPending = false,
    this.chosenCategoryIds = const <int>[],
  });

  /// `ReceiverType.code` (`SM`, `PB`, `BG`, `PO`).
  final String type;
  final String key;
  final String name;

  /// 0 Suggested, 1 Ask first, 2 Auto-record.
  final int level;
  final int? categoryId;
  final int? ceilingCents;
  final bool autoPending;

  /// The person's chosen Suggest categories (DATABASE ids, in the order chosen; 0.2.2 item 2
  /// B-BK). Written as `sc` by seed key or name; empty = "Last 10 payments".
  final List<int> chosenCategoryIds;
}

/// Reads the rules to export. Must return an empty list while "Record receiver details" is OFF
/// (no rules exist then); the real source gets that from the rule store.
typedef BackupRulesSource = Future<List<BackupRuleInput>> Function();

/// The rows for the file, what had to be tidied and what had to be left out.
class BackupRuleRows {
  const BackupRuleRows({required this.rows, required this.repaired, required this.skipped});

  /// File-shaped rows (keys per `kBackupRuleKeys`), sorted by kind then key.
  final List<Map<String, Object?>> rows;

  /// Rows kept but changed in the copy (name tidied, Paybill Auto-record written as Ask first, a
  /// chosen list trimmed: a category not in the file, an id twice, more than 2, or a list held
  /// above Suggested).
  final int repaired;

  /// Rules left out: table `receiver_rules`, no row id, the field and rule only (never a value).
  final List<BackupSkippedRow> skipped;
}

/// Builds the `receiver_rules` rows. [classifications] are the file-shaped category rows that
/// WILL be in the file (after repair): a rule's category id is looked up there, written as
/// `cat_seed` for a built-in or `cat_name` for the person's own, and as no category when the id is
/// not found (deleted or left out). A rule that cannot be made valid is skipped, never guessed:
/// an unreadable kind, key, level or ceiling (dropping a ceiling would widen Auto-record).
///
/// Chosen Suggest categories (`sc`, B-BK): written only for a rule that is Suggested in the file,
/// each id named the same way as the rule's category; an id not found is dropped (never guessed),
/// an id twice is written once, at most [kBackupMaxChosenCategories] in order. Any trim counts the
/// row as repaired; a chosen list never makes a rule skipped (the rule is still valid without it).
BackupRuleRows buildBackupRuleRows(
  List<BackupRuleInput> inputs,
  List<Map<String, Object?>> classifications,
) {
  final byId = <int, Map<String, Object?>>{
    for (final c in classifications)
      if (c['id'] is int) c['id']! as int: c,
  };
  final sorted = List<BackupRuleInput>.of(inputs)
    ..sort((a, b) {
      final t = a.type.compareTo(b.type);
      return t != 0 ? t : a.key.compareTo(b.key);
    });
  final rows = <Map<String, Object?>>[];
  final skipped = <BackupSkippedRow>[];
  final seen = <String>{};
  var repaired = 0;

  void skip(String field, String rule) =>
      skipped.add(BackupSkippedRow(table: 'receiver_rules', rowId: null, field: field, rule: rule));

  for (final r in sorted) {
    if (!kBackupRuleTypes.contains(r.type)) {
      skip('t', 'enum');
      continue;
    }
    final k = r.key;
    if (k.isEmpty || k.length > kBackupMaxRuleKeyLength || k != k.trim() || !backupTextIsClean(k)) {
      skip('k', 'format');
      continue;
    }
    if (r.level < 0 || r.level > kBackupMaxRuleLevel) {
      skip('lv', 'range');
      continue;
    }
    final ceil = r.ceilingCents;
    if (ceil != null && (ceil < kBackupMinCeilingCents || ceil > kBackupMaxCeilingCents)) {
      skip('ceil', 'range');
      continue;
    }
    final name = BackupRepair.cleanText(r.name, kBackupMaxLabelLength);
    if (name.isEmpty) {
      skip('name', 'empty');
      continue;
    }
    if (!seen.add('${r.type}\u0000$k')) {
      skip('k', 'duplicate');
      continue;
    }
    var changed = name != r.name;
    // Paybill never holds Auto-record: the copy says Ask first (the app would do the same).
    var level = r.level;
    if (r.type == 'PB' && level == kBackupMaxRuleLevel) {
      level = 1;
      changed = true;
    }
    String? seed;
    String? catName;
    final cat = r.categoryId == null ? null : byId[r.categoryId];
    if (cat != null) {
      if (cat['seed_key'] is String) {
        seed = cat['seed_key']! as String;
      } else if (cat['name'] is String) {
        catName = cat['name']! as String;
      }
    }
    final chosen = level == 0 ? _chosenRefs(r.chosenCategoryIds, byId) : const <Map<String, Object?>>[];
    if (chosen.length != r.chosenCategoryIds.length) changed = true;
    if (changed) repaired++;
    rows.add(<String, Object?>{
      't': r.type,
      'k': k,
      'name': name,
      'lv': level,
      'cat_seed': seed,
      'cat_name': catName,
      'ceil': ceil,
      'ap': r.autoPending ? 1 : 0,
      'sc': chosen,
    });
  }
  return BackupRuleRows(rows: rows, repaired: repaired, skipped: skipped);
}

/// The `sc` entries for [ids]: each id found in the file's categories as `{cat_seed}` (built-in)
/// or `{cat_name}` (the person's own); not found = dropped; an id twice = once; at most
/// [kBackupMaxChosenCategories], order kept.
List<Map<String, Object?>> _chosenRefs(List<int> ids, Map<int, Map<String, Object?>> byId) {
  final out = <Map<String, Object?>>[];
  final seen = <int>{};
  for (final id in ids) {
    if (out.length == kBackupMaxChosenCategories) break;
    if (!seen.add(id)) continue;
    final cat = byId[id];
    if (cat == null) continue;
    if (cat['seed_key'] is String) {
      out.add(<String, Object?>{'cat_seed': cat['seed_key']});
    } else if (cat['name'] is String) {
      out.add(<String, Object?>{'cat_name': cat['name']});
    }
  }
  return out;
}
