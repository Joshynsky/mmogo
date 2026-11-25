/// §DATA.BACKUP.RULE_SEAMS - the ONE holder that joins the rules to backups (0.2.2 item 2, B1).
///
/// `lib/data` and `lib/ui/screens` must never import `lib/autoread/` (the standard build drops that
/// folder), so the auto-read build fills this holder from its own wiring (`RulesWiring`, called once
/// from `main.dart`). Both seams travel as ONE pair: [install] takes the export's rules source AND the
/// restore's rules sink together, so the app can never write rules into a backup it cannot read back,
/// nor read rules back from a file it never wrote them into (an Undo of a Replace would lose them).
///
/// Every construction of [BackupService] that writes a file and of [RestoreService] goes through
/// [backupService] / [restoreService] (the automatic backup, the manual export, the restore and the
/// Replace safety copy). Nothing installed (the standard build, and every test that does not install)
/// = exactly the pre-0.2.2 behaviour: no rule travels and a restore leaves rules to the Replace hook.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import 'backup_rules.dart' show BackupRulesSource;
import 'backup_service.dart';
import 'backup_settings.dart';
import 'restore_service.dart';
import 'safety_copy_store.dart';

/// The two rule seams, always together.
class _RuleSeamPair {
  const _RuleSeamPair(this.source, this.sink);
  final BackupRulesSource source;
  final RuleRestoreSink sink;
}

class RuleBackupSeams {
  RuleBackupSeams._();

  /// One reference, swapped whole: a reader never sees one seam without the other.
  static _RuleSeamPair? _pair;

  /// True when both seams are set (auto-read build after `RulesWiring.installBackupRules`).
  static bool get installed => _pair != null;

  /// The export's rules source, or null when not installed.
  static BackupRulesSource? get source => _pair?.source;

  /// The restore's rules sink, or null when not installed.
  static RuleRestoreSink? get sink => _pair?.sink;

  /// Sets BOTH seams. There is no way to set only one.
  static void install({required BackupRulesSource source, required RuleRestoreSink sink}) {
    _pair = _RuleSeamPair(source, sink);
  }

  /// Clears BOTH seams (tests, or the wiring's uninstall).
  static void uninstall() {
    _pair = null;
  }

  /// A [BackupService] that writes the installed rules (none when not installed). The optional
  /// arguments are the service's own; the app passes only [db].
  static BackupService backupService({
    required Future<Database> Function() db,
    DateTime Function()? now,
    BackupSettings? settings,
  }) =>
      BackupService(db: db, now: now, settings: settings, rules: _pair?.source);

  /// A [RestoreService] whose rules step AND whose Replace safety copy read the SAME installed pair
  /// (read once here), so a Replace's safety copy holds the phone's rules and its Undo brings them back.
  /// The optional arguments are the services' own; the app passes only [db].
  static RestoreService restoreService({
    required Future<Database> Function() db,
    DateTime Function()? now,
    BackupSettings? settings,
    SafetyCopyStore? safety,
    bool validateInIsolate = true,
    Future<void> Function()? afterReplace,
  }) {
    final pair = _pair;
    return RestoreService(
      db: db,
      backup: BackupService(db: db, now: now, settings: settings, rules: pair?.source),
      safety: safety,
      settings: settings,
      validateInIsolate: validateInIsolate,
      afterReplace: afterReplace,
      rules: pair?.sink,
    );
  }
}
