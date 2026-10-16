import 'package:flutter/foundation.dart';

/// §SCREEN.BACKUP.SEAMS — 0.1.2 S10b (A12). The one guard that keeps a widget
/// test from reaching the real restore service, the real share sheet / temp
/// files or the real backup export through a DEFAULT in the Backup page flows
/// (`RestoreFlow._defaultService`, `BackupExportFlow` defaults,
/// `DeviceTempFiles`). A test turns it on with `useFakeBackupUi()`
/// (`test/support/fake_backup_ui.dart`); the app never does.
class BackupUiSeams {
  const BackupUiSeams._();

  /// True while a test has declared "nothing real here".
  @visibleForTesting
  static bool guarded = false;

  /// Called by every default that would touch real data. Throws while guarded.
  static void ensureReal(String what) {
    if (guarded) {
      throw StateError('A test reached the real $what. Inject a fake (useFakeBackupUi).');
    }
  }
}
