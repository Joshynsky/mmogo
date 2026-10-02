import '../../../data/prefs/backup_prefs.dart';

/// A snapshot of the auto-backup prefs, read by the Backup page and shown by
/// the Auto-backup card. Plain data; the card renders it, the flow changes it.
class AutoBackupState {
  const AutoBackupState({
    this.enabled = false,
    this.folderUri,
    this.folderName,
    this.paused = false,
    this.everyN = BackupPrefs.defaultEveryN,
    this.keepK = BackupPrefs.defaultKeepK,
    this.sinceCount = 0,
    this.lastAt,
    this.failCount = 0,
  });

  final bool enabled;
  final String? folderUri;
  final String? folderName;

  /// Only meaningful while [enabled].
  final bool paused;
  final int everyN;
  final int keepK;
  final int sinceCount;
  final DateTime? lastAt;
  final int failCount;

  bool get hasFolder => folderUri != null;

  /// Paused as the user sees it.
  bool get isPaused => enabled && paused;

  /// The last automatic backup failed and it is not paused (so it will retry).
  bool get lastFailed => enabled && !paused && failCount > 0;

  /// The date for the "Last auto-backup" part of the last-backup line; only
  /// while it is on, has a folder and is not paused (as in the prototype).
  DateTime? get lastForLine => (enabled && hasFolder && !paused) ? lastAt : null;

  static Future<AutoBackupState> load() async => AutoBackupState(
        enabled: await BackupPrefs.readEnabled(),
        folderUri: await BackupPrefs.readFolderUri(),
        folderName: await BackupPrefs.readFolderName(),
        paused: await BackupPrefs.readPaused(),
        everyN: await BackupPrefs.readEveryN(),
        keepK: await BackupPrefs.readKeepK(),
        sinceCount: await BackupPrefs.readSinceCount(),
        lastAt: await BackupPrefs.readLastAt(),
        failCount: await BackupPrefs.readFailCount(),
      );
}
