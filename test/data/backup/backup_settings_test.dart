// B8: BackupSettings (the settings allowlist) and BackupPrefs (typed
// `auto_backup_*` keys). Plain tests with mock SharedPreferences.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _validBlock = <String, Object?>{
  'user_display_name': 'Amina',
  'palette_id': 'leaf',
  'auto_recognize_classifications': false,
  'capture_identity_preference': false,
  'auto_backup_every_n': 20,
  'auto_backup_keep_k': 7,
};

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('allowlist_accepts_only_listed_keys', () {
    test('every listed key with a valid value is accepted', () async {
      expect(BackupSettings.firstProblem(_validBlock), isNull);
      final r = await BackupSettings().applyAfterCommit(_validBlock);
      expect(r.ok, isTrue);
      expect(r.applied.toSet(), _validBlock.keys.toSet());
      final p = await _prefs();
      expect(p.getString('user_display_name'), 'Amina');
      expect(p.getString('palette_id'), 'leaf');
      expect(p.getBool('auto_recognize_classifications'), false);
      expect(p.getBool('capture_identity_preference'), false);
      expect(p.getInt('auto_backup_every_n'), 20);
      expect(p.getInt('auto_backup_keep_k'), 7);
    });

    test('an unknown key fails the whole block and writes nothing', () async {
      final block = {..._validBlock, 'something_else': 1};
      final r = await BackupSettings().applyAfterCommit(block);
      expect(r.ok, isFalse);
      expect(r.problemKey, 'something_else');
      expect(r.applied, isEmpty);
      final p = await _prefs();
      expect(p.getKeys(), isEmpty);
    });

    test('an empty block is ok and writes nothing', () async {
      final r = await BackupSettings().applyAfterCommit({});
      expect(r.ok, isTrue);
      expect((await _prefs()).getKeys(), isEmpty);
    });

    test('merge (onlyIfUnset) fills unset keys and leaves set ones', () async {
      SharedPreferences.setMockInitialValues({'palette_id': 'indigo'});
      final r = await BackupSettings()
          .applyAfterCommit(_validBlock, onlyIfUnset: true);
      expect(r.ok, isTrue);
      expect(r.skipped, ['palette_id']);
      final p = await _prefs();
      expect(p.getString('palette_id'), 'indigo');
      expect(p.getString('user_display_name'), 'Amina');
      expect(p.getInt('auto_backup_keep_k'), 7);
    });

    test('merge treats a blank display name as unset', () async {
      SharedPreferences.setMockInitialValues({'user_display_name': '   '});
      await BackupSettings()
          .applyAfterCommit({'user_display_name': 'Amina'}, onlyIfUnset: true);
      expect((await _prefs()).getString('user_display_name'), 'Amina');
    });

    test('replace overwrites values already set', () async {
      SharedPreferences.setMockInitialValues({'palette_id': 'indigo'});
      await BackupSettings().applyAfterCommit(_validBlock);
      expect((await _prefs()).getString('palette_id'), 'leaf');
    });

    test('applying a display name bumps the greeting notifier', () async {
      final before = AppPrefs.userDisplayNameRevision.value;
      await BackupSettings().applyAfterCommit({'user_display_name': 'Amina'});
      expect(AppPrefs.userDisplayNameRevision.value, before + 1);
    });
  });

  group('forbidden_keys_never_applied', () {
    // Each of these is a real pref of the app that a file must never reach.
    const forbidden = <String, Object>{
      'auto_backup_folder_uri': 'content://evil/tree/x',
      'auto_backup_folder_name': 'evil',
      'auto_backup_enabled': true,
      'auto_backup_paused': false,
      'auto_backup_since_count': 99,
      'auto_backup_last_at': '2099-01-01T00:00:00',
      'backup_last_manual_at': 1,
      'update_check_enabled': false,
      'update_last_check_at': 1,
      'updates_inbox_v1': '[]',
      'whatsnew_seen_version': '99.0.0',
      'last_seen_version': '99.0.0',
      'onboarding_complete': true,
      'tour_seen_home': true,
      'tour_step_home': 3,
      'id': 5,
      'path': '/etc/passwd',
      'url': 'https://example.com',
    };

    for (final e in forbidden.entries) {
      test('${e.key} is refused and nothing is written', () async {
        expect(backupSettingSpecFor(e.key), isNull);
        final r = await BackupSettings().applyAfterCommit({e.key: e.value});
        expect(r.ok, isFalse);
        expect(r.problemKey, e.key);
        expect((await _prefs()).getKeys(), isEmpty);
      });
    }

    test('a forbidden key next to valid ones still writes nothing', () async {
      final r = await BackupSettings().applyAfterCommit(
        {..._validBlock, 'update_check_enabled': false},
      );
      expect(r.ok, isFalse);
      expect((await _prefs()).getKeys(), isEmpty);
    });

    test('snapshot never includes forbidden keys even when they are set',
        () async {
      SharedPreferences.setMockInitialValues({
        ...forbidden,
        'palette_id': 'leaf',
      });
      final snap = await BackupSettings().snapshot();
      expect(snap, {'palette_id': 'leaf'});
    });
  });

  group('type_and_range_rejected', () {
    final bad = <String, List<Object?>>{
      'user_display_name': [
        '',
        ' ',
        ' padded ',
        'x' * 31,
        'line\nbreak',
        'bidi\u202Eevil',
        'nul\u0000',
        5,
        true,
        null,
      ],
      'palette_id': ['red', 'OCEAN', '', 1, true, null],
      'auto_recognize_classifications': ['true', 1, 0, null, 'false'],
      'capture_identity_preference': ['yes', 1, null],
      'auto_backup_every_n': [0, 101, -1, 10.0, 10.5, '10', true, null],
      'auto_backup_keep_k': [0, 1, 21, 5.0, '5', false, null],
    };
    for (final entry in bad.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final v = entry.value[i];
        test('${entry.key} rejects case $i (${v.runtimeType})', () async {
          expect(BackupSettings.firstProblem({entry.key: v}), entry.key);
          final r = await BackupSettings().applyAfterCommit({entry.key: v});
          expect(r.ok, isFalse);
          expect((await _prefs()).getKeys(), isEmpty);
        });
      }
    }

    test('boundaries are accepted', () {
      for (final b in <Map<String, Object?>>[
        {'auto_backup_every_n': 1},
        {'auto_backup_every_n': 100},
        {'auto_backup_keep_k': 2},
        {'auto_backup_keep_k': 20},
        {'user_display_name': 'x' * 30},
      ]) {
        expect(BackupSettings.firstProblem(b), isNull, reason: '$b');
      }
    });

    test('one bad value fails the whole block, even after good keys',
        () async {
      final r = await BackupSettings().applyAfterCommit({
        'palette_id': 'leaf',
        'auto_backup_keep_k': 999,
      });
      expect(r.ok, isFalse);
      expect((await _prefs()).getKeys(), isEmpty);
    });
  });

  group('snapshot', () {
    test('contains only the settings that are set', () async {
      SharedPreferences.setMockInitialValues({
        'palette_id': 'indigo',
        'auto_backup_keep_k': 9,
      });
      expect(await BackupSettings().snapshot(),
          {'palette_id': 'indigo', 'auto_backup_keep_k': 9});
    });

    test('is empty on a fresh phone', () async {
      expect(await BackupSettings().snapshot(), isEmpty);
    });

    test('leaves out a stored value that would fail its own check', () async {
      SharedPreferences.setMockInitialValues({
        'palette_id': 'red',
        'auto_backup_every_n': 500,
        'user_display_name': 'Amina',
      });
      expect(await BackupSettings().snapshot(), {'user_display_name': 'Amina'});
    });

    test('snapshot passes its own validation', () async {
      SharedPreferences.setMockInitialValues({..._validBlock}
          .map((k, v) => MapEntry(k, v as Object)));
      final snap = await BackupSettings().snapshot();
      expect(snap, _validBlock);
      expect(BackupSettings.firstProblem(snap), isNull);
    });
  });

  test('key_mapping_table_matches_architecture_d12', () {
    // Architecture D12 "Backup settings allowlist" (with the F3 pref names).
    // (file key, prefs key, kind, min, max, maxLength, choices)
    final actual = kBackupSettingSpecs
        .map((s) => [
              s.fileKey,
              s.prefsKey,
              s.kind,
              s.min,
              s.max,
              s.maxLength,
              s.choices,
            ])
        .toList();
    expect(actual, [
      ['user_display_name', 'user_display_name', BackupSettingKind.text, null, null, 30, null],
      ['palette_id', 'palette_id', BackupSettingKind.choice, null, null, null, ['ocean', 'leaf', 'indigo']],
      ['auto_recognize_classifications', 'auto_recognize_classifications', BackupSettingKind.boolean, null, null, null, null],
      ['capture_identity_preference', 'capture_identity_preference', BackupSettingKind.boolean, null, null, null, null],
      ['auto_backup_every_n', 'auto_backup_every_n', BackupSettingKind.integer, 1, 100, null, null],
      ['auto_backup_keep_k', 'auto_backup_keep_k', BackupSettingKind.integer, 2, 20, null, null],
    ]);

    // Of the auto-backup keys only every-N and keep-K are in the file.
    final inFile = kBackupSettingSpecs.map((s) => s.prefsKey).toSet();
    for (final k in [
      BackupPrefs.keyAutoBackupEnabled,
      BackupPrefs.keyAutoBackupFolderUri,
      BackupPrefs.keyAutoBackupFolderName,
      BackupPrefs.keyAutoBackupSinceCount,
      BackupPrefs.keyAutoBackupPaused,
      BackupPrefs.keyAutoBackupLastAt,
      BackupPrefs.keyBackupLastManualAt,
    ]) {
      expect(inFile.contains(k), isFalse, reason: '$k must never be restored');
    }
    expect(inFile.contains(BackupPrefs.keyAutoBackupEveryN), isTrue);
    expect(inFile.contains(BackupPrefs.keyAutoBackupKeepK), isTrue);

    // The existing AppPrefs key constants are the ones the table names.
    expect(inFile.contains(AppPrefs.keyUserDisplayName), isTrue);
    expect(inFile.contains(AppPrefs.keyPaletteId), isTrue);
    expect(inFile.contains(AppPrefs.keyAutoRecognizeClassifications), isTrue);
    expect(inFile.contains(AppPrefs.keyCaptureIdentityPreference), isTrue);
    // No duplicate file keys.
    expect(kBackupSettingSpecs.map((s) => s.fileKey).toSet().length,
        kBackupSettingSpecs.length);
  });

  group('BackupPrefs pinned keys and defaults (F3)', () {
    test('key names are the pinned ones', () {
      expect(BackupPrefs.keyAutoBackupEnabled, 'auto_backup_enabled');
      expect(BackupPrefs.keyAutoBackupEveryN, 'auto_backup_every_n');
      expect(BackupPrefs.keyAutoBackupKeepK, 'auto_backup_keep_k');
      expect(BackupPrefs.keyAutoBackupFolderUri, 'auto_backup_folder_uri');
      expect(BackupPrefs.keyAutoBackupSinceCount, 'auto_backup_since_count');
      expect(BackupPrefs.keyAutoBackupPaused, 'auto_backup_paused');
      expect(BackupPrefs.keyAutoBackupLastAt, 'auto_backup_last_at');
      expect(BackupPrefs.keyBackupLastManualAt, 'backup_last_manual_at');
    });

    test('defaults on a fresh phone', () async {
      expect(await BackupPrefs.readEnabled(), isFalse);
      expect(await BackupPrefs.readEveryN(), 10);
      expect(await BackupPrefs.readKeepK(), 5);
      expect(await BackupPrefs.readFolderUri(), isNull);
      expect(await BackupPrefs.readSinceCount(), 0);
      expect(await BackupPrefs.readPaused(), isFalse);
      expect(await BackupPrefs.readLastAt(), isNull);
      expect(await BackupPrefs.readLastManualAt(), isNull);
    });

    test('round trips and clamps', () async {
      expect(await BackupPrefs.writeEnabled(true), isTrue);
      expect(await BackupPrefs.readEnabled(), isTrue);
      await BackupPrefs.writeEveryN(50);
      expect(await BackupPrefs.readEveryN(), 50);
      await BackupPrefs.writeEveryN(5000);
      expect(await BackupPrefs.readEveryN(), 100);
      await BackupPrefs.writeKeepK(1);
      expect(await BackupPrefs.readKeepK(), 2);
      await BackupPrefs.writeKeepK(8);
      expect(await BackupPrefs.readKeepK(), 8);
      await BackupPrefs.writeFolderUri('content://tree/a');
      expect(await BackupPrefs.readFolderUri(), 'content://tree/a');
      await BackupPrefs.writeFolderUri(null);
      expect(await BackupPrefs.readFolderUri(), isNull);
      await BackupPrefs.writeSinceCount(3);
      expect(await BackupPrefs.readSinceCount(), 3);
      await BackupPrefs.writeSinceCount(-4);
      expect(await BackupPrefs.readSinceCount(), 0);
      final t = DateTime(2026, 10, 2, 9, 30);
      await BackupPrefs.writeLastAt(t);
      expect(await BackupPrefs.readLastAt(), t);
      await BackupPrefs.writeLastManualAt(t);
      expect(await BackupPrefs.readLastManualAt(), t);
    });

    test('out-of-range stored values are clamped on read', () async {
      SharedPreferences.setMockInitialValues({
        'auto_backup_every_n': 0,
        'auto_backup_keep_k': 99,
      });
      expect(await BackupPrefs.readEveryN(), 1);
      expect(await BackupPrefs.readKeepK(), 20);
    });

    test('a wrong-typed stored value falls back to the default', () async {
      SharedPreferences.setMockInitialValues({
        'auto_backup_every_n': 'ten',
        'auto_backup_enabled': 'yes',
      });
      expect(await BackupPrefs.readEveryN(), 10);
      expect(await BackupPrefs.readEnabled(), isFalse);
    });

    test('paused notifier follows writes', () async {
      await BackupPrefs.writePaused(true);
      expect(BackupPrefs.pausedNotifier.value, isTrue);
      await BackupPrefs.writePaused(false);
      expect(BackupPrefs.pausedNotifier.value, isFalse);
    });

    test('clearAutoBackup removes the folder keys and keeps N, K, last', () async {
      SharedPreferences.setMockInitialValues({
        'auto_backup_folder_uri': 'content://x',
        'auto_backup_folder_name': 'x',
        'auto_backup_enabled': true,
        'auto_backup_paused': true,
        'auto_backup_since_count': 4,
        'auto_backup_every_n': 20,
        'auto_backup_keep_k': 6,
        'auto_backup_last_at': '2026-10-01T00:00:00.000',
      });
      expect(await BackupPrefs.clearAutoBackup(), isTrue);
      final p = await _prefs();
      expect(p.getKeys().toSet(), {
        'auto_backup_every_n',
        'auto_backup_keep_k',
        'auto_backup_last_at',
      });
      expect(BackupPrefs.pausedNotifier.value, isFalse);
    });
  });
}
