/// §AUTOREAD.RULE_BACKUP_SOURCE - AUTOREAD RULES to backup adapter (0.2.2 item 2, S-4a): the
/// export's `BackupRulesSource` over a [RuleStore]. Plain data out (kind code, key, name, level,
/// category DATABASE id, ceiling, marker, chosen Suggest category ids): `lib/data/backup` turns
/// each id into a seed key or name.
/// Empty while "Record receiver details" is OFF (the real store answers empty then). Wired since
/// 0.2.2 B1: `RulesWiring.backupSource` reads it for every `BackupService(rules:)` (RuleBackupSeams).
library;

import '../../data/backup/backup_rules.dart';
import 'rule_store.dart';

/// The rules of [store] as export input. Pass `() => backupRulesFrom(store)`.
Future<List<BackupRuleInput>> backupRulesFrom(RuleStore store) async => [
      for (final r in await store.all())
        BackupRuleInput(
          type: r.type.code,
          key: r.key,
          name: r.name,
          level: r.level.code,
          categoryId: r.categoryId,
          ceilingCents: r.ceilingCents,
          autoPending: r.autoPending,
          chosenCategoryIds: r.chosenCategoryIds,
        ),
    ];
