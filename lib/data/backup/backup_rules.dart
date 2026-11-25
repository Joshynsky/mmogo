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
}

/// Reads the rules to export. Must return an empty list while "Record receiver details" is OFF
/// (no rules exist then); the real source gets that from the rule store.
typedef BackupRulesSource = Future<List<BackupRuleInput>> Function();

/// The rows for the file, what had to be tidied and what had to be left out.
class BackupRuleRows {
  const BackupRuleRows({required this.rows, required this.repaired, required this.skipped});

  /// File-shaped rows (keys per `kBackupRuleKeys`), sorted by kind then key.
  final List<Map<String, Object?>> rows;

  /// Rows kept but changed in the copy (name tidied, Paybill Auto-record written as Ask first).
  final int repaired;

  /// Rules left out: table `receiver_rules`, no row id, the field and rule only (never a value).
  final List<BackupSkippedRow> skipped;
}

/// Builds the `receiver_rules` rows. [classifications] are the file-shaped category rows that
/// WILL be in the file (after repair): a rule's category id is looked up there, written as
/// `cat_seed` for a built-in or `cat_name` for the person's own, and as no category when the id is
/// not found (deleted or left out). A rule that cannot be made valid is skipped, never guessed:
/// an unreadable kind, key, level or ceiling (dropping a ceiling would widen Auto-record).
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
    });
  }
  return BackupRuleRows(rows: rows, repaired: repaired, skipped: skipped);
}
