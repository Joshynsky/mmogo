/// The ONE table that decides which preferences may travel inside a backup
/// file (B8, criterion 10), plus the pure value check for each.
///
/// Pure Dart with no imports, so the restore validator (which runs in an
/// isolate) can use it. Anything not in [kBackupSettingSpecs] is excluded by
/// construction: the auto-backup folder, enabled, paused, count and last-at
/// keys, `backup_last_manual_at`, the update-check switch and state, the
/// What's-new marker, onboarding and tour flags, the Updates inbox, ids and
/// paths. A backup file can therefore never switch the update check on or
/// off, or point the app at a folder.
library;

import 'backup_limits.dart';

enum BackupSettingKind { text, boolean, integer, choice }

class BackupSettingSpec {
  const BackupSettingSpec({
    required this.fileKey,
    required this.prefsKey,
    required this.kind,
    this.maxLength,
    this.min,
    this.max,
    this.choices,
  });

  /// Key inside the file's `prefs` object.
  final String fileKey;

  /// Key in `shared_preferences` it is applied to.
  final String prefsKey;

  final BackupSettingKind kind;
  final int? maxLength;
  final int? min;
  final int? max;
  final List<String>? choices;

  /// Whether [value] is acceptable for this key: strict JSON type (a double
  /// is not an int, a string is not a bool), range, length, no control or
  /// bidi characters.
  bool accepts(Object? value) {
    switch (kind) {
      case BackupSettingKind.boolean:
        return value is bool;
      case BackupSettingKind.integer:
        return value is int && value >= min! && value <= max!;
      case BackupSettingKind.choice:
        return value is String && choices!.contains(value);
      case BackupSettingKind.text:
        return value is String &&
            value.isNotEmpty &&
            value == value.trim() &&
            value.length <= maxLength! &&
            backupTextIsClean(value);
    }
  }
}

/// file key -> prefs key -> type and range. Pinned by the test
/// `key_mapping_table_matches_architecture_d12` against architecture D12.
/// File keys and prefs keys are identical by design: one name per setting.
const List<BackupSettingSpec> kBackupSettingSpecs = [
  BackupSettingSpec(
    fileKey: 'user_display_name',
    prefsKey: 'user_display_name',
    kind: BackupSettingKind.text,
    maxLength: kBackupMaxDisplayNameLength,
  ),
  BackupSettingSpec(
    fileKey: 'palette_id',
    prefsKey: 'palette_id',
    kind: BackupSettingKind.choice,
    choices: ['ocean', 'leaf', 'indigo'],
  ),
  BackupSettingSpec(
    fileKey: 'auto_recognize_classifications',
    prefsKey: 'auto_recognize_classifications',
    kind: BackupSettingKind.boolean,
  ),
  BackupSettingSpec(
    fileKey: 'capture_identity_preference',
    prefsKey: 'capture_identity_preference',
    kind: BackupSettingKind.boolean,
  ),
  BackupSettingSpec(
    fileKey: 'auto_backup_every_n',
    prefsKey: 'auto_backup_every_n',
    kind: BackupSettingKind.integer,
    min: 1,
    max: 100,
  ),
  BackupSettingSpec(
    fileKey: 'auto_backup_keep_k',
    prefsKey: 'auto_backup_keep_k',
    kind: BackupSettingKind.integer,
    min: 2,
    max: 20,
  ),
];

/// The spec for [fileKey], or `null` when the key is not allowlisted.
BackupSettingSpec? backupSettingSpecFor(String fileKey) {
  for (final s in kBackupSettingSpecs) {
    if (s.fileKey == fileKey) return s;
  }
  return null;
}
